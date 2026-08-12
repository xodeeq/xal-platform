# Platform deployment conventions

> **Status:** canonical in the platform repo (ADR-0009 — the shared `platform` repo +
> template/sync; extracted auth session 16, 2026-06-18). Like
> [`service-conventions.md`](service-conventions.md) captures the *contract* surface, this
> captures the *deployment* contract: the language-agnostic operational invariants every xal
> service must satisfy to be deployable and composable. Extracted from what the **auth**
> reference service did on its first production deploy (Fly.io, ADR-0016). Each convention is
> stated language-agnostically, then cited to the real auth artifact that realizes it.

This document is the deployment counterpart to [`service-conventions.md`](service-conventions.md). A service is
"platform-deployable" when it satisfies every convention below. Auth (.NET 10) is the
reference; a new service in any language mirrors the *intent*, not the .NET specifics.

---

## The overriding principle: the runtime is reproducible from files (ADR-0018)

**Convention.** A service's **entire runtime** — the compute shell *and* its observability
— is **reproducible from committed files, applied by CI**. **Nothing a human clicks.** No
dashboard hand-drawn in a UI, no alert created by memory, no app/secret/scale knob set
ad-hoc and forgotten. If it isn't in the repo and applied by a pipeline, it doesn't exist.

**Why.** A hand-built runtime is a single point of failure with no source of truth: a lost
account, a second environment, or an incident recovery means re-clicking from memory.
Committed + CI-applied definitions make the runtime auditable, reviewable (a diff before it
ships), and rebuildable.

### The interface is two-handed — match the declarative tool to each platform

There is **no single tool** that declares a whole runtime, so don't force one. Auth uses
**two hands**, and the split itself is the convention:

| Hand | Pattern | Realized by |
|---|---|---|
| **Compute** | A declarative app manifest **+ an idempotent, reconcile-first provisioning script** | `fly.toml` + `infra/fly/provision.sh` |
| **Observability + external monitors** | **Terraform** (reusable modules), one provider per managed system | `infra/observability/` (`grafana/grafana`, `uptimerobot/uptimerobot`) |

The lesson generalizes past Fly and Terraform: **match the declarative interface to each
platform.** A platform with a healthy Terraform provider → Terraform it. A platform that
deprecated its provider and treats its own manifest as the source of truth (Fly) → use that
manifest plus a scripted API for the imperative gaps. The anti-pattern is a monolith tool
fighting a platform that has its own opinion.

### Pattern A — compute: declarative manifest + idempotent reconcile-first script

**Convention.** The app config is a **committed declarative manifest**. The surrounding
shell the manifest can't express — app existence, managed-DB attach, region, scaling /
min-instances, IP allocation, and the **declaration of required secret *names and shapes***
— is a **single idempotent script** that is **reconcile-first**: every step is
check-then-create, tolerates "already exists", and is **safe to re-run against the live
app** without duplicating or destroying it. Secret **values** are read from CI-injected env
and set into the platform secret store **by the script**; they are never in the manifest,
the script, or the repo.

**Auth reference.** `fly.toml` (declarative) + `infra/fly/provision.sh` (idempotent). The
script reconciles app/Postgres/region/scale/IPs and declares the required secrets
(`AUTH_*` env ⇄ Fly secret names ⇄ shapes in its header); `./infra/fly/provision.sh
--dry-run` reports without mutating (used on PRs). Fly is **not** Terraformed — Fly
deprecated its provider on purpose, and `fly.toml` is its declarative interface (ADR-0018).
*Enforce:* the dry-run runs on PRs touching `infra/**`; a fresh run against the live app
changes nothing.

### Pattern B — observability + external monitors: Terraform modules

**Convention.** Dashboards, alert rules, contact points, and external uptime monitors are
**Terraform**, structured as **reusable modules** (they generalize across services). Use the
**first-party/official provider** per system (vet it — maintenance + resource coverage).
Resources that carry **external identity** (a monitor, a contact point, a data source) are
**imported**, not recreated; pure **definitions** (dashboard JSON, alert rules) are recreated
from code. **No** dashboard/alert/monitor exists outside this — what's live is what's in the
modules.

**Auth reference.** `infra/observability/` — a `grafana` module (Fly-Prometheus data source,
the RED dashboard from the committed JSON, the 5xx error-rate alert, the email contact point)
and an `uptimerobot` module (the liveness monitor), via `grafana/grafana` + the official
`uptimerobot/uptimerobot` providers. The dashboard/alert are recreated from code; the data
source, contact point, and monitor are imported (`imports.tf`). *Enforce:* a fresh
`terraform apply` rebuilds the observability + monitor from files.

### State and secrets hygiene (both hands)

**Convention.** Terraform **state is remote, locked, and sensitive** (a backend that
encrypts at rest, with state locking). **No runtime secret** (signing keys, peppers,
encryption keys, DB credentials) ever enters Terraform, its state, the app manifest, or the
repo — those live **only** in the platform secret store, set by the provisioning script from
CI env. **Provider/API tokens** (the IaC tooling's own credentials) come from **CI env
only**, never committed.

**Auth reference.** HCP Terraform free tier as a **state-only** backend (encrypted + locked;
org via `TF_CLOUD_ORGANIZATION`). Runtime secrets live in `fly secrets` (set by
`provision.sh`); provider auth via `GRAFANA_URL`/`GRAFANA_AUTH`/`UPTIMEROBOT_API_KEY` env and
the Fly Prometheus token via `TF_VAR_fly_prometheus_token` from a CI secret (a least-privilege
read-only observability token, distinct from runtime secrets — ADR-0018 §4).

### CI applies it (GitOps-lite), separate from app CI/CD

**Convention.** Infra is applied by a **dedicated CI workflow**, separate from app CI and app
CD: `plan` (Terraform) + a provisioning **dry-run** on **PRs touching `infra/**`**, posted
for review and **never applying**; `apply` + the provisioning script on **merge to `main`**.
Application changes never run infra; infra changes never rebuild the app.

**Auth reference.** `.github/workflows/infra.yml` — `terraform plan` (commented on the PR) +
`provision.sh --dry-run` on infra PRs; `terraform apply` + `provision.sh` on merge to main;
kept separate from `ci.yml` (app gates) and `deploy.yml` (app deploy). *Enforce:* the PR path
has no apply step; a concurrency group serializes infra applies.

> **Composition-engine note.** This pair of artifacts (declarative manifest + reconcile
> script; Terraform modules) is exactly what the composition engine will eventually
> **generate per composed solution**. Keeping the modules reusable and the patterns
> platform-agnostic is what makes that generation tractable later.

---

## Migrations run as a release-step artifact, never from the runtime container

**Convention.** Schema migrations are applied as a **release step** that runs against the
target database **before** new application instances take traffic — executed from a
**purpose-built migration artifact**, never from the running service container and never
from application startup code.

**Why.** Two forces meet here:

1. **The runtime image is minimal on purpose.** A production service image should be a
   minimal, non-root, attack-surface-reduced artifact — which means **no SDK and often no
   shell** (auth uses the chiseled .NET runtime). You therefore *cannot* run the framework's
   "apply migrations" CLI inside it (`dotnet ef database update`, `alembic upgrade`,
   `migrate`, etc. all need tooling the image deliberately omits). <!-- auth-ref -->
2. **Migrations must run exactly once per deploy, before traffic, with a clean failure
   mode.** Applying them from application startup races across replicas and couples "can the
   app boot" to "can the app migrate"; a failed migration should fail the *deploy*, loudly,
   not crash-loop the service.

The answer to both: build a **self-contained migration artifact** at image-build time (it
has the SDK) and invoke it as the platform's release hook.

**Auth reference.**
- `Dockerfile` build stage produces a **self-contained EF Core migrations bundle**
  (`dotnet ef migrations bundle --self-contained -r linux-x64 -o /app/efbundle`) and ships
  it into the chiseled runtime image. Self-contained trades ~130 MB of image size for
  **runtime-independence** — the bundle carries its own runtime, so it runs even though the
  image's primary purpose is to host the app. (A service whose runtime image already
  contains the platform runtime may choose a framework-dependent bundle to stay lean; the
  *contract* is "a purpose-built artifact run as a release step," not "self-contained".)
- The bundle is wired as Fly's **`[deploy] release_command`** (see `fly.toml`), so Fly runs
  it on a one-off machine against the attached Postgres before the new version is promoted.
- It reads the connection string **from the environment**
  (`AuthDbContextDesignTimeFactory` resolves `ConnectionStrings__AuthDb`, the same secret the
  app uses), so the release command is a **bare `/app/efbundle`** — no arguments and no shell
  to expand `--connection "$VAR"` (the chiseled image has neither).

**Gotchas the reference hit (so you don't).** <!-- auth-ref -->
- **Idempotency is mandatory** — the release step re-runs on *every* deploy, so applying
  migrations to an already-migrated database must be a clean no-op, not an error. Validate it
  by running the artifact **twice** against the same database in CI/locally.
- **Pin the migrations-history table to an explicit schema** if your model uses a non-default
  schema. Left unqualified, the history table's location follows the DB's `search_path` and
  can FLIP once your schema is created mid-first-migration — producing an empty "shadow"
  history table on the second run, so every migration re-runs and collides. Auth pins it via
  `AuthNpgsqlOptions` (history in `public`; the app schema `auth` does not yet exist when the
  table is first created). See `docs/lessons.md` (2026-06-12).
- **Verify the artifact runs on the *actual* runtime image** (shell-less, non-root,
  minimal): auth runs `efbundle` inside the chiseled image against Postgres as a pre-deploy
  check, catching globalization/native-dependency surprises before they hit a real deploy.
- **Mind the image ENTRYPOINT.** Platforms typically run the release step as
  `<image ENTRYPOINT> + release_command`. If your release artifact is a *different executable*
  from the app (it is — the migration bundle vs the server), an app-shaped ENTRYPOINT will
  corrupt the release command: a `["dotnet","App.dll"]` entrypoint turns `release_command=
  "/migrate"` into `dotnet App.dll /migrate` (runs the app), and many minimal base images bake
  in their own `ENTRYPOINT ["dotnet"]` that resurfaces if you only set CMD (running
  `dotnet /migrate` — which fails on a *native* self-contained bundle). Auth's fix:
  **reset `ENTRYPOINT []` and put the app command in `CMD`**, so app machines run the CMD and
  the release runner runs a bare `/app/efbundle`. See `docs/lessons.md` (2026-06-12).

*Enforce:* CI builds the image (which builds the artifact); a smoke/release rehearsal applies
the artifact twice against a throwaway database and asserts the second run is a no-op.

---

## Secrets come from the platform secret store, with fail-fast production validation

**Convention.** Secrets (signing keys, peppers, encryption keys, DB credentials) are injected
from the platform's **secret store** as environment variables — **never** in the deploy
manifest, the image, or the repo. In **production the service fails fast on boot** if a required
secret is missing: it must refuse to start rather than silently fall back to throwaway/ephemeral
material.

**Why.** A service that boots with a generated-on-the-fly key "works" until the second replica
or the next restart, then mints tokens nobody can verify — a silent, corrupting failure. Failing
the boot turns that into a loud, immediate, un-missable error at deploy time.

**Auth reference.** Secrets via `fly secrets set` (injected as env vars), documented by name and
shape in `README.md`; **never** in `fly.toml`. The secret factories
(`EcdsaSigningKeyFactory`, the pepper factories, `TotpEncryptionKeyFactory`, …) take a
`requireConfigured` flag that the host sets from `IsProduction()`; `Program` eagerly resolves the
profile's security singletons after `Build()` so a missing secret throws **on boot**, not on the
first request. A warned ephemeral fallback remains for local development only.
*Enforce:* a per-factory unit test that the production guard refuses the fallback; a startup test
per profile that a missing required secret aborts boot.

## Liveness + readiness wired to the platform's health checks

**Convention.** Expose `GET /health/live` (process up) and `GET /health/ready` (200 only when
hard dependencies — the DB — are reachable, else 503). Wire the orchestrator's health checks to
them: **readiness gates traffic**, **liveness gates restart**, with a startup **grace period**
that covers boot and the release-step migration.

**Auth reference.** `Program.cs` maps both endpoints (self check tagged `live`; Npgsql probe
tagged `ready`). `fly.toml` defines two `[[http_service.checks]]`: `/health/ready` (traffic gate,
15s grace) and `/health/live` (restart on sustained failure). *Enforce:* the smoke gate hits both
and expects 200; a service must answer 503 on `/health/ready` before its DB is up.

## Metrics scraped from `/metrics` (Prometheus/OpenTelemetry)

**Convention.** Export metrics in Prometheus format at `GET /metrics` via OpenTelemetry (the
cross-language standard); the platform scrapes it. A RED dashboard (Rate, Errors, Duration) over
those metrics is the baseline.

**Auth reference.** OpenTelemetry Prometheus exporter at `/metrics`; `fly.toml [metrics]`
(`port`, `path`) points Fly's built-in Prometheus at it. The RED dashboard + the error-rate
alert are **codified as Terraform (Pattern B above)** in `infra/observability/`, applied by
the infra workflow — not drawn by hand; the dashboard model + queries also live in
`docs/observability/` and `docs/observability.md`. *Caveat captured as a gap:* keep
`/metrics` on the platform's **private** network or behind a scrape token — do not expose internal
telemetry publicly (see `docs/lessons.md`).

## Structured JSON logs to the platform's log stream

**Convention.** One JSON event per line to stdout (the platform collects stdout), every line
carrying `service`, `environment`, `traceId`, `event`; **never** log secrets/tokens/credentials.
The log format is **environment-independent** — no human-pretty console formatter sneaking into
production.

**Auth reference.** Serilog `RenderedCompactJsonFormatter` on both the bootstrap and the main
logger (same JSON in every environment), enriched with `service`/`environment`; `traceId` added
per request by `TraceIdMiddleware`. Fly collects stdout into its log stream. *Enforce:* a
log-shape test for the required keys; the "no secrets" half is review-only.

## A non-root, minimal runtime image

**Convention.** The runtime image runs as a **non-root** user and carries the **minimum** surface
(no shell/SDK/package manager beyond what the process needs). This both reduces attack surface and
forces the healthy patterns above (e.g. migrations-as-release-step, because you *can't* shell in).

**Auth reference.** `Dockerfile` final stage is the **chiseled** .NET runtime (no shell, no
package manager), running as **UID 1654**, reading all config from the environment. The CI Docker
gate (`scripts/check.sh`) builds it on every run. *Enforce:* CI builds the image; a scanner /
review confirms non-root + minimal base.

## A post-deploy smoke gate

**Convention.** After every deploy, a **smoke test** drives the live service through its core
end-to-end flow and **fails the deploy** if anything is wrong — idempotent and safe to rerun, with
a unique throwaway identity per run. This is the contract for "the deploy actually works", beyond
"the process started".

**Auth reference.** `scripts/smoke.sh <base-url>`: health 200, JWKS publishes an ES256 key, then a
full register → login → **offline JWKS verification** → refresh-rotation → reuse-rejection →
logout → session-dead round-trip. Dependency-light (curl + openssl + python3). *Enforce:* the CD
workflow runs it against production and fails loudly on any check.

## CD from `main` only, after the gates

**Convention.** Deployment is **continuous from `main` only**, and only **after the full gate
suite passes** — kept in a **separate** workflow from CI so pull-request runs never touch
production. A manual dispatch path exists for controlled redeploys; production deploys are
serialized.

**Auth reference.** `.github/workflows/deploy.yml` triggers on push-to-`main` + `workflow_dispatch`
only (never `pull_request`); a `gate` job runs `scripts/check.sh`, then a `deploy` job runs
`flyctl deploy` and `scripts/smoke.sh`; a concurrency group serializes prod deploys. CI
(`ci.yml`) stays PR/main verification and never deploys. *Enforce:* the deploy workflow's own
gate + branch protection on `main`.

---

## Checklist (a service is "platform-deployable" when…)

- [ ] The runtime is **reproducible from committed files, applied by CI** — nothing clicked
      (ADR-0018): compute via a **declarative manifest + an idempotent reconcile-first script**;
      observability/external monitors via **Terraform modules**.
- [ ] Terraform **state is remote, locked, and sensitive**; **no runtime secret** is in
      Terraform/state/manifest/repo (secrets only in the platform store, set by the script);
      provider/API tokens come from CI env only.
- [ ] A **separate infra workflow** plans (+ provisions dry-run) on infra PRs and applies on
      merge to main — never applying on a PR, never coupled to app CI/CD.
- [ ] Migrations run as a **release-step artifact** (idempotent; verified twice), not from the
      runtime container or app startup.
- [ ] Secrets come from the **platform secret store**; production **fails fast** on a missing one.
- [ ] `/health/live` + `/health/ready` exist and are **wired to the orchestrator** (readiness gates
      traffic, with a startup grace period).
- [ ] Prometheus metrics at **`/metrics`** (scraped), with a RED dashboard; `/metrics` not public.
- [ ] **Structured JSON logs** to stdout with the required fields; no secrets logged.
- [ ] **Non-root, minimal** runtime image, config from the environment.
- [ ] A **post-deploy smoke gate** fails the deploy on a broken round-trip.
- [ ] **CD from `main` only, after gates**, in a workflow separate from PR CI.
