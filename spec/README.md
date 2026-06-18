# spec/ — the canonical language-agnostic shared assets

This is the **source of truth** for everything every xal service must conform to,
independent of its implementation language. A service consumes these by vendoring a
read-only copy into its own `docs/platform/` via the sync mechanism
([`../sync/SYNC.md`](../sync/SYNC.md)) — it never edits a vendored copy. Edit the spec
**here**.

> **The rule (ADR-0009):** the platform owns the SPEC (these files); each service owns
> its language's IMPLEMENTATION. Nothing here is normatively .NET-specific — auth is
> cited only as the **reference realization**.

| File | What it governs |
|---|---|
| [`process-guide.md`](process-guide.md) | The shared engineering lifecycle: the phases and the Definition of Done every service moves through. |
| [`service-conventions.md`](service-conventions.md) | The §1–9 operational + HTTP **contract** surface (health, telemetry, logging, trace propagation, container interface, event envelope, purity, variation-behind-contract). |
| [`deployment-conventions.md`](deployment-conventions.md) | The **deployment** contract: runtime-reproducible-from-files (IaC), migrations-as-release-step, secrets/fail-fast, health wiring, smoke gate, CD-from-main. |
| [`adr-discipline.md`](adr-discipline.md) | How decisions are recorded (Context→Decision→Consequences), numbered, superseded; platform- vs service-level ADRs. |
| [`adr-template.md`](adr-template.md) | The single-ADR template to copy. |
| [`concept-note-structure.md`](concept-note-structure.md) | The learning curriculum: the fixed concept-note form and the onboarding-path discipline. |
| [`session-ritual.md`](session-ritual.md) | The begin/wrap work-session ritual, the handoff format, and the ephemeral-briefs lifecycle. |

Changing any file here is a spec change: bump the repo [`../VERSION`](../VERSION) per the
policy in [`../CLAUDE.md`](../CLAUDE.md) so consumers can detect the drift.
