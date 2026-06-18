# Service scaffold

The seed a **new xal service** is created from. Copying this directory gives a service the
shared structure — the session ritual, the docs layout, the skill stubs, and the
vendored-spec landing dir — so it conforms to the platform from commit one.

## Create a new service

```bash
cp -r platform/scaffold ../<service>          # e.g. ../user-management
cd ../<service>
git init                                       # each service is its own repo (auth ADR-0005)

# vendor the platform spec into docs/platform/:
../platform/sync/platform-sync.sh ../platform

# make it yours:
mv CLAUDE.md.template CLAUDE.md                 # then fill in every <…> placeholder
rm README.md                                    # replace this file with the service's own README
```

Then build the service **test-first**, following the vendored conventions
(`docs/platform/service-conventions.md`, `docs/platform/deployment-conventions.md`) and the
lifecycle (`docs/platform/process-guide.md`). Auth is the reference implementation to mirror
file-by-file in your language.

## What's in here

| Path | Purpose |
|---|---|
| `CLAUDE.md.template` | the service's living-source-of-truth skeleton (rename + fill in) |
| `.claude/commands/{begin,wrap}-session.md` | the work-session ritual launchers |
| `.claude/skills/platform-service-conventions/` | points at the vendored contract spec |
| `.claude/skills/concept-note/` | the learning-curriculum generator (points at the vendored spec) |
| `docs/adr/` | the service's decision log (template + index seeded) |
| `docs/concepts/` | the concept-note curriculum (index seeded) |
| `docs/briefs/` | ephemeral forward briefs (lifecycle README seeded) |
| `docs/sessions/` | work-session handoffs (README seeded) |
| `docs/lessons.md` | the continuous-improvement ledger (header seeded) |
| `docs/platform/` | where the vendored platform spec lands after sync (read-only) |

Keep `docs/platform/` in sync (`platform-sync.sh … --check` in CI) so the service never
silently drifts from the platform conventions. See the platform repo's `sync/SYNC.md`.
