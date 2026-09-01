---
type: adr
title: "The domain-event envelope contract"
status: proposed
created: 2026-08-20
updated: 2026-08-20
author: research-lead
service: platform
department: research
confidence: medium
decision_date:
open_risks:
  - "`correlationid` and `causationid` are provably equal on every event emitted today; they earn their keep at service #3"
  - "`tenant`, `correlationid` and `causationid` are project-local extensions, not CloudEvents-registered — a generic SDK will not know them"
  - "The envelope is the costlier half to change once a second service consumes it, and it received less scrutiny than the transport during research"
tags: [events, cloudevents, envelope, contract]
adrs:
  - "[Platform repo structure + template/sync consumption model](0001-platform-repo-and-sync-model.md)"
---

# Platform ADR-0002: The domain-event envelope contract

- **Status:** Proposed
- **Date:** 2026-08-20
- **Deciders:** Sodiq (platform architect)
- **Realizes:** [`spec/service-conventions.md`](../spec/service-conventions.md) §7, which
  fixed the envelope *shape* and deferred everything else
- **Consumed by:** auth [ADR-0019](https://github.com/xodeeq/xal-auth/blob/main/docs/adr/0019-event-transport.md)
  (the first transport behind this contract). **That ADR chooses a transport; this one
  chooses the contract, and the two are deliberately decidable apart.**

## Context

`service-conventions.md` §7 has, since auth's Phase 1, required every service to emit
domain events in a versioned CloudEvents-style envelope, and explicitly deferred the
transport: *"only the **shape** is fixed."* That deferral held while there was one service.
It stops holding the moment a second service consumes the first's events, which is the
situation auth ADR-0019 addresses.

Researching that transport surfaced the reason this belongs here rather than in a service
repo. **The envelope is a contract every service in the catalogue is bound by; the broker
behind it is a swappable implementation** (principle P5, the platform's own core design
rule). Auth ADR-0019 originally carried both halves, concluded mid-document that the
envelope half was platform-level, and was split on that basis at decision time.

Two facts about the starting position, because both were misread once already and both
change the size of the work:

- **The envelope type is declared but never constructed.** In auth,
  `grep -rn "EventEnvelope" src/ tests/` returns the type declaration and three
  documentation cross-references — nothing else. The publisher logs a few fields directly.
  A type existing is not a contract being honoured, and §7's own "Auth ref" line has
  described a wrapping step that does not happen (corrected alongside this ADR).
- **§7 is marked [CI-enforceable] with the enforcement deferred** until a broker exists.
  A convention nothing emits against has no way to notice it is unimplemented — which is
  exactly how the gap above survived.

## Decision

**Adopt CloudEvents v1.0, carried in structured content mode, with the attribute set below.
Consumers dispatch on the envelope, never on transport-native metadata.**

| Attribute | Registered? | Value |
|---|---|---|
| `specversion` | core | `"1.0"` |
| `id` | core | unique per occurrence |
| `source` | core | absolute URI, `urn:xal:service:<name>` |
| `type` | core | versioned, e.g. `auth.session-revoked.v1` |
| `subject` | core | the opaque subject id, when the event has one |
| `time` | core | RFC 3339 UTC |
| `data` | core | typed payload |
| `datacontenttype` | core | `application/json` |
| `partitionkey` | [Partitioning](https://github.com/cloudevents/spec/blob/main/cloudevents/extensions/partitioning.md) | `subject` when present, else `tenant` |
| `sequence` | [Sequence](https://github.com/cloudevents/spec/blob/main/cloudevents/extensions/sequence.md) | gapless commit-order ordinal per `source` |
| `traceparent` | [Distributed Tracing](https://github.com/cloudevents/spec/blob/main/cloudevents/extensions/distributed-tracing.md) | W3C Trace Context |
| `tenant` | **project-local** | tenant id, `default` today |
| `correlationid` | **project-local** | workflow correlation |
| `causationid` | **project-local** | id of the message that caused this one |

All names satisfy the spec's extension-attribute rules — lowercase `[a-z0-9]`, under 20
characters ([CloudEvents spec](https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md)).

### The rule that does more work than any attribute

**Consumers dispatch on the envelope `type` and dedup on `(source, id)`. Consumers MUST NOT
read transport-native metadata** — Kafka headers, NATS subjects, AMQP routing keys, SQS
message attributes. Structured content mode, always; the transport carries opaque bytes.

The CloudEvents HTTP binding defines structured mode as keeping "event metadata and data
together in the payload, allowing simple forwarding of the same event across multiple
routing hops, and across multiple protocols"
([HTTP protocol binding](https://github.com/cloudevents/spec/blob/main/cloudevents/bindings/http-protocol-binding.md)).
That sentence is the transport-swap argument, from the primary source.

**The tradeoff this accepts:** no *broker-side* filtering. A consumer wanting one event type
receives all of them and discards the rest in-process. Free at hundreds-to-thousands of
events/day; stops being free around 100k/day with a consumer interested in under 10%.

### Which attributes exist to survive a transport swap

Stated explicitly, because the whole point of separating this ADR from the transport is that
this list has to be defensible on its own.

| Attribute | The transport difference it neutralizes |
|---|---|
| `id` (with `source`) | at-least-once vs "exactly-once" — the consumer dedups on `(source, id)` and behaves identically either way |
| `sequence` | ordering and gap detection, without depending on the transport's ordering guarantee |
| `type` | the routing model — dispatch happens on an in-payload field, not a subject/topic/routing key |
| `partitionkey` | the partitioning model — declared in the message, so a partitioned transport can be adopted later and an unpartitioned one ignores it |
| `time` | ordering, weakly — staleness and reconciliation, subordinate to `sequence` |
| `datacontenttype` | the payload encoding — one level below transport, same move |

**And precisely which do not.** `tenant` insulates a *data-model* change, not a transport
change. `correlationid`, `causationid` and `traceparent` are observability and lineage.
`specversion` versions the envelope format. Calling these transport insulation would be a
nice story and it would be false.

### Version lives inside `type`

No separate `version` attribute. The CloudEvents primer endorses this — producers "may
include version numbers (v1, v2) or dates in the `type` value," and `type` is "the primary
means by which consumers identify the type of event"
([primer](https://github.com/cloudevents/spec/blob/main/cloudevents/primer.md)).

### `source` is an absolute URI, and is frozen once a consumer exists

The spec's uniqueness guarantee is over `source` + `id`, and that pair is what a consumer's
dedup table keys on. A bare service token is a valid relative URI-reference but is not
globally unique, making the guarantee weaker than consumers will assume. **Changing `source`
after a consumer exists silently breaks deduplication rather than failing loudly** — so it
is frozen from the first consumer onward.

### Alternatives considered

- **Binary content mode** (attributes in transport headers, payload in the body) — rejected:
  it is precisely the coupling this contract exists to prevent. Every swap would rewrite the
  attribute-mapping layer in every consumer, in every language.
- **A separate `version` attribute** — rejected: forces two-dimensional filtering, and it is
  already built the other way across auth's eighteen events, so it costs a migration to buy
  nothing.
- **A bespoke envelope** — rejected: CloudEvents gives us registered extensions, existing
  SDKs in every target language, and a spec to point consumers at rather than documentation
  we maintain.
- **Deferring `sequence` until a consumer needs it** — rejected during the auth ADR-0019
  critic pass. A per-source ordinal is the cheapest defence against the single most-cited
  thing that leaks on a transport swap, and retrofitting it into a contract other services
  already consume is far more expensive than carrying it unused.

## Consequences

**Positive**

- The envelope is decidable, and revisable, without touching any transport decision — which
  is the P5 rule applied to the platform's own contract layer.
- Dispatch and dedup logic is portable across every transport in the candidate set.
- Registered extensions mean a generic CloudEvents SDK understands most of the envelope
  without project-specific code.

**Negative / cost**

- **`IDomainEvent`-equivalent interfaces need a subject/partition member.** `partitionkey` is
  REQUIRED once the Partitioning extension is in use, and at least one of auth's events
  (`LoginFailed`) has no subject id at all. Services must supply the `subject`-else-`tenant`
  rule from their own event interface — in auth's case a change to a layer with a strict
  zero-dependency purity rule.
- **Three attributes are project-local.** `tenant`, `correlationid` and `causationid` are not
  CloudEvents-registered; a consumer using a stock SDK will see them as unknown extensions.
- **`correlationid` and `causationid` are provably equal on every event emitted today**, and
  will be until a consumer emits events in reaction — service #3. Shipping two attributes
  that are always equal risks training the first consumer to treat them as interchangeable,
  which becomes a bug the moment they diverge. They are carried anyway because retrofitting
  lineage into a live contract is far more expensive than a redundant field, but the
  redundancy is real.
- **No broker-side filtering**, as above.
- **The enforcement §7 promises is still unwritten.** It becomes buildable once a service
  actually emits envelopes, and until then this contract has the same "declared but
  unverified" exposure that let the previous gap persist.

**Deferred**

- **`dataschema`.** *Trigger:* a schema registry exists, or a consumer wants codegen.
- **The §7 CI enforcement** (schema-validate emitted envelopes; assert `type` is versioned).
  *Trigger:* the first service emits real envelopes — i.e. auth ADR-0019's outbox landing.

## Revisit trigger

Reopen when **any** of these becomes true:

1. **A second service emits events** — the first moment this contract is tested by someone
   who did not write it, and the last cheap moment to change it.
2. **A consumer needs `causationid` to differ from `correlationid`** — the redundancy above
   stops being redundant, and the semantics must be pinned before they are relied on.
3. **A transport is adopted whose native metadata a consumer wants to read** — that is a
   request to abandon structured mode, and it should be an explicit decision, not a drift.
4. **A consumer filters to under 10% of a stream above 100k events/day** — the structured-mode
   filtering tradeoff stops being free.

## Confidence and open risks

**Confidence: medium.**

High confidence in structured mode, in version-in-`type`, and in the absolute-URI `source` —
each rests on a primary-source spec statement rather than a judgment call.

Lower confidence in the extension set. It is the costlier half of the original decision to
change, and it received **less** scrutiny than the transport during research: the ADR-0019
critic pass spent most of its blockers on the transport, which is the half designed to be
swappable. That asymmetry is the wrong way round and is recorded here rather than smoothed
over. The specific places it could bite: `partitionkey`'s `subject`-else-`tenant` rule is
asserted rather than validated against a real partitioned transport, and the two lineage
attributes are being shipped ahead of any consumer that needs them.
