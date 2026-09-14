---
description: End-of-session ritual — gates, rig sweep, lessons promotion, comprehension checks, standardized handoff, an optional forward brief, then push + PR.
argument-hint: "(no args)"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# /wrap-session

Close out the session deliberately and leave the repo pickup-able cold. Run the steps
**in order**; if a step can't complete, stop and say why. This is the only sanctioned way
to end a session.

> **The canonical procedure is `docs/platform/session-ritual.md`** (the vendored platform
> spec) → "Wrap a session", and the handoff format is defined there. This command is the
> launcher.

## Steps (in order)

1. **Gates must be green.** Run this service's gate command (see `CLAUDE.md`). If it fails,
   **stop** — report the failing gate; don't edit source to force it green as part of
   wrapping.
2. **Temporary-rig sweep.** Grep for rigs that must not silently outlive the session
   (disabled CI steps, skipped/ignored tests, `xfail`, newly-added not-implemented seams,
   `TODO`-for-later). Remove each leftover now or log it `open` in `docs/lessons.md` with a
   tracked removal task. Never leave an undocumented rig.
3. **Docs currency check.** Confirm `CLAUDE.md` and `README.md` still match reality;
   update if drifted.
4. **Lessons promotion review.** For every `open` entry in `docs/lessons.md`, propose its
   home — script · skill/command · CLAUDE.md guardrail · ADR. Promote what you can; for an
   ADR or anything needing the user's call, recommend and **ask** — never create/edit an
   ADR without approval. Capture any new lesson.
5. **Write the handoff** to `docs/sessions/NN.md` (next zero-padded number) in the format
   from the ritual spec — **before** the comprehension checks. Tell the user it's ready to
   read.
6. **Comprehension checks** — 3–5 questions tied to what was actually built/decided (favor
   "why" / "what breaks if" / "predict"). **Pose them interactively**, one at a time,
   confirm/correct each, then record in the handoff *exactly* what happened (never a
   fabricated score).
7. **Leave a forward brief only if the next session genuinely needs one** — a judgment
   call; "no brief" is the common, correct outcome.
8. **Suggest a concept note** if something substantial and durable was built and lacks one
   (`concept-note` skill). Offer; don't auto-generate.
9. **Sync the work board.** A session that does not write to the board has not handed off.
   `CLAUDE.md` names the board. For each item this session touched, and any work with no
   item: set status to where the work actually is; attach the evidence link (**an item you
   cannot give an artifact is not done**); fill routing, ownership and cost; park what
   stalled in the state naming who it waits on. If you cannot reach the board, that is a
   **park, not a skip** — record what the item should say under a **BOARD NOT SYNCED**
   heading in the handoff and in the PR body. Never record a field you did not verify.
   Full step: `docs/platform/session-ritual.md` → "Wrap a session", step 9.
10. **Push + open/update the PR**, linking the handoff and summarizing changes, gate status,
   and open questions — only after steps 1–9 succeed. Name and link the board items you
   moved; board state never appears in the diff.

A session is "wrapped" only when: gates green · no undocumented rigs · docs current · open
lessons triaged · handoff written · comprehension checks actually posed after it (and
truthfully recorded) · a forward brief left or consciously skipped · **the board synced, or
the failure recorded as BOARD NOT SYNCED** · branch pushed and PR open.
