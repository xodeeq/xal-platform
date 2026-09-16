# `docs/plan/` — the multi-session build plan

`plan.md` is the ordered list of build sessions for this service, emitted by the planner
from the admitted spec and reviewed by a person before any of it runs. One markdown file, so
it can be carried out of the repo for verification and back unchanged.

Each session in it carries: scope in and scope out, the artifacts that must exist at the end,
a **gate command whose exit code decides pass**, a retry cap, and what happens when the cap
is exhausted. As sessions run, their status and evidence are written back into this file —
that is the state that survives between sessions.

Until the planner has run, this directory holds only this README. An empty `plan.md` is
worse than none: it reads as a plan that says nothing is needed.
