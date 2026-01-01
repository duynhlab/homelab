# AI Agent Guide

> **IMPORTANT**: AGENTS.md files are the source of truth for AI agent instructions. Always update the relevant AGENTS.md file when adding or modifying agent guidance.

> **CRITICAL**: **ALWAYS READ THIS FILE FIRST** before starting any task. This file contains essential patterns, conventions, and best practices that must be followed.

## Overview

This guide provides quick reference for AI agents working with this codebase. For detailed documentation, see [`docs/`](docs/README.md) - start with [`docs/guides/`](docs/guides/) for development workflows.

---

## Agent Workflow

### Before Starting Any Task

1. **Read AGENTS.md FIRST** - This file contains essential patterns, conventions, and best practices
2. **Read relevant docs** - Check `docs/guides/` for existing documentation
3. **Research if needed** - For API/architecture work, research industry patterns (see [`docs/guides/RESEARCH_PATTERNS.md`](docs/guides/RESEARCH_PATTERNS.md))
4. **Plan before coding** - Understand the problem, propose solution, get approval
5. **Follow conventions** - Use existing patterns, don't reinvent

### Code Quality Standards

- **Consistency**: Follow existing code patterns (see [`docs/guides/API_REFERENCE.md`](docs/guides/API_REFERENCE.md#conventions-and-standards))
- **Documentation**: Update relevant docs when adding features
- **Testing**: Write tests for new functionality
- **Error Handling**: Use consistent error patterns
- **Logging**: Use structured logging with appropriate levels (see [`docs/apm/LOGGING.md`](docs/apm/LOGGING.md))
- **API Patterns**: Research industry best practices before implementing (see [`docs/guides/RESEARCH_PATTERNS.md`](docs/guides/RESEARCH_PATTERNS.md))
- **APM Patterns**: Follow established observability patterns (see [`docs/apm/`](docs/apm/))
- **Database Patterns**: Research database patterns, reference [`docs/guides/DATABASE.md`](docs/guides/DATABASE.md)

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

```mermaid
sequenceDiagram
    Client->>API: Request
    API->>Database: Query
    Database-->>API: Response
    API-->>Client: Result
```

**Enforcement**: When reviewing or creating documentation:
- Replace existing ASCII diagrams with Mermaid equivalents
- Ensure all new diagrams use Mermaid syntax
- Use appropriate Mermaid diagram types for the content

---

## Development Commands

Quick Go commands for local development (no Docker/Kubernetes needed):

```bash
# Run service locally
cd services
go run cmd/{service}/main.go

# Run tests
go test ./...
go test ./internal/{service}/...

# Build binary (no Docker needed for dev)
go build -o bin/{service} cmd/{service}/main.go
```

**Detailed Configuration**: See [`docs/guides/CONFIGURATION.md`](docs/guides/CONFIGURATION.md) for environment variables, `.env` files, and local setup.

**Deployment**: Docker/Kubernetes deployment details in [`docs/guides/SETUP.md`](docs/guides/SETUP.md)

---

## Architecture Overview

### 3-Layer Architecture

All microservices follow a consistent 3-layer architecture:

```mermaid
flowchart TD
    subgraph Web["Web Layer (web/v1/, web/v2/)"]
        Handler[HTTP Handlers<br/>Request/Response<br/>Validation]
    end
    
    subgraph Logic["Logic Layer (logic/v1/, logic/v2/)"]
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

**Database Integration**: See [`docs/guides/DATABASE.md`](docs/guides/DATABASE.md) for database architecture, connection patterns (direct, PgBouncer, PgCat), and configuration.

**Layer Responsibilities**:
- **Web Layer** (`web/v1/`, `web/v2/`): HTTP handlers, request/response, validation
- **Logic Layer** (`logic/v1/`, `logic/v2/`): Business logic, orchestration, database queries
- **Core Layer** (`core/domain/`, `core/database.go`): Domain models, database connections

**Detailed Architecture**: See [`docs/apm/ARCHITECTURE.md`](docs/apm/ARCHITECTURE.md) for middleware chain and APM integration. Full system architecture in [`specs/system-context/01-architecture-overview.md`](specs/system-context/01-architecture-overview.md)

---

## Key Design Patterns

- **Clean Architecture**: 3-layer separation (web → logic → core) with clear boundaries
- **API Versioning**: Parallel v1/v2 endpoints, no breaking changes, gradual migration path
- **Microservices**: 9 independent services with bounded contexts, each in own namespace
- **Middleware Chain**: Ordered middleware (tracing → logging → metrics) for observability

**Middleware Details**: See [`docs/guides/TRACING_ARCHITECTURE.md`](docs/guides/TRACING_ARCHITECTURE.md) for middleware chain ordering and responsibilities.

---

## Technology Stack

- **Runtime**: Go 1.25
- **Database**: PostgreSQL (5 clusters via Zalando/CloudNativePG operators)
  - Connection poolers: PgBouncer, PgCat
  - Migrations: Flyway 11.19.0 (8 migration images)
  - **Database Documentation**: [`docs/guides/DATABASE.md`](docs/guides/DATABASE.md)
- **HTTP Framework**: Gin
- **Observability**: OpenTelemetry (traces, metrics, logs)
- **Deployment**: Kubernetes (Kind), Helm 3
- **Monitoring**: Prometheus, Grafana, Tempo, Loki, Pyroscope, Jaeger

**Observability Details**: See [`docs/apm/README.md`](docs/apm/README.md) for complete APM system overview. Metrics documentation in [`docs/monitoring/METRICS.md`](docs/monitoring/METRICS.md)

---

## Project Structure

```
monitoring/
├── services/          # Go application code (9 microservices)
├── charts/            # Helm chart for microservices
├── k8s/               # Kubernetes manifests
├── scripts/           # Deployment scripts (01-12)
├── docs/              # Documentation (starting point for details)
├── k6/                # K6 load testing
└── specs/             # Specifications and research
```

**Full Documentation Index**: See [`docs/README.md`](docs/README.md) for complete documentation structure.

---

## API Endpoints

9 microservices with RESTful APIs:

| Service | Namespace | Base URLs |
|---------|-----------|-----------|
| auth | auth | `/api/v1/*`, `/api/v2/*` |
| user | user | `/api/v1/*`, `/api/v2/*` |
| product | product | `/api/v1/*`, `/api/v2/*` |
| cart | cart | `/api/v1/*`, `/api/v2/*` |
| order | order | `/api/v1/*`, `/api/v2/*` |
| review | review | `/api/v1/*`, `/api/v2/*` |
| notification | notification | `/api/v1/*`, `/api/v2/*` |
| shipping | shipping | `/api/v1/*` (v1 only) |
| shipping-v2 | shipping | `/api/v2/*` (v2 only) |

**Complete API Documentation**: See [`docs/guides/API_REFERENCE.md`](docs/guides/API_REFERENCE.md) for all endpoints, request/response models, and examples.

---

## Important Notes

### Deployment Order

Infrastructure → Monitoring → APM → **Databases** → Apps → Load Testing → SLO → Access

1. Infrastructure (01) - Kind cluster
2. Monitoring (02) - Prometheus, Grafana, metrics (BEFORE apps)
3. APM (03) - Tempo, Pyroscope, Loki, Vector (BEFORE apps)
4. **Databases (04)** - PostgreSQL operators, clusters, poolers (BEFORE apps)
5. Deploy Apps (05) - Deploy services from OCI registry (images built by GitHub Actions)
6. Load Testing (06) - K6 load generators (AFTER apps)
7. SLO (07) - Sloth Operator and SLO CRDs
8. Access Setup (08) - Port-forwarding

**Detailed Deployment Guide**: See [`docs/guides/SETUP.md`](docs/guides/SETUP.md)

### Key Infrastructure

- **5 PostgreSQL Clusters**: review-db, auth-db, supporting-db, product-db, transaction-db
- **Connection Poolers**: PgBouncer (Auth), PgCat (Product, Cart+Order)
- **Migrations**: Flyway 11.19.0 with 8 migration images
- **Operators**: Zalando Postgres Operator (v1.15.0), CloudNativePG Operator (v1.24.0)
- **SLO**: Managed via Sloth Operator (PrometheusServiceLevel CRDs)
- **CI/CD**: GitHub Actions workflows (build-images, build-init-images, build-k6-images, helm-release)

---

## Quick Navigation

### Detailed Guides

- **Research Patterns**: [`docs/guides/RESEARCH_PATTERNS.md`](docs/guides/RESEARCH_PATTERNS.md) - API, APM, Database research patterns
- **Command Reference**: See [`docs/guides/SETUP.md`](docs/guides/SETUP.md#command-reference) - Deployment scripts, Helm, kubectl commands
- **Conventions**: [`docs/guides/API_REFERENCE.md`](docs/guides/API_REFERENCE.md#conventions-and-standards) - Naming conventions, code standards, build verification
- **API Reference**: [`docs/guides/API_REFERENCE.md`](docs/guides/API_REFERENCE.md) - Complete API documentation
- **Setup Guide**: [`docs/guides/SETUP.md`](docs/guides/SETUP.md) - Deployment instructions
- **Configuration**: [`docs/guides/CONFIGURATION.md`](docs/guides/CONFIGURATION.md) - Environment variables and config
- **Database**: [`docs/guides/DATABASE.md`](docs/guides/DATABASE.md) - Database architecture and patterns

### Find Files by Purpose

**Add a new service:**
- Service code: `services/cmd/{service}/`, `services/internal/{service}/`
- Helm values: `charts/values/{service}.yaml`
- SLO CRD: `k8s/sloth/crds/{service}-slo.yaml`
- Migration: `services/migrations/{service}/Dockerfile` + `sql/001__init_schema.sql`

**Update monitoring:**
- Dashboard JSON: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
- Prometheus Operator values: `k8s/prometheus/values.yaml`
- ServiceMonitor: `k8s/prometheus/servicemonitor-microservices.yaml`

**Modify SLOs:**
- Edit CRDs: `k8s/sloth/crds/*.yaml` (PrometheusServiceLevel CRDs)
- Apply: `kubectl apply -f k8s/sloth/crds/`

### Find Documentation by Topic

- **Getting Started**: [`docs/guides/SETUP.md`](docs/guides/SETUP.md), [`docs/guides/API_REFERENCE.md`](docs/guides/API_REFERENCE.md)
- **Development**: [`docs/guides/CONFIGURATION.md`](docs/guides/CONFIGURATION.md), [`docs/guides/API_REFERENCE.md#error-handling`](docs/guides/API_REFERENCE.md#error-handling), [`docs/guides/TRACING_ARCHITECTURE.md`](docs/guides/TRACING_ARCHITECTURE.md)
- **Monitoring**: [`docs/monitoring/METRICS.md`](docs/monitoring/METRICS.md), [`docs/monitoring/TROUBLESHOOTING.md`](docs/monitoring/TROUBLESHOOTING.md)
- **APM**: [`docs/apm/README.md`](docs/apm/README.md), [`docs/apm/TRACING.md`](docs/apm/TRACING.md), [`docs/apm/LOGGING.md`](docs/apm/LOGGING.md), [`docs/apm/PROFILING.md`](docs/apm/PROFILING.md)
- **SLO**: [`docs/slo/README.md`](docs/slo/README.md), [`docs/slo/GETTING_STARTED.md`](docs/slo/GETTING_STARTED.md)
- **k6**: [`docs/k6/K6_LOAD_TESTING.md`](docs/k6/K6_LOAD_TESTING.md)
- **Docs Index**: [`docs/README.md`](docs/README.md)

---

## Troubleshooting

Common issues and quick fixes. For detailed troubleshooting, see [`docs/monitoring/TROUBLESHOOTING.md`](docs/monitoring/TROUBLESHOOTING.md).

**Dashboard not updating:**
- Re-apply: `kubectl apply -k k8s/grafana-operator/dashboards/`
- Check status: `kubectl get grafanadashboards -n monitoring`

**Prometheus not scraping:**
- Check ServiceMonitor: `kubectl get servicemonitor -n monitoring`
- Check targets: http://localhost:9090/targets

**SLO rules not loading:**
- Check CRDs: `kubectl get prometheusservicelevels -n monitoring`
- Check rules: `kubectl get prometheusrules -n monitoring`

**Metrics not appearing:**
- Verify `/metrics` endpoint exists
- Check ServiceMonitor configuration
- Verify labels match (app, namespace, job)

---

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for complete version history.

**Important for AI Agents**: Do NOT modify existing entries in [`CHANGELOG.md`](CHANGELOG.md). ONLY add new entries at the top. Never edit or remove historical changelog entries.

---
