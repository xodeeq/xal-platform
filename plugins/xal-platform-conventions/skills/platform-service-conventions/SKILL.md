---
name: platform-service-conventions
description: The language-agnostic contract every xal service must satisfy. Consult whenever creating or modifying ANY part of a service repo — it defines the stable platform surface that makes services composable across languages.
---

# Platform service conventions

xal is a catalogue of independently versioned, **polyglot** microservices that a registry
and a composition frontend stitch together. That only works if every service — whatever
language it's written in — exposes the **same operational and contract surface**.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD PLATFORM CONTRACT.**

## The contract lives in this service's vendored spec

Every xal service vendors a read-only copy of the platform spec into its own
`docs/platform/`. The authoritative §1–9 contract for the repo you are working in is:

- **`docs/platform/service-conventions.md`** — the operational + HTTP contract (health,
  telemetry, structured logs, trace propagation, container interface, versioned event
  envelope, domain purity, variation-behind-contract).
- **`docs/platform/deployment-conventions.md`** — the deployment contract (runtime-as-code,
  migrations-as-release-step, secrets/fail-fast, health wiring, smoke gate, CD-from-main).

Those paths are deliberately written as repo-relative text rather than links: this skill is
distributed as a plugin to many repos, and a link from the plugin's own directory cannot
reach the consuming repo's files.

`docs/platform/sync.config` records which platform spec version this service is pinned to.

## The read-only rule

The files under `docs/platform/` are **vendored copies** and must never be edited in place.
Byte-identity with the platform spec is not a nicety — it is the enforcement mechanism,
because the drift check is a plain diff. A local edit cannot be reconciled; it only holds
the gate red.

To change a convention: change it in
[`xal-platform/spec/`](https://github.com/xodeeq/xal-platform/tree/main/spec), bump that
repo's `VERSION` per its policy, then re-sync here and review the diff. This is one-way:
the platform is upstream of every service, always.

## Auth is the reference realization

The §1–9 document states each convention language-agnostically, then cites the **auth**
service's .NET implementation as one worked example. Mirror the *intent* in this service's
language, never the .NET specifics. If a rule can only be expressed in one language's
terms, it is not a platform rule yet.

## How to use this skill

- **Building or modifying a service:** open the two documents above and treat them as the
  acceptance checklist. Wire every **[CI-enforceable]** item into this repo's gate script
  and CI.
- **When you change code a convention cites:** re-read the rule and confirm it still holds.
- **If a change would break an invariant** — the HTTP or event contract, health, trace
  propagation, the variation-invariant core — that is a **contract-version decision**
  recorded as an ADR, not a quiet edit.
