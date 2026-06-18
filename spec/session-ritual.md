# The work-session ritual

xal is built in **deliberate, gated work sessions**: each session takes **one coherent
concern**, and every session opens and closes with a fixed ritual so the next session
(human or agent) can pick up cold. This is a core part of how the platform stays
learnable and how state survives across sessions — it is not optional ceremony.

The ritual is realized as two commands in every repo — **`/begin-session`** and
**`/wrap-session`** (under `.claude/commands/`) — plus three durable artifacts:
`docs/sessions/NN.md` (handoffs), `docs/briefs/` (ephemeral forward briefs), and the
repo's `docs/lessons.md` (continuous-improvement log). The scaffold seeds all of them.

> The ritual references each repo's **own standing laws** (its `CLAUDE.md` — e.g. a
> service's testing discipline, dependency rule, and ADRs). Those laws are
> service-specific; the *ritual* of restating them at session start and enforcing the
> gate at session end is the platform-level convention.

## Begin a session (before touching code)

Do these in order; don't jump to planning until the slice is framed.

1. **Load the latest handoff** — open the highest-numbered `docs/sessions/NN.md`. That
   handoff, not the codebase, is the entry point: what the last session did, the concrete
   next step, open questions/blockers. Then read any **advisory brief** in `docs/briefs/`
   as *input to deliberation, not a spec* (see Briefs below).
2. **Internalize the standing laws** from `CLAUDE.md` — the repo's testing discipline,
   structural rules, "ask before deviating from an ADR", and the gate command. These are
   laws to restate, not to rediscover.
3. **Check the open design decisions** — `CLAUDE.md` → "Open design decisions" and any
   ADR marked Proposed/Open. If the slice touches one, it is *not* already designed;
   surface it and settle scope before planning.
4. **Confirm a clean baseline** — know the branch/PR and whether the tree is clean
   (`git status -s`, current branch, recent log, open PRs) before adding to it.
5. **Frame the slice, then proceed** — restate in a line or two the single coherent
   concern, the layers it touches, and any open decision it depends on. Settle real
   scope forks with the user *before* writing code.
6. **Delete the consumed brief** once the plan is approved (briefs are ephemeral).

## Wrap a session (close it out deliberately)

Run in order; if a step can't complete, stop and say why.

1. **Gates must be green.** Run the repo's gate command. If it fails, **stop** — report
   the failing gate; do not edit source to force it green as part of wrapping.
2. **Temporary-rig sweep.** Grep for rigs that must not silently outlive the session that
   introduced them (disabled CI steps, skipped/ignored tests, `xfail`, new
   not-implemented seams, `TODO`-for-later). Each leftover is removed now or logged as an
   open entry in `docs/lessons.md` with a tracked removal task. **Never leave an
   undocumented rig.**
3. **Docs currency check.** Confirm `CLAUDE.md` and `README.md` still match reality after
   the session's changes; update them if they drifted (in-scope for any session).
4. **Lessons promotion review.** For every `open` entry in `docs/lessons.md`, propose its
   permanent home — a **script** (mechanical task), a **skill/command** (recurring
   procedure), a **CLAUDE.md guardrail** (always-true rule), or an **ADR** (architectural
   decision). Promote what can be promoted; for anything needing the user's call
   (especially an ADR), recommend and **ask** — never create/edit an ADR without
   approval. Capture any new lesson before moving on.
5. **Write the handoff** to `docs/sessions/NN.md` (next zero-padded number) using the
   format below — **before** the comprehension checks, so the user can read it first.
6. **Comprehension checks** — generate 3–5 questions tied to what was actually built or
   decided (favor "why" / "what breaks if" / "predict the next step"). **Pose them
   interactively**, one at a time, confirming/correcting each. Record in the handoff
   *exactly* what happened — never fabricate a score; "posed; not self-answered" is the
   honest result when the user declines.
7. **Leave a forward brief only if the next session genuinely needs one** (a judgment
   call; "no brief" is the common, correct outcome — see Briefs below).
8. **Suggest a concept note** if something substantial and durable was built and lacks
   one ([`concept-note-structure.md`](concept-note-structure.md)). Offer; don't
   auto-generate.
9. **Push + open/update the PR**, linking the handoff and summarizing changes, gate
   status, and open questions — only after steps 1–7 succeed.

## Forward briefs (ephemeral)

A **brief** (`docs/briefs/<topic>.md`) is a short, *advisory* note one session leaves for
the next: forward-passed pointers — what existing structure to reuse/mirror, pitfalls,
the genuinely-open forks to decide. It is **not a spec** and **not permanent
documentation**.

- **Written** at wrap time *only* when a decision the next session faces should be
  influenced by existing/past structure that isn't already captured in an ADR, a concept
  note, `CLAUDE.md`, or the handoff's "What's next." Greenfield next slices get none —
  do not manufacture one.
- **Read** at the start of the next session as input to deliberation — adopt, adapt, or
  discard it as a senior engineer would.
- **Deleted** by that session once its plan is approved. Anything still worth keeping
  graduates to the plan, an ADR, or `docs/lessons.md`.

So `docs/briefs/` is normally empty (or holds at most the one brief awaiting the next
session). Durable decisions live in `docs/adr/`; durable learning in `docs/lessons.md`
and `docs/concepts/`; cross-session state in `docs/sessions/`. Briefs are the throwaway
seed in between.

## Handoff format (`docs/sessions/NN.md`)

Keep these headings, in this order, every time:

```markdown
# Session NN — <short title>

_Date: YYYY-MM-DD · Branch: <branch> · PR: <link or "pending">_

## What changed
- Bullet list of concrete changes (files/areas), each one line.

## Decisions & lessons captured
- Decisions made this session and why.
- Lessons logged to docs/lessons.md, with their proposed/applied home.
- **Promotions:** any lesson moved open→promoted this session, with the link.

## Gate status
- Output/summary of the gate command (which gates passed; any caveats).

## Comprehension checks
- The questions posed (3–5), each followed by the user's answer if given and any
  correction. Recorded truthfully — never a fabricated score.

## What's next
- The concrete next step(s) for the following session.

## Open questions / blockers
- Anything undecided, waiting on the user, or external. "None" is a valid answer.
```

A session is **wrapped** only when: gates green · no undocumented rigs · docs current ·
open lessons triaged · handoff written · comprehension checks actually posed after it
(and truthfully recorded) · a forward brief left or consciously skipped · branch pushed
and PR open.
