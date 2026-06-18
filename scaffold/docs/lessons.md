# Lessons log

A running ledger of pitfalls, workarounds, repeated explanations, and consequential
decisions — so none of them evaporate at the end of a session.

**The loop: capture → review → promote.**

1. **Capture** (any time): the moment something bites, a workaround goes in, or you find
   yourself explaining the same thing twice, append a one-line entry here with status `open`.
2. **Review** (every session, via `/wrap-session`): walk the open entries and decide each
   one's permanent **home**.
3. **Promote**: move the lesson into the thing that makes it stick, then flip the entry to
   `promoted→<link>`. A lesson that stays `open` for many sessions is a signal it needs a
   decision, not that it should be forgotten.

**Homes** (where a lesson goes to live permanently):

| Home | Use when the lesson is… | Example |
|---|---|---|
| **script** | a mechanical, repeatable task | the gate sequence → a gate script |
| **skill / command** | a recurring procedure or judgement | end-of-session ritual → `/wrap-session` |
| **guardrail** (CLAUDE.md) | an always-true rule | "the domain layer references nothing" |
| **ADR** | an architectural decision with tradeoffs | token strategy, language choice |

> **Never let a temporary workaround outlive the session that created it** without a tracked
> entry here to remove it.

## Format

One line per entry:

```
date | context | lesson | proposed home (script/skill/guardrail/ADR) | status (open / promoted→link)
```

## Entries

```
```
