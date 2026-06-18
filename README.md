# xal platform

The **single source of truth** for the language-agnostic conventions, process, and
learning discipline that every **xal** service conforms to. xal is a catalogue of
independently versioned, **polyglot** microservices (auth, user-management, inventory,
…) that a registry and a composition frontend stitch together — that only works if
every service, whatever language it's written in, exposes the **same operational and
contract surface**. This repo is where that surface is defined once and kept from
drifting.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD PLATFORM CONTRACT.**

## The one rule this repo exists to protect (ADR-0009)

> The platform owns the **SPEC** — language-agnostic: *what* a conforming service
> must do. Each service owns its language's **IMPLEMENTATION** of that spec.

So `spec/` never contains a `.csproj`, an `xUnit` layout, or any other .NET-ism: those
are auth's *realization* of the generic rules, and they live in the `auth` repo. When a
spec file needs to point at a concrete example, it cites auth as the **reference
realization** — clearly labelled as such, never as a normative requirement.

**Auth (.NET 10) is service #1 and the reference implementation.** Every convention in
`spec/` was discovered and proven there first, then lifted here.

## Repo map

| Path | What it holds |
|---|---|
| [`spec/`](spec/) | The canonical language-agnostic shared assets (process, conventions, deployment, ADR + concept + session discipline). The thing services consume. |
| [`adr/`](adr/) | This repo's **own** decision log — how the platform governs itself (e.g. the repo structure + sync model). |
| [`scaffold/`](scaffold/) | The seed a **new** xal service is created from: a `CLAUDE.md` skeleton, the docs structure, the session-ritual commands, the skill stubs, and the vendored-spec landing dir. |
| [`sync/`](sync/) | The **template + sync** mechanism: how a service pulls spec updates forward, with drift surfaced as a reviewable diff (`platform-sync.sh`). |
| [`docs/sessions/`](docs/sessions/) | This repo's own work-session handoff log (the session ritual continues here). |
| [`VERSION`](VERSION) | The platform-spec version a consuming service pins to. |

## Quickstart

**Start a new xal service** (service #2 onward):

```bash
cp -r platform/scaffold ../my-service
cd ../my-service
git init
../platform/sync/platform-sync.sh ../platform   # vendor the spec into docs/platform/
# then fill in CLAUDE.md.template for the new language and build test-first
```

**Pull spec updates into an existing service:**

```bash
cd <service>
<path-to>/platform/sync/platform-sync.sh <path-to>/platform   # updates docs/platform/, leaves changes unstaged for PR review
```

**Check a service is in sync** (CI):

```bash
<path-to>/platform/sync/platform-sync.sh <path-to>/platform --check   # non-zero exit if the service is behind
```

See [`sync/SYNC.md`](sync/SYNC.md) for the full model and [`CLAUDE.md`](CLAUDE.md) for
how to work *in* this repo.

## Status

Extracted from auth on 2026-06-18 (auth session 16; ADR-0009 fulfilled). This is the
**repo + scaffold + sync** slice: the spec is canonical here, the scaffold and sync
mechanism are live. Retrofitting auth itself to *consume* the synced spec (rather than
hold the originals) is a tracked follow-up — until then auth keeps its in-repo copies
and this repo is the forward source of truth.
