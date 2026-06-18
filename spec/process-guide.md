# The Complete Senior Engineer's Guide to Building & Running a Microservice in Production

> A full lifecycle playbook — from whiteboard to production monitoring — with every tool explained and prioritized for free/free-tier access.

---

## Table of Contents

1. [Phase 0 — Planning & Architecture](#phase-0)
2. [Phase 1 — Project Scaffolding & Developer Environment](#phase-1)
3. [Phase 2 — Test-Driven Development (TDD)](#phase-2)
4. [Phase 3 — Multi-Layered Testing Strategy](#phase-3)
5. [Phase 4 — CI/CD Pipeline](#phase-4)
6. [Phase 5 — Pre-Production & Staging Management](#phase-5)
7. [Phase 6 — Production Deployment](#phase-6)
8. [Phase 7 — Logging Strategy](#phase-7)
9. [Phase 8 — Monitoring & Observability](#phase-8)
10. [Phase 9 — Post-Production Management & Incident Response](#phase-9)
11. [The Complete Toolchain Summary](#toolchain)

---

## Phase 0 — Planning & Architecture {#phase-0}

This is the phase most junior engineers skip and most senior engineers wish they'd spent more time on. Every decision you make here will cost or save you time in every phase that follows.

### 0.1 Define the Service Contract First

Before writing a single line of code, document what your service does at its boundaries. This is called **contract-first design**.

Answer these questions in writing:
- What problem does this service own? (One sentence.)
- What are its inputs and outputs? (Data shapes, not code.)
- What does it explicitly NOT do? (Defines the boundary.)
- Who calls it? Who does it call?
- What happens when a dependency is down?

**Tool: OpenAPI / Swagger**
- **What it is:** A specification standard (YAML/JSON) that describes your REST API — endpoints, request/response shapes, authentication, error codes — as a machine-readable contract.
- **Why it matters:** It becomes your source of truth. Your tests, your mocks, your documentation, and your client SDKs all derive from it. Changes to the spec trigger downstream awareness.
- **Free tier:** Fully open-source. Use `swagger-editor` (online at editor.swagger.io or run locally).
- **Alternatives:** Postman (free tier), Insomnia (open-source).

**Tool: Excalidraw or draw.io**
- **What it is:** Free diagramming tools for drawing system architecture, data flow, and sequence diagrams.
- **Why it matters:** Drawing the system forces you to find logical gaps before they become code bugs.
- **Free tier:** Both are free. Excalidraw is open-source. draw.io (diagrams.net) is fully free.

### 0.2 Architecture Decision Records (ADRs)

Document every significant technical decision as an ADR — a short Markdown file with: **Context → Decision → Consequences**.

Example decisions to document:
- Why this database? (Postgres vs. MongoDB vs. Redis)
- Sync (REST/gRPC) vs. async (message queue) communication
- Monorepo vs. separate repo
- Stateless vs. stateful service design

Store ADRs in your repository under `/docs/adr/`. They are your future self's most valuable asset during incident post-mortems.

**Tool: adr-tools (CLI)**
- **What it is:** A command-line tool for managing ADR files.
- **Free tier:** Fully open-source.

### 0.3 Define Your Non-Functional Requirements (NFRs)

These are what senior interviews are actually testing. Define them before you build:

| NFR | Example Target | Why It Drives Architecture |
|---|---|---|
| Latency | p99 < 200ms | Affects DB indexing, caching, async choices |
| Throughput | 1,000 req/s | Affects connection pooling, horizontal scaling |
| Availability | 99.9% (8.7 hrs downtime/yr) | Affects redundancy, health checks, retries |
| Data Durability | Zero data loss on crash | Affects write-ahead logging, transaction design |
| Security | Auth on every endpoint | Affects middleware, token strategy |

### 0.4 Domain-Driven Design (DDD) Basics

Identify your **domain entities**, **value objects**, and **aggregates**. Keep your service boundary aligned to a single **bounded context**. This prevents the most common microservice failure: a service that knows too much about other services' internals.

---

## Phase 1 — Project Scaffolding & Developer Environment {#phase-1}

### 1.1 Version Control & Branching Strategy

**Tool: Git + GitHub / GitLab**
- **Free tier:** GitHub free tier is sufficient for most solo/small team work. GitLab free tier includes CI/CD minutes.
- **Branching strategy to use:** GitHub Flow (simpler than GitFflow, appropriate for services with continuous deployment).
  - `main` is always deployable.
  - Features go on short-lived `feature/` branches.
  - Changes enter `main` only via Pull Requests with passing CI.

Set up branch protection on `main`: require passing CI checks and at least one review before merge.

### 1.2 Repository Structure

A production microservice repository should follow this layout:

```
my-service/
├── src/
│   ├── domain/          # Pure business logic, no framework deps
│   ├── application/     # Use cases / service layer
│   ├── infrastructure/  # DB, HTTP clients, message brokers
│   └── api/             # Controllers, route handlers, DTOs
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── docs/
│   └── adr/             # Architecture Decision Records
├── scripts/             # DB migrations, seed scripts, deploy helpers
├── .github/workflows/   # CI/CD pipeline definitions
├── docker-compose.yml   # Local dev environment
├── Dockerfile
├── openapi.yaml         # Service contract
└── README.md
```

This layered structure (Domain → Application → Infrastructure → API) is a simplified **Clean Architecture** / **Hexagonal Architecture**. The key rule: inner layers never import from outer layers. Domain logic never imports your web framework.

### 1.3 Containerize From Day One

**Tool: Docker**
- **What it is:** Packages your app and its runtime dependencies into a portable image that runs identically everywhere.
- **Why it matters:** "Works on my machine" is eliminated. Your local environment, CI, staging, and production all run the same image.
- **Free tier:** Docker Desktop is free for personal use. Docker Hub has a free tier.

Write your `Dockerfile` using a multi-stage build:

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Runtime (lean image, no build tools)
FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY src ./src
EXPOSE 3000
CMD ["node", "src/index.js"]
```

Multi-stage builds produce smaller final images (smaller attack surface, faster pulls).

**Tool: Docker Compose**
- **What it is:** Defines and runs multi-container local environments with a single YAML file.
- **Why it matters:** Your service probably needs a DB, a cache, a message broker. Compose spins all of it up with `docker-compose up`.
- **Free tier:** Bundled with Docker Desktop.

```yaml
# docker-compose.yml — Local dev environment
version: "3.9"
services:
  app:
    build: .
    ports: ["3000:3000"]
    environment:
      DATABASE_URL: postgres://user:pass@db:5432/myservice
    depends_on: [db, redis]

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: myservice
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine

volumes:
  pgdata:
```

### 1.4 Environment Configuration

**Tool: dotenv + environment variable validation**
- Never hardcode secrets. Use `.env` files locally (git-ignored), and inject environment variables in CI/production.
- Use a library like `zod` (Node) or `pydantic` (Python) to validate all required env vars at startup. Fail fast if config is missing — don't let your service start in a broken state.

```javascript
// config.js — Validate on startup, crash with a clear message if broken
import { z } from 'zod';

const schema = z.object({
  DATABASE_URL: z.string().url(),
  PORT: z.coerce.number().default(3000),
  JWT_SECRET: z.string().min(32),
});

export const config = schema.parse(process.env);
```

### 1.5 Dependency Management & Security

**Tool: npm audit / pip-audit / Dependabot**
- Run `npm audit` or `pip-audit` regularly to catch vulnerable dependencies.
- Enable **GitHub Dependabot** (free) to get automated PRs when dependencies have known CVEs.

---

## Phase 2 — Test-Driven Development (TDD) {#phase-2}

TDD is not about coverage numbers. It is a design discipline. Writing the test first forces you to design your code's interface before its implementation.

### 2.1 The TDD Cycle

```
RED   → Write a failing test for the behavior you want.
GREEN → Write the minimum code to make the test pass.
REFACTOR → Clean up the code without breaking the test.
```

Repeat this cycle for every piece of behavior. The test suite becomes a living specification of what your service does.

### 2.2 What to Test First

Always start with your **domain layer** — the pure business logic with no external dependencies. This layer is the cheapest and most valuable to test because:
- Tests run in milliseconds (no DB, no network).
- They encode your business rules as executable documentation.
- They survive framework changes (you can swap Express for Fastify; your domain tests don't care).

### 2.3 TDD Tools by Language

**Node.js / TypeScript:**

*Vitest* (recommended) or *Jest*
- **What it is:** A test runner with built-in assertion library, mocking, and code coverage.
- **Why Vitest over Jest:** Faster, native ESM support, same API as Jest (easy migration).
- **Free tier:** Open-source.

```javascript
// tests/unit/domain/order.test.js
import { describe, it, expect } from 'vitest';
import { Order } from '../../src/domain/order.js';

describe('Order', () => {
  it('should not allow an order with zero items', () => {
    expect(() => new Order({ items: [] }))
      .toThrow('Order must contain at least one item');
  });

  it('calculates total correctly including tax', () => {
    const order = new Order({
      items: [{ price: 100, quantity: 2 }],
      taxRate: 0.1,
    });
    expect(order.total).toBe(220);
  });
});
```

**Python:**

*pytest* (industry standard)
- Cleaner syntax than unittest, powerful fixture system, rich plugin ecosystem.
- Free, open-source.

**Java:**

*JUnit 5 + AssertJ*
- JUnit 5 for test lifecycle. AssertJ for fluent, readable assertions.
- Free, open-source.

### 2.4 Mocking & Stubbing

In unit tests, replace all external dependencies (databases, HTTP clients, message queues) with **mocks** or **stubs**.

- A **stub** returns a fixed value (you control the input).
- A **mock** verifies that a function was called with specific arguments (you verify the interaction).

**Node.js:** Built into Vitest/Jest via `vi.fn()` and `vi.mock()`.
**Python:** Built into pytest via `unittest.mock` or the `pytest-mock` plugin.

```javascript
// Testing a service that depends on a repository (database abstraction)
import { vi, describe, it, expect } from 'vitest';
import { OrderService } from '../../src/application/order-service.js';

describe('OrderService', () => {
  it('saves the order and returns the ID', async () => {
    const mockRepo = {
      save: vi.fn().mockResolvedValue({ id: 'order-123' }),
    };

    const service = new OrderService({ orderRepository: mockRepo });
    const result = await service.createOrder({ items: [{ price: 50, quantity: 1 }] });

    expect(mockRepo.save).toHaveBeenCalledOnce();
    expect(result.id).toBe('order-123');
  });
});
```

### 2.5 Code Coverage

Coverage is a floor, not a ceiling. Aim for high coverage in domain and application layers (90%+), and be practical about infrastructure layers. A 60% coverage score with weak tests is worse than 80% with strong ones.

Configure minimum thresholds in your test runner to fail CI if coverage drops below your agreed floor.

---

## Phase 3 — Multi-Layered Testing Strategy {#phase-3}

The **Testing Trophy** (for microservices) is the mental model: most of your tests should be integration tests, supported by a solid unit test base, with a thin layer of end-to-end tests.

```
         /‾‾‾‾‾‾‾‾‾‾\
        /  E2E Tests  \        ← Few, slow, high confidence
       /‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
      / Integration Tests \    ← Most tests live here
     /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
    /     Unit Tests        \  ← Fast, domain-focused
   /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\
  /  Static Analysis / Types  \ ← Cheapest bug prevention
```

### Layer 1: Static Analysis (Zero Runtime Cost)

**Tool: TypeScript / mypy / pyright**
- Type systems catch entire categories of bugs at compile time for free. Use strict mode.

**Tool: ESLint / Pylint / Checkstyle**
- Linters enforce code style and catch common anti-patterns (unused variables, dangerous patterns).
- Free, open-source.

**Tool: Prettier / Black / gofmt**
- Formatters eliminate style debates and make diffs cleaner.
- Free, open-source.

Run linting and type-checking in CI. A lint failure should block a merge.

### Layer 2: Unit Tests

- **Scope:** A single class, function, or module in isolation.
- **Dependencies:** All external deps are mocked.
- **Speed:** Milliseconds per test. Thousands of tests in under 10 seconds.
- **When they fail:** They pinpoint exactly which logic is broken.
- **Coverage target:** 90%+ on domain and application layers.

### Layer 3: Integration Tests

This is the most important layer for microservices. Integration tests verify that your code works correctly with real infrastructure — a real database, a real cache, a real message broker.

**Tool: Testcontainers**
- **What it is:** A library that spins up real Docker containers (Postgres, Redis, Kafka, etc.) during your test run, then tears them down automatically.
- **Why it matters:** You test your real SQL queries, your real ORM behavior, your real Redis TTL logic — not mocked versions of them. Most production bugs live in this gap.
- **Free tier:** Fully open-source. Available for Node.js, Java, Python, Go, and others.

```javascript
// tests/integration/order-repository.test.js
import { PostgreSqlContainer } from '@testcontainers/postgresql';
import { OrderRepository } from '../../src/infrastructure/order-repository.js';

describe('OrderRepository (Integration)', () => {
  let container;
  let repo;

  beforeAll(async () => {
    container = await new PostgreSqlContainer().start();
    repo = new OrderRepository({ connectionString: container.getConnectionUri() });
    await repo.runMigrations();
  });

  afterAll(() => container.stop());

  it('persists and retrieves an order by ID', async () => {
    const saved = await repo.save({ items: [{ price: 100, quantity: 1 }] });
    const found = await repo.findById(saved.id);
    expect(found.id).toBe(saved.id);
  });
});
```

**Tool: Supertest / httpx**
- **What it is:** Libraries for making real HTTP requests to your server in tests, without actually needing a network.
- **Why it matters:** Tests your route handlers, middleware, validation, and serialization together.

```javascript
// tests/integration/api/orders.test.js
import request from 'supertest';
import { app } from '../../src/api/app.js';

it('POST /orders returns 201 with a valid payload', async () => {
  const res = await request(app)
    .post('/orders')
    .send({ items: [{ productId: 'abc', quantity: 2 }] })
    .set('Authorization', 'Bearer valid-test-token');

  expect(res.status).toBe(201);
  expect(res.body).toHaveProperty('id');
});
```

### Layer 4: Contract Tests

Contract tests are critical in a microservice architecture. They verify that the communication contract between two services doesn't break when either side changes.

**Tool: Pact**
- **What it is:** A consumer-driven contract testing framework. The consumer (the service that calls yours) defines what it expects from the API. The provider (your service) runs those expectations as tests.
- **Why it matters:** Catches breaking API changes before deployment. Replaces the need for a deployed staging environment to test integration between services.
- **Free tier:** Open-source. Pact Broker (the server that stores contracts) has a free hosted tier at pactflow.io (up to 5 integrations).

### Layer 5: End-to-End (E2E) Tests

E2E tests run against a fully deployed, running version of your service (staging environment). They simulate real user/client behavior.

**Tool: Playwright / Cypress (for UI-heavy services)**
**Tool: k6 / Newman (for API-only services)**

- **Newman:** Runs your Postman collections as automated tests. Great for API smoke tests post-deployment.
- **k6:** An open-source load testing tool. Write tests in JavaScript, run load tests to validate your NFRs.
- Keep E2E tests small — only cover the critical happy paths and the highest-risk failure scenarios.

### Layer 6: Performance / Load Testing

Run these before every production release.

**Tool: k6**
- **What it is:** An open-source load testing tool. Write test scripts in JavaScript that simulate concurrent users hitting your API.
- **Why it matters:** Validates your latency NFRs under real load. Catches N+1 query problems, connection pool exhaustion, and memory leaks that never show up in functional tests.
- **Free tier:** k6 open-source is fully free to run locally or in CI.

```javascript
// tests/performance/load-test.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 50,           // 50 virtual users
  duration: '30s',   // for 30 seconds
  thresholds: {
    http_req_duration: ['p(99)<200'],  // 99% of requests under 200ms
    http_req_failed: ['rate<0.01'],    // Less than 1% error rate
  },
};

export default function () {
  const res = http.get('http://localhost:3000/health');
  check(res, { 'status is 200': (r) => r.status === 200 });
}
```

---

## Phase 4 — CI/CD Pipeline {#phase-4}

CI/CD is the automated assembly line that takes code from a developer's machine to production safely and repeatedly.

**CI (Continuous Integration):** Every push triggers automated builds and tests. Broken code never enters `main`.
**CD (Continuous Delivery/Deployment):** Every merged commit is automatically prepared for (or deployed to) production.

### 4.1 Choose Your CI Platform

**Tool: GitHub Actions (Recommended)**
- **What it is:** CI/CD workflows defined as YAML files inside your repository. Triggered by git events (push, pull request, tag).
- **Why it's recommended:** Zero setup if you're on GitHub. Free tier includes 2,000 minutes/month for private repos (unlimited for public repos).
- **Free tier:** Very generous for solo/small teams.

**Alternatives:**
- **GitLab CI/CD:** Free tier with 400 CI minutes/month. Very powerful, especially for self-hosted.
- **CircleCI:** Free tier with 6,000 build minutes/month.

### 4.2 The CI Pipeline — What Runs on Every PR

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      # Layer 1: Static analysis
      - name: Lint
        run: npm run lint

      - name: Type check
        run: npm run typecheck

      # Layer 2: Unit tests
      - name: Unit tests
        run: npm run test:unit -- --coverage

      # Layer 3: Integration tests (Testcontainers handles the DB)
      - name: Integration tests
        run: npm run test:integration

      # Security scan
      - name: Audit dependencies
        run: npm audit --audit-level=high

      # Build the Docker image (verify it builds successfully)
      - name: Build Docker image
        run: docker build -t my-service:${{ github.sha }} .
```

### 4.3 The CD Pipeline — What Runs on Merge to Main

```yaml
# .github/workflows/cd.yml
name: CD

on:
  push:
    branches: [main]

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build and push Docker image
        run: |
          docker build -t registry/my-service:${{ github.sha }} .
          docker push registry/my-service:${{ github.sha }}

      - name: Deploy to staging
        run: ./scripts/deploy.sh staging ${{ github.sha }}

      - name: Run smoke tests against staging
        run: npm run test:e2e -- --env staging

  deploy-production:
    needs: deploy-staging   # Only runs if staging deploy passes
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval in GitHub
    steps:
      - name: Deploy to production
        run: ./scripts/deploy.sh production ${{ github.sha }}
```

### 4.4 Container Registry

**Tool: GitHub Container Registry (GHCR)**
- **What it is:** Stores your Docker images. Integrated with GitHub.
- **Free tier:** Free for public repositories. Private: uses your GitHub storage quota.

**Alternatives:**
- **Docker Hub:** Free tier allows 1 private repo.
- **Google Artifact Registry / AWS ECR:** Both have free tiers.

### 4.5 Semantic Versioning & Release Tags

Tag every production release with a semantic version (`v1.2.3`). Use **Conventional Commits** as your commit message format (`feat:`, `fix:`, `chore:`, etc.) and automate changelog and version bumping.

**Tool: semantic-release**
- Reads your commit history, determines the next version, creates a GitHub release, and publishes changelogs — automatically.
- Free, open-source.

---

## Phase 5 — Pre-Production & Staging Management {#phase-5}

Staging is a production mirror — not a testing playground. The golden rule: **if it doesn't exist in staging, it doesn't exist in production.**

### 5.1 What "Staging" Actually Means

Staging must have:
- The same infrastructure topology as production (same number of replicas, same DB engine and version).
- Production-like (not production) data — anonymized or synthetically generated.
- The same environment variable structure as production (different values, same keys).
- The same deployment process as production (deploy to staging first; then promote the same image to production).

### 5.2 Infrastructure as Code (IaC)

Never click-ops your infrastructure. Define it in code so staging and production are provably identical.

**Tool: Terraform**
- **What it is:** Declares your cloud infrastructure (servers, databases, networking, DNS) as code. Apply the same Terraform config to both staging and production with different variable files.
- **Why it matters:** Eliminates the "it works in staging but not production" class of infrastructure bugs. Infrastructure is reproducible, reviewable, and version-controlled.
- **Free tier:** Terraform OSS is fully free. The cloud resources it provisions cost money, but you minimize this by scaling down staging.

**Tool: Pulumi**
- An alternative to Terraform where you write infrastructure in TypeScript/Python/Go instead of HCL.
- Free tier for individual use.

### 5.3 Database Migrations

**Tool: Flyway / Liquibase / db-migrate**
- **What it is:** Manages database schema changes as versioned, numbered SQL files. Tracks which migrations have run. Runs missing migrations automatically on deploy.
- **Why it matters:** Your database schema is part of your code. Migrations let you evolve it safely, rollback if needed, and keep staging/production in sync.
- **Free tier:** Flyway Community is open-source and free.

Migration workflow:
1. Write a new numbered migration file (`V4__add_index_on_orders_user_id.sql`).
2. Test it against your local Docker DB.
3. CI runs migrations against the integration test DB.
4. CD runs migrations against staging DB before deploying new code.
5. Production deploy runs migrations before swapping traffic.

**Rule: Migrations must be backward-compatible.** The old code must run correctly against the new schema while the deployment is in progress (because deployment is not instantaneous). Never drop a column in the same release that stops using it — deprecate in one release, remove in the next.

### 5.4 Feature Flags

Feature flags decouple deployment from release. You deploy dark (feature disabled), validate in production with a small % of traffic, then roll out.

**Tool: Unleash**
- **What it is:** An open-source feature flag management platform.
- **Why it matters:** Enables canary releases, A/B testing, and instant rollbacks without a new deployment.
- **Free tier:** Self-hosted version is fully free. Cloud free tier supports 2 users.

**Alternative:** **Flagsmith** (open-source, free self-hosted).

### 5.5 Staging Data Management

Never copy real production data to staging. Instead:
- Use database seed scripts (stored in `/scripts/seed.js`) for consistent, repeatable test data.
- For realistic-looking data, use a fake data generator.

**Tool: Faker.js / Faker (Python)**
- Generates realistic fake names, emails, addresses, etc. for seeding staging databases.
- Free, open-source.

---

## Phase 6 — Production Deployment {#phase-6}

### 6.1 Deployment Strategies

Choose your deployment strategy based on your availability requirements:

**Rolling Deployment (Default)**
- Gradually replace old instances with new ones, a few at a time.
- Zero downtime if health checks are configured correctly.
- If new code breaks, some users hit old code, some hit new code during the rollout window.
- Use for: most deployments.

**Blue/Green Deployment**
- Run two identical production environments ("blue" = current, "green" = new).
- Route 100% of traffic to blue. Deploy to green. Run tests against green. Flip traffic to green in one step. Keep blue as instant rollback.
- Use for: high-stakes releases where you need instant rollback capability.

**Canary Deployment**
- Route a small % (1%, 5%) of real traffic to the new version. Monitor error rates and latency. Gradually increase if healthy.
- Use for: changes with uncertain performance characteristics.

### 6.2 Container Orchestration

**Tool: Kubernetes (k8s)**
- **What it is:** The industry-standard container orchestration platform. Manages deploying, scaling, networking, and health-checking your containers across a cluster of machines.
- **Why it matters:** Provides self-healing (auto-restarts failed containers), horizontal scaling, rolling deployments, and service discovery out of the box.
- **Free tier:** Use **k3s** (lightweight Kubernetes) or **Minikube** locally for free. Managed Kubernetes has free tiers on some platforms.

**Managed Kubernetes Free Tiers:**
- **Google Kubernetes Engine (GKE) Autopilot:** Free tier for small workloads.
- **Civo:** Free $250 credit. Very k8s-friendly.
- **Fly.io:** Not k8s, but a very developer-friendly container platform with a generous free tier.

**Alternative for simpler services:**

**Tool: Fly.io**
- **What it is:** Runs Docker containers on a global edge network. Much simpler than Kubernetes for a single microservice.
- **Free tier:** Very generous (3 shared VMs, 3GB persistent storage, 160GB outbound data).
- **Why use it:** If you don't need the full power of Kubernetes, Fly.io deploys your Docker container globally with one command.

### 6.3 Essential Kubernetes Manifests

Every production service needs these Kubernetes objects:

**Deployment** — Defines what runs and how many replicas:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
spec:
  replicas: 3                    # Always at least 3 in production
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      app: my-service
  template:
    spec:
      containers:
        - name: my-service
          image: registry/my-service:v1.2.3
          ports:
            - containerPort: 3000
          # Health checks — critical for zero-downtime deploys
          livenessProbe:          # If this fails, restart the container
            httpGet:
              path: /health/live
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:         # If this fails, stop sending traffic
            httpGet:
              path: /health/ready
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
          # Resource limits — always set these
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
```

**Health Check Endpoints — Required:**

Every production service MUST expose two health endpoints:

- `/health/live` — **Liveness:** Is the process alive? Returns 200 if the server is running. Returns 500 if the process is stuck.
- `/health/ready` — **Readiness:** Is the service ready to receive traffic? Returns 200 only if all dependencies (DB, cache) are connected. During startup or DB failover, returns 503, and Kubernetes stops routing traffic to this instance.

### 6.4 Secrets Management

Never put secrets in environment variables in your Kubernetes YAML or Dockerfile.

**Tool: Kubernetes Secrets + Sealed Secrets / HashiCorp Vault**
- **Kubernetes Secrets:** Base64-encoded (not encrypted) key-value store. Better than plaintext in YAML. Inject into containers as env vars or mounted files.
- **Sealed Secrets:** Encrypts Kubernetes Secrets so they can be safely committed to git. Free, open-source.
- **HashiCorp Vault:** Full secrets management platform. Free open-source version, free cloud tier (HCP Vault Secrets: 25 secrets free).

### 6.5 Horizontal Pod Autoscaler (HPA)

Configure Kubernetes to automatically scale your service based on CPU or custom metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    name: my-service
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70  # Scale up when CPU > 70%
```

---

## Phase 7 — Logging Strategy {#phase-7}

Logs are your primary debugging tool in production. A good logging strategy is the difference between "we found the bug in 5 minutes" and "we spent a day reproducing it."

### 7.1 Structured Logging

Never log plain strings. Log JSON. Every log line should be machine-parseable.

```javascript
// Bad — unstructured, unsearchable
console.log('Order 123 failed for user 456 because item was out of stock');

// Good — structured, searchable, filterable
logger.error({
  event: 'order.failed',
  orderId: '123',
  userId: '456',
  reason: 'item_out_of_stock',
  itemId: 'abc',
  durationMs: 45,
});
```

**Tool: Pino (Node.js) / structlog (Python) / logback + logstash-encoder (Java)**
- **Pino:** The fastest structured logger for Node.js. Outputs NDJSON. Free, open-source.
- **structlog:** Structured logging for Python. Free, open-source.

### 7.2 Mandatory Fields in Every Log Line

Every log entry must include:
- `timestamp` — ISO 8601.
- `level` — `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`.
- `service` — Name of your service.
- `version` — Deployed version.
- `traceId` — The request trace ID (explained in Phase 8).
- `event` — What happened (namespaced: `order.created`, `payment.failed`).
- `environment` — `staging`, `production`.

### 7.3 Log Levels — When to Use Each

| Level | When to use | Production default? |
|---|---|---|
| DEBUG | Verbose detail for debugging. Never use in hot paths. | OFF |
| INFO | Normal business events (order created, user logged in). | ON |
| WARN | Unexpected but recoverable situation (retry #2 of 3). | ON |
| ERROR | Operation failed, requires investigation. | ON |
| FATAL | Service is about to crash. | ON |

Dynamically switch `DEBUG` on in production via a feature flag when debugging a specific incident. Never leave it on permanently.

### 7.4 Correlation IDs / Trace IDs

Assign a unique `traceId` (UUID v4) to every incoming request. Pass it in all log lines, all database queries, and all outgoing HTTP calls (in a header: `X-Trace-Id`). This lets you filter your log aggregator for `traceId = "abc-123"` and see the complete journey of that request across all services.

```javascript
// Middleware that assigns a traceId to every request
app.use((req, res, next) => {
  req.traceId = req.headers['x-trace-id'] || crypto.randomUUID();
  res.setHeader('X-Trace-Id', req.traceId);
  req.log = logger.child({ traceId: req.traceId });
  next();
});
```

### 7.5 Log Aggregation

In production, containers are ephemeral — they can restart and lose logs. Ship your logs to a central aggregation platform.

**Tool: Grafana Loki + Promtail**
- **What it is:** Loki is a log aggregation system by Grafana Labs. Promtail is the agent that collects logs from your containers and ships them to Loki.
- **Why it's recommended:** Cheaper than Elasticsearch because it only indexes labels (not the full log text). Integrates natively with Grafana (which you'll use for metrics too).
- **Free tier:** Grafana Cloud free tier includes 50GB of log ingestion per month and 14-day retention. Excellent for a learning project.

**Alternative:** **Papertrail** — Free tier: 48-hour search, 7-day archive, 100MB/month.

**How to query Loki (LogQL):**
```logql
# Show all errors from the orders service in the last hour
{service="my-service", environment="production"} |= "ERROR"

# Show all logs for a specific trace ID
{service="my-service"} | json | traceId="abc-123-def"

# Count error rate over time
sum(rate({service="my-service"} |= "ERROR" [5m]))
```

### 7.6 What NOT to Log

- Passwords, API keys, secrets (obvious).
- Full credit card numbers or PAN data (PCI-DSS).
- Personal data without a clear need (GDPR/NDPR compliance).
- Request/response bodies by default (can contain sensitive data; log on ERROR only).
- Success logs for every DB query in production (high volume, low value).

---

## Phase 8 — Monitoring & Observability {#phase-8}

Observability is the ability to understand the internal state of your system from its external outputs. It has three pillars:

```
Metrics  → "Is something wrong?"     (quantitative, low cost)
Logs     → "What happened?"          (narrative, medium cost)
Traces   → "Where did it break?"     (request path, high detail)
```

### 8.1 The RED Method for Service Metrics

For every service, instrument these three metric types:

- **R — Rate:** How many requests per second is this service handling?
- **E — Errors:** What percentage of those requests are failing?
- **D — Duration:** How long are requests taking? (p50, p95, p99 — NOT average)

This gives you a complete picture of service health with just three dashboards.

### 8.2 Metrics Collection

**Tool: Prometheus + Grafana**
- **Prometheus:** An open-source metrics collection and storage system. Your service exposes a `/metrics` endpoint. Prometheus scrapes it on a schedule and stores the time-series data.
- **Grafana:** An open-source visualization platform. Connects to Prometheus and renders dashboards.
- **Free tier:** Both are fully open-source. Grafana Cloud free tier includes 10,000 metrics series, 50GB logs, 50GB traces.

**Instrumenting your service (Node.js example):**
```javascript
import { Registry, Counter, Histogram } from 'prom-client';

const registry = new Registry();

// Count total HTTP requests
const httpRequests = new Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [registry],
});

// Track request duration (use Histogram, not Gauge)
const httpDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
  registers: [registry],
});

// Middleware to record metrics
app.use((req, res, next) => {
  const end = httpDuration.startTimer();
  res.on('finish', () => {
    const labels = { method: req.method, route: req.route?.path, status_code: res.statusCode };
    httpRequests.inc(labels);
    end(labels);
  });
  next();
});

// Prometheus scrape endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', registry.contentType);
  res.end(await registry.metrics());
});
```

### 8.3 Alerting

**Tool: Grafana Alerting (built into Grafana)**
- Define alert rules in Grafana based on Prometheus queries.
- Route alerts to Slack, PagerDuty, email, or webhooks.
- Free on Grafana Cloud free tier.

**Critical alerts every service must have:**

| Alert | Condition | Severity |
|---|---|---|
| High Error Rate | Error rate > 1% over 5 min | Critical |
| High Latency | p99 latency > 500ms over 5 min | Warning |
| Service Down | No health check for 1 min | Critical |
| Disk Space Low | Disk usage > 85% | Warning |
| Memory Pressure | Memory usage > 90% | Warning |
| Database Connection Failures | DB error rate > 0 | Critical |

**Tool: PagerDuty / Opsgenie**
- Routes critical alerts to an on-call engineer (phone call, SMS, app push).
- **PagerDuty:** Free tier for 1 on-call responder.
- **Better Stack (BetterUptime):** Free tier includes 3 monitors, 30-day log history.

### 8.4 Distributed Tracing

Distributed tracing follows a single request as it moves through multiple services, recording the time spent in each operation. A trace is composed of **spans** (one span per operation).

**Tool: OpenTelemetry + Jaeger / Tempo**
- **OpenTelemetry (OTel):** The open-source standard for instrumenting code for traces, metrics, and logs. Language-agnostic. One SDK, many backends.
- **Jaeger:** An open-source distributed tracing backend. View request waterfalls.
- **Grafana Tempo:** Grafana's distributed tracing backend. Integrates with Grafana Cloud (free tier).
- **Free tier:** All open-source. Grafana Cloud free tier includes 50GB of traces.

```javascript
// Auto-instrumentation with OpenTelemetry
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';

const sdk = new NodeSDK({
  traceExporter: /* your exporter — Jaeger or Tempo */,
  instrumentations: [getNodeAutoInstrumentations()], // auto-instruments HTTP, DB, etc.
});

sdk.start();
```

With OTel auto-instrumentation, every inbound HTTP request, every DB query, and every outbound HTTP call becomes a span automatically. You see the full tree of operations for any request.

### 8.5 Uptime Monitoring (External)

Internal health checks tell you if the service thinks it's healthy. External uptime monitoring tells you if the service is actually reachable from the outside world.

**Tool: Better Stack (BetterUptime) / UptimeRobot**
- **What they do:** Send HTTP requests to your `/health` endpoint every 1-3 minutes from locations around the world. Alert you if it goes down.
- **UptimeRobot:** Free tier — 50 monitors, 5-minute intervals.
- **Better Stack:** Free tier — 3 monitors, 3-minute intervals.

### 8.6 The Observability Dashboard Checklist

Your Grafana dashboard for a healthy microservice should show:
- [ ] Request rate (req/s) — last 24h
- [ ] Error rate (%) — last 24h
- [ ] p50 / p95 / p99 latency — last 24h
- [ ] Active instances / pod count
- [ ] CPU usage per pod
- [ ] Memory usage per pod
- [ ] Database connection pool utilization
- [ ] Database query latency (p99)
- [ ] Cache hit/miss rate (if applicable)
- [ ] Business metrics (orders/min, signups/hour) — the "golden path"

---

## Phase 9 — Post-Production Management & Incident Response {#phase-9}

This is the phase most interview candidates are missing. Shipping to production is not the finish line.

### 9.1 SLOs, SLAs, and Error Budgets

**SLA (Service Level Agreement):** The commitment you make to your users. "We guarantee 99.9% uptime."

**SLO (Service Level Objective):** The internal target you set to meet your SLA with a buffer. "We target 99.95% uptime internally."

**SLI (Service Level Indicator):** The actual metric you measure. "Last 30 days: 99.97% of requests returned a non-5xx response."

**Error Budget:** The amount of unreliability you're allowed. 99.9% availability means 43.8 minutes of downtime per month is your budget. This budget governs how aggressively you can release. If your error budget is exhausted, you stop shipping features and focus on reliability.

Define your SLOs before you go to production. Store them in your `/docs/slo.md`.

### 9.2 Runbooks

A runbook is a step-by-step document for responding to a specific alert or incident. Write one for every alert you create.

Format:
```
## Alert: High Error Rate on /api/orders

### What this means
> 1% of order requests are returning 5xx errors.

### Immediate triage
1. Check Grafana error rate graph — is it rising or stable?
2. Check Loki for recent ERROR logs — what is the error message?
3. Check if a deployment happened in the last 30 minutes.

### Common causes and fixes
- **DB connection exhaustion:** Check `db_pool_active` metric. If at max, 
  restart the service pods and increase `DATABASE_POOL_SIZE`.
- **Downstream service failure:** Check trace in Jaeger for failed spans.
  Enable circuit breaker for that dependency.
- **Bad deploy:** Rollback with `kubectl rollout undo deployment/my-service`.

### Escalation
If not resolved in 15 minutes, page the DB team lead.
```

Store runbooks in your repository under `/docs/runbooks/`. They are living documents — update them after every incident.

### 9.3 Incident Response Process

A structured incident response prevents chaos and speeds up resolution:

**1. Detect** — Alert fires (Grafana/PagerDuty). Don't wait for user reports.

**2. Respond** — Acknowledge the alert. Create an incident channel (Slack: `#incident-2024-01-15`).

**3. Assess** — What is the blast radius? How many users affected? Is data at risk?

**4. Mitigate FIRST** — Rollback, disable feature flag, scale up. Restore service before you investigate root cause. Speed of recovery matters more than speed of root cause analysis during an incident.

**5. Resolve** — Confirm metrics returned to normal. Close the incident.

**6. Post-mortem** — Within 48 hours.

**Tool: Incident.io / PagerDuty / Rootly**
- Manages incident lifecycle (declare, track, communicate, resolve).
- **Incident.io:** Free tier available.

### 9.4 Post-Mortem (Blameless)

A post-mortem is the most valuable artifact an incident produces. The rule: **blameless**. No individual is at fault. Systems and processes are at fault. This creates psychological safety, which creates honesty, which creates better post-mortems.

**Post-Mortem Template:**

```markdown
## Incident Post-Mortem: [Title]
**Date:** | **Duration:** | **Severity:** | **Author:**

### Summary
One paragraph. What happened, what was the user impact, how was it resolved.

### Timeline
| Time (UTC) | Event |
|---|---|
| 14:22 | Alert fired: High error rate on /orders |
| 14:25 | Engineer acknowledged, started investigation |
| 14:31 | Root cause identified: DB migration lock |
| 14:35 | Mitigation applied: migration rolled back |
| 14:37 | Error rate returned to normal |

### Root Cause
The V12 migration added a full table lock on the orders table (47M rows), 
which blocked all ORDER INSERTs for ~13 minutes.

### Contributing Factors
- Migration was not tested against production-scale data (staging had 10K rows).
- No procedure for estimating migration lock duration before deploy.

### What Went Well
- Alert fired within 3 minutes of incident start.
- Rollback procedure was documented and executed in 4 minutes.

### Action Items
| Action | Owner | Due |
|---|---|---|
| Add 10M row seed option to staging | @engineer | Jan 22 |
| Add migration duration estimator script to deploy checklist | @lead | Jan 20 |
| Create runbook for migration-related incidents | @engineer | Jan 22 |
```

### 9.5 Canary Analysis & Automatic Rollback

Configure your CD pipeline to automatically rollback if a new deployment degrades key metrics.

**Tool: Argo Rollouts (Kubernetes)**
- **What it is:** Kubernetes controller for advanced deployment strategies (canary, blue/green) with automated analysis.
- **Free tier:** Open-source.
- It can automatically rollback if error rate or latency exceeds thresholds during a canary rollout.

### 9.6 Chaos Engineering

Intentionally inject failures into your production system (during low-traffic periods) to verify your resilience mechanisms work.

**Tool: Chaos Monkey / LitmusChaos**
- **LitmusChaos:** Open-source chaos engineering platform for Kubernetes. Randomly kills pods, introduces network latency, simulates disk failures.
- **Free tier:** Open-source.

Chaos engineering validates that your health checks, circuit breakers, retries, and autoscalers actually work before a real incident forces the test.

---

## The Complete Toolchain Summary {#toolchain}

| Phase | Tool | Purpose | Cost |
|---|---|---|---|
| **Planning** | Swagger Editor | API contract design | Free |
| **Planning** | Excalidraw | Architecture diagrams | Free |
| **Scaffolding** | GitHub | Version control + CI | Free tier |
| **Scaffolding** | Docker + Compose | Containerization | Free |
| **TDD** | Vitest / pytest | Test runner | Free |
| **Testing** | Testcontainers | Real DB in tests | Free |
| **Testing** | Supertest / httpx | API integration tests | Free |
| **Testing** | Pact | Contract testing | Free (OSS) |
| **Testing** | k6 | Load / perf testing | Free |
| **CI/CD** | GitHub Actions | CI/CD pipeline | Free tier |
| **CI/CD** | GHCR | Container registry | Free tier |
| **Staging** | Terraform | Infrastructure as Code | Free (OSS) |
| **Staging** | Flyway | DB migrations | Free (OSS) |
| **Staging** | Unleash | Feature flags | Free (self-host) |
| **Production** | Fly.io / k8s | Container orchestration | Free tier |
| **Production** | Sealed Secrets | Secrets management | Free |
| **Logging** | Pino / structlog | Structured logging | Free |
| **Logging** | Grafana Loki | Log aggregation | Free tier (50GB/mo) |
| **Monitoring** | Prometheus | Metrics collection | Free |
| **Monitoring** | Grafana | Dashboards + alerting | Free tier |
| **Monitoring** | OpenTelemetry + Tempo | Distributed tracing | Free tier |
| **Monitoring** | UptimeRobot | External uptime monitoring | Free (50 monitors) |
| **Incidents** | PagerDuty | On-call alerting | Free (1 user) |
| **Post-production** | Argo Rollouts | Canary + auto-rollback | Free |
| **Post-production** | LitmusChaos | Chaos engineering | Free |

---

## The Senior Engineer Mindset Checklist

Before every deployment, a senior engineer asks:

- [ ] **Can I roll this back in under 5 minutes?** (Deployment strategy + runbook)
- [ ] **Will I know within 3 minutes if this breaks something?** (Alerting)
- [ ] **Can I debug it without a debugger attached?** (Structured logs + traces)
- [ ] **What happens if the database is unavailable for 30 seconds?** (Circuit breaker + graceful degradation)
- [ ] **What happens if this pod is killed mid-request?** (Graceful shutdown handler)
- [ ] **Does this deployment change the DB schema in a way that breaks the current running version?** (Backward-compatible migrations)
- [ ] **Is the staging test result a reliable predictor of production behavior?** (Staging parity)

The difference between a junior and a senior is not the ability to write code. It is the ability to reason about systems under failure conditions, communicate that reasoning to a team, and build the scaffolding (tests, observability, runbooks) that makes the system safe to operate and change over time.

---

*This guide is your living document. Revisit and update each section as you build your service. The act of building a real system end-to-end with this framework — not just reading it — is what builds the intuition interviewers are testing for.*
