# Platform Architecture Decision Records

Decisions that govern the **platform repo itself** and the cross-service platform — as
opposed to any single service. Each captures one decision as
**Context → Decision → Consequences**, following [`../spec/adr-discipline.md`](../spec/adr-discipline.md).

Service-level decisions (a service's bounded context, data store, token strategy, …)
live in *that service's* `docs/adr/`, not here. A decision lands here only when it binds
**every** service or the platform's own machinery.

| # | Decision | Status |
|---|---|---|
| [0001](0001-platform-repo-and-sync-model.md) | Platform repo structure + template/sync consumption model (realizes auth ADR-0009) | Accepted |
| [0002](0002-domain-event-envelope-contract.md) | The domain-event envelope contract: CloudEvents v1.0 in structured content mode, the registered extensions used, and the consumers-never-read-transport-metadata rule (realizes `spec` §7; consumed by auth ADR-0019, which chooses a transport behind it) | Proposed |

> **Provenance.** The platform was discovered while building **auth** (service #1), so its
> founding cross-service decisions were first recorded as *auth* ADRs — notably auth
> **ADR-0005** (separate repo per service) and auth **ADR-0009** (shared-asset
> distribution: this repo's charter). Those remain in the auth repo as the historical
> record of how the platform was found; new platform-level decisions are recorded here.
