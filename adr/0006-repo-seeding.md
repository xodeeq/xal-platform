---
type: adr
title: "Repo seeding: a new service repo begins with its gate"
status: accepted
created: 2026-09-15
updated: 2026-09-15
author: claude (drafted Decision-first for Sodiq); Sodiq (ruling)
service: platform
department: engineering
confidence: high
decision_date: 2026-09-15
open_risks:
  - "check-gate-inputs.sh reaches a seeded repo as a copy of this repo's vendored copy, which is itself a copy of the xcos-core canonical; cross-repo replica drift is still detected only agent-side"
  - "The seeded deploy.yml is dispatch-only, so the CD-from-main convention is satisfied in shape but not in trigger until a service has a deploy target"
  - "Seeding is a one-shot copy: a later improvement to scaffold/ does not reach an already-seeded repo, and nothing diffs them"
  - "Non-service repos (xal-site) are still unreached; this ADR closes the service half of the gap only"
tags: [seeding, scaffold, gates, ci, pipeline, track-b]
adrs:
  - "[Platform ADR-0001, platform repo structure and the template/sync model](0001-platform-repo-and-sync-model.md)"
  - "[xal-company ADR-0004, agent-definition distribution via plugins](https://github.com/xodeeq/xal-company/blob/main/docs/adr/0004-agent-definition-distribution.md)"
  - "[xal-company ADR-0005, gate inputs are declared data](https://github.com/xodeeq/xal-company/blob/main/docs/adr/0005-declared-gate-input-contract.md)"
  - "[xal-org ADR-0001, stack selection (the first consumer of scaffold/lang/go)](https://github.com/xodeeq/xal-org/blob/main/docs/adr/0001-stack-selection.md)"
---

# Platform ADR-0006: Repo seeding — a new service repo begins with its gate

- **Status:** Accepted
- **Date:** 2026-09-15
- **Deciders:** Sodiq

## Context

**The estate has a scissors.** From
[`xal-company/docs/lessons.md`](https://github.com/xodeeq/xal-company/blob/main/docs/lessons.md),
2026-08-18, recorded while comprehension-checking xal-company ADR-0005's largest residual:

> Getting a new repo to START with a gate has no mechanism. Two mechanisms exist for
> "every new repo begins with X" and neither reaches the case: **platform `sync/` +
> `scaffold/`** is a SERVICE-repo contract, and the scaffold ships no gate script anyway —
> an open item since platform session 02; **`xcos-core`**, which per ADR-0004 is installed
> by every xal repo "code or not", cannot ship an executable CI can run, because CI runs
> plain scripts and bootstrapping a plugin would itself be a new gate input. So the
> mechanism with the right scope has the wrong reach and vice versa. Adoption is a
> **seeding** problem, and seeding is the one step with no gate on it.

That entry routes its own fix to *"**ADR** (platform)"* and offers two options: extend the
scaffold and teach it to ship a gate script, or accept that `.xal/` is seeded by an
agent-side bootstrap and say so — *"acknowledging it is 'someone remembers', which is the
guardrail failure again."*

Three other records name the same gap from their own side. xal-company ADR-0005's
consequences list *"the repo never adopts it"* as the **largest** of the four things that
would have to be true for a fourth gate-input outage. xal-company
`docs/ops/xal-decisions-2026-09-01.md` §10 item 2 carries it as open and blocking:
*"nothing seeds a new repo with the gate … Blocks user-management; needs a platform ADR."*
And the pipeline roadmap
([`xcos-service-pipeline-roadmap-2026-09-09.md`](https://github.com/xodeeq/xal-company/blob/main/docs/ops/xcos-service-pipeline-roadmap-2026-09-09.md)
§2) calls it *"fatal for a pipeline whose first act is 'create the service repo'"* and
makes closing it session S2.

**Why it is urgent now rather than tidy-later.** The pipeline's design is that a spec
becomes a repo becomes a plan becomes N headless build sessions, each gated by a script
whose exit code decides pass. Every one of those decisions is the gate script's. A repo
created without one does not fail loudly; it runs the whole pipeline emitting green from a
gate that is not there. This is the estate's single most-repeated failure shape — a rule
that matches nothing and a rule that finds nothing emit byte-identical green — arriving at
the one step that precedes all the others.

**What exists to build on.** `scaffold/` already seeds the docs layout, the session-ritual
commands and an empty `docs/platform/` landing dir; `sync/platform-sync.sh` already
vendors the spec and detects drift; `scripts/check.sh` **gate 3 already gates scaffold
self-consistency** on every PR here. What is missing is a gate script, CI, the declared
input contract, the fixture pair, and a mechanism that puts a language-specific set of
those into a repo without someone assembling it from memory.

## Decision

### 1. The scaffold lives in `xal-platform`, and it is the existing `scaffold/` grown up

`xcos-core` is disqualified by its own distribution decision, not by preference.
xal-company ADR-0005 §Distribution: *"CI runs plain scripts, and a plugin is not resolvable
from a plain `run:` step"* — and making CI resolve one requires `claude plugin marketplace
add` + `claude plugin install` before the gate step, **which is itself a new gate input, in
every workflow, in every repo.** A seeding mechanism shipped from `xcos-core` would
reproduce the exact bug ADR-0005 exists to prevent. `xcos-core` also ships from **private**
`xal-company`, so a service build reaching it needs the credential xal-company ADR-0004
made this repo public to avoid.

`xal-platform` has the opposite profile: public, already the home of `scaffold/` and
`sync/`, already the thing a new service copies, and already gating its scaffold in CI.
The ledger entry's own option (a) is what this takes.

The scaffold is reorganised into three parts:

```
scaffold/
  common/            everything language-agnostic (the previous scaffold/ contents, moved)
  lang/<language>/   the language-specific overlay; go/ is the first
  seed-service.sh    the seeder: copy common, overlay lang, sync the spec, fill placeholders
```

This is breaking for `cp -r scaffold ../<service>` as documented in the old
`scaffold/README.md`. **No repo has ever been created that way** — auth predates the
scaffold and is the reference it was extracted *from* — so the blast radius is that README,
which is rewritten to point at the seeder.

**The seeder is plain bash with no inputs beyond the platform checkout it lives in**, the
same discipline as `platform-sync.sh` and for the same reason: a seeding step that can
need a toolchain is a seeding step that can be missing one.

### 2. `spec/` is not touched, and `VERSION` does not move

Stated as a decision because the alternative is the obvious one. Making "a service repo
carries these files" a `spec/service-conventions.md` obligation would be a minor bump,
0.5.0 → 0.6.0, and would put `xal-auth`'s gate 7 red on every merge until it re-vendored —
for a rule auth cannot retroactively satisfy, since auth was never seeded. Seeding is a
decision about **how a repo is created**, which is over before the service exists; the
conventions bind what a service **is**. So: ADR plus scaffold, `sync/manifest` unchanged,
no consumer re-vendors, auth untouched.

### 3. What a seeded repo contains on day one

| | Artifact | From |
|---|---|---|
| **Context** | `CLAUDE.md`, filled from the template, pointing at the vendored platform conventions **and carrying the status-file rule** — read `xal-company/status/current.md` first, every session, in any repo; update it in the same sitting; the `gh api` path for a headless run | `common/` |
| **Gate** | `scripts/check.sh` in **auth's gate order**, realized for the service's language | `lang/<language>/` |
| | `.xal/gate-inputs`, pre-declared for that language's inputs, so gate 0 is live from commit one | `lang/<language>/` |
| | `.xal/check-gate-inputs.sh`, copied from **this repo's own `.xal/`** — not a new copy (§7) | seeder |
| **CI** | `.github/workflows/ci.yml`, invoking `./scripts/check.sh` and nothing else, supplying every declared input, checking out `xodeeq/xal-platform` to `.xal-platform` for the drift gate | `lang/<language>/` |
| | `.github/workflows/deploy.yml`, the CD-from-main shape, **dispatch-only at seeding** (§6) | `lang/<language>/` |
| | `.github/workflows/claude.yml` and `claude-code-review.yml`, inert until the App is installed (§7) | `common/` |
| **Drift** | `docs/platform/` vendored and `sync.config` pinned, by the seeder running `platform-sync.sh`; the drift gate is the last gate, delegating to `$XAL_PLATFORM_DIR/sync/platform-sync.sh --check` | seeder |
| **Docs** | `docs/spec/`, `docs/plan/`, `docs/adr/` (index + template), `docs/lessons.md`, plus `docs/briefs/`, `docs/concepts/`, `docs/sessions/` | `common/` |
| **Fixtures** | `gates/check.test.sh` with a committed failing fixture and a clean one | `lang/<language>/` |
| **Build** | `Dockerfile`, linter config, the per-package coverage-floors file, `openapi.yaml` stub, `.gitignore`, `README.md`, `.claude/` | mixed |

`docs/spec/` and `docs/plan/` are seeded as real directories with a README each, not
created later by whoever first needs them. Roadmap §4.1 and §4.2 fix both paths; a path the
pipeline writes to is part of the seed.

### 4. The fixtures, and why they are not a gate inside `check.sh`

The standing rule is one committed fixture proving the rule fails, **asserting which rule
fired**, plus a clean fixture proving the gate can say yes. Applied to `check.sh` itself the
naive shape recurses — `check.sh` calling a harness that calls `check.sh`. So:

- `gates/check.test.sh` copies the repo to a temp dir, overlays one fixture over the copy,
  runs **that copy's** `scripts/check.sh`, and asserts both the exit code **and** the gate
  name in the output.
- It is invoked by **`ci.yml` as a separate step**, never from `check.sh`. Nothing recurses
  and nothing is carried without a caller.
- The Go realization ships two failing fixtures and one clean one. The first failing fixture
  trips an early, cheap gate deliberately, so the failing run is seconds. The second trips
  the **coverage-floors** gate, which is the only gate in the chain whose logic is
  hand-written rather than delegated to a tool, and therefore the only one that can be
  silently wrong in the way this estate has already been bitten by four times.
- Fixture source lives under `gates/_fixtures/`. The leading underscore is load-bearing:
  the Go tool ignores directories beginning with `_`, so a deliberately broken package
  cannot be picked up by `./...` in the repo's own real gate run.

### 5. Language-specific pieces come from the service's ADR-0001 — never from a default

```bash
scaffold/seed-service.sh --name xal-org --lang go \
    --adr docs/adr/0001-stack-selection.md --dest ../xal-org
```

- **`--lang` omitted is exit 2, not a default.** A default language is a stack decision
  taken by a script, and stack decisions are the human-gated per-service tool-selection
  layer's, recorded as that service's first ADR.
- **`--lang` naming a directory that does not exist under `scaffold/lang/` is exit 2**,
  listing what does exist. Adding a language is a PR adding `scaffold/lang/<name>/` with the
  full artifact set, and §6's gate refuses a partial one.
- The seeder writes **`.xal/seed.config`** recording the language, the ADR path it was told
  to cite, the platform `VERSION` pinned and the date — so "why is this repo Go?" resolves
  to a decision record, in the repo, mechanically.

### 6. Two changes to this repo's own `check.sh`

- **A new rule, `scripts/check-seed-set.sh`:** every directory under `scaffold/lang/` ships
  the full required artifact set, and `seed-service.sh` refuses a missing or unknown
  `--lang`. It ships with `gates/seed.test.sh` and committed fixture language sets — one
  per rule, each proving that rule fails and no other, plus a clean one. Without this,
  "the scaffold ships a gate script" is a claim; this repo's whole ledger says not to accept
  one.
- The rule and its fixture harness are **two gates** in `scripts/check.sh`, matching the
  pairing xal-company already uses. Both need only bash, grep, sed and find, so
  `.xal/gate-inputs` does not change and gate 0 stays green.

**One deviation, stated rather than smuggled.** `deployment-conventions.md` says the deploy
workflow triggers on push-to-`main` plus dispatch. A freshly seeded repo has no deploy
target, and the Fly overdue-invoice 403 (xal-org spec H-13) blocks every deploy in the
estate. Seeding a push-triggered `deploy.yml` would manufacture a red `main` on every merge
from commit one, which is how a signal becomes one everyone learns to ignore. The seeded
`deploy.yml` is therefore **`workflow_dispatch`-only, with the push trigger commented in
place** and a comment naming the two human-only actions that un-comment it.

### 7. Human-only at creation

P6's line is blast radius, not difficulty.

| Action | Who | Why |
|---|---|---|
| `gh repo create xodeeq/<name> --private`, the initial push, branch protection, opening the first PR | **agent** | reversible — the repo can be deleted, and private means nothing is published |
| **Installing the Claude GitHub App on the new repo** | **Sodiq** | granting a third party access to a repo. P6 names granting access explicitly, and it is not scriptable: the App install is a GitHub UI grant |
| **Setting `CLAUDE_CODE_OAUTH_TOKEN` as a repo secret** | **Sodiq** | a credential. `gh secret set` exists; the token is his to mint |
| Making the repo public | **Sodiq** | publishing; irreversible in effect |
| Provisioning the database, production secrets, first deploy approval | **Sodiq** | already recorded as the service's own human-only actions |

The seeder therefore goes as far as `git init` and one commit — a pushable tree — and then
**stops and prints the human-only list**, rather than reporting success over a repo whose
`claude.yml` is committed and silently non-functional. Those
two workflows are committed **at seeding** precisely so the App install has something to
activate — an inert workflow waiting on one grant, not a missing file waiting on someone
remembering.

## Rejected alternatives

**A GitHub template repository.** The shape everyone reaches for, and it fails on three
counts. It is a **second** source of truth for content that already lives in `scaffold/` —
the duplication this repo exists to stop — and nothing would diff them. It cannot take a
parameter, so "Go or .NET" becomes N template repos multiplying on every change to the
common part. And a template repo is **not gated**: `scripts/check.sh` gate 3 checks this
scaffold on every PR, while a template repo's contents are checked by nothing, which is
exactly how one comes to ship a gate script that no longer runs.

**Copying `xal-auth` by hand.** This is the status quo, and it is what produced the gap. It
carries .NET into a Go repo, and it requires the copier to know which of auth's root files
are platform contract and which are auth's own — the judgement xal-company ADR-0005 already
showed is satisfied ambiently and therefore unreliable. It also leaves no artifact saying
what a seeded repo *should* contain, so a missing file stays invisible.

**A generator in `xcos-core`.** Right reach (every repo, code or not), wrong mechanism —
§1. A plugin cannot ship an executable CI can run without becoming a gate input in every
workflow in every repo, and it ships from a private repo, so reaching it in a service build
needs the credential ADR-0004 was built to eliminate. The mechanism with the right scope has
the wrong reach and vice versa, which is precisely what the ledger entry said; this ADR
resolves it by giving the right-scope mechanism the missing reach, not by giving the
right-reach one an executable it cannot carry.

## Consequences

**Positive — the gap closes with a checkable property, not a promise.** After this, "a new
service repo has a gate" is decided by `scripts/check-seed-set.sh` on every PR here, and
"that gate can actually fail" is decided by the seeded repo's own `gates/check.test.sh` on
every PR there. Both are mechanical. Neither is "someone remembers", which is what the
ledger entry said the alternative amounted to.

**Positive — platform session 02's open item closes with it.** "The scaffold ships no gate
script" and "nothing seeds a new repo with the gate" were one item seen from two repos.

**Positive — the second language arrives as data, not as a rewrite.** Adding .NET, Rust or
TypeScript later is a PR adding one directory under `scaffold/lang/`, and the new gate
refuses it until it is complete.

**Cost — seeding is a one-shot copy, and this ADR does not change that.** A later
improvement to `scaffold/lang/go/check.sh` does not reach an already-seeded repo, and
nothing diffs them. That is the same exposure `sync/` was built to close for `spec/`, and the
honest reading is that the gate script is a *starting point* a service then owns, while the
*spec* is a contract a service continues to track. Extending `sync/` to cover the gate
script would mean a service could not adapt its own gate, which is worse. Recorded as an
open risk rather than solved.

**Cost — the `check-gate-inputs.sh` copy is now third-order.** Canonical in `xcos-core`,
vendored into this repo, and copied from that vendored copy into each seeded repo.
Seeding from this repo's own copy rather than adding a **new** copy inside the scaffold
keeps the count at one per repo and adds no replica pair, but cross-repo drift between them
is still detected only agent-side — already the open residual in xal-company ADR-0005's
2026-09-15 addendum, *"tracked on the board, not built"*. This ADR names it and does not
claim to close it.

**Scope, stated.** This closes the gap for **service** repos. `xal-company` already has its
own `check.sh` and is deliberately not a scaffold consumer; `xal-site` remains unseeded and
unreached. That half of the 2026-08-18 entry stays open and says so.

## Revisit triggers

1. A second language is added to `scaffold/lang/` and the split between `common/` and
   `lang/` turns out to be in the wrong place — most likely candidate is `ci.yml`, which is
   language-specific today but mostly boilerplate.
2. A seeded repo's `scripts/check.sh` diverges far enough from the scaffold's that the
   scaffold stops being a useful starting point; the answer is to re-extract, not to sync.
3. The pipeline's driver (roadmap S5) needs to seed a repo unattended, and the human-only
   stop in §7 becomes the thing that blocks a run rather than the thing that protects it —
   the response is to batch the App install into the plan-approval gate, not to remove it.
4. A non-service repo needs a gate seeded and §Scope's honesty becomes a live cost.
