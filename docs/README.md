# Documentation Index

Complete documentation for the Go REST API Monitoring & Observability Platform.

---

## Documentation Structure

```
docs/
├── api/                          # API & implementation documentation
│   ├── api.md                    # Complete API reference (canonical /api/v1)
│   ├── api-naming-convention.md # Draft v1.0.0: gateway URL naming (gateway.duynh.me), does not replace api.md
│   ├── grpc-internal-comms.md   # Implemented: gRPC for internal east-west comms
│   ├── microservices.md         # Service catalog: per-service features, call graph
│   ├── temporal-order-fulfillment.md # Implemented: Temporal saga — why/when/how, design, infra, ops
│   └── gke-internal-dns.md      # GKE cluster.local, Cloud DNS private zones, multi-environment
├── proposals/                    # Design proposals & decisions
│   ├── README.md                 # umbrella: ADR vs RFC + flow + links
│   ├── adr/                      # Architecture Decision Records
│   │   ├── README.md             # ADR conventions + index
│   │   └── ADR-001 … ADR-006     # Temporal ×2, JWT-in-services (superseded), OpenBAO audit/HA, RS256+edge-auth
│   └── rfc/                      # Requests for Comments
│       ├── README.md             # process + index + backlog
│       ├── RFC-0000/             # template
│       └── RFC-0001 … RFC-0009   # Temporal, mTLS, inventory, caching, shared-db, mesh, DR drills, secrets, API gateway
├── databases/                    # Database documentation
│   ├── 002-database-integration.md               # PostgreSQL architecture
│   ├── 003-operator-comparison.md               # CloudNativePG vs Zalando decision guide
│   ├── 003.1-operator-cnpg.md                   # CloudNativePG operator deep dive
│   ├── 003.2-operator-zalando.md                # Zalando Postgres Operator deep dive
│   ├── 007-architecture.md           # Database architecture overview
│   ├── 006-backup-strategy.md                 # Backup strategy and retention
│   ├── 009-extensions.md             # PostgreSQL extensions
│   ├── 008-pooler.md                 # Connection pooler documentation
│   ├── 004-replication-strategy.md   # Replication strategy
│   ├── 005-ha-dr-deep-dive.md        # HA vs DR (cnpg-db-replica)
│   ├── 001-postgresql-internals.md  # PostgreSQL internals deep dive
│   ├── 010-drp.md                    # PostgreSQL DRP, RTO/RPO, PITR, restore evidence
│   ├── 010.1-rpo-rto-planning.md     # Per-tier RPO/RTO targets vs as-built
│   ├── 010.2-restore-and-failover-drills.md  # Drill cadence, roles, evidence log
│   ├── 010.3-cross-region-dr.md      # Cross-zone/cross-region DR roadmap
│   ├── 010.4-emergency-recovery.md   # "Start here when it's down" runbook
│   ├── 011-documents.md              # Further reading / document map
│   └── runbooks/                     # Database ops runbooks
│       ├── endpoints-to-configmaps.md
│       ├── prepared-databases.md
│       └── zalando-ha-scaling.md
├── observability/                # Observability documentation
│   ├── README.md                 # Master index + 4-pillar architecture
│   ├── architecture.md           # 3-layer service architecture + APM integration
│   ├── metrics/                  # Pillar 1: Metrics
│   │   ├── README.md             # Hub: fundamentals, stack, architecture, coverage
│   │   ├── metrics-apps.md       # Application + gRPC east-west metrics (RED)
│   │   ├── metrics-infra.md      # Cluster / infrastructure metrics (USE)
│   │   ├── victoriametrics.md    # VictoriaMetrics Operator stack
│   │   ├── vmauth.md             # VMAuth/vmauth HTTP proxy (auth.config, Operator CRs)
│   │   ├── promql-guide.md       # PromQL reference
│   │   └── postgresql/           # PostgreSQL-specific metrics (databases layer)
│   │       ├── monitoring.md
│   │       ├── custom-metrics.md
│   │       ├── pg-exporter-dashboards.md
│   │       └── pg-exporter-mapping.md
│   ├── tracing/                  # Pillar 2: Distributed Tracing
│   │   ├── README.md             # Tracing guide (Tempo + OTel)
│   │   ├── architecture.md       # Dual backend (Tempo + Jaeger)
│   │   ├── jaeger.md             # Jaeger UI guide
│   │   ├── backends-comparison.md # Tempo vs Jaeger vs VictoriaTraces
│   │   └── victoriatraces.md     # VictoriaTraces pilot (3rd backend)
│   ├── logging/                  # Pillar 3: Structured Logging
│   │   ├── README.md             # Architecture, why-this-stack, scaling
│   │   └── victorialogs.md       # VictoriaLogs backend & Vector pipeline ops
│   ├── profiling/                # Pillar 4: Continuous Profiling
│   │   └── README.md             # Pyroscope (CPU, heap, goroutine)
│   ├── grafana/                  # Visualization layer
│   │   ├── README.md             # Grafana overview + plugins
│   │   ├── rbac-multi-team.md    # Org roles, Teams, anonymous vs named users
│   │   ├── datasources.md        # Dual datasource strategy (case study)
│   │   ├── dashboard-reference.md # Microservices dashboard (34 panels)
│   │   └── variables.md          # Dashboard variables & regex
│   ├── alerting/                 # Alerting rules
│   │   ├── README.md             # 2-layer alerting strategy
│   │   └── alert-catalog.md      # Full alert reference (145 rules) + coverage gaps
│   ├── slo/                      # Service Level Objectives
│   │   ├── README.md             # Sloth Operator + SLO targets
│   │   ├── getting_started.md    # Enable SLO via Helm values
│   │   ├── alerting.md           # Multi-window burn-rate alerts
│   │   ├── error_budget_policy.md
│   │   └── annotation-driven-slo-controller.md
│   └── runbooks/                 # Operational runbooks
│       ├── README.md             # Runbook index
│       ├── observability-deep-dive.md   # Theory + interview prep
│       └── microservices-alerts.md      # Per-alert investigation guide
├── caching/                     # Valkey cache: Cache-Aside, eviction policies, distributed-cache concept
│   └── caching.md
├── platform/                     # Platform/deployment documentation
│   ├── setup.md                  # GitOps deployment guide
│   ├── application-delivery.md    # ResourceSet patterns & templates
│   ├── cicd.md                   # CI/CD pipelines + standard/policy (pinning, permissions, signing, GoReleaser)
│   ├── gitflow.md                # Git branching & release standard
│   ├── sonarcloud.md             # SonarCloud integration
│   └── kong-gateway.md           # Kong API gateway — concept + DB-less, plugins, routing, rate-limiting
├── runbooks/                     # Operational runbooks
│   ├── metrics-audit-fixes.md    # Metrics audit runbook (before/after fixes)
│   └── troubleshooting/          # Troubleshooting guides
│       ├── pgcat_prepared_statement_error.md
│       ├── pgcat_read_only_transaction_error.md
│       ├── pgcat_upstream_connectivity_errors.md
│       ├── postgres_backup_restore.md  # PostgreSQL backup/restore procedures
│       └── victorialogs_kubernetes_logs_debug.md  # VictoriaLogs log debugging
├── secrets/                      # Secrets, TLS & trust distribution (one chain)
│   ├── README.md                 # OpenBAO architecture & operations (folder hub)
│   ├── secrets-management.md     # Per-app ESO usage, add/rotate runbooks
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

1. **[Services Index](../SERVICES.md)** - List of all service repositories (Polyrepo)
2. **[Setup Guide](./platform/setup.md)** - Complete GitOps deployment guide
   - Quick start (3 commands, 5 minutes)
   - GitOps architecture with Flux Operator
   - Simplified structure (infra/ + apps/, refactored 2026-01-12)
   - Multi-environment support
   - Step-by-step instructions
   - Troubleshooting common issues

3. **[API Reference](./api/api.md)** - API endpoints and adding new microservices
   - Requirements and conventions
   - Step-by-step guide
   - Automatic monitoring setup

4. **[API naming convention (draft v1.0.0)](./api/api-naming-convention.md)** - Gateway URL layout (`gateway.duynh.me`), Chợ Tốt–style segments + Google notes; does not replace `api.md`

5. **[GKE internal & private DNS](./api/gke-internal-dns.md)** - `cluster.local`, Cloud DNS private zones, multi-environment naming

### Observability

#### Metrics

1. **[Metrics Guide](./observability/metrics/README.md)** - Complete metrics documentation
   - 4 custom application metrics (RED method)
   - 34 data panels + 5 row panels in Grafana dashboard
   - Exemplars, path normalization, auto-discovery

2. **[PromQL Guide](./observability/metrics/promql-guide.md)** - Complete guide to PromQL functions
   - `rate()` vs `increase()` functions
   - Counter resets handling
   - Time range vs rate interval
   - Best practices and troubleshooting

3. **[Variables & Regex](./observability/grafana/variables.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

4. **[Grafana Dashboard Guide](./observability/grafana/dashboard-reference.md)** - Complete dashboard reference for SRE/DevOps
    - All 34 panels with query analysis and troubleshooting
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
    - Metrics, Tracing, Logging, Profiling
    - Component inventory and correlation workflow
    - Deployment and quick start

2. **[Distributed Tracing](./observability/tracing/README.md)** - Tempo integration guide
3. **[Tracing Architecture](./observability/tracing/architecture.md)** - Dual backend (Tempo + Jaeger)
4. **[Jaeger Guide](./observability/tracing/jaeger.md)** - Jaeger UI usage, comparison with Tempo
5. **[Backend Comparison](./observability/tracing/backends-comparison.md)** - Tempo vs Jaeger vs VictoriaTraces (+ roadmap)
6. **[VictoriaTraces (pilot)](./observability/tracing/victoriatraces.md)** - 3rd backend via the VM operator
5. **[Continuous Profiling](./observability/profiling/README.md)** - Pyroscope setup
6. **[Logging](./observability/logging/README.md)** - Architecture, VictoriaLogs vs Loki, scaling
7. **[VictoriaLogs](./observability/logging/victorialogs.md)** - VictoriaLogs deployment and configuration
    - Single Vector architecture (ships to VictoriaLogs)
    - PostgreSQL auto_explain plan parsing pipeline
    - Verification and troubleshooting

### API Reference

1. **[API Reference](./api/api.md)** - Complete API documentation
    - All 8 microservices
    - Endpoints, models, examples
    - Health checks and metrics

2. **[API naming convention (draft v1.0.0)](./api/api-naming-convention.md)** - Edge/gateway naming exploration; canonical routes remain in `api.md`

3. **[gRPC internal comms (proposed/draft)](./api/grpc-internal-comms.md)** - Selective gRPC for internal east-west calls; dual-port, HTTP/2 LB pitfall, phased roadmap

4. **[Temporal order-fulfillment saga (implemented)](./api/temporal-order-fulfillment.md)** - Why/when to use Temporal, the durable saga design, contracts, infra, ops — with [ADR-001](./proposals/adr/ADR-001-adopt-temporal-for-order-fulfillment/)/[ADR-002](./proposals/adr/ADR-002-deploy-temporal-via-operator/)

5. **[RFCs — propose & track substantial changes](./proposals/rfc/)** - RFC process, index, and the consolidated backlog (the old API/architecture review is retired — its findings merged into `api.md`, open items moved to the RFC backlog)

6. **[GKE internal & private DNS](./api/gke-internal-dns.md)** - In-cluster DNS and Cloud DNS private zones

### Databases

1. **[Database Guide](./databases/002-database-integration.md)** - PostgreSQL database integration guide
    - 4 PostgreSQL clusters architecture with comprehensive diagrams
    - Overview diagram showing operators, services, poolers, and clusters
    - Individual cluster diagrams with secrets, connections, and patterns

2. **[Operator Comparison](./databases/003-operator-comparison.md)** - CloudNativePG vs Zalando decision guide
    - Concise decision matrix
    - Homelab cluster-to-operator mapping
    - Links to [CloudNativePG](./databases/003.1-operator-cnpg.md) and [Zalando](./databases/003.2-operator-zalando.md) deep dives

3. **[PostgreSQL Internals Deep Dive](./databases/001-postgresql-internals.md)** - PostgreSQL internals using cnpg-db examples
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
    - Connection patterns (direct, PgBouncer, PgCat)
    - Environment variables and Helm configuration
    - Database verification and troubleshooting
    - Monitoring and best practices

4. **[PostgreSQL Disaster Recovery](./databases/010-drp.md)** - HA, DR, RPO/RTO, PITR, standby taxonomy, and restore evidence
    - [RPO/RTO Planning](./databases/010.1-rpo-rto-planning.md) - per-tier targets vs as-built, mapped to clusters
    - [Restore & Failover Drills](./databases/010.2-restore-and-failover-drills.md) - drill cadence, roles, and evidence log
    - [Cross-Region / Cross-Zone DR](./databases/010.3-cross-region-dr.md) - roadmap to independent failure domains
    - [Emergency Recovery](./databases/010.4-emergency-recovery.md) - "start here when it's down" runbook

### Runbooks & Troubleshooting

1. **[Metrics Audit Fixes](./runbooks/metrics-audit-fixes.md)** - Metrics audit runbook with before/after code, PromQL verification, dashboard impact
2. **[PgCat Prepared Statement Error](./runbooks/troubleshooting/pgcat_prepared_statement_error.md)** - Fix intermittent 500 errors with PgCat connection pooler
3. **[PgCat Read-Only Transaction](./runbooks/troubleshooting/pgcat_read_only_transaction_error.md)** - Fix read-only transaction errors
4. **[PgCat Upstream Connectivity](./runbooks/troubleshooting/pgcat_upstream_connectivity_errors.md)** - Fix upstream connectivity errors
5. **[PostgreSQL Backup/Restore](./runbooks/troubleshooting/postgres_backup_restore.md)** - Backup and restore procedures (CNPG vs Zalando)
6. **[VictoriaLogs Log Debugging](./runbooks/troubleshooting/victorialogs_kubernetes_logs_debug.md)** - Kubernetes log debugging with VictoriaLogs

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
- [Grafana Dashboard Guide](./observability/grafana/dashboard-reference.md) - Complete SRE/DevOps dashboard reference (34 panels + annotations planning)

#### SLO/SRE
- [SLO Overview](./observability/slo/README.md) - Architecture, SLI definitions, targets
- [Getting Started](./observability/slo/getting_started.md) - Enable SLOs via Helm values
- [SLO Burn-Rate Alerts](./observability/alerting/slo-burn-rate-alerts.md) - Alert configuration
- [Error Budget Policy](./observability/slo/error_budget_policy.md) - Budget management
- [Annotation-Driven Controller](./observability/slo/annotation-driven-slo-controller.md) - Future approach

#### Observability Pillars
- [Observability Overview](./observability/README.md) - Master index, 4-pillar architecture, 3-layer service architecture + APM integration
- [Distributed Tracing](./observability/tracing/README.md) - Tempo integration
- [Tracing Architecture](./observability/tracing/architecture.md) - Dual backend (Tempo + Jaeger)
- [Jaeger Guide](./observability/tracing/jaeger.md) - Jaeger UI usage, comparison with Tempo
- [Backend Comparison](./observability/tracing/backends-comparison.md) - Tempo vs Jaeger vs VictoriaTraces
- [VictoriaTraces (pilot)](./observability/tracing/victoriatraces.md) - 3rd backend via the VM operator
- [Continuous Profiling](./observability/profiling/README.md) - Pyroscope setup
- [Logging](./observability/logging/README.md) - Architecture, VictoriaLogs vs Loki, scaling
- [VictoriaLogs](./observability/logging/victorialogs.md) - VictoriaLogs deployment (single Vector, dual-ship)

### API

- [API Reference](./api/api.md) - Complete API documentation
- [gRPC Internal Comms (proposed/draft)](./api/grpc-internal-comms.md) - Selective gRPC for internal east-west calls; dual-port, HTTP/2 LB pitfall, phased roadmap
- [Temporal Order-Fulfillment Saga](./api/temporal-order-fulfillment.md) - Durable order saga (why/when/how, design, infra, ops)
- [RFC-0009: Production-grade API gateway (signed JWT + Kong edge auth)](./proposals/rfc/RFC-0009/) - Partially implemented; supersedes ADR-003 via ADR-006
- [RFCs](./proposals/rfc/) - Propose & track substantial changes (process + index + backlog)

### Decisions (ADRs)

- [ADR index](./proposals/adr/README.md) - Architecture Decision Records (the *why* behind significant choices)
- [ADR-001: Adopt Temporal for order fulfillment](./proposals/adr/ADR-001-adopt-temporal-for-order-fulfillment/)
- [ADR-002: Deploy Temporal via the operator](./proposals/adr/ADR-002-deploy-temporal-via-operator/)
- [ADR-003: Keep JWT validation in services, not at Kong](./proposals/adr/ADR-003-jwt-validation-in-services-not-kong/) - **Superseded by ADR-006**
- [ADR-004: Enable OpenBAO audit logging](./proposals/adr/ADR-004-enable-openbao-audit-logging/) - Accepted
- [ADR-005: Run OpenBAO HA (Raft) instead of Vault dev mode](./proposals/adr/ADR-005-openbao-ha-raft/) - Accepted
- [ADR-006: Adopt RS256 signed JWTs + Kong edge authentication](./proposals/adr/ADR-006-rs256-jwt-kong-edge-auth/) - Accepted; implements [RFC-0009](./proposals/rfc/RFC-0009/)

### Databases

- [Database Guide](./databases/002-database-integration.md) - PostgreSQL database integration guide
- [Operator Comparison](./databases/003-operator-comparison.md) - CloudNativePG vs Zalando decision guide
- [CloudNativePG Operator](./databases/003.1-operator-cnpg.md) - CloudNativePG feature and operations deep dive
- [Zalando Postgres Operator](./databases/003.2-operator-zalando.md) - Patroni/Spilo operator deep dive
- [Architecture](./databases/007-architecture.md) - Database architecture overview
- [Backup Strategy](./databases/006-backup-strategy.md) - Backup architecture and retention
- [Extensions](./databases/009-extensions.md) - PostgreSQL extensions (operand built-in vs Image Volume models)
- [Connection Poolers](./databases/008-pooler.md) - PgBouncer, PgCat, PgDog
- [Replication Strategy](./databases/004-replication-strategy.md) - Replication strategy
- [HA & DR Deep Dive](./databases/005-ha-dr-deep-dive.md) - cnpg-db vs cnpg-db-replica (object-store DR)
- [PostgreSQL DRP](./databases/010-drp.md) - DRP, RTO/RPO, PITR, standby taxonomy, and restore evidence
    - [RPO/RTO Planning](./databases/010.1-rpo-rto-planning.md) - per-tier targets vs as-built, mapped to clusters
    - [Restore & Failover Drills](./databases/010.2-restore-and-failover-drills.md) - drill cadence, roles, and evidence log
    - [Cross-Region / Cross-Zone DR](./databases/010.3-cross-region-dr.md) - roadmap to independent failure domains
    - [Emergency Recovery](./databases/010.4-emergency-recovery.md) - "start here when it's down" runbook
- [PostgreSQL Further Reading](./databases/011-documents.md) - Curated external references
- [PostgreSQL Internals](./databases/001-postgresql-internals.md) - Deep dive using cnpg-db examples

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

### Secrets

- [Secrets Management](./secrets/secrets-management.md) - OpenBAO + ESO guide for centralized secret management
- [OpenBAO](./secrets/README.md) - OpenBAO HA architecture & operations (incl. reviewer-JWT pitfall, bootstrap-only Cloudflare token)
- [cert-manager + Flux](./secrets/cert-manager.md) - TLS with Let's Encrypt, HelmRelease, Ingress
- [Trust Distribution](./secrets/trust-distribution.md) - trust-manager `homelab-ca-bundle` and the LE / homelab-CA dual-PKI split
- [Secrets decisions & hardening](./proposals/) - ADR-004 (audit) + ADR-005 (OpenBAO HA); [RFC-0008](./proposals/rfc/RFC-0008/) production hardening + parity/testing matrix (+ its implementation.md migration plan); RFC backlog for rotation / PushSecret

### Runbooks

- [Metrics Audit Fixes](./runbooks/metrics-audit-fixes.md) - Before/after metrics audit with PromQL verification
- [PgCat Prepared Statement Error](./runbooks/troubleshooting/pgcat_prepared_statement_error.md) - Fix intermittent 500 errors with connection pooler
- [PgCat Read-Only Transaction](./runbooks/troubleshooting/pgcat_read_only_transaction_error.md) - Fix read-only transaction errors
- [PgCat Upstream Connectivity](./runbooks/troubleshooting/pgcat_upstream_connectivity_errors.md) - Fix upstream connectivity errors
- [PostgreSQL Backup/Restore](./runbooks/troubleshooting/postgres_backup_restore.md) - Backup and restore procedures
- [VictoriaLogs Log Debugging](./runbooks/troubleshooting/victorialogs_kubernetes_logs_debug.md) - Kubernetes log debugging with VictoriaLogs

---

## Quick Reference

### Key Concepts

- **GitOps** - Declarative infrastructure managed via Flux Operator
- **Flux Operator** - Kubernetes-native GitOps reconciliation engine
- **Kustomize** - Simplified structure (direct manifests in infra/ + apps/, refactored 2026-01-12)
- **OCI Registry** - `localhost:5050` (local), stores Kubernetes manifests as artifacts
- **Helm Chart** - Generic chart for all microservices (`charts/`)
- **HelmRelease CRDs** - Flux manages Helm deployments declaratively
- **34 Data Panels + 5 Row Panels** - Complete monitoring dashboard
- **4 Custom Metrics** - Application-level metrics (RED method)
- **8 Microservices** - All services with v1 API (canonical)
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
- **[.cursor/rules/](../.cursor/rules/)** - Development guidelines

---

**Last Updated**: 2026-07-01
