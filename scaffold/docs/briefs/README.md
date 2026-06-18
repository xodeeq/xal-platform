# Forward briefs (ephemeral)

A **brief** here is a short, *advisory* note one session leaves for the next: forward-passed
pointers — what existing code to reuse/mirror, pitfalls to avoid, the genuinely-open forks to
decide, a suggested coherent scope. It is **not a spec** and **not permanent documentation**.

Lifecycle (enforced by the session ritual —
[`../platform/session-ritual.md`](../platform/session-ritual.md)):

- **Written** at the end of a session by `/wrap-session` — a judgment call, and **usually
  skipped**. Written *only* when a decision the next session faces should be influenced by
  existing/past structure that isn't already captured in an ADR, a concept note, `CLAUDE.md`,
  or the handoff's "What's next". Greenfield next slices get none.
- **Read** at the start of the next session by `/begin-session`, as *input to deliberation* —
  adopt, adapt, or discard it as a senior engineer would.
- **Deleted** by that session once its implementation plan is approved. Anything still worth
  keeping graduates to the plan, an ADR, or `docs/lessons.md`.

So this directory is normally empty (or holds at most the one brief awaiting the next
session). Durable decisions live in `docs/adr/`; durable learning in `docs/lessons.md` and
`docs/concepts/`; cross-session state in `docs/sessions/`. Briefs are the throwaway seed in
between.
