---
type: adr
title: "The service-to-service feed credential"
status: accepted
created: 2026-09-14
updated: 2026-09-15
author: Spec Lab (drafted for Sodiq); Sodiq (ruling O-1, option (a), 2026-09-15)
service: platform
department: research
confidence: medium
decision_date: 2026-09-15
open_risks:
  - "The composition engine does not exist yet; until it does, generation, rotation and revocation live in each publisher's provisioning script and must be lifted, not duplicated, when the engine lands"
  - "Private-network reachability of feeds is asserted for Fly (6PN); a unit on another host has only TLS + credential, which is still sufficient but must be verified per host"
  - "A leaked credential grants read of one feed in one deployment until revoked; detection depends on the per-credential metrics being watched"
  - "The credential is tenant-agnostic by construction; a second tenant in one deployment is a revisit trigger, not a supported case"
tags: [events, transport, credentials, composition, security]
adrs:
  - "[Platform ADR-0002, the domain-event envelope contract](0002-domain-event-envelope-contract.md)"
  - "[Platform ADR-0004, async-first interaction between services](0004-async-first-interaction-model.md)"
  - "[Auth ADR-0019, event transport](https://github.com/xodeeq/xal-auth/blob/main/docs/adr/0019-event-transport.md)"
  - "[xal-org spec 1.0.0 §5, FR-33, FR-34, FR-36](https://github.com/xodeeq/xal-company/blob/main/specs/admitted/xal-org/1.0.0.md)"
---

# Platform ADR-0005: The service-to-service feed credential

- **Status:** Accepted
- **Date:** 2026-09-14; revised 2026-09-15 on ruling O-1 (xal-org spec §9)
- **Deciders:** Sodiq (platform architect). Option (a) chosen 2026-09-14; terms fixed and
  **accepted 2026-09-15** (ruling O-1, with the consumer-on-401 addition in decision 5)
- **Satisfies:** auth ADR-0019 condition 2 ("the machine-to-machine credential ADR lands
  before the feed is built") and closes its blocking risk W1
- **Amends:** `spec/service-conventions.md` §7 (a new "Feed authentication" paragraph and
  enforce line); `VERSION` 0.4.0 → 0.5.0
- **Consumed by:** every publisher of a `GET /events` feed (auth, xal-org, xal-onboarding,
  xal-notify) and every consumer of one; realized in xal-org by FR-33, FR-34, FR-36, FR-78
  and ADR-0001 decision 6

> **Provenance.** Drafted as the xal-org spec's companion document (2026-09-14) and landed
> verbatim in PR #11. Revised 2026-09-15 to carry ruling O-1's terms, per-consumer
> revocation, human-gated rotation until the registry exists, the rate-limit keying, the
> registry consequence, and the two revisit triggers ruling O-1 requires, and **accepted**
> on that ruling with one addition Sodiq made at acceptance: consumer behaviour on 401
> (decision 5). Section order follows `spec/adr-template.md`; the Decision was presented
> first for approval.

## Context

Auth ADR-0019 chose a transactional outbox served as a cursor-paged HTTP pull feed and
recorded as its first blocking risk that "auth has no machine-to-machine credential; the
feed cannot be authenticated without one — its own ADR, must land first" (W1). It framed the
question with bounded-context weight: does auth own service identities, and where would a
new credential type sit in the ADR-0003 flag table? Condition 6 (R1) requires the feed to
ship with per-credential rate limiting from day one, which presupposes an identity per
consumer.

What has changed since it was written:

- **There is a second publisher.** xal-org (spec 1.0.0) emits its own feed and consumes
  xal-onboarding's; xal-onboarding and xal-notify consume from B2. The credential is an
  estate-wide contract, and ADR-0019's revisit trigger 4 ("a second publisher appears") has
  fired.
- **Deployments are per client.** Clients deploy a selected set of units behind a gateway;
  the composition engine will generate each composed solution's manifest, reconcile script
  and modules (deployment-conventions). Secrets are already set by the reconcile script and
  live only in the platform store. A credential generated at composition time fits that
  model with nothing new.
- **Async-first (ADR-0004) defines the feed poll as the event dependency itself**, a read
  one hop deep, and requires every edge to be declared in the registry. The credential is
  what makes a declared edge the only edge.
- **The cursor is tenant-scoped by ADR-0019** (`(tenant, seq)`, resolving to `default`), but
  every deployment today is single-tenant. The credential is scoped to the deployment, not
  to a tenant, and says so.

The counter-argument on record (xal-company PR #5): "Conditions 2 and 6 favour a broker. A
managed broker supplies its own credential, removing the W1 blocker the feed creates; and
pushing moves the read surface off the login-critical-path service." It is weighed under
alternative (c) and is the path this decision is designed to stay compatible with.

Scale, stated honestly: at B3 the estate has three feed edges in one deployment
(onboarding → org, org → onboarding, notify → onboarding). This decision plans for tens of
edges per deployment, not thousands.

## Decision

1. **One credential per (consumer, publisher) pair, per client deployment.** Every
   `GET /events` feed is protected by a feed credential identifying exactly one consumer
   unit to exactly one publisher unit inside one deployment: a random secret of at least
   256 bits, generated by the composition engine when it produces a composed solution;
   until the engine exists, by a step in the publisher's idempotent reconcile-first
   provisioning script (deployment-conventions Pattern A). No dependency on xal-auth: no
   grant, no service account, no row in the ADR-0003 flag table, no call to auth on any
   poll. W1's question, whether auth owns service identities, is answered "not now":
   service identity is a composition concern.
2. **Hashed at rest on the publisher; constant-time compare on every poll.** The consumer
   holds the plaintext as `XAL_FEED_CREDENTIAL__<publisher>`. The publisher holds
   `XAL_FEED_ALLOWLIST`: one line per consumer, `consumer-name sha256hex[ sha256hex]`, the
   optional second hash present only during rotation. The publisher hashes the presented
   bearer, compares in constant time against every listed hash, and resolves the match to
   the consumer name (xal-org: `crypto/subtle.ConstantTimeCompare` over SHA-256, ADR-0001
   decision 6; auth: `CryptographicOperations.FixedTimeEquals`). Anything else is 401. A
   publisher with `feed=on` and no allow-list fails fast at boot (xal-org FR-78). Nothing
   plaintext is stored on the publisher; nothing is written to a manifest, Terraform, its
   state or a repo.
3. **Scope is `GET /events`, nothing else.** Presented as `Authorization: Bearer <secret>`
   on the feed only; rejected on every other route; xal-auth access tokens rejected on the
   feed. The feed is not routed through the deployment's gateway; consumers reach publishers
   over the deployment's private network; the credential travels only over TLS.
4. **The resolved consumer name keys rate limiting and metrics.** The per-credential request
   cap and the concurrency cap of 1 (ADR-0019 R1; xal-org FR-34) key on it and return 429 on
   breach; `feed_distinct_clients` and `feed_consumer_lag_seq` (FR-36) are labelled by it.
   The consumer registry stays observed, not declared.
5. **Revocation is per consumer, and a consumer treats 401 as revocation.** Removing one
   consumer's line from a publisher's allow-list revokes that consumer alone on the next
   reconcile: its polls return 401, every other consumer is unaffected, and its persisted
   cursor survives so a re-issued credential resumes without loss inside the retention
   window. **On a 401 from a feed, the consumer's poller stops that feed, increments a
   metric that alerts on first occurrence, and does not resume until the credential is
   re-issued and the process restarted.** A 401 is a revocation or a mis-issued credential,
   never a transient error: retrying or backing off against it hides the revocation, burns
   the publisher's per-credential rate limit (decision 4) and leaves the consumer silently
   behind. Only the feed that returned 401 stops; the same consumer's other feeds are
   unaffected, and the cursor is left where it stood so the restart resumes from it.
6. **Rotation is a two-pass composition action, gated by a human until the registry
   exists.** Pass one adds the new hash beside the old and delivers the new plaintext to the
   consumer; pass two removes the old hash. Either pass is idempotent; no downtime. Rotation
   on suspicion is immediate and human-triggered; scheduled rotation is deferred. Until
   D-29's registry lands, issuance, rotation and revocation are operator actions through the
   provisioning script (P6: granting access stops and waits, however small).
7. **When the registry lands, the allow-list is derived, not written.** A publisher's
   allow-list becomes exactly the set of consumers whose registry entries declare an event
   dependency on it; the composition engine generates credentials from those declarations;
   an undeclared consumer has no credential and cannot poll (§9's honesty rule, enforced at
   the credential level). Edge declaration becomes promotable to [CI-enforceable] (ADR-0004
   revisit trigger 3); issuance and rotation become mechanical steps of composition, and the
   human gate moves to the registry change that adds or removes the edge.
8. **`spec/service-conventions.md` §7 gains the obligation** (text in this PR) and each
   publisher ships three request tests with committed failing fixtures: valid credential
   200, unknown credential 401, auth access token 401; and each consumer ships one
   test for decision 5's 401 behaviour — a 401 stops that feed's poller, increments the
   alerting metric, and no further poll is issued without a re-issued credential and a
   restart. `VERSION` bumps minor.
9. **This is not a general service identity.** An authenticated call between units that is
   not a feed poll is revisit trigger 1, a new decision, not an extension of this one.

### Alternatives considered

**(b) A client-credentials grant issued by xal-auth (RFC 6749 §4.4).** Each unit holds a
client id and secret, obtains a short-lived JWT with `sub` = the unit, and publishers verify
it offline against auth's JWKS. Real advantages: one identity system, offline verification,
rotation by key rotation, an audit trail in auth. Rejected, for the four reasons W1
anticipated: it is a new capability in auth, outside ADR-0019's estimate, that must be
placed in the ADR-0003 flag table; it makes auth a runtime dependency of every feed poll
(token acquisition and refresh in every consumer, in every language) where ADR-0019's aim
was that validation survives auth being down; it gives auth ownership of service
identities, a bounded-context decision the estate has not needed to make; and it couples
the composition engine to auth's client registry, so a composed solution cannot be
generated without a live auth to register clients in. Deferred with a trigger, not closed.

**(c) A broker-supplied credential (PR #5).** Under a managed broker each deployment gets a
broker account and per-client credentials, publishers stop serving a read surface, and both
W1 and the login-critical-path concern behind R1 disappear by construction. Rejected here
only because it reopens ADR-0019, which the hold ruling and xal-org spec §6.6 decline to do
at two publishers and three edges. Forward-compatible: under (c) the problem becomes "a
secret generated at composition time and injected per unit", which is the same shape as
(a); the consumer-side polling code changes, the secret distribution does not.

**(d) Mutual TLS between units.** Strongest binding of identity to transport. Rejected for
now: per-deployment certificate provisioning and rotation is infrastructure a solo operator
would run, and the deployment's private network already provides transport isolation.
Deferred (trigger: a compliance requirement), consistent with review 0.1's mTLS deferral.

**(e) No authentication on the private network.** Rejected. R1 requires per-credential rate
limiting, which needs an identity; registry honesty for feed edges needs one; a private
network is a boundary, not an authorization.

**(f) One shared secret per deployment.** Simpler to distribute; rejected because it cannot
key per-consumer limits, lag metrics or revocation, and a leak grants every feed to every
holder.

## Consequences

**Positive**

- No new infrastructure and no change to auth's bounded context; W1 closes; condition 2 is
  met once this ADR is Accepted.
- R1 and ADR-0019's metric-based revisit triggers get their identity for free.
- Per-consumer revocation with cursor preservation: a compromised or retired consumer is cut
  off without touching any other and without losing its place.
- Registry honesty becomes enforceable for feed edges once D-29 lands: no declaration, no
  credential.
- Forward-compatible with a broker (c): the same composition-time secret shape.
- Secrets follow deployment-conventions unchanged: platform store only, set by the reconcile
  script, never in manifest, state or repo; hashed at rest on the publisher side.
- xal-org's `feed` flag can move to `on` when this ADR is Accepted; FR-33 has its
  definition.

**Negative / cost**

- **Edges multiply secrets.** N consumers × M publishers per deployment, each a rotation
  item; three at B3. The composition engine must own generation to keep this mechanical.
- **The composition engine does not exist yet.** The interim lives in each publisher's
  provisioning script, is on B2's critical path (xal-onboarding cannot be tested end to end
  without credentials on both feeds), and is the part most likely to be done twice.
- **Rotation and revocation are human-gated operator actions until the registry exists**,
  and there is no scheduled rotation until the trigger below.
- **A leaked secret grants one feed in one deployment** until revoked; detection relies on
  the per-credential metrics being watched.
- **The credential is deployment-scoped, not tenant-scoped.** A consumer holding it can
  read every tenant's events on that feed. Correct while every deployment is single-tenant;
  a revisit trigger otherwise.
- **Consumers still hand-write polling** (ADR-0019); this decision adds one header and one
  secret to that code.

**What changes when D-29's registry lands**

- The allow-list is derived from event-dependency declarations (decision 7); a publisher no
  longer receives a hand-written list.
- Issuance and rotation are generated by composition from the registry; the human gate is
  the registry change that adds or removes an edge, not each secret.
- Edge declaration is promoted to [CI-enforceable] under ADR-0004 trigger 3; a consumer
  polling a feed it has not declared is a red gate before it is a 401.
- The registry records, per edge, the credential's issue date and rotation state, which is
  where scheduled rotation lives when its trigger fires.

**Deferred, with triggers**

- **Client-credentials grant in auth (b).** Trigger: a unit needs an authenticated call to
  another unit that is not a feed poll, or an external consumer (below) is admitted.
- **Scheduled rotation.** Trigger: first real client data in a deployment; until then, rotate
  on suspicion.
- **mTLS (d).** Trigger: a compliance requirement.
- **Tenant-scoped credentials.** Trigger: revisit trigger 2 below.

## Revisit trigger

Reopen when any of these becomes true:

1. ADR-0004's trigger 1 or 2 fires (a two-hop sync edge, or a sync write): a real service
   identity is needed and (b) returns.
2. **A second tenant is provisioned in one deployment.** The credential is
   deployment-scoped and the feed's cursor is `(tenant, seq)`; a consumer must then be
   limited to the tenants it serves, which means either tenant-scoped credentials or
   per-credential tenant filters enforced by the publisher. Neither exists; this is a new
   decision.
3. **Any external consumer.** A consumer outside the deployment (a client's own system, a
   partner, a third-party integration) asks to poll a feed. This credential is not for third
   parties; that is (b), a public API product, or a broker.
4. ADR-0019's trigger 3 fires (`feed_distinct_clients` reaches 3 on any feed) or a broker is
   adopted: move to the broker's credential model (c).
5. Edges per deployment exceed what one reconcile pass can rotate without downtime.
6. The registry lands (D-29): confirm decision 7's derivation replaced the hand-written
   allow-list everywhere; this is a fulfilment addendum, not a reopening, unless the registry
   model cannot express it.

## Confidence and open risks

**Confidence: medium.** High confidence that a composition-time secret is sufficient for
feed reads at this scale, that per-consumer revocation and two-pass rotation are correct as
stated, and that nothing in auth changes. Lower confidence in the interim distribution path,
which lives in provisioning scripts until the composition engine exists.

Open risks are listed in the frontmatter.
