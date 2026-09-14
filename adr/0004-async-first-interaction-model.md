---
type: adr
title: "Async-first interaction between services"
status: proposed
created: 2026-09-14
updated: 2026-09-14
author: Sodiq (ruling D-34), drafted by the Spec Lab
service: platform
confidence: medium
open_risks:
  - "One-hop-deep is stated, not enforced, until the registry validates edges"
  - "The forward-auth carve-out makes the gateway a hard dependency of every org-scoped route; gateway product choice is open"
  - "Feed polls are reads too; declaring them as event dependencies is a definition, and a future transport may change it"
adrs:
  - "[The domain-event envelope contract](0002-domain-event-envelope-contract.md)"
  - "[auth ADR-0019, event transport](https://github.com/xodeeq/xal-auth/blob/main/docs/adr/0019-event-transport.md)"
---

# Platform ADR-0004: Async-first interaction between services

- **Status:** Proposed
- **Date:** 2026-09-14
- **Deciders:** Sodiq (platform architect), ruling D-34
- **Amends:** [`spec/service-conventions.md`](../spec/service-conventions.md) §7, which
  stated the rule with almost no rationale and did not resolve the three cases below.
  The replacement wording is this ADR's decision 6; `VERSION` bumps minor.
- **Consumes:** auth [ADR-0019](https://github.com/xodeeq/xal-auth/blob/main/docs/adr/0019-event-transport.md)
  (the held transport, and the source of the "why pull" rationale §7 lacked), and
  [ADR-0002](0002-domain-event-envelope-contract.md) (the envelope, unchanged here)

> **Provenance.** Drafted in the xal-org spec's Appendix A.3 (`spec_version` 1.0.0,
> admitted at `xal-company/specs/admitted/xal-org/1.0.0.md`) and landed here verbatim.
> Its Context, Alternatives, Consequences and Revisit triggers are that draft's words;
> the section order follows `spec/adr-template.md` and ADR-0002 rather than the
> Decision-first order the appendix used to present it for approval.

## Context
spec/service-conventions.md §7 has required since auth's Phase 1 that cross-service
effects happen by emitting events, never by synchronous calls. Its origin is auth
ADR-0001 (events as the seam) and its purpose, stated in auth ADR-0019, is that a
publisher never holds a consumer registry. Designing the second and third services
surfaced three cases the sentence did not resolve: token verification on every request
(and, under the opaque session strategy, only introspection can do it); org-scoped
authorization, which every unit other than xal-org needs and which a literal reading
forces into N full-stream read models; and the transport itself, since under ADR-0019
a consumer polls the publisher's feed, which is a synchronous read.

## Decision
1. Effects (anything changing another service's state) travel as events. Never sync.
2. Under the held transport (auth ADR-0019) an event dependency is realized by polling
   the publisher's feed; that poll is declared as the event dependency, with fallback
   "retry within the retention window", and is not counted as a sync edge.
3. Sync calls are permitted for reads only, when local data cannot serve the request
   with acceptable staleness, one hop deep.
4. Standing carve-outs: token verification against xal-auth (JWKS under jwt;
   introspection under opaque); the gateway's forward-auth read to xal-org.
5. Every sync edge is declared in the service's registry entry as a runtime dependency,
   distinct from event dependencies, with timeout and fallback; composition treats it
   as hard co-deployment; §9's honesty rule applies to edges.
6. §7 is amended to the wording in xal-org spec Appendix A.2; VERSION bumps minor.

### Alternatives considered
- Pure async, including authorization via per-unit membership read models: rejected;
  each is a full-stream consumer under ADR-0002's no-filtering tradeoff, stale by one
  hop, duplicating xal-org's data for a three-role check.
- Roles in the auth token: rejected (D-05); inverts the auth → org dependency and
  contradicts auth's own contract ("/me returns sub and tenant only").
- Sync allowed generally with a "prefer async" note: rejected; the rule stops being
  decidable in review.

## Consequences
- The gateway is a hard dependency of every org-scoped route in every deployment.
- The registry data model gains a runtime-dependency kind with timeout and fallback,
  and records feed polls under event dependencies.
- Timeouts and fallbacks are requirements on every declared edge.
- A second hop, or a sync write, reopens this ADR rather than being an exception.

## Revisit triggers
1. A service needs a sync edge two hops deep.
2. A service needs a synchronous write for correctness.
3. The registry can validate edges: promote the declaration to [CI-enforceable].
4. The transport changes so that event consumption is no longer a poll (decision 2
   is a definition tied to ADR-0019).
