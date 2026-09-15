# Platform service conventions

xal is a catalogue of independently versioned, **polyglot** microservices that a
registry and a composition frontend stitch together. That only works if every
service — whatever language it's written in — exposes the **same operational and
contract surface**. This document is that contract.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD PLATFORM CONTRACT.**

**Auth (.NET 10) is service #1 and the reference implementation.** Each convention
below is stated language-agnostically, then cited to the real auth code that
realizes it, so a new service in TypeScript/Python/Go/Rust has a concrete model to
match. **Conform to this document whenever you create or modify any service.**

> This is the canonical spec. The auth citations below are the **reference
> realization** in .NET — they show *one* way to satisfy each rule, never the rule
> itself. A service in another language mirrors the *intent*, not the .NET specifics.

Each convention is tagged:
- **[CI-enforceable]** — a machine can verify it; wire it into the service's gate
  script / CI (or a future platform conformance test).
- **[review-only]** — judgement required; verify in code review / PR.

---

## 1. OpenAPI is the HTTP source of truth — **[CI-enforceable]**
The HTTP surface is declared in `openapi.yaml` at the service root; routes and
handlers conform to it, not the other way round. Generated clients, the registry,
and contract tests all read this file.
- **Auth ref:** `openapi.yaml`; routes mapped 1:1 in
  `src/Auth.Api/Endpoints/AuthEndpoints.cs` (Phase 1 returned `501` but the route
  surface already matched the contract).
- *Enforce:* lint the spec and assert the running app's routes match it
  (schemathesis / a spec-vs-routes diff) in CI.

## 2. Health: `/health/live` + `/health/ready` — **[CI-enforceable]**
- `GET /health/live` → 200 whenever the process is up (liveness; no dependencies).
- `GET /health/ready` → 200 **only** when hard dependencies (e.g. the DB) are
  reachable, else 503. Orchestrators gate traffic on readiness.
- **Auth ref:** `src/Auth.Api/Program.cs` — `self` check tagged `live`; the Npgsql
  connectivity probe tagged `ready`; mapped at `/health/live` and `/health/ready`
  with tag predicates.
- *Enforce:* CI/smoke hits both endpoints; readiness must be 503 before the DB is
  up and 200 after.

## 3. Telemetry: OpenTelemetry + Prometheus `/metrics` — **[CI-enforceable]**
Metrics and traces use **OpenTelemetry** (the cross-language standard); Prometheus
metrics are scraped at `GET /metrics`.
- **Auth ref:** `src/Auth.Api/Program.cs` — `AddOpenTelemetry()` with ASP.NET/HTTP/
  runtime instrumentation, the Prometheus exporter, and tracing (incl. the `Npgsql`
  ActivitySource); `MapPrometheusScrapingEndpoint("/metrics")`.
- *Enforce:* assert `/metrics` returns Prometheus exposition format in CI.

## 4. Structured JSON logs with required fields — **[CI-enforceable]**
One JSON event per line, every line carrying **`service`**, **`environment`**,
**`traceId`**, **`event`**. **Never** log secrets, tokens, or credentials.
- **Auth ref:** `src/Auth.Api/Program.cs` — Serilog `RenderedCompactJsonFormatter`,
  enriched with `service` and `environment`; `traceId` added per request by
  `src/Auth.Api/Observability/TraceIdMiddleware.cs`.
- *Enforce:* a log-shape test asserting the required keys; the "no secrets" half is
  **[review-only]**.

## 5. `X-Trace-Id` propagation — **[CI-enforceable]**
Read inbound `X-Trace-Id`; if absent, generate a UUID. Echo it on the response and
propagate it on outbound calls. One request is followable across service
boundaries.
- **Auth ref:** `src/Auth.Api/Observability/TraceIdMiddleware.cs` (`HeaderName =
  "X-Trace-Id"`): reads-or-generates, writes it to the response header, and pushes
  it onto the log context so every line carries it.
- *Enforce:* integration test — supplied header is echoed; absent header yields a
  generated one on the response.

## 6. The container interface — **[CI-enforceable]** (config/port) · **[review-only]** (SIGTERM)
A service is a well-behaved container:
- **config from the environment** (no `.env` files; secrets via env / secret store);
- **listens on a configurable port**;
- **handles SIGTERM with graceful shutdown** (drain in-flight work, bounded).
- **Auth ref:** `Dockerfile` (chiseled, non-root, `ASPNETCORE_HTTP_PORTS=8080`,
  reads config from env); `src/Auth.Api/Program.cs` sets `HostOptions.ShutdownTimeout`
  to 15s and logs on `ApplicationStopping`; Kestrel drains on SIGTERM.
- *Enforce:* CI builds the image (the docker gate). SIGTERM drain behavior is
  **[review-only]** (hard to assert cheaply).

## 7. Async-first interaction and the versioned CloudEvents envelope — **[CI-enforceable]** (envelope) · **[review-only]** (edge declaration, until the registry gates it)

**Effects travel as events.** Anything that changes another service's state happens by emitting a domain event, never by a synchronous call out of the service. A publisher never holds a list of its consumers (auth ADR-0001; auth ADR-0019 "why pull").

**Event dependencies are realized by polling the publisher's feed** under the current transport (auth ADR-0019): a consumer's poll of `GET /events` is the event dependency itself, declared as such, with the fallback always "retry within the publisher's retention window". It is not a sync edge in the sense below.

**Reads may be synchronous, narrowly.** A service may make a synchronous call for a **read only**, when the request cannot be served with acceptable staleness from its own data, and **one hop deep**. Two standing carve-outs: **token verification against the identity service** (JWKS offline verification under the `jwt` session strategy; `POST /tokens/introspect` under the `opaque` strategy), and **the gateway's forward-auth read** to the organization service.

**Every sync edge is declared.** A service's registry entry lists each synchronous dependency as a **runtime dependency**, distinct from event dependencies, with a **timeout** and a **fallback** (serve stale, deny, or degrade). Composition treats a runtime dependency as a **hard co-deployment requirement**; a service that cannot honour its declared fallback must not advertise the edge (§9).

**Every feed is authenticated with the feed credential.** A publisher's `GET /events` accepts only the per-deployment, per-consumer feed credential defined in [platform ADR-0005](https://github.com/xodeeq/xal-platform/blob/main/adr/0005-service-to-service-feed-credential.md): a bearer secret held in plaintext by exactly one consumer and as a **SHA-256 hash** in the publisher's allow-list, compared in **constant time** and resolved to the consumer's name, which keys the feed's **per-credential rate limit** and its `feed_distinct_clients` / `feed_consumer_lag_seq` metrics. The credential is rejected on every other route; identity-service access tokens are rejected on the feed; the feed is not routed through the gateway. A publisher with the feed enabled and no allow-list **fails fast at boot** (§6). **On a 401 from a feed, the consumer's poller stops that feed, increments a metric that alerts on first occurrence, and does not resume until the credential is re-issued and the process restarted** — a 401 is a revocation, not a transient error. Issuance, rotation and revocation are composition actions, human-gated until the registry derives the allow-list from declared event dependencies (ADR-0005 decision 7).

- **Org ref (first realization):** xal-org FR-33, FR-34, FR-36, FR-78 (publisher side) and FR-42 with FR-46's first-occurrence alert shape (consumer side); ADR-0001 decision 6.
- *Enforce:* three request tests per publisher with committed failing fixtures — valid credential 200, unknown credential 401, access token 401 — a boot test that a missing allow-list aborts under the feed profile, and one consumer-side test that a 401 stops that feed's poller, increments the alerting metric, and issues no further poll without a re-issued credential and a restart. **[CI-enforceable]** per publisher and per consumer.

**Every event is a CloudEvents v1.0 envelope in structured content mode** — the attribute set, the registered extensions and the rule that consumers dispatch on the envelope, never on transport-native metadata, are the contract in [platform ADR-0002](https://github.com/xodeeq/xal-platform/blob/main/adr/0002-domain-event-envelope-contract.md). `type` is versioned (`auth.session-revoked.v1`). **The transport behind the envelope is a per-service decision**; auth ADR-0019 is the reference. Rationale and alternatives: [platform ADR-0004](https://github.com/xodeeq/xal-platform/blob/main/adr/0004-async-first-interaction-model.md).

- **Auth ref:** `src/Auth.Domain/Events/EventEnvelope.cs` (the envelope type),
  `IDomainEvent.cs` (versioned `EventType`), `AuthEvents.cs` (the events),
  `src/Auth.Infrastructure/Messaging/EventPublisher.cs` (the publisher port's only
  adapter — **a log-only seam: it records a few fields and does not yet construct the
  envelope**; completing that path is auth ADR-0019's work).
- **Org ref (second publisher):** `urn:xal:service:org`; outbox + sequencer + `GET /events`; forward-auth target `GET /orgs/{orgId}/me` (xal-org spec §5, §6).
- *Enforce:* schema-validate served envelopes against ADR-0002; assert `type` is versioned (buildable now). Edge declaration becomes **[CI-enforceable]** when the registry validates entries.

## 8. The purity principle — **[review-only]**
The **domain layer never touches wall-clock time, randomness, or I/O** — these are
**injected**. Time enters through an explicit `now` parameter; persistence, hashing,
signing, and clocks live behind ports implemented in outer layers. This keeps the
core deterministic and unit-testable without mocks-of-everything.
- **Auth ref:** `src/Auth.Domain/Sessions/Session.cs` and
  `src/Auth.Domain/Accounts/AuthAccount.cs` thread `DateTimeOffset now` through
  `Start` / `Authenticate` / `Lock` / `Revoke`; ports live in
  `Auth.Domain/Abstractions` and `Auth.Application/Abstractions`, implemented only in
  `Auth.Infrastructure`.
- *Verify in review:* no wall-clock reads, no RNG, no I/O in the domain layer.
  (Promotable to **[CI-enforceable]** via an analyzer/banned-API list or an
  architecture test.)

## 9. Variation behind an invariant contract — **[review-only]**
A service exposes **variation flags**, but each flag sits **behind an invariant
contract**: the core surface is identical across every flag combination; only the
explicitly-allowed slice may differ. The host **fails fast** if it's configured for
a profile it can't actually serve — a service in the registry must never advertise a
capability it can't honor. Anything that breaks the invariant core is a **contract
version bump, not a flag**.
- **Auth ref:** auth's ADR-0003; `src/Auth.Application/Variations/VariationFlags.cs`;
  `src/Auth.Api/Configuration/VariationOptionsValidator.cs` (boot fails on an
  unimplemented profile); `AuthEndpoints.cs` splits the **invariant core**
  (refresh/introspect/revoke/JWKS/`/me`) from the **per-backend** login surface.
- *Verify in review:* the invariant surface is byte-identical across flags; the
  fail-fast validator covers every unimplemented profile. (The fail-fast boot is
  partially **[CI-enforceable]** via a startup test per profile.)

---

## How to use this document
- **New service:** treat §1–§9 as the acceptance checklist for "platform-ready".
  Mirror the auth reference in the new language. Wire every **[CI-enforceable]** item
  into that service's gate script and CI.
- **Modifying any service:** if a change touches one of these surfaces, re-check it
  here first; if it would break an invariant (esp. §1, §2, §5, §7, §9), that's a
  contract-version decision, not a quiet edit.
- The **deployment** counterpart to this contract is
  [`deployment-conventions.md`](deployment-conventions.md) — the operational
  invariants a service must satisfy to be deployable and composable.
