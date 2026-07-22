# Documentation Index

Documentation for the **duynhlab microservices platform** — 10 Go services + a React SPA, with GitOps (Flux Operator), observability, databases, secrets, and the RFC/ADR design record.

---

## Documentation Structure

```
docs/
├── api/                          # API surface, service contracts, and workflow guides
│   ├── README.md                 # Area hub and recommended learning path
│   ├── api.md                    # Canonical shared HTTP + gRPC conventions and call graph
│   ├── microservices.md          # Feature ownership, techniques, dependencies, known gaps
│   ├── auth.md                   # Auth HTTP contract, refresh rotation, JWKS
│   ├── user.md                   # User profile contract
│   ├── product.md                # Catalog, aggregation, stock gRPC contract
│   ├── cart.md                   # Cart HTTP contract + checkout gRPC read
│   ├── order.md                  # Order HTTP/gRPC contract + Saga handoff
│   ├── review.md                 # Review HTTP/gRPC contract
│   ├── notification.md           # Inbox and delivery contracts
│   ├── shipping.md               # Tracking, quotes, shipment gRPC contract
│   ├── checkout.md               # P1-P5 checkout subsystem; P6 planned
│   ├── payments.md               # Payment contract, ledger, reconciliation
│   └── temporal-order-fulfillment.md # Saga vs 2PC + live Temporal workflow and ops
├── proposals/                    # Design proposals & decisions
│   ├── README.md                 # umbrella: ADR vs RFC + flow + links
│   ├── adr/                      # Architecture Decision Records
│   │   ├── README.md             # ADR conventions + index
│   │   ├── ADR-0000-template/    # template
│   │   └── ADR-001 … ADR-016     # Temporal ×2, JWT-in-services (superseded), OpenBAO audit/HA, RS256+edge-auth, payment ledger, mockpay, saga authorize/capture, shared idempotency, detect-only recon, recon auto-heal, CNPG triplets ×3, OTel metrics cutover
│   ├── rfc/                      # Requests for Comments
│   │   ├── README.md             # process + index + backlog
│   │   ├── RFC-0000/             # template (research.md + README.md)
│   │   └── RFC-0001 … RFC-0018   # reserve number → research.md → README.md
├── databases/                    # Database documentation
│   ├── 002-database-integration.md               # PostgreSQL architecture
│   ├── 003-operator-comparison.md               # CloudNativePG vs Zalando decision guide
│   ├── 003.1-operator-cnpg.md                   # CloudNativePG operator deep dive
│   ├── 003.2-operator-zalando.md                # Zalando Postgres Operator deep dive (historical/reference — operator removed)
│   ├── 007-architecture.md           # Database architecture overview
│   ├── 006-backup-strategy.md                 # Backup strategy and retention
│   ├── 009-extensions.md             # PostgreSQL extensions
│   ├── 008-pooler.md                 # Connection pooler documentation
│   ├── 004-replication-strategy.md   # Replication strategy
│   ├── 005-ha-dr-deep-dive.md        # HA vs DR (product-db-replica)
│   ├── 001-postgresql-internals.md  # PostgreSQL internals deep dive
│   ├── 010-drp.md                    # PostgreSQL DRP, RTO/RPO, PITR, restore evidence
│   ├── 010.1-rpo-rto-planning.md     # Per-tier RPO/RTO targets vs as-built
│   ├── 010.2-restore-and-failover-drills.md  # Drill cadence, roles, evidence log
│   ├── 010.3-cross-region-dr.md      # Cross-zone/cross-region DR roadmap
│   ├── 010.4-emergency-recovery.md   # "Start here when it's down" runbook
│   ├── 011-documents.md              # Further reading / document map
│   ├── 012-declarative-role-management.md  # RFC-0012 per-service triplets (ExternalSecret + DatabaseRole + Database)
│   └── runbooks/                     # Database ops runbooks
│       ├── README.md
│       ├── add-service-database.md   # Add a service DB to product-db (RFC-0012 triplet)
│       ├── rotate-cnpg-service-password.md  # Rotate a product-db service password end-to-end
│       ├── pgdog-operations.md       # PgDog day-2 ops: rotations, backends, failure modes
│       ├── postgres-backup-restore.md  # Backup/restore and PITR
│       ├── cnpg-dr-replica-bootstrap.md
│       ├── endpoints-to-configmaps.md
│       ├── prepared-databases.md
│       ├── zalando-ha-scaling.md
│       └── postgres-backup-restore.md  # Backup/restore and PITR
├── observability/                # Observability documentation
│   ├── README.md                 # Master index + 4-pillar architecture
│   ├── opentelemetry/             # OTel instrumentation, transport, and migration learning
│   │   ├── README.md              # Canonical policy + current platform behavior
│   │   └── rfc-0014-explainer.md  # Beginner old-vs-new walkthrough
│   ├── metrics/                  # Pillar 1: Metrics
│   │   ├── README.md             # Hub: fundamentals, stack, architecture, coverage
│   │   ├── metrics-apps.md       # Application + gRPC east-west metrics (RED)
│   │   ├── metrics-catalog.md    # Lookup catalog — all emitted series incl. 34 business metrics
│   │   ├── metrics-infra.md      # Cluster / infrastructure metrics (USE)
│   │   ├── victoriametrics.md    # VictoriaMetrics Operator stack (incl. VMAuth planned)
│   │   ├── promql-guide.md       # PromQL reference
│   │   ├── streaming-aggregation.md  # VictoriaMetrics stream aggregation (vmagent)
│   │   └── postgresql/           # PostgreSQL-specific metrics (databases layer)
│   │       ├── README.md
│   │       ├── builtin-metrics.md
│   │       └── custom-metrics.md
│   ├── tracing/                  # Pillar 2: Distributed Tracing
│   │   ├── README.md             # Tracing guide (Tempo + OTel)
│   │   ├── architecture.md       # Triple backend (Tempo + Jaeger + VictoriaTraces pilot)
│   │   ├── jaeger.md             # Jaeger UI guide
│   │   ├── backends-comparison.md # Tempo vs Jaeger vs VictoriaTraces
│   │   └── victoriatraces.md     # VictoriaTraces pilot (3rd backend)
│   ├── logging/                  # Pillar 3: Structured Logging
│   │   ├── README.md             # Architecture, why-this-stack, scaling
│   │   ├── logging-standards.md  # App-side logging conventions (libraries, levels, JSON fields)
│   │   └── victorialogs.md       # VictoriaLogs backend & Vector pipeline ops
│   ├── profiling/                # Pillar 4: Continuous Profiling
│   │   └── README.md             # Pyroscope (CPU, heap, goroutine)
│   ├── clickhouse/               # ClickHouse OTel logs+traces OLAP (deployed)
│   │   └── README.md             # OLAP fundamentals, MergeTree, schema + ops, Grafana chapter
│   ├── grafana/                  # Visualization layer
│   │   ├── README.md             # Grafana overview + plugins
│   │   ├── rbac-multi-team.md    # Org roles, Teams, anonymous vs named users
│   │   ├── datasources.md        # Dual datasource strategy (case study)
│   │   ├── dashboard-reference.md # Microservices dashboard (40 panels)
│   │   └── variables.md          # Dashboard variables & regex
│   ├── alerting/                 # Alerting rules
│   │   ├── README.md             # 2-layer alerting strategy
│   │   ├── alert-catalog.md      # Full alert reference + coverage gaps
│   │   ├── slo-burn-rate-alerts.md # Multi-window burn-rate alerts
│   │   └── dashboard-comparison.md
│   ├── slo/                      # Service Level Objectives
│   │   ├── README.md             # Sloth Operator + SLO targets
│   │   ├── fundamentals.md       # SLI/SLO/error-budget concepts
│   │   ├── getting_started.md    # Enable SLO via Helm values
│   │   ├── error_budget_policy.md
│   │   └── annotation-driven-slo-controller.md
│   └── runbooks/                 # Operational runbooks
│       ├── README.md             # Runbook index
│       ├── observability-deep-dive.md   # Theory + interview prep
│       ├── infrastructure-alerts.md     # Infra alert investigation guide
│       ├── microservices-alerts.md      # Workflows, tuning hub
│       ├── victorialogs-kubernetes-logs-debug.md  # Blank Grafana logs / VictoriaLogs ingest
│       ├── microservices/               # Per-alert runbooks (19 files)
│       └── postgresql/                  # Per-alert CNPG runbooks
├── caching/                     # Valkey cache: Cache-Aside, eviction policies, distributed-cache concept
│   └── caching.md
├── platform/                     # Platform/deployment documentation
│   ├── setup.md                  # GitOps deployment guide (+ seed data & demo accounts)
│   ├── graceful-shutdown.md      # Graceful shutdown pattern (drain, readiness, timeouts)
│   ├── gke-internal-dns.md       # GKE cluster.local, Cloud DNS private zones, multi-environment
│   ├── application-delivery.md    # ResourceSet patterns & templates
│   ├── cicd.md                   # CI/CD pipelines + standard/policy (pinning, permissions, signing, GoReleaser)
│   ├── gitflow.md                # Git branching & release standard
│   ├── sonarcloud.md             # SonarCloud integration
│   ├── kong-gateway.md           # Kong API gateway — concept + DB-less, plugins, routing, rate-limiting
│   ├── kyverno.md                # Kyverno admission-policy platform guide
│   ├── mcp-servers.md            # MCP servers wired into the platform
│   └── ruleset-automation.md     # GitHub ruleset automation
├── secrets/                      # Secrets, TLS & trust distribution (one chain)
│   ├── README.md                 # Homelab secrets/TLS/trust hub
│   ├── openbao.md                # OpenBAO HA/Raft architecture and learning notes
│   ├── runbooks/                 # Add, rotate, bootstrap, troubleshoot secrets
│   ├── production-hardening.md   # Planned production target and guardrails
│   ├── cert-manager.md           # cert-manager + Let's Encrypt + Flux (Helm, Ingress, TLS)
│   └── trust-distribution.md     # trust-manager Bundle (homelab-ca-bundle), dual-PKI
│                                 # (production hardening → docs/proposals/rfc/RFC-0008/)
└── security/                     # Admission control & network segmentation
    ├── policy-catalog.md         # Kyverno ClusterPolicy catalog (tiers, modes, NetworkPolicy generate)
    ├── policy-exceptions.md      # PolicyException register (owner + TTL)
    └── network-policies.md       # East-west NetworkPolicy caller matrix + topology diagram
```

---

## Learning Path

### Getting Started (New Users)

1. **[Repositories](#repositories)** - Polyrepo index: GitHub links, images, and CI badges
2. **[Setup Guide](./platform/setup.md)** - Complete GitOps deployment guide
   - Quick start (3 commands, 5 minutes)
   - GitOps architecture with Flux Operator
   - Simplified structure (infra/ + apps/, refactored 2026-01-12)
   - Multi-environment support
   - Step-by-step instructions
   - Troubleshooting common issues

3. **[API area hub](./api/README.md)** - How the api docs fit together (routes / payloads / catalog / subsystems)

4. **[Shared API and communication guide](./api/api.md)** - URL model, audiences, common contracts, service index, and gRPC runtime

5. **[GKE internal & private DNS](./platform/gke-internal-dns.md)** - `cluster.local`, Cloud DNS private zones, multi-environment naming

## Repositories {#repositories}

Polyrepo layout: application code lives in separate GitHub repositories; this
repo (`homelab`) is the Infrastructure & GitOps hub. API contracts:
[api/README.md § Service contracts](./api/README.md#service-contracts).

### Infrastructure and shared libraries

| Component | Repository | Description | CI |
|-----------|------------|-------------|-----|
| **Infrastructure** | [duynhlab/homelab](https://github.com/duynhlab/homelab) | GitOps, K8s manifests, docs | [![CI](https://github.com/duynhlab/homelab/actions/workflows/ci.yml/badge.svg)](https://github.com/duynhlab/homelab/actions) |
| **Helm Charts** | [duynhlab/helm-charts](https://github.com/duynhlab/helm-charts) | `mop` chart — OCI `ghcr.io/duynhlab/helm-charts/mop` | [![CI](https://github.com/duynhlab/helm-charts/actions/workflows/e2e.yml/badge.svg)](https://github.com/duynhlab/helm-charts/actions) |
| **Shared Workflows** | [duynhlab/gha-workflows](https://github.com/duynhlab/gha-workflows) | Reusable GitHub Actions | [![CI](https://github.com/duynhlab/gha-workflows/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/duynhlab/gha-workflows/actions) |
| **Common Lib** | [duynhlab/pkg](https://github.com/duynhlab/pkg) | Shared Go packages | [![CI](https://github.com/duynhlab/pkg/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/pkg/actions) |

### Microservices and frontend

| Service | Repository | Contract | Image | CI |
|---------|------------|----------|-------|-----|
| Auth | [auth-service](https://github.com/duynhlab/auth-service) | [auth.md](./api/auth.md) | `ghcr.io/duynhlab/auth-service/auth-service` | [![CI](https://github.com/duynhlab/auth-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/auth-service/actions) |
| User | [user-service](https://github.com/duynhlab/user-service) | [user.md](./api/user.md) | `ghcr.io/duynhlab/user-service/user-service` | [![CI](https://github.com/duynhlab/user-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/user-service/actions) |
| Product | [product-service](https://github.com/duynhlab/product-service) | [product.md](./api/product.md) | `ghcr.io/duynhlab/product-service/product-service` | [![CI](https://github.com/duynhlab/product-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/product-service/actions) |
| Cart | [cart-service](https://github.com/duynhlab/cart-service) | [cart.md](./api/cart.md) | `ghcr.io/duynhlab/cart-service/cart-service` | [![CI](https://github.com/duynhlab/cart-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/cart-service/actions) |
| Order | [order-service](https://github.com/duynhlab/order-service) | [order.md](./api/order.md) | `ghcr.io/duynhlab/order-service/order-service` | [![CI](https://github.com/duynhlab/order-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/order-service/actions) |
| Review | [review-service](https://github.com/duynhlab/review-service) | [review.md](./api/review.md) | `ghcr.io/duynhlab/review-service/review-service` | [![CI](https://github.com/duynhlab/review-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/review-service/actions) |
| Notification | [notification-service](https://github.com/duynhlab/notification-service) | [notification.md](./api/notification.md) | `ghcr.io/duynhlab/notification-service/notification-service` | [![CI](https://github.com/duynhlab/notification-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/notification-service/actions) |
| Shipping | [shipping-service](https://github.com/duynhlab/shipping-service) | [shipping.md](./api/shipping.md) | `ghcr.io/duynhlab/shipping-service/shipping-service` | [![CI](https://github.com/duynhlab/shipping-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/shipping-service/actions) |
| Checkout | [checkout-service](https://github.com/duynhlab/checkout-service) | [checkout.md](./api/checkout.md) | `ghcr.io/duynhlab/checkout-service/checkout-service` | [![CI](https://github.com/duynhlab/checkout-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/checkout-service/actions) |
| Payment | [payment-service](https://github.com/duynhlab/payment-service) | [payments.md](./api/payments.md) | `ghcr.io/duynhlab/payment-service/payment-service` | [![CI](https://github.com/duynhlab/payment-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/payment-service/actions) |
| Frontend | [frontend](https://github.com/duynhlab/frontend) | — | `ghcr.io/duynhlab/frontend/frontend` | [![CI](https://github.com/duynhlab/frontend/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/frontend/actions) |

Clone all repositories: [platform/setup.md](./platform/setup.md).

### Observability

#### Metrics

1. **[Metrics Guide](./observability/metrics/README.md)** - Complete metrics documentation
   - 4 custom application metrics (RED method)
   - 40 data panels across 6 row groups in the Grafana dashboard
   - Exemplars, path normalization, auto-discovery

2. **[PromQL Guide](./observability/metrics/promql-guide.md)** - Complete guide to PromQL functions
   - `rate()` vs `increase()` functions
   - Counter resets handling
   - Time range vs rate interval
   - Best practices and troubleshooting

3. **[PostgreSQL metrics hub](./observability/metrics/postgresql/README.md)** - CNPG custom queries, workflows, signal guides

4. **[PostgreSQL alert runbooks](./observability/runbooks/postgresql/README.md)** - Per-alert CNPG investigation (33 files)

4b. **[Microservices alert runbooks](./observability/runbooks/microservices/README.md)** - Per-alert RED/Golden investigation (19 files); hub [`microservices-alerts.md`](./observability/runbooks/microservices-alerts.md)

5. **[Variables & Regex](./observability/grafana/variables.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

4. **[Grafana Dashboard Guide](./observability/grafana/dashboard-reference.md)** - Complete dashboard reference for SRE/DevOps
    - All panels with query analysis and troubleshooting
    - PromQL patterns and best practices (Google SRE, Prometheus docs)
    - Before/After comparisons for updated panels (Status Code, Apdex, 4xx/5xx)
    - SRE runbooks and incident response scenarios
    - Grafana Annotations planning (planned feature)

#### Service Level Objectives (SLO)

1. **[SLO Documentation](./observability/slo/README.md)** - Complete SLO system overview
   - Architecture (Helm chart auto-generation)
   - SLI definitions and PromQL queries
   - SLO targets and error budgets

2. **[SLO Getting Started](./observability/slo/getting_started.md)** - Enable SLOs via Helm values
   - `slo.enabled: true` in HelmRelease
   - Per-service target overrides
   - Verification checklist

3. **[SLO Burn-Rate Alerts](./observability/alerting/slo-burn-rate-alerts.md)** - Alert configuration and runbooks
4. **[Error Budget Policy](./observability/slo/error_budget_policy.md)** - Budget management guidelines
5. **[Annotation-Driven Controller](./observability/slo/annotation-driven-slo-controller.md)** - Future approach for large-scale automation

#### Observability (4 Pillars)

1. **[Observability Overview](./observability/README.md)** - Master index, 4-pillar architecture
   - **[OpenTelemetry guide](./observability/opentelemetry/README.md)** - current instrumentation policy and operations
   - **[RFC-0014 explainer](./observability/opentelemetry/rfc-0014-explainer.md)** - old-vs-new, plain-language (start here if new)
    - Metrics, Tracing, Logging, Profiling
    - Component inventory and correlation workflow
    - Deployment and quick start

2. **[Distributed Tracing](./observability/tracing/README.md)** - Tempo integration guide
3. **[Tracing Architecture](./observability/tracing/architecture.md)** - Triple backend (Tempo + Jaeger + VictoriaTraces)
4. **[Jaeger Guide](./observability/tracing/jaeger.md)** - Jaeger UI usage, comparison with Tempo
5. **[Backend Comparison](./observability/tracing/backends-comparison.md)** - Tempo vs Jaeger vs VictoriaTraces (+ roadmap)
6. **[VictoriaTraces (pilot)](./observability/tracing/victoriatraces.md)** - 3rd backend via the VM operator
7. **[Continuous Profiling](./observability/profiling/README.md)** - Pyroscope setup
8. **[ClickHouse OTel OLAP](./observability/clickhouse/README.md)** - Deployed supplementary OLAP; OTel logs/traces SQL + [Grafana chapter](./observability/clickhouse/README.md#grafana) (dashboard suite, Explore, linking) ([RFC-0019](./proposals/rfc/RFC-0019/))
9. **[Logging](./observability/logging/README.md)** - Architecture: OTLP app logs (otelzap tee) + Vector for non-instrumented pods, scaling
10. **[VictoriaLogs](./observability/logging/victorialogs.md)** - VictoriaLogs deployment and configuration
    - OTLP app-log ingest + Vector for non-instrumented pods (DB/Kong/frontend/infra)
    - PostgreSQL auto_explain plan parsing pipeline
    - Verification and troubleshooting

### API Reference

1. **[API area hub](./api/README.md)** - Start here for the learning path and all ten service contracts

2. **[Shared API and communication guide](./api/api.md)** - URL naming, audiences, auth, errors, pagination, HTTP-vs-gRPC, current call graph, HTTP/2 load balancing, security, and observability

3. **[Microservices catalog](./api/microservices.md)** - Feature ownership, service dependencies, techniques, and known gaps

4. **Service contracts** - [Auth](./api/auth.md), [User](./api/user.md), [Product](./api/product.md), [Cart](./api/cart.md), [Order](./api/order.md), [Review](./api/review.md), [Notification](./api/notification.md), [Shipping](./api/shipping.md), [Checkout](./api/checkout.md), and [Payment](./api/payments.md)

5. **[Temporal order-fulfillment Saga](./api/temporal-order-fulfillment.md)** - Saga vs 2PC theory, live workflow steps and compensations, infrastructure, and operations

6. **[RFCs — research then decide](./proposals/rfc/)** — owner approves next `RFC-NNNN` → `research.md` (plain-language + Context7) → `README.md` → optional `docs/<area>/` spin-off

7. **[GKE internal and private DNS](./platform/gke-internal-dns.md)** - In-cluster DNS and Cloud DNS private zones

### Databases

1. **[Database Guide](./databases/002-database-integration.md)** - PostgreSQL database integration guide
    - 4 PostgreSQL clusters architecture with comprehensive diagrams
    - Overview diagram showing operators, services, poolers, and clusters
    - Individual cluster diagrams with secrets, connections, and patterns

2. **[Operator Comparison](./databases/003-operator-comparison.md)** - CloudNativePG vs Zalando decision guide (reference/historical — the platform standardised on CloudNativePG; the Zalando operator was removed)
    - Concise decision matrix
    - Homelab cluster-to-operator mapping
    - Links to [CloudNativePG](./databases/003.1-operator-cnpg.md) and [Zalando](./databases/003.2-operator-zalando.md) deep dives

3. **[PostgreSQL Internals Deep Dive](./databases/001-postgresql-internals.md)** - PostgreSQL internals using product-db examples
    - INSERT/UPDATE workflow with sequence diagrams
    - Shared Buffers and Buffer Manager explained
    - WAL (Write-Ahead Log) and crash recovery
    - MVCC, tuple versioning, and visibility
    - Streaming Replication internals (WAL sender/receiver, lag)
    - Storage: files, pages, and on-disk layout
    - Autovacuum and bloat control
    - CNPG vs EC2/VM operational differences
    - Backup/restore, scaling, and sharding concepts
    - Cross-namespace secrets visualization for supporting-shared-db
    - Connection patterns (direct, PgBouncer, PgDog)
    - Environment variables and Helm configuration
    - Database verification and troubleshooting
    - Monitoring and best practices

4. **[PostgreSQL Disaster Recovery](./databases/010-drp.md)** - HA, DR, RPO/RTO, PITR, standby taxonomy, and restore evidence
    - [RPO/RTO Planning](./databases/010.1-rpo-rto-planning.md) - per-tier targets vs as-built, mapped to clusters
    - [Restore & Failover Drills](./databases/010.2-restore-and-failover-drills.md) - drill cadence, roles, and evidence log
    - [Cross-Region / Cross-Zone DR](./databases/010.3-cross-region-dr.md) - roadmap to independent failure domains
    - [Emergency Recovery](./databases/010.4-emergency-recovery.md) - "start here when it's down" runbook

### Runbooks & Troubleshooting

1. **[PostgreSQL Backup/Restore](./databases/runbooks/postgres-backup-restore.md)** - Backup and restore procedures (CNPG Barman)
2. **[VictoriaLogs Log Debugging](./observability/runbooks/victorialogs-kubernetes-logs-debug.md)** - Kubernetes log debugging with VictoriaLogs
3. **[Add a service database](./databases/runbooks/add-service-database.md)** - RFC-0012 triplet flow on product-db
4. **[Rotate a product-db service password](./databases/runbooks/rotate-cnpg-service-password.md)** - End-to-end rotation via OpenBAO → triplet → PgDog
5. **[PgDog operations](./databases/runbooks/pgdog-operations.md)** — day-2 pooler ops (`pgdog-platform`, `pgdog-product`)

---

## Documentation by Category

### Getting Started

- [Setup Guide](./platform/setup.md) - Complete deployment instructions
- [API Reference](./api/api.md) - API endpoints and adding new microservices

### Observability

#### Metrics
- [Metrics Guide](./observability/metrics/README.md) - Comprehensive metrics documentation
- [PromQL Guide](./observability/metrics/promql-guide.md) - Complete guide to PromQL functions, time range vs rate interval, and counter handling
- [Variables & Regex](./observability/grafana/variables.md) - Filter patterns
- [Grafana Dashboard Guide](./observability/grafana/dashboard-reference.md) - Complete SRE/DevOps dashboard reference (40 panels + annotations planning)

#### SLO/SRE
- [SLO Overview](./observability/slo/README.md) - Architecture, SLI definitions, targets
- [Getting Started](./observability/slo/getting_started.md) - Enable SLOs via Helm values
- [SLO Burn-Rate Alerts](./observability/alerting/slo-burn-rate-alerts.md) - Alert configuration
- [Error Budget Policy](./observability/slo/error_budget_policy.md) - Budget management
- [Annotation-Driven Controller](./observability/slo/annotation-driven-slo-controller.md) - Future approach

#### Observability Pillars
- [Observability Overview](./observability/README.md) - Master index, 4-pillar architecture, 3-layer service architecture + APM integration
- [OpenTelemetry guide](./observability/opentelemetry/README.md) - Current OTel policy, architecture, and operations
- [RFC-0014 explainer](./observability/opentelemetry/rfc-0014-explainer.md) - old client_golang vs new OpenTelemetry (OTLP push), beginner-friendly
- [Distributed Tracing](./observability/tracing/README.md) - Tempo integration
- [Tracing Architecture](./observability/tracing/architecture.md) - Triple backend (Tempo + Jaeger + VictoriaTraces)
- [Jaeger Guide](./observability/tracing/jaeger.md) - Jaeger UI usage, comparison with Tempo
- [Backend Comparison](./observability/tracing/backends-comparison.md) - Tempo vs Jaeger vs VictoriaTraces
- [VictoriaTraces (pilot)](./observability/tracing/victoriatraces.md) - 3rd backend via the VM operator
- [Continuous Profiling](./observability/profiling/README.md) - Pyroscope setup
- [ClickHouse learning guide](./observability/clickhouse/README.md) - Planned OLAP; OTel SQL + optional commerce ([RFC-0019](./proposals/rfc/RFC-0019/))
- [Logging](./observability/logging/README.md) - Architecture: OTLP app logs (otelzap tee) + Vector for non-instrumented pods
- [Logging Standards](./observability/logging/logging-standards.md) - App-side logging conventions (libraries, levels, JSON fields)
- [VictoriaLogs](./observability/logging/victorialogs.md) - VictoriaLogs deployment (OTLP app logs + Vector for non-instrumented pods)

### API

- [API area hub](./api/README.md) - Learning path, document ownership, deployment rollup, and all service contracts
- [Shared API and communication guide](./api/api.md) - HTTP/gRPC conventions, call graph, user journeys, load balancing, security, and observability
- [Microservices catalog](./api/microservices.md) - Feature ownership, techniques, dependencies, and known gaps
- [Service contracts](./api/README.md#service-contracts) - Platform deployment rollup and one file per Go service
- [Workflow registry](./api/workflows.md) - Temporal workflows: owners, workers, task queues, and participants
- [Temporal Order-Fulfillment Saga](./api/temporal-order-fulfillment.md) - Saga-vs-2PC learning, live compensations, Temporal infrastructure, and operations
- [Checkout](./api/checkout.md) - Session orchestration, P1-P5 shipped (local-stack + cluster); P6 legacy removal planned
- [Payments](./api/payments.md) - Payment API, state machine, ledger, provider, and reconciliation
- [RFC-0009: Production-grade API gateway (signed JWT + Kong edge auth)](./proposals/rfc/RFC-0009/) - Partially implemented; supersedes ADR-003 via ADR-006
- [RFC-0010: Payment service (PaymentIntent, ledger, charge/refund saga step)](./proposals/rfc/RFC-0010/) - Implemented; P1–P6 landed (ledger, outbox, mockpay, webhooks, saga wiring, reconciliation, cluster GitOps, frontend read path) → ADR-007…011
- [RFC-0011: Homelab migration — Kind to bare-metal Talos](./proposals/rfc/RFC-0011/) - Provisional; 1 → 3 node HA path
- [RFC-0012: Declarative CNPG role & database management](./proposals/rfc/RFC-0012/) - Implemented (P0–P4); per-service triplets on CNPG `DatabaseRole`/`Database` CRDs + pg_hba isolation
- [RFC-0014: Full OpenTelemetry adoption](./proposals/rfc/RFC-0014/) - Provisional; OTLP push for metrics/logs/traces + semconv naming, phases P0–P5, consumer tracking table
- [RFC-0019: ClickHouse for OTel logs/traces SQL](./proposals/rfc/RFC-0019/) - Provisional; Phase B Collector→ClickHouse, Phase A optional Postgres facts; **planned**, no manifests
- [RFCs](./proposals/rfc/) - Propose & track substantial changes (process + index + backlog)

### Decisions (ADRs)

- [ADR index](./proposals/adr/README.md) - Architecture Decision Records (the *why* behind significant choices)
- [ADR-001: Adopt Temporal for order fulfillment](./proposals/adr/ADR-001-adopt-temporal-for-order-fulfillment/)
- [ADR-002: Deploy Temporal via the operator](./proposals/adr/ADR-002-deploy-temporal-via-operator/)
- [ADR-003: Keep JWT validation in services, not at Kong](./proposals/adr/ADR-003-jwt-validation-in-services-not-kong/) - **Superseded by ADR-006**
- [ADR-004: Enable OpenBAO audit logging](./proposals/adr/ADR-004-enable-openbao-audit-logging/) - Accepted
- [ADR-005: Run OpenBAO HA (Raft) instead of Vault dev mode](./proposals/adr/ADR-005-openbao-ha-raft/) - Accepted
- [ADR-006: Adopt RS256 signed JWTs + Kong edge authentication](./proposals/adr/ADR-006-rs256-jwt-kong-edge-auth/) - Accepted; implements [RFC-0009](./proposals/rfc/RFC-0009/)
- [ADR-007: Append-only double-entry payment ledger](./proposals/adr/ADR-007-double-entry-payment-ledger/) - Accepted; from [RFC-0010](./proposals/rfc/RFC-0010/)
- [ADR-008: Run the mock payment provider as a standalone process](./proposals/adr/ADR-008-mockpay-standalone-provider/) - Accepted; from [RFC-0010](./proposals/rfc/RFC-0010/)
- [ADR-009: Authorize payment early, capture late in the order saga](./proposals/adr/ADR-009-saga-authorize-early-capture-late/) - Accepted; from [RFC-0010](./proposals/rfc/RFC-0010/)
- [ADR-010: Extract idempotency into a shared pkg/idempotency library](./proposals/adr/ADR-010-shared-idempotency-library/) - Accepted; from [RFC-0010](./proposals/rfc/RFC-0010/)
- [ADR-011: Ship reconciliation detect-only; defer auto-heal](./proposals/adr/ADR-011-detect-only-reconciliation/) - Accepted; from [RFC-0010](./proposals/rfc/RFC-0010/)
- [ADR-012: Auto-heal one reconciliation class (lost-capture-response window)](./proposals/adr/ADR-012-reconciliation-auto-heal/) - Accepted; from [RFC-0010](./proposals/rfc/RFC-0010/); supersedes the detect-only stance of ADR-011 for a single drift class (off by default)
- [ADR-013: Per-service database triplet on product-db](./proposals/adr/ADR-013-per-service-db-triplet/) - Accepted; from [RFC-0012](./proposals/rfc/RFC-0012/); ExternalSecret + DatabaseRole + Database, one file per service
- [ADR-014: PgDog pooler credentials via Flux valuesFrom](./proposals/adr/ADR-014-pooler-credentials-valuesfrom/) - Accepted; from [RFC-0012](./proposals/rfc/RFC-0012/); per-user targetPath injection from ESO Secrets, no credentials in Helm values
- [ADR-015: Connection isolation via declarative pg_hba](./proposals/adr/ADR-015-pg-hba-connection-isolation/) - Accepted; from [RFC-0012](./proposals/rfc/RFC-0012/); per-pair allow + trailing reject, applied by reload
- [ADR-016: OTel metrics cutover](./proposals/adr/ADR-016-otel-metrics-cutover/) - Accepted; from [RFC-0014](./proposals/rfc/RFC-0014/); apps ServiceMonitor deleted (checkout never integrated — no fence), D-4 absence alerts activated in the same commit
- [ADR-017: Collection-noun API paths](./proposals/adr/ADR-017-api-path-collection-noun/) - Accepted; the segment after the audience is a service-owned collection noun; 13 routes renamed (expand→contract)
- [ADR-020: Checkout re-validation policy](./proposals/adr/ADR-020-checkout-revalidation-policy/) - Accepted; from [RFC-0015](./proposals/rfc/RFC-0015/); product is the checkout price authority, stock checked never reserved
- [ADR-021: Cart gRPC read surface](./proposals/adr/ADR-021-cart-grpc-read-surface/) - Accepted; from [RFC-0015](./proposals/rfc/RFC-0015/); read-only GetCart for the checkout snapshot, writes stay REST

### Payments

- [Payments](./api/payments.md) - Design record (RFC-0010 + ADR-007…011) + payment↔provider reconciliation: classes, equivalence rules, internal API, e2e evidence

### Databases

- [Database Guide](./databases/002-database-integration.md) - PostgreSQL database integration guide
- [Operator Comparison](./databases/003-operator-comparison.md) - CloudNativePG vs Zalando decision guide (reference/historical — standardised on CloudNativePG)
- [CloudNativePG Operator](./databases/003.1-operator-cnpg.md) - CloudNativePG feature and operations deep dive
- [Zalando Postgres Operator](./databases/003.2-operator-zalando.md) - Patroni/Spilo operator deep dive (historical/reference — operator removed)
- [Architecture](./databases/007-architecture.md) - Database architecture overview
- [Backup Strategy](./databases/006-backup-strategy.md) - Backup architecture and retention
- [Extensions](./databases/009-extensions.md) - PostgreSQL extensions (operand built-in vs Image Volume models)
- [Connection Poolers](./databases/008-pooler.md) - PgBouncer, PgDog
- [Replication Strategy](./databases/004-replication-strategy.md) - Replication strategy
- [HA & DR Deep Dive](./databases/005-ha-dr-deep-dive.md) - product-db vs product-db-replica (object-store DR)
- [PostgreSQL DRP](./databases/010-drp.md) - DRP, RTO/RPO, PITR, standby taxonomy, and restore evidence
    - [RPO/RTO Planning](./databases/010.1-rpo-rto-planning.md) - per-tier targets vs as-built, mapped to clusters
    - [Restore & Failover Drills](./databases/010.2-restore-and-failover-drills.md) - drill cadence, roles, and evidence log
    - [Cross-Region / Cross-Zone DR](./databases/010.3-cross-region-dr.md) - roadmap to independent failure domains
    - [Emergency Recovery](./databases/010.4-emergency-recovery.md) - "start here when it's down" runbook
- [Declarative Role & Database Management](./databases/012-declarative-role-management.md) - Per-service triplet (ExternalSecret + DatabaseRole + Database) on product-db; RFC-0012 rollout state
- [PostgreSQL Further Reading](./databases/011-documents.md) - Curated external references
- [PostgreSQL Internals](./databases/001-postgresql-internals.md) - Deep dive using product-db examples

### Caching

- [Caching (Valkey)](./caching/caching.md) - Cache-Aside, stampede prevention, eviction policies (with tradeoffs), and the distributed-cache concept

### Platform

- [Setup Guide](./platform/setup.md) - Complete deployment and configuration guide
- [Application Delivery](./platform/application-delivery.md) - ResourceSet patterns & templates
- [cert-manager + Flux](./secrets/cert-manager.md) - TLS with Let's Encrypt, HelmRelease, Ingress, trust-manager
- [Trust Distribution (trust-manager)](./secrets/trust-distribution.md) - CA bundle distribution to namespaces via trust-manager Bundle CRD
- [CI/CD](./platform/cicd.md) - CI/CD pipelines, workflows, **and the standard/policy** (action SHA-pinning, least-privilege permissions, image signing/verification, required-checks matrix, GoReleaser binary releases)
- [Git Branching & Release](./platform/gitflow.md) - Hybrid Enterprise Gitflow standard (dev/uat/main + immutable tags)
- [SonarCloud](./platform/sonarcloud.md) - SonarCloud integration
- [Kong API Gateway](./platform/kong-gateway.md) - API-gateway concept + tradeoffs; DB-less Kong (plugins, routing, rate-limiting, TLS)
- [Kyverno](./platform/kyverno.md) - Admission policies: tiers, Audit→Enforce rollout, exceptions
- [Graceful Shutdown](./platform/graceful-shutdown.md) - Readiness-drain + signal handling pattern (all 10 services)
- [GKE internal & private DNS](./platform/gke-internal-dns.md) - In-cluster DNS and Cloud DNS private zones
- [MCP Servers](./platform/mcp-servers.md) - In-cluster MCP servers (VictoriaMetrics/Logs, Flux, Grafana)
- [Ruleset Automation](./platform/ruleset-automation.md) - GitHub repo ruleset provisioning

### Secrets

- [Secrets hub](./secrets/README.md) - Homelab-wide OpenBAO → ESO → cert-manager → trust-manager flow, secret catalog, and runbook index
- [OpenBAO Architecture](./secrets/openbao.md) - OpenBAO HA/Raft internals, auth, engines, policies
- [Secrets runbooks](./secrets/runbooks/) - OpenBAO/ESO troubleshooting and recovery
- [Secrets Production Hardening](./secrets/production-hardening.md) - Planned TLS, KMS/Transit, OIDC, AppRole, and dynamic DB credentials
- [cert-manager + Flux](./secrets/cert-manager.md) - TLS with Let's Encrypt, HelmRelease, Ingress
- [Trust Distribution](./secrets/trust-distribution.md) - trust-manager `homelab-ca-bundle` and the LE / homelab-CA dual-PKI split
- [Secrets decisions & hardening](./proposals/) - ADR-004 (audit) + ADR-005 (OpenBAO HA); [RFC-0008](./proposals/rfc/RFC-0008/) production hardening + parity/testing matrix; RFC backlog for rotation / PushSecret

### Security

- [Policy Catalog](./security/policy-catalog.md) - Kyverno ClusterPolicy catalog (tiers, modes, acceptance criteria)
- [Policy Exceptions](./security/policy-exceptions.md) - PolicyException register (owner + TTL)
- [Network Policies](./security/network-policies.md) - East-west NetworkPolicy caller matrix + topology

### Runbooks

- [PostgreSQL Backup/Restore](./databases/runbooks/postgres-backup-restore.md) - Backup and restore procedures
- [VictoriaLogs Log Debugging](./observability/runbooks/victorialogs-kubernetes-logs-debug.md) - Kubernetes log debugging with VictoriaLogs
- [Add a service database](./databases/runbooks/add-service-database.md) - RFC-0012 triplet flow
- [Rotate a product-db service password](./databases/runbooks/rotate-cnpg-service-password.md) - End-to-end rotation

---

## Quick Reference

### Key Concepts

- **GitOps** - Declarative infrastructure managed via Flux Operator
- **Flux Operator** - Kubernetes-native GitOps reconciliation engine
- **Kustomize** - Simplified structure (direct manifests in infra/ + apps/, refactored 2026-01-12)
- **OCI Registry** - `localhost:5050` (local), stores Kubernetes manifests as artifacts
- **Helm Chart** - Generic chart for all microservices (`charts/`)
- **HelmRelease CRDs** - Flux manages Helm deployments declaratively
- **40 Data Panels + 6 Row Groups** - Complete monitoring dashboard
- **4 Custom Metrics** - Application-level metrics (RED method)
- **9 Microservices** - All services with v1 API (canonical)
- **Monitoring Stack** - VictoriaMetrics Operator (VMAgent, VMSingle, VMAlert, VMAlertmanager) + prometheus-operator-crds + Grafana Operator + metrics-server
- **SLO System** - Sloth Operator with PrometheusServiceLevel CRDs
- **APM Stack** - Tempo + Jaeger (tracing), OTel Collector (fan-out), Pyroscope (profiling), VictoriaLogs + Vector (logging)
- **Secrets Stack** - OpenBAO (HA Raft) + External Secrets Operator for centralized secret management
- **TLS / PKI** - cert-manager with **dual issuers**: Let's Encrypt (DNS-01 via Cloudflare) for browser-facing `*.duynh.me`; self-signed `homelab-ca` for future internal mTLS, distributed via trust-manager `homelab-ca-bundle`
- **Bootstrap-only secrets** - Cloudflare API token (`secret/local/infra/cloudflare/api-token`) is operator-supplied (not in Git, not seeded by `openbao-bootstrap`); re-seed after every fresh cluster

---

## Additional Resources

- **[AGENTS.md](../AGENTS.md)** - AI agent guide for navigating the codebase
- **[README.md](../README.md)** - Project overview and quick start

---

_Last updated: 2026-07-21 — Retired `docs/runbooks/troubleshooting/`; runbooks live under domain hubs._
