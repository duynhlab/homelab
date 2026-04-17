# AI Agent Guide

> **IMPORTANT**: AGENTS.md files are the source of truth for AI agent instructions. Always update the relevant AGENTS.md file when adding or modifying agent guidance.

> **IMPORTANT**: This project is directly related to the user's day-to-day work as a Senior DevOps / SRE. Recommendations should prioritize production-grade, scalable, and maintainable solutions.

> **CRITICAL**: **ALWAYS READ THIS FILE FIRST** before starting any task. This file contains essential patterns, conventions, and best practices that must be followed.

## Overview

This guide provides quick reference for AI agents working with the `duynhlab` microservices platform.

**Repository Context**:
- **This Repository (`monitoring`)**: Infrastructure, GitOps, Observability, and Docs.
- **Service Repositories**: Application code is in separate repositories (e.g., `auth-service`, `user-service`).
- **Shared Workflows**: CI/CD templates in `duyhenryer/shared-workflows`.

**Detailed Index**: See [`docs/`](docs/README.md) for platform docs and [**SERVICES.md**](SERVICES.md) for the list of repositories.

---

## Agent Workflow

### Before Starting Any Task

1.  **Identify the Scope**:
    - **Infrastructure/GitOps**: Work in this repository (`monitoring`).
    - **Application Code**: Check [**SERVICES.md**](SERVICES.md) to find the correct service repo.
    - **CI/CD Pipelines**: Check `duyhenryer/shared-workflows` if modifying reusable workflows.
2.  **Read AGENTS.md FIRST** - In the target repository (each service has its own AGENTS.md).
3.  **Read relevant docs** - Check `docs/` in this repo for architecture/platform context.
4.  **Plan before coding** - Understand the problem, propose solution, get approval.

### Code Quality Standards (General)

(See specific `AGENTS.md` in service repositories for language-specific standards)

- **Consistency**: Follow existing code patterns.
- **Documentation**: Update relevant docs when adding features.
- **Testing**: Write tests for new functionality.
- **Error Handling**: Use consistent error patterns.
- **Logging**: Use structured logging with appropriate levels.

---

## Documentation Standards

### Diagram Requirements

**MANDATORY**: All architecture diagrams, flowcharts, and system visualizations MUST use Mermaid syntax.

**Rules**:

1. ❌ **NEVER** use ASCII art diagrams (boxes with `┌─┐`, arrows with `│`, `→`, `▼`, etc.)
2. ✅ **ALWAYS** use Mermaid diagrams for:
   - Architecture diagrams (`flowchart`, `graph`)
   - Sequence diagrams (`sequenceDiagram`)
   - State diagrams (`stateDiagram`)
   - Entity relationship diagrams (`erDiagram`)
   - Class diagrams (`classDiagram`)
   - Gantt charts (`gantt`)

**Examples**:

```mermaid
flowchart TD
    A[Component A] --> B[Component B]
    B --> C[Component C]
```

**Enforcement**: When reviewing or creating documentation:

- Replace existing ASCII diagrams with Mermaid equivalents
- Ensure all new diagrams use Mermaid syntax
- Use appropriate Mermaid diagram types for the content

---

## Development Commands

### Infrastructure & GitOps

This repository manages deployment via **Flux**.

```bash
# Validate manifests (dry-run)
make validate

# Deploy entire platform (Kind + Flux + Apps)
make up

# Check status
make flux-status
```

### Microservices Development

To work on a specific service (e.g., `auth-service`):

1.  **Find Repo**: Check [**SERVICES.md**](SERVICES.md).
2.  **Clone**: `git clone https://github.com/duynhlab/auth-service` (or use setup script).
3.  **Run Locally** (inside service repo):
    ```bash
    go run cmd/main.go
    ```
4.  **Test**: `go test ./...`

**GitOps Deployment**: See deployment commands in [Deployment Order](#deployment-order) section. Use `make up` for one-command deployment or `make flux-push` to deploy all services to Kubernetes.

---

## Architecture Overview

### 3-Layer Architecture

All microservices follow a consistent 3-layer architecture:

```mermaid
flowchart TD
    subgraph Web["Web Layer (web/v1/)"]
        Handler[HTTP Handlers<br/>Request/Response<br/>Validation]
    end
    
    subgraph Logic["Logic Layer (logic/v1/)"]
        Service[Business Logic<br/>Orchestration<br/>Database Queries]
    end
    
    subgraph Core["Core Layer (core/)"]
        Domain[Domain Models]
        Database[Database Connection<br/>core/database.go]
    end
    
    Handler -->|calls| Service
    Service -->|uses| Domain
    Service -->|queries| Database
    Database -->|PostgreSQL| DB[(Database)]
```

**Database Integration**: See [`docs/databases/002-database-integration.md`](docs/databases/002-database-integration.md) for database architecture, connection patterns (direct, PgBouncer, PgDog), and configuration.

**Layer Responsibilities**:

- **Web Layer** (`web/v1/`): HTTP handlers, request/response, validation
- **Logic Layer** (`logic/v1/`): Business logic, orchestration, Cache-Aside pattern, database queries via repository interfaces
- **Core Layer** (`core/domain/`, `core/database.go`, `core/cache/`): Domain models, database connections, cache client interfaces and implementations

**Detailed Architecture**: See [`docs/observability/architecture.md`](docs/observability/architecture.md) for middleware chain and APM integration. Full system architecture in [`specs/system-context/01-architecture-overview.md`](specs/system-context/01-architecture-overview.md)

---

### Frontend Integration Rules

**CRITICAL**: Frontend (React SPA) can ONLY interact with Web Layer endpoints.

**Allowed:**

- ✅ HTTP requests to `/api/v1/*` endpoints (canonical API)
- ✅ All requests go through Web Layer handlers
- ✅ Web Layer handles aggregation, validation, error translation

**Forbidden:**

- ❌ Direct calls to Logic Layer (no function calls to services)
- ❌ Direct calls to Core Layer (no database access)
- ❌ Client-side orchestration (use aggregation endpoints instead)
- ❌ Bypassing Web Layer in any way

**Why:**

- Web Layer provides HTTP interface, validation, authentication
- Logic/Core layers are internal implementation details
- Aggregation endpoints handle complex operations server-side

**Reference:** See [`docs/api/api.md`](docs/api/api.md) for complete API documentation and 3-layer architecture details.

---

## Key Design Patterns

- **Clean Architecture**: 3-layer separation (web → logic → core) with clear boundaries
- **Frontend → Web Layer Only**: Frontend can ONLY call Web Layer HTTP endpoints, never Logic/Core directly
- **API Versioning**: v1 only (canonical, frontend-aligned); v2 removed
- **Microservices**: 8 independent services with bounded contexts, each in own namespace
- **Middleware Chain**: Ordered middleware (tracing → logging → metrics) for observability
- **Caching**: Cache-Aside pattern with Valkey (Redis-compatible) for read-heavy endpoints

**Middleware Details**: See [`docs/observability/tracing/architecture.md`](docs/observability/tracing/architecture.md) for middleware chain ordering and responsibilities.

**Caching Details**: See [`docs/caching/caching.md`](docs/caching/caching.md) for cache architecture, Cache-Aside pattern, and configuration.

---

## Technology Stack

- **Runtime**: Go 1.25
- **Database**: PostgreSQL (3 clusters + DR replica via Zalando/CloudNativePG operators)
  - Connection poolers: PgBouncer, PgDog
  - Migrations: Flyway 11.19.0 (8 migration images)
  - **Database Documentation**: [`docs/databases/002-database-integration.md`](docs/databases/002-database-integration.md)
- **Cache**: Valkey (Redis-compatible) for read-heavy endpoints
  - Cache-Aside pattern in Logic Layer
  - Product service: `GET /api/v1/products`, `GET /api/v1/products/:id`
  - **Caching Documentation**: [`docs/caching/caching.md`](docs/caching/caching.md)
- **HTTP Framework**: Gin
- **Observability**: OpenTelemetry (traces, metrics, logs)
- **GitOps**: Flux Operator, Kustomize, OCI Registry
- **Deployment**: Kubernetes (Kind), Helm 3
- **Monitoring**: VictoriaMetrics (VMSingle, VMAgent, VMAlert, VMAlertmanager), Grafana, Tempo, VictoriaLogs, Pyroscope, Jaeger, Vector
- **Secrets**: OpenBAO (HA Raft, 3-node) + External Secrets Operator (ESO)
  - Centralized secret management with Kubernetes sync
  - **Secrets Documentation**: [`docs/secrets/secrets-management.md`](docs/secrets/secrets-management.md)

**Observability Details**: See [`docs/observability/README.md`](docs/observability/README.md) for complete observability system overview. Metrics documentation in [`docs/observability/metrics/README.md`](docs/observability/metrics/README.md)

---

## Project Structure

```
monitoring/
├── kubernetes/        # GitOps manifests (Flux + Kustomize)
│   ├── clusters/      # Flux cluster configurations (local/prod)
│   ├── infra/         # Controllers + configs (operators, monitoring, databases, secrets)
│   └── apps/          # Domain ResourceSets + per-service InputProviders + frontend
├── scripts/           # Kind/Flux helper scripts (used by Makefile)
├── docs/              # Documentation (starting point for details)
└── specs/             # Specifications and research
```

**GitOps Structure:**

- `kubernetes/clusters/` - Flux bootstrap and Kustomization CRDs per cluster
- `kubernetes/infra/` - Operators/controllers + infrastructure configs (monitoring, APM, databases, secrets, SLO)
- `kubernetes/apps/` - Application layer (domain ResourceSets + per-service InputProviders + frontend)

**Full Documentation Index**: See [`docs/README.md`](docs/README.md) for complete documentation structure.

---

## API Endpoints

8 microservices with RESTful APIs (v1 only - canonical, frontend-aligned):

| Service | Namespace | Base URL |
|---------|-----------|----------|
| auth | auth | `/api/v1/*` |
| user | user | `/api/v1/*` |
| product | product | `/api/v1/*` |
| cart | cart | `/api/v1/*` |
| order | order | `/api/v1/*` |
| review | review | `/api/v1/*` |
| notification | notification | `/api/v1/*` |
| shipping | shipping | `/api/v1/*` |

**Complete API Documentation**: See [`docs/api/api.md`](docs/api/api.md) for all endpoints, request/response models, and examples.

---

## Important Notes

### Deployment Order

**GitOps Workflow** - Infrastructure → Apps (Flux enforces via `dependsOn`)

```bash
# One-command deployment
make up

# Or step-by-step:
make cluster-up   # 1. Create Kind Cluster + OCI Registry
make flux-up      # 2. Bootstrap Flux Operator
make flux-push    # 3. Deploy All (Flux reconciles in dependency order)
```

**Flux automatically deploys in correct order:**

1. **Foundation** - Flux Operator, namespaces, OCI sources
2. **Infrastructure** (BEFORE apps) - Monitoring, APM, Databases, SLO
   - Monitoring: VictoriaMetrics (VMSingle, VMAgent, VMAlert), Grafana, Metrics Server
   - APM: Tempo, VictoriaLogs, Vector, OTel Collector, Pyroscope, Jaeger
   - MCP Servers: victoria-metrics-mcp, victoria-logs-mcp, flux-operator-mcp
   - Databases: PostgreSQL operators, 3 clusters + DR replica, connection poolers
   - SLO: Sloth Operator + 8 PrometheusServiceLevel CRDs
3. **Applications** - 8 microservices + frontend + k6 load testing

**Dependency Chain:**

```
flux-system (bootstrap)
  ├── controllers-local (operators, CRDs, Kong, cert-manager, secrets managers)
  ├── cert-manager-local (depends: controllers)
  ├── kong-config-local (depends: controllers + cert-manager) — Ingress resources
  ├── secrets-local (depends: controllers)
  ├── databases-local (depends: secrets + monitoring)
  ├── databases-cnpg-dr-local (depends: databases + secrets) — DR replica
  ├── monitoring-local (depends: controllers) — VMSingle, VLSingle, Grafana, alerting
  ├── mcp-local (depends: monitoring, wait: false) — 3 MCP HelmReleases
  └── apps-local (depends: databases + monitoring) — 8 microservices via ResourceSets
```

- Apps **will NOT start** until infrastructure is ready
- Flux enforces this automatically via Kustomization CRDs

**Verification:**

```bash
# Check Flux reconciliation status
make flux-status
# Or: flux get kustomizations

# Check all resources
kubectl get pods --all-namespaces
kubectl get helmreleases --all-namespaces

# Trigger manual reconciliation (if needed)
make flux-sync
# Or: flux reconcile kustomization infrastructure-local --with-source
```

**Detailed Deployment Guide**: See [`docs/platform/setup.md`](docs/platform/setup.md)

### Key Infrastructure

- **3 PostgreSQL Clusters + DR**: auth-db (Zalando), supporting-shared-db (Zalando), cnpg-db (CNPG, hosts product/cart/order), cnpg-db-replica (CNPG DR)
- **Connection Poolers**: PgBouncer (Auth, Shared), PgDog (cnpg-db)
- **Migrations**: Flyway 11.19.0 with 8 migration images
- **Operators**: Zalando Postgres Operator (v1.15.1), CloudNativePG Operator (v1.28.1)
- **SLO**: Managed via Sloth Operator (PrometheusServiceLevel CRDs)
- **CI/CD**: GitHub Actions workflows (build-images, build-init-images, build-k6-images, helm-release)

---

## Quick Navigation

### Detailed Guides

- **Command Reference**: See [`docs/platform/setup.md`](docs/platform/setup.md#command-reference) - Deployment scripts, Helm, kubectl commands
- **Conventions**: [`docs/api/api.md`](docs/api/api.md#conventions-and-standards) - Naming conventions, code standards, build verification
- **API Reference**: [`docs/api/api.md`](docs/api/api.md) - Complete API documentation
- **Setup Guide**: [`docs/platform/setup.md`](docs/platform/setup.md) - Deployment instructions
- **Configuration**: [`docs/api/api.md`](docs/api/api.md) - Environment variables and config
- **Database**: [`docs/databases/002-database-integration.md`](docs/databases/002-database-integration.md) - Database architecture and patterns; [`docs/databases/010-documents.md`](docs/databases/010-documents.md) - Further reading (internals, replication, ops)

### Find Files by Purpose

**Add a new service:**

- Service code: separate repo (e.g., `duynhlab/{service}-service`)
- Create `kubernetes/apps/services/{name}.yaml` (ResourceSetInputProvider with `platform.duynhlab.dev/domain: <domain>` label)
- The domain ResourceSet in `kubernetes/apps/domains/` auto-discovers the new InputProvider via label selector
- SLO: `slo.enabled: true` is set in the shared domain template (automatic for all backend services)
- Migration image: built in the service repo, referenced automatically by the template
- Deploy: `make validate && make sync`
- See [`docs/platform/application-delivery.md`](docs/platform/application-delivery.md) for full onboarding guide

**Update monitoring:**

- Dashboard JSON: `kubernetes/infra/configs/monitoring/grafana/dashboards/*.json`
- ServiceMonitors: `kubernetes/infra/configs/monitoring/servicemonitors/`
- PodMonitors: `kubernetes/infra/configs/monitoring/podmonitors/`

**Modify SLOs:**

- Edit CRDs: `kubernetes/infra/configs/monitoring/slo/*.yaml` (PrometheusServiceLevel CRDs)
- Push changes: `make flux-push` (updates OCI registry)
- Apply: Flux reconciles automatically, or `make flux-sync`

**Modify infrastructure:**

- Databases: `kubernetes/infra/configs/databases/`
- Controllers: `kubernetes/infra/controllers/` (metrics, logging, tracing, profiling, databases, secrets)
- Configs: `kubernetes/infra/configs/` (monitoring, databases, secrets)
- MCP servers: `kubernetes/infra/controllers/mcp/` (decoupled from controllers chain)
- Kong Ingress: `kubernetes/infra/configs/kong/` (ingress resources for all services)
- Cluster Kustomizations: `kubernetes/clusters/local/` (dependency chain)

**Add/modify secrets:**

- OpenBAO bootstrap: `kubernetes/infra/configs/secrets/openbao-bootstrap/configmap.yaml` (add `bao kv put` command)
- ClusterExternalSecret (shared): `kubernetes/infra/configs/secrets/cluster-external-secrets/{name}.yaml`
- ExternalSecret (per-cluster): `kubernetes/infra/configs/databases/clusters/{cluster}/secrets/{name}.yaml`
- ClusterSecretStore: `kubernetes/infra/configs/secrets/cluster-secret-store.yaml`
- OpenBAO HelmRelease: `kubernetes/infra/controllers/secrets/openbao/helmrelease.yaml`
- ESO HelmRelease: `kubernetes/infra/controllers/secrets/external-secrets/helmrelease.yaml`

**Access services via domain names:**

- All services are routed through Kong Ingress Controller with `/etc/hosts` mapping
- Domain pattern: `*.duynhne.me` (e.g., `grafana.duynhne.me`, `vmui.duynhne.me`)
- Kong runs as NodePort (30080/30443), Kind maps host ports 80/443
- Fallback: `make flux-ui` for port-forwarding
- See `README.md` for full domain list and `/etc/hosts` setup

### Gateway Edge Naming (Variant A — adopted)

All **browser** API traffic goes through Kong at `gateway.duynhne.me` using Variant A edge paths:

```
https://gateway.duynhne.me/{service}/v1/{audience}/{resource...}
```

- `{service}` ∈ `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`.
- `{audience}` ∈ `public` (anonymous), `private` (JWT user), `protected` (webhooks — reserved), `internal` (**never** on the gateway).
- `{resource...}` mirrors the cluster resource path.

**Services keep `/api/v1/*`** — Kong rewrites edge → cluster via a per-namespace `KongPlugin` (pre-function) called `rewrite-edge-to-cluster`. Service handlers and JWT middleware are unchanged.

**Sample mappings:**

| Browser (edge) | Cluster (service-to-service) |
|----------------|------------------------------|
| `POST gateway.duynhne.me/auth/v1/public/login` | `POST /api/v1/auth/login` |
| `GET gateway.duynhne.me/product/v1/public/products/:id/details` | `GET /api/v1/products/:id/details` |
| `GET gateway.duynhne.me/cart/v1/private/cart` | `GET /api/v1/cart` |
| `GET gateway.duynhne.me/order/v1/private/orders/:id/details` | `GET /api/v1/orders/:id/details` |
| `GET gateway.duynhne.me/notification/v1/private/notifications` | `GET /api/v1/notifications` |

**Rules for AI agents:**

1. **Never** add internal endpoints (`POST /notify/*`, `POST /products`, `POST /users`, `GET /shipping/orders/:id`) to `ingress-api.yaml`. They stay reachable only via in-cluster `*.svc.cluster.local` DNS.
2. When adding a new browser-facing route: add the service handler on `/api/v1/*`, add an edge row to `ingress-api.yaml` + (if shape differs) update `rewrite-plugins.yaml`, and update the mapping table in `docs/api/api-naming-convention.md`.
3. When the frontend needs a new call, use the edge path, not the cluster path. Frontend base URL is `VITE_API_BASE_URL` (defaults to `http://gateway.duynhne.me`).

**Authoritative docs:**

- [`docs/api/api-naming-convention.md`](docs/api/api-naming-convention.md) — edge convention + complete mapping.
- [`docs/api/api.md`](docs/api/api.md) — cluster-internal API reference (source of truth for handler contracts).
- [`docs/platform/kong-gateway.md`](docs/platform/kong-gateway.md) — Kong setup, CORS, rate limiting, verification runbook.

### Demo / Test Credentials

Default seeded user (Flyway migration on `auth-db`) — use for login testing:

- **Username**: `alice`
- **Password**: `password123`
- **Email**: `alice@example.com`

Hardcoded as initial form values in `frontend/src/pages/LoginPage/LoginPage.jsx`.

**API usage:**

```bash
# Login via API (use username, NOT email)
curl -H "Host: gateway.duynhne.me" -X POST http://localhost/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"password123"}'
# → {"token":"jwt-token-...","user":{"id":"1","username":"alice","email":"alice@example.com"}}
```

Token stored in `localStorage.authToken`, sent as `Authorization: Bearer <token>` on subsequent requests.

### Find Documentation by Topic

- **Getting Started**: [`docs/platform/setup.md`](docs/platform/setup.md), [`docs/api/api.md`](docs/api/api.md)
- **Development**: [`docs/api/api.md`](docs/api/api.md), [`docs/api/api.md#error-handling`](docs/api/api.md#error-handling), [`docs/observability/tracing/architecture.md`](docs/observability/tracing/architecture.md)
- **Monitoring**: [`docs/observability/metrics/README.md`](docs/observability/metrics/README.md), [`docs/observability/metrics/postgresql/monitoring.md`](docs/observability/metrics/postgresql/monitoring.md) (PostgreSQL exporters, VMAgent/VMSingle, alerts)
- **Observability**: [`docs/observability/README.md`](docs/observability/README.md), [`docs/observability/tracing/README.md`](docs/observability/tracing/README.md), [`docs/observability/logging/README.md`](docs/observability/logging/README.md), [`docs/observability/profiling/README.md`](docs/observability/profiling/README.md)
- **SLO**: [`docs/observability/slo/README.md`](docs/observability/slo/README.md), [`docs/observability/slo/getting_started.md`](docs/observability/slo/getting_started.md)
- **Secrets**: [`docs/secrets/secrets-management.md`](docs/secrets/secrets-management.md), [`docs/secrets/openbao.md`](docs/secrets/openbao.md) (OpenBAO architecture + Flux/sealed runbook in §13)
- **k6**: [`docs/testing/k6.md`](docs/testing/k6.md)
- **Docs Index**: [`docs/README.md`](docs/README.md)

---

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for complete version history.

**Important for AI Agents**: Do NOT modify existing entries in [`CHANGELOG.md`](CHANGELOG.md). ONLY add new entries at the top. Never edit or remove historical changelog entries.

---
