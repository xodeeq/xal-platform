---
name: platform-service-conventions
description: The language-agnostic contract every xal service must satisfy. Consult whenever creating or modifying ANY part of this service — it defines the stable platform surface that makes services composable across languages.
---

# Platform service conventions

xal is a catalogue of independently versioned, **polyglot** microservices that a registry
and a composition frontend stitch together. That only works if every service — whatever
language it's written in — exposes the **same operational and contract surface**.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD PLATFORM CONTRACT.**

## The contract lives in the vendored platform spec

The authoritative §1–9 contract is the **vendored copy** of the platform spec at:

- **[`docs/platform/service-conventions.md`](../../../docs/platform/service-conventions.md)** —
  the operational + HTTP contract (health, telemetry, structured logs, trace propagation,
  container interface, versioned event envelope, domain purity, variation-behind-contract).
- **[`docs/platform/deployment-conventions.md`](../../../docs/platform/deployment-conventions.md)** —
  the deployment contract (runtime-as-code, migrations-as-release-step, secrets/fail-fast,
  health wiring, smoke gate, CD-from-main).

These are **read-only vendored copies** synced from the platform repo (see
`docs/platform/sync.config` for the pinned version; never edit them here — edit the spec in
the platform repo and re-run `platform-sync.sh`).

## How to use this skill

- **Building or modifying this service:** open the two docs above and treat them as the
  acceptance checklist. Each convention is stated language-agnostically, then cited to the
  **auth reference realization** — mirror the *intent* in this service's language, not the
  .NET specifics. Wire every **[CI-enforceable]** item into this service's gate/CI.
- **If a change would break an invariant** (the HTTP/event contract, health, trace
  propagation, the variation-invariant core): that's a **contract-version decision**, recorded
  as an ADR — not a quiet edit.
