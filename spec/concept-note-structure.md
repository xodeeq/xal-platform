# Concept notes — the learning curriculum

Every xal service maintains a **curriculum of concept notes** under `docs/concepts/`: a
sequenced set of teaching documents that explain the service end-to-end for a human who
wants to *understand* it — not API reference, not a changelog. This is a first-class
deliverable, not an afterthought: building xal is as much a **learning path** as a
product, and the concept notes are how the hard-won understanding is kept durable.

This document defines the **form** of a note and the **discipline** of the curriculum.
Each service fills it with its own notes, citing its own code; the structure is shared,
the content is the service's.

## The hard rules

1. **Every note cites real code in its own repo** (concrete files/types) **and the
   relevant ADR.** A note that could have been written without the repo open is a
   failure — it must bridge concept ↔ implementation and never drift into generic
   textbook content.
2. **Teach from first principles** in §2 — explain the *mechanism*, so the reader can
   re-derive it, not just recognize an API.
3. Save to `docs/concepts/<topic>.md` (kebab-case topic).
4. **Update `docs/concepts/README.md`** (the curriculum index) whenever a note is added,
   placing it in a sensible reading order.

## Fixed structure (every note — these exact sections, in order)

```markdown
# <Topic>

## 1. The problem it solves
Why this exists at all — the failure mode it prevents. No solution yet.

## 2. How it works — from first principles
The mechanism, built up from basics. The reader should be able to re-derive it,
not just recognize the API.

## 3. The tradeoff space
The real alternatives and when you'd choose each. Be fair to the options not
chosen. A short table or list is good.

## 4. What THIS project chose and why
The decision, linked to the relevant ADR, and citing the real code in this repo
that implements it (named files/types). Tie it back to §3: why this point in the
tradeoff space, for this service.

## 5. Comprehension checks
3–5 active-recall questions (favor "why" / "what breaks if" / "predict"). Provide
brief answers or an answer key after the questions.

## 6. Go deeper
Pointers for further study — books, specs, papers, other notes in this curriculum
(link docs/concepts/...), relevant ADRs.
```

## The curriculum index is an onboarding path

`docs/concepts/README.md` is not just a file list — it is a **reading order**. Notes are
sequenced so each builds on the ones above it (the structural/foundational concepts
before the ones that lean on them). When a note is added, slot it into the order that
keeps that true. Read top-to-bottom, the index should teach the whole service.

## Quality bar (reject a note if any fail)

- [ ] Cites at least one real file in the service's repo, by path, that exists.
- [ ] Links the relevant ADR.
- [ ] §2 explains a mechanism, not an API.
- [ ] §3 is fair to the alternatives.
- [ ] §4 connects the choice to §3 for *this* service.
- [ ] `docs/concepts/README.md` updated so the curriculum still reads as a coherent path.

## When to write one

Write (or offer to write) a concept note when something **substantial and durable** was
just built or decided and lacks a note. The end-of-session ritual
([`session-ritual.md`](session-ritual.md), wrap step) surfaces this as a suggestion —
the note is offered, never auto-generated.
