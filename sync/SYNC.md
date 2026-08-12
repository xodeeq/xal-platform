# The template + sync model

How a service consumes the platform spec without silently drifting from it. This realizes
[platform ADR-0001](../adr/0001-platform-repo-and-sync-model.md) (auth ADR-0009), which
chose **template + sync** over git submodules and per-language packages.

## The model in one picture

```
platform/spec/*.md   ──(cp -r scaffold + platform-sync.sh)──►   <service>/docs/platform/*.md   (read-only, vendored)
       ▲  edit here, the only source of truth                          │  pinned to a VERSION in sync.config
       └──────────────  bump platform/VERSION  ◄── drift detected by `--check` ──────────────┘
```

- **Template** — a new service is seeded by copying [`../scaffold/`](../scaffold/), which
  already contains the docs structure, the session-ritual commands, the skill stubs, and
  an (empty) `docs/platform/` landing dir.
- **Sync** — [`platform-sync.sh`](platform-sync.sh) copies the spec files listed in
  [`manifest`](manifest) into the service's `docs/platform/` and records the platform
  `VERSION` it pinned in `docs/platform/sync.config`.

## Rules

1. **The spec is edited only in the platform repo.** Files under a service's
   `docs/platform/` are **read-only vendored copies** — never edit them there. (The vendored
   copies are byte-identical to `spec/`, which is what makes `--check` a simple diff.)
2. **A sync leaves changes unstaged.** `platform-sync.sh` does not commit or stage — the
   service's normal **PR review is the drift review**: the diff of `docs/platform/` shows
   exactly what spec changed, reviewed like any other change.
3. **`--check` makes "behind" visible.** Wire `platform-sync.sh <platform> --check` into the
   service's gate/CI. It exits non-zero if any vendored file differs from the platform spec
   or the pinned version is stale — so "the spec moved and this service hasn't synced" is a
   gating, reviewable state, not a silent one.
4. **Versioning.** Bump [`../VERSION`](../VERSION) whenever a `spec/` change should
   propagate (patch = clarification, minor = additive obligation, major = breaking) — see
   [`../CLAUDE.md`](../CLAUDE.md). The pinned version in a service's `sync.config` is what
   `--check` compares against.

## Usage

```bash
# From the SERVICE's root directory:

# vendor / update the spec (then review & commit the docs/platform/ diff in your PR):
/path/to/platform/sync/platform-sync.sh /path/to/platform

# CI / gate — fail if this service is behind the platform spec:
/path/to/platform/sync/platform-sync.sh /path/to/platform --check
```

A fresh service (just `cp -r`'d from the scaffold) has an empty `docs/platform/`; the first
`platform-sync.sh` run populates it and writes `sync.config`. A re-run with no spec change
is a clean no-op.

## What's in scope to sync

[`manifest`](manifest) lists the vendored files; keep it aligned with
[`../spec/README.md`](../spec/README.md). The manifest is the contract for "what a service
must carry a copy of" — add a spec file to both when it becomes a shared obligation.

### Rule: a manifest file's relative links may not escape the vendored set

A manifest file is copied **verbatim** into a consumer's `docs/platform/`. Its links travel
with it, but its *neighbours* do not: inside a consumer, `../` resolves to that service's
`docs/`, not to this repo's root. So a link that is perfectly correct here can be broken in
every consumer simultaneously — and it will look fine to anyone reviewing it here, which is
exactly how it goes unnoticed.

Therefore, in any file listed in [`manifest`](manifest):

- **Allowed:** a relative link to another file **in the vendored set**, always as a bare
  sibling (`service-conventions.md`) — the whole set lands in one flat directory.
- **Not allowed:** any relative link outside that set — `../VERSION`, `../sync/SYNC.md`,
  `../CLAUDE.md`, `../adr/0001-….md`. Use an absolute
  `https://github.com/xodeeq/xal-platform/blob/main/…` URL (this repo is public, so no
  credential is needed to follow it), or don't make it a link.
- **Move the link text too.** These links commonly use the path as their label
  (`` [`../VERSION`](../VERSION) ``); retargeting the URL alone leaves a label still
  displaying a path that is wrong in a consumer.

Anywhere *outside* the manifest set — this file, `../README.md`, `../CLAUDE.md`, `../adr/` —
ordinary relative links are correct and preferred; those files are never vendored.

[`../scripts/check.sh`](../scripts/check.sh) **gate 2** enforces this. It exists because
three such links shipped in `spec/README.md` and reached auth's `docs/platform/` before a
link check caught them (fixed in `0.1.1`).
