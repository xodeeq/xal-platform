# docs/platform/ — vendored platform spec (read-only)

The files here are **vendored, read-only copies** of the xal platform spec, synced from the
platform repo by `platform-sync.sh`. **Do not edit them here** — edit the spec in the
platform repo and re-run the sync. `sync.config` records the platform `VERSION` this service
is pinned to.

```bash
# from this service's root — update the vendored spec, then review the diff in your PR:
/path/to/platform/sync/platform-sync.sh /path/to/platform

# CI gate — fail if this service is behind the platform spec:
/path/to/platform/sync/platform-sync.sh /path/to/platform --check
```

After the first sync this directory will also contain `process-guide.md`,
`service-conventions.md`, `deployment-conventions.md`, `adr-discipline.md`,
`adr-template.md`, `concept-note-structure.md`, and `session-ritual.md`. See the platform
repo's `sync/SYNC.md` for the full model.
