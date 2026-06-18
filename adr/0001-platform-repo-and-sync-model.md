# ADR-0001: Platform repo structure + template/sync consumption model

- **Status:** Accepted
- **Date:** 2026-06-18
- **Deciders:** Platform architect

## Context

Auth **ADR-0009** ("Cross-service shared-asset distribution") fixed the *direction* — a
dedicated **`platform` repo** holding the language-agnostic shared assets, consumed via a
**template + sync** model — but explicitly **deferred the extraction** "until service #2
is imminent," and left the concrete *structure* and the *sync mechanism* undecided. That
trigger has now arrived (a second consumer is on the horizon), so the extraction is being
done and the deferred "how" must be settled.

ADR-0009 also rejected two alternatives that remain rejected here: **git submodules**
(awkward detached checkouts, easy to forget, pins a working copy rather than expressing
"conform to this spec") and **per-language packages** (premature — multiplies the
published-artifact surface across a polyglot catalogue before there is enough shared
*code*, as opposed to shared *prose/spec*, to justify it).

The load-bearing constraint to preserve: the platform owns the language-agnostic **SPEC**;
each service owns its language's **IMPLEMENTATION**. The platform must never contain
service-language specifics as normative requirements.

## Decision

Realize ADR-0009 as a `platform` git repo (sibling to each service repo, honoring auth
ADR-0005's repo-per-unit pattern) with this structure:

- **`spec/`** — the canonical shared assets (process guide, service + deployment
  conventions, ADR discipline + template, concept-note structure, session ritual). The
  only normative source; never service-language-specific.
- **`adr/`** — the platform's own decision log (this file).
- **`scaffold/`** — the template a new service is seeded from (`cp -r`): a `CLAUDE.md`
  skeleton, the `docs/{adr,concepts,briefs,sessions}` structure, the session-ritual
  commands, skill stubs pointing at the vendored spec, and the vendored-spec landing dir.
- **`sync/`** — the consumption mechanism (below).
- **`VERSION`** — a semver spec version that consumers pin to.

**Consumption is vendored-copy + pinned-version sync, drift surfaced as a reviewable
diff:**

1. A service vendors a **read-only copy** of the `spec/` files (per a `sync/manifest`)
   into its own `docs/platform/`, recording the platform `VERSION` it pinned in a
   `sync.config`.
2. `sync/platform-sync.sh <platform-path>`, run from the service, copies the manifest
   files forward and updates the pinned version, **leaving the changes unstaged** — so the
   service's ordinary PR review *is* the drift review (ADR-0009's "drift surfaced as a
   reviewable change rather than silently diverging").
3. `sync/platform-sync.sh <platform-path> --check` (CI mode) compares the vendored copies
   and pinned version against the platform repo and **exits non-zero if the service is
   behind** — making "spec changed, service hasn't synced yet" a visible, gating state
   rather than a silent one.

The spec is edited **only** in this repo; a vendored copy in a service is never edited.

## Consequences

- **Positive:** a single source of truth for conventions/process across every service;
  the spec stops living in (and drifting from) whichever service was built first.
- **Positive:** the spec-vs-implementation split is structural — `spec/` carries no
  .NET-isms (enforced by a grep guard in `CLAUDE.md`), so the platform stays
  language-agnostic while each service stays idiomatic.
- **Positive:** this is the precursor to the **service registry** — the same conformance
  spec the registry will check services against starts life here as the synced spec, and
  `--check` is the embryonic conformance gate.
- **Cost:** the sync step is a real (small) process tax, and "behind on the spec" is a
  state that must be surfaced and reviewed — accepted as cheaper than uncontrolled
  copy-paste drift. `--check` keeps it honest.
- **Deferred this slice (auth session 16):**
  1. **Auth-as-consumer retrofit** — auth still holds the *originals*; making auth vendor
     the synced spec, wiring `--check` into its gate, and removing the
     `xal/docs/process-guide.md` duplication is a tracked follow-up. **Trigger:** the next
     platform session, or when auth's spec and this repo's first meaningfully diverge.
  2. **Lifting the reusable `infra/` observability Terraform modules** into a `scaffold/`
     module (deployment-conventions Pattern B). **Trigger:** service #2 needs deployable
     observability.
  3. A **generic, xal-stripped** export for unrelated projects — explicitly out of scope;
     a separate effort when a non-xal consumer actually needs it.
