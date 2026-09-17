---
type: adr
title: "The .claude/ sync boundary: a plugin-distributed normative core plus a service-owned overlay"
status: accepted
created: 2026-09-17
updated: 2026-09-17
author: claude (drafted Decision-first for Sodiq); Sodiq (ruling)
service: platform
department: engineering
confidence: high
decision_date: 2026-09-17
open_risks:
  - "Per-repo version pinning does not work: ~/.claude/plugins/known_marketplaces.json is keyed by marketplace name globally, last-write-wins, so a plugin change reaches every repo on a machine as soon as any one of them updates. Until that is fixed, additive-only is the only change shape with a known blast radius"
  - "Nothing detects overlay drift. A repo that reimplements a core behaviour locally instead of consuming the plugin is caught by review, not by a gate"
  - "The boundary is stated as a test, not enforced by one: no check asserts that a file in the overlay could not have been shared"
tags: [claude-config, plugins, sync, subagents, distribution]
adrs:
  - "[Platform ADR-0001, platform repo structure and the template/sync model](0001-platform-repo-and-sync-model.md)"
  - "[Platform ADR-0006, repo seeding](0006-repo-seeding.md)"
  - "[xal-company ADR-0004, agent-definition distribution via plugins](https://github.com/xodeeq/xal-company/blob/main/docs/adr/0004-agent-definition-distribution.md)"
  - "[Platform ADR-0008, marketplace sources are remote and pinned](0008-marketplace-sources-are-remote.md)"
---

# Platform ADR-0007: The `.claude/` sync boundary — a plugin-distributed normative core plus a service-owned overlay

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Sodiq

## Context

`sync/manifest` covers `spec/` → `docs/platform/` and **nothing else**. Everything under
`scaffold/.claude/` — skills, `/begin-session`, `/wrap-session` — is a one-time `cp -r` at
service creation that `--check` never inspects. From
[`docs/lessons.md`](../docs/lessons.md), 2026-08-12:

> It will therefore drift silently and permanently across auth and `xal-registry-api` — and
> it is already drifting: auth's `.claude/commands/wrap-session.md` and `begin-session.md`
> restate the ritual that `spec/session-ritual.md` now owns canonically, with no mechanism
> to notice when the two disagree.

That entry named three options — (a) extend the sync model to cover `.claude/`, (b) split
into a synced normative core plus an explicitly service-owned overlay, or (c) accept the
drift deliberately and say so — and required whichever won to be recorded as a **platform**
ADR, because it binds every service.

**Two things have happened since, and neither removed the need for this record.**

First, XCOS §6.2 proposed adding `.claude/agents/` — `implementer`, `test-writer`,
`contract-reviewer`, `docs-writer` — "in each service repo". That bypasses ADR-0001
entirely: per-repo agent definitions are exactly the copy-paste drift the platform repo
exists to stop. `xal-company/CLAUDE.md` has forbidden creating those four ever since,
naming *this* ADR as the thing they wait on.

Second, [xal-company ADR-0004](https://github.com/xodeeq/xal-company/blob/main/docs/adr/0004-agent-definition-distribution.md)
took option (b) on 2026-08-15 and built it: this repo became a marketplace, `xal-platform-conventions`
ships from it, and auth consumes the plugin instead of holding its own copy
([xal-platform#5](https://github.com/xodeeq/xal-platform/pull/5)). ADR-0006 then ruled the
adjacent question in the same direction — seeded files are **owned**, not synced.

So the decision is, in practice, already made and already load-bearing. What does not exist
is the platform-level record of it. **That gap is not cosmetic.** A service-repo ADR binds
one repo; this binds every repo, including ones not yet created. And a standing prohibition
in `xal-company/CLAUDE.md` currently cites an ADR that does not exist — the estate's own
standing rule for that shape is *"citing a gate is not having one"*, and a rule whose
authority is a missing document is the same defect wearing different clothes.

## Decision

**Option (b): a synced normative core, distributed as a Claude Code plugin, plus an
explicitly service-owned overlay.** `sync/manifest` is **not** extended to cover `.claude/`.

The boundary is the duplication test this estate already uses, and it is the same one in
`xal-company/CLAUDE.md` — do not invent a second:

> **If a definition would be byte-identical in the next repo, it belongs in a plugin. If it
> encodes something true only of this repo, it stays in that repo's `.claude/`.**

Applied:

| Plugin-distributed core (shared, one-way) | Service-owned overlay (local, owned) |
|---|---|
| the session ritual, concept-note discipline, `/explain` (`xcos-core`) | the repo's `CLAUDE.md` — bounded context, stack, ADR index |
| the language-agnostic service conventions (`xal-platform-conventions`) | the gate command a ritual step invokes, and language-specific patterns |
| language-agnostic subagents | language-specific subagents |

**Sync is one-way.** Shared behaviour changes by a PR against the marketplace repo, never by
editing an installed copy. **`scaffold/.claude/agents/` is where a shared agent definition
goes**, and a service repo never holds its own copy of one.

**Consequence for the four blocked subagents.** `implementer`, `test-writer`,
`contract-reviewer` and `docs-writer` are unblocked *as a distribution question*: when they
are written they arrive as plugin-distributed definitions. Two of them are expected to split
by language rather than being forced together — a .NET `test-writer` and a Go one are not the
same file, and merging them yields an agent mediocre in both. **This ADR says what they may
be, not that they should be written now**; they remain board items.

### Alternatives considered

**(a) Extend `sync/manifest` to cover `.claude/`.** Rejected. It needs a second manifest or
destination paths, plus a rule for the parts a service legitimately customizes — auth's
`/wrap-session` names `scripts/check.sh` and its own grep, which a Rust service must not
inherit verbatim. More decisively, **a file copy has no version identity.** A marketplace
gives pinning and an explicit update step; `cp -r` gives neither, which is how the drift this
ADR answers started. Extending the copy mechanism would have scaled the failure, not fixed it.

**(c) Accept the drift and say so.** Rejected, but it deserves its due: it is honest, it is
free, and it would have removed the false assurance that `--check` covers `.claude/`. It was
rejected because the drift is not benign — two statements of the session ritual that disagree
is a correctness problem in the thing that governs every session, not an untidiness. Option
(c) remains the right answer for anything genuinely per-repo, which is what the overlay is.

**A fourth, considered and rejected on the way: make `xcos-core` the seeding mechanism.**
ADR-0006 disqualified it — a plugin is not resolvable from a plain CI `run:` step, so that
would add a gate input to every workflow in every repo. Recorded here because "distribute it
as a plugin" and "seed it from a plugin" look alike and are not.

## Consequences

- **Positive.** One statement of every shared behaviour, changed by PR with a reviewable
  diff. Version identity and an explicit update step, which a `cp -r` never had. The
  `xal-company/CLAUDE.md` prohibition now cites a record that exists, and the four subagents
  are unblocked as a distribution question. ADR-0006's "seeded files are owned" and this
  ADR's overlay are one rule, not two.
- **Negative / cost.** Two distribution channels to keep straight, and the boundary is a
  **judgement call on every new file** — the duplication test is stated, not gated. Consuming
  a plugin costs a marketplace registration and an install step per repo, which is real setup
  a copy did not need, and which ADR-0008 constrains further. A shared change now requires a
  release, a tag and an update in each consumer; a copy could be edited in place, which was
  faster and is exactly the speed being given up on purpose.
- **Negative, and the sharpest one.** **Per-repo pinning does not currently work.**
  `known_marketplaces.json` is keyed by marketplace *name* globally, last-write-wins — two
  repos pinned to `xcos-core` 0.1.0 and 0.1.1 both resolved 0.1.1, silently (probe recorded
  in xal-company session 03). ADR-0004 §5's claim that a breaking change "must not land in
  every repo at once" is therefore asserted and **untrue today**. Until it is fixed, treat
  every shared-plugin change as estate-wide on this machine, and ship **additive changes
  only** — not as a style preference but because additive is the only change shape whose
  blast radius is known.
- **Deferred.** (1) A gate for the boundary itself: nothing asserts that an overlay file
  could not have been shared. *Trigger:* the second time review catches a local
  reimplementation of a core behaviour. (2) Real per-repo pinning; `ref` is a recognised
  field on a marketplace `source` entry and is the most likely route, untested. *Trigger:* a
  shared change that genuinely must break. (3) The four subagents themselves. *Trigger:*
  their board items, not this ADR.
