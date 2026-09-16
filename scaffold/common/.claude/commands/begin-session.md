---
description: Start-of-session ritual — load the latest handoff and any forward brief, restate this service's standing laws, surface open decisions, confirm a clean baseline, frame the next slice, and delete the consumed brief once the plan is approved.
argument-hint: "(no args)"
allowed-tools: Bash, Read, Grep, Glob
---

# /begin-session

The symmetric counterpart to `/wrap-session`. Run **before** touching code so you start
grounded instead of reconstructing state from the codebase.

> **The canonical procedure is `docs/platform/session-ritual.md`** (the vendored platform
> spec) → "Begin a session". Follow it; this command is the launcher. Do the steps in
> order; don't jump to planning until the slice is framed.

## Steps (in order)

1. **Load the latest handoff** — open the highest-numbered `docs/sessions/NN.md` and read
   it fully (what the last session did, the concrete next step, open questions). Then read
   any advisory brief in `docs/briefs/` as *input to deliberation, not a spec*.
2. **Internalize this service's standing laws** from `CLAUDE.md` — its testing discipline,
   structural/dependency rules, "ask before deviating from an ADR", and the gate command.
   Restate them; don't rediscover them.
3. **Check the open design decisions** — `CLAUDE.md` → "Open design decisions" and any ADR
   marked Proposed/Open. If the slice touches one, settle scope before planning.
4. **Confirm a clean baseline:**
   ```bash
   git status -s && git branch --show-current
   git log --oneline -5
   gh pr list --state open --limit 10 2>/dev/null || echo "gh unavailable"
   ```
5. **Frame the slice, then proceed** — one coherent concern, the layers it touches, the
   open decisions it depends on. Settle real scope forks with the user before writing code.
6. **Once the plan is approved, delete the consumed brief** (`git rm docs/briefs/<topic>.md`).
   Anything worth keeping graduates to the plan, an ADR, or `docs/lessons.md`.

A session is "begun" only when: the latest handoff (and any brief) is read · the standing
laws are restated · open decisions on the path are surfaced · the branch/PR baseline is
known · the slice is framed · the consumed brief is deleted once the plan is approved.
