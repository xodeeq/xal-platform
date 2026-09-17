---
type: adr
title: "Marketplace sources are remote and pinned, and a credential declares its expiry"
status: accepted
created: 2026-09-17
updated: 2026-09-17
author: claude (drafted Decision-first for Sodiq); Sodiq (ruling)
service: platform
department: engineering
confidence: high
decision_date: 2026-09-17
open_risks:
  - "A private marketplace needs a read credential in CI, which is exactly the dependency ADR-0004 avoided by shipping the service conventions from a public repo. This ADR accepts that cost for xcos-core and constrains it; it does not remove it"
  - "Per-repo version pinning still does not work (ADR-0007): marketplaces are keyed by name globally, last-write-wins. A remote source makes the tag load-bearing for WHAT is fetched, not for per-repo resolution"
  - "The expiry field is a declaration checked against the clock, not against the provider: a token revoked early, or one whose declared date is simply wrong, still fails at use"
  - "check-gate-inputs.sh matches caller workflows textually (xal-company ADR-0005 residual 4), so a workflow that checks out a now-private repo without a credential is not caught by the caller check"
tags: [plugins, marketplace, credentials, gate-inputs, ci, distribution]
adrs:
  - "[Platform ADR-0007, the .claude/ sync boundary](0007-claude-config-sync-boundary.md)"
  - "[Platform ADR-0006, repo seeding](0006-repo-seeding.md)"
  - "[xal-company ADR-0004, agent-definition distribution via plugins](https://github.com/xodeeq/xal-company/blob/main/docs/adr/0004-agent-definition-distribution.md)"
  - "[xal-company ADR-0005, gate inputs are declared data](https://github.com/xodeeq/xal-company/blob/main/docs/adr/0005-declared-gate-input-contract.md)"
---

# Platform ADR-0008: Marketplace sources are remote and pinned, and a credential declares its expiry

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Sodiq

## Context

ADR-0007 makes plugins the distribution channel for every shared `.claude/` asset. That only
works if a plugin can be **resolved from somewhere other than the machine it was authored
on**, and today one of them cannot.

Measured 2026-09-17 in `~/.claude/plugins/known_marketplaces.json`:

```json
"xcos": {
  "source": { "source": "directory", "path": "/Users/xodeeq/Engineering/xal/xal-company" },
  "installLocation": "/Users/xodeeq/Engineering/xal/xal-company"
}
```

The `xcos` marketplace is a **path on one laptop**, and its install location is the working
tree itself. Three consequences, all verified rather than reasoned:

1. **The version tag is decorative.** `installed_plugins.json` records `xcos-core` at
   **0.3.0** while `plugins/xcos-core/.claude-plugin/plugin.json` says **0.6.0** — three
   minor versions of skew that nothing reported, because every repo on this machine gets
   whatever happens to be checked out.
2. **On any other machine, and in CI, the plugin is not found at all.** A headless run in a
   fresh checkout has no such path.
3. The release ritual in `xal-company/CLAUDE.md` — bump, `claude plugin tag`, push the tag —
   produces tags that are real (`xcos-core--v0.6.0` is on `origin`) and **that nothing
   consumes**.

Two pressures make this urgent now rather than eventually. The pipeline's driver (roadmap
§4.5) runs sessions **headless in GitHub Actions**, where a laptop path does not exist. And
`xal-platform` is planned to go **private**, with a public engineering-process repo extracted
— which moves the *other* marketplace, currently consumable without a credential precisely
because the repo is public, into the same position.

One related gap is already on record and belongs to this decision: **`.xal/gate-inputs` has
no expiry column**, so a token's expiry date lives only in someone's memory. On 2026-09-17 a
90-day PAT was issued (`XAL_READ_TOKEN`, expires 2026-12-16) and had to be parked in
`status/current.md` for want of anywhere better — which is the predicted failure happening on
the day the credential was created.

## Decision

**1. Every xal marketplace is registered by GitHub repo, never by local directory path.** A
`"source": "directory"` registration is a **defect**, not a configuration choice: it makes the
version tag decorative, and it makes the plugin unresolvable anywhere but the authoring
machine. `xcos` is re-registered as `xodeeq/xal-company`.

**2. A private marketplace declares its read credential as a gate input.** The credential is
least-privilege — **Contents: read-only**, scoped to the named repositories and nothing else
— supplied from CI secrets, never committed.

**3. `.xal/gate-inputs` gains a sixth field, `expires`.** An ISO date, or `-` for an input
that cannot expire (a toolchain, a runner-provided binary). `check-gate-inputs.sh` fails when
a declared credential has no `expires`, and when that date is in the past. The canonical copy
in `xcos-core` changes first and is re-vendored; the seed fixtures move with it.

The format becomes:

```
id | detect | required-in-ci | caller-pattern | expires | description
```

**3b. `caller-pattern` may name the workflow it applies to** — `board-add.yml:secrets.XAL_PROJECT_TOKEN`
asserts that *that file* exists and matches, and says nothing about the gate script's callers.

> **This clause was added while implementing decision 3, not when this ADR was drafted, and
> the discovery is worth keeping.** `.xal/gate-inputs` was built to answer exactly one
> question — *does every caller of the gate script supply what that script needs?* — so a
> repo's other workflows had no input contract at all. Both credentials this ADR is about
> are supplied to workflows that never invoke `scripts/check.sh`: the marketplace read token
> to a future plugin-install step, and the board's project token to `board-add.yml`.
> Declaring them the original way would have forced `ci.yml` and `deploy.yml` to reference
> secrets they have no use for — a false wiring, to satisfy a checker, in the file whose
> whole purpose is to stop false wiring. **A manifest that can only describe one script's
> inputs cannot hold a repo's credentials**, which is what decision 3 asked it to do. The
> clause is the smallest change that makes the decision implementable, and it closes a
> blind spot that predates this ADR.

**4. Rotation is a dated obligation, not a reminder.** Because the expiry is data rather than
prose, the date is checkable by the same mechanism that checks every other gate input, and it
fails **before** the token lapses rather than at the first red checkout.

### Alternatives considered

**Keep the directory source and treat the drift as acceptable.** Rejected. It is not a
trade-off between tidiness and effort: the pipeline's driver cannot run at all under it, and
the 0.3.0-vs-0.6.0 skew shows the failure is already silent and already happening.

**Make `xal-company` public so no credential is needed**, mirroring what ADR-0004 did for the
service conventions. Rejected, and this is the closest call in the ADR — it would remove the
credential entirely, which is a genuinely better end state. It is rejected because
`xal-company` is the company's operating record: status, decisions, specs, board tooling. The
public/private split is being decided in the opposite direction right now, with `xal-platform`
moving toward private and a *narrower* public process repo extracted from it. Making the
widest repo public to dodge a token inverts that.

**A deploy key per repo.** Rejected: per-repo rather than per-consumer, awkward over the
HTTPS path a marketplace fetch uses, and — decisively for this ADR — **deploy keys do not
expire**, so there is no date to declare and no rotation signal. The expiry is a feature here,
not a cost.

**A GitHub App installation token.** The right long answer: short-lived, scoped, auto-rotating,
no date to track. Deferred, not rejected — it is more machinery than one private marketplace
justifies today. *Trigger:* a second private marketplace, or the first credential rotation
that is missed.

> **STATUS ADDENDUM 2026-09-17 — this deferral's trigger has already fired, and the App is
> now owed rather than optional.** Wiring the board workflow the same day needed a second
> credential, and every narrow option was eliminated by test, not by argument:
> `GITHUB_TOKEN` has no Projects permission for a user-owned project; a **fine-grained PAT
> cannot reach user-owned projects at all** (searching `project` in its account-permission
> picker returns "No items available"); and a classic PAT with `project` but **not** `repo`
> fails the mutation with `NOT_FOUND`, proven twice — through `actions/add-to-project` and
> through a direct `addProjectV2ItemById` passing the node id straight from the event
> payload, which is what establishes that the **mutation** needs repository read rather
> than the action's own lookup.
>
> So `XAL_PROJECT_TOKEN` carries `repo` — **full control of every private repository on the
> account, to tick a box on a board.** That is a genuinely poor ratio of privilege to
> purpose, and it is recorded here as accepted-under-protest rather than settled: it was
> taken because the alternative was leaving the P1 defect open, on the same reasoning as
> decision 5 of 2026-09-17, and because a token that expires in 90 days is a bounded
> mistake where a permanent one would not be.
>
> **A GitHub App of our own is the fix**, and the confusion worth pre-empting: the *Claude*
> GitHub App installed on these repos is **Anthropic's**, serving the PR-review workflows.
> Its installation token is not ours to mint and carries no Projects permission — it does
> not and cannot cover this.
>
> **Concrete shape when it is picked up:** register a GitHub App owned by `xodeeq`;
> permissions **Projects: read & write** (account level) plus **Contents: read** and
> **Metadata: read** on the five repos, and nothing else; install it; store the App ID and
> private key as secrets; mint a short-lived installation token in `board-add.yml` and use
> it in place of `XAL_PROJECT_TOKEN`. That deletes a `repo`-scoped credential from five
> repositories and removes an expiry date from the rotation calendar.
>
> **Hard deadline rather than a soft trigger: 2026-12-16**, when `XAL_PROJECT_TOKEN`
> expires. Doing the App instead of rotating turns a chore into the fix. Tracked on the
> board; this addendum is the reasoning so that session does not start from scratch.

## Consequences

- **Positive.** The plugin resolves anywhere, including a headless CI checkout, so ADR-0007's
  distribution model actually holds off this laptop. The version tag becomes load-bearing for
  what is fetched, so the release ritual produces something consumed. A credential's expiry
  becomes declared data on the same footing as every other gate input, checked by the gate
  rather than remembered.
- **Negative / cost.** A credential now exists in the plugin path that did not before —
  precisely the dependency ADR-0004 avoided by publishing the service conventions from a
  public repo. That decision was right and is unchanged; this ADR accepts the cost for
  `xcos-core` specifically, where the alternative is a plugin that does not work. **The
  authoring loop also changes:** the plugin is fetched from what is **pushed**, so a local
  edit to `plugins/xcos-core/` no longer takes effect until it is committed, tagged, pushed
  and updated. That is the point, and it is slower.
- **Negative.** Three repos and the seed fixtures carry a vendored `check-gate-inputs.sh` and
  a `gate-inputs` manifest; a sixth field touches all of them in one change. The replica-parity
  gate covers the script, not the manifests.
- **A consequence that only appeared in the build, and is kept as a property:** the manifest
  **refuses to hold a credential whose consumer does not exist yet**. A workflow-scoped record
  naming a missing workflow fails, by the same reasoning as "zero callers is never a pass" —
  a record pointing at nothing asserts nothing. So `XAL_READ_TOKEN` cannot be declared until
  the plugin-install step it feeds is written, and its expiry stays in `status/current.md`
  until then. That is the right trade — a declaration that asserts nothing is worse than an
  honest note — but it means this ADR does not fully close its own gap on the day it lands.
- **Deferred.** (1) A GitHub App in place of the PAT — *trigger:* a second private marketplace
  or a missed rotation. (2) Real per-repo pinning, still the open item from ADR-0007 — a remote
  source does not fix it. (3) Whether the extracted public process repo hosts a marketplace of
  its own — *trigger:* the `xal-platform` privacy change, which is where the four workflow
  callers (`xal-auth` ci + deploy, `xal-org` ci + deploy) that check out `xal-platform` with no
  credential come due.
