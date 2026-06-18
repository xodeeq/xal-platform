# CLAUDE.md — xal platform repo (living source of truth)

This file is the durable context for working **in the platform repo itself**. For a
*service's* context, see that service's own `CLAUDE.md` (auth is the reference).

## What this repo is

The canonical home of xal's **language-agnostic** conventions, process, and learning
discipline. Services consume it; it never depends on a service. The governing rule
(ADR-0009): **the platform owns the SPEC, each service owns its language's
IMPLEMENTATION.** See [README.md](README.md).

## The prime directive when editing `spec/`

**No service-language specifics may become a normative statement.** Every rule in
`spec/` must be stated language-agnostically. A concrete example is allowed *only* as a
clearly-labelled **"auth reference realization"** citation — never as the requirement
itself. Before committing a `spec/` change, grep it for leaked .NET-isms:

```bash
grep -nE '\bdotnet\b|\.csproj|\.slnx|xUnit|Npgsql|Argon2|\bAuth\.[A-Z]' spec/*.md
```

Any hit must sit inside an explicit "auth realizes this by…" citation, not in a
normative sentence. If a rule can only be expressed in one language's terms, it isn't a
platform rule yet — it belongs in that service.

## What is canonical here vs what is a copy

| Asset | Canonical home | Notes |
|---|---|---|
| process guide, service/deployment conventions, ADR + concept + session discipline | **`spec/` in this repo** | the forward source of truth |
| the auth realizations (`scripts/check.sh`, `Directory.Packages.props`, the .NET layout, auth's specific ADRs/concept notes) | the `auth` repo | the reference *implementation*, not duplicated here |
| `process-guide.md` legacy copy at `xal/docs/` | de-facto pre-extraction location | left in place this session; removed when auth becomes a consumer (tracked) |

When a service "syncs", it vendors a **read-only copy** of `spec/` into its own
`docs/platform/`. Edit the spec **here**; never edit a vendored copy in a service.

## Versioning the spec

`VERSION` (semver) is what consumers pin to. Bump it whenever a `spec/` change should
propagate:

- **patch** — clarifications/typos, no new obligation on services;
- **minor** — a new convention or an additive requirement;
- **major** — a breaking change to an existing convention (services must act).

The sync mechanism (`sync/`) compares a consumer's pinned version against this file to
detect drift. Record notable bumps in `adr/` or a session handoff.

## How we work here

- **This repo is docs/tooling/process** — there is no application and no TDD gate. The
  quality bar is: spec stays language-agnostic, links resolve, the scaffold stays
  self-consistent, and the sync round-trip works (see `sync/SYNC.md`).
- **The session ritual still applies.** Work sessions wrap with a handoff in
  `docs/sessions/NN.md` and the same begin/wrap discipline auth uses — that discipline
  is itself one of the assets this repo defines (`spec/session-ritual.md`). Eat the dog
  food.
- **ADRs govern this repo too.** A structural decision about the platform (the sync
  model, the scaffold shape, the versioning policy) is recorded in `adr/`, following
  `spec/adr-discipline.md`.
- **Conventional Commits; small logical commits.** Decisions explained in commit bodies
  or ADRs.

## Phase status

- **Extraction (auth session 16, 2026-06-18):** repo stood up; `spec/` canonical; the
  scaffold and `sync/` mechanism built and verified by a round-trip. ADR-0009 fulfilled
  (direction → realized structure) and recorded as `adr/0001`.
- **Next:** (1) auth-as-consumer retrofit (vendor spec into `auth/docs/platform/`, wire
  `--check` into auth CI, slim auth's in-repo skill bodies to reference the synced spec,
  remove the `xal/docs/process-guide.md` duplication); (2) lift the reusable `infra/`
  observability Terraform modules into a `scaffold/` module; (3) a generic, xal-stripped
  export for unrelated projects (separate effort).
