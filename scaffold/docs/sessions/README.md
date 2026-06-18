# Work-session handoffs

One file per work session, `NN.md` (zero-padded, starting `01`). Each handoff is written at
the **end** of a session by `/wrap-session` and is the **entry point** for the next session —
read the highest-numbered one first, before touching code. It records what the session did,
the concrete next step, and any open questions/blockers.

The fixed handoff format and the begin/wrap ritual are the platform spec:
[`../platform/session-ritual.md`](../platform/session-ritual.md). Do not reconstruct state
from the codebase — the latest handoff is the source of truth for "where are we".
