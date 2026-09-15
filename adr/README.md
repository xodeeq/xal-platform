# Platform Architecture Decision Records

Decisions that govern the **platform repo itself** and the cross-service platform — as
opposed to any single service. Each captures one decision as
**Context → Decision → Consequences**, following [`../spec/adr-discipline.md`](../spec/adr-discipline.md).

Service-level decisions (a service's bounded context, data store, token strategy, …)
live in *that service's* `docs/adr/`, not here. A decision lands here only when it binds
**every** service or the platform's own machinery.

| # | Decision | Status |
|---|---|---|
| [0001](0001-platform-repo-and-sync-model.md) | Platform repo structure + template/sync consumption model (realizes auth ADR-0009) | Accepted |
| [0002](0002-domain-event-envelope-contract.md) | The domain-event envelope contract: CloudEvents v1.0 in structured content mode, the registered extensions used, and the consumers-never-read-transport-metadata rule (realizes `spec` §7; consumed by auth ADR-0019, which chooses a transport behind it) | Proposed |
| [0004](0004-async-first-interaction-model.md) | Async-first interaction between services: effects travel as events; a feed poll is the event dependency, not a sync edge; synchronous **reads** only, one hop deep, with two standing carve-outs; every sync edge declared in the registry with timeout and fallback (amends `spec` §7 — `VERSION` 0.3.0 → 0.4.0) | Proposed |
| [0005](0005-service-to-service-feed-credential.md) | The service-to-service feed credential: one per (consumer, publisher) pair per deployment, generated at composition time, SHA-256 hashed allow-list on the publisher with constant-time compare, scoped to `GET /events` and nothing else; per-consumer revocation and a consumer that stops a feed on 401; rotation human-gated until the registry derives the allow-list; keys R1 rate limiting (satisfies auth ADR-0019 condition 2, closes W1; amends `spec` §7, `VERSION` 0.4.0 → 0.5.0) | Accepted |

> **0003 is reserved, not missing.** `adr/0003-repository-visibility.md` is the home the
> lessons ledger assigns to the 2026-08-12 decision to make this repo public — a decision
> that is made and acted on, with only its record outstanding
> ([`docs/lessons.md`](../docs/lessons.md)). The number is held so that entry can be
> promoted into it without renumbering anything.

> **Provenance.** The platform was discovered while building **auth** (service #1), so its
> founding cross-service decisions were first recorded as *auth* ADRs — notably auth
> **ADR-0005** (separate repo per service) and auth **ADR-0009** (shared-asset
> distribution: this repo's charter). Those remain in the auth repo as the historical
> record of how the platform was found; new platform-level decisions are recorded here.
