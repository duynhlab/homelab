# Documentation Index

Complete documentation for the Go REST API Monitoring & Observability Platform.

---

## Documentation Structure

```
docs/
├── api/                          # API documentation
│   └── api.md                    # Complete API reference
├── databases/                    # Database documentation
│   ├── database.md               # PostgreSQL architecture
│   ├── operator.md               # CloudNativePG vs Zalando operator deep dive
│   ├── architecture.md           # Database architecture overview
│   ├── backup.md                 # Backup strategy and retention
│   ├── extensions.md             # PostgreSQL extensions
│   ├── pooler.md                 # Connection pooler documentation
│   ├── replication_strategy.md   # Replication strategy
│   └── postgresql_internals_product_db.md  # PostgreSQL internals deep dive
├── observability/                # Observability documentation
│   ├── apm/                      # Application Performance Monitoring
│   │   ├── README.md             # APM overview
│   │   ├── architecture.md       # APM architecture
│   │   ├── tracing.md            # Distributed tracing (Tempo)
│   │   ├── tracing_architecture.md # Tracing architecture
│   │   ├── jaeger.md             # Jaeger UI guide
│   │   ├── logging.md            # Log aggregation (Loki + Vector)
│   │   └── profiling.md          # Continuous profiling (Pyroscope)
│   ├── logs/                     # Logging systems
│   │   └── victorialogs/         # VictoriaLogs
│   │       └── README.md
│   ├── metrics/                  # Metrics documentation
│   │   ├── README.md             # Complete metrics guide (RED method, architecture)
│   │   ├── grafana-dashboard.md  # Dashboard reference (34 panels)
│   │   ├── grafana-variables.md  # Dashboard variables & regex
│   │   ├── promql-guide.md       # PromQL functions & counter handling
│   │   ├── postgresql-monitoring.md           # PostgreSQL monitoring overview
│   │   ├── postgresql-custom-metrics.md       # PostgreSQL custom queries
│   │   ├── postgresql-pg-exporter-mapping.md  # pg_exporter metric mapping
│   │   └── postgresql-pg-exporter-dashboards.md  # pg_exporter dashboard analysis
│   └── slo/                      # Service Level Objectives
│       ├── README.md             # SLO overview, architecture, targets
│       ├── getting_started.md    # Enable SLO via Helm values
│       ├── alerting.md           # Alert configuration
│       ├── error_budget_policy.md
│       └── annotation-driven-slo-controller.md  # Future: annotation-based automation
├── platform/                     # Platform/deployment documentation
│   ├── setup.md                  # GitOps deployment guide
│   ├── cicd.md                   # CI/CD pipelines
│   └── sonarcloud.md             # SonarCloud integration
├── runbooks/                     # Operational runbooks
│   ├── metrics-audit-fixes.md    # Metrics audit runbook (before/after fixes)
│   └── troubleshooting/          # Troubleshooting guides
│       ├── pgcat_prepared_statement_error.md
│       ├── pgcat_read_only_transaction_error.md
│       ├── pgcat_upstream_connectivity_errors.md
│       ├── postgres_backup_restore.md  # PostgreSQL backup/restore procedures
│       └── loki_kubernetes_logs_debug.md  # Loki log debugging
├── secrets/                      # Secrets management documentation
│   ├── secrets-management.md     # Vault + ESO guide
│   └── vault.md                  # Vault configuration details
└── testing/                      # Testing documentation
    └── k6.md                     # k6 load testing guide
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

2. **[API Reference](./api/api.md)** - API endpoints and adding new microservices
   - Requirements and conventions
   - Step-by-step guide
   - Automatic monitoring setup

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

3. **[Variables & Regex](./observability/metrics/grafana-variables.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

4. **[Grafana Dashboard Guide](./observability/metrics/grafana-dashboard.md)** - Complete dashboard reference for SRE/DevOps
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

3. **[Alerting](./observability/slo/alerting.md)** - Alert configuration and runbooks
4. **[Error Budget Policy](./observability/slo/error_budget_policy.md)** - Budget management guidelines
5. **[Annotation-Driven Controller](./observability/slo/annotation-driven-slo-controller.md)** - Future approach for large-scale automation

#### Application Performance Monitoring (APM)

1. **[APM Overview](./observability/apm/README.md)** - Complete APM system overview
    - Distributed tracing with Tempo + Jaeger
    - OpenTelemetry Collector for trace fan-out
    - Continuous profiling with Pyroscope
    - Log aggregation with Loki + Vector + VictoriaLogs
    - Grafana Operator datasource integration

2. **[APM Architecture](./observability/apm/architecture.md)** - System architecture
3. **[Distributed Tracing](./observability/apm/tracing.md)** - Tempo integration guide
4. **[Tracing Architecture](./observability/apm/tracing_architecture.md)** - Distributed tracing architecture
5. **[Jaeger Guide](./observability/apm/jaeger.md)** - Jaeger UI usage, comparison with Tempo
6. **[Continuous Profiling](./observability/apm/profiling.md)** - Pyroscope setup
7. **[Log Aggregation](./observability/apm/logging.md)** - Loki + Vector configuration
8. **[VictoriaLogs](./observability/logs/victorialogs/README.md)** - VictoriaLogs deployment and configuration
    - Single Vector architecture (dual-ship to Loki + VictoriaLogs)
    - PostgreSQL auto_explain plan parsing pipeline
    - Verification and troubleshooting

### API Reference

1. **[API Reference](./api/api.md)** - Complete API documentation
    - All 8 microservices
    - Endpoints, models, examples
    - Health checks and metrics

### Databases

1. **[Database Guide](./databases/database.md)** - PostgreSQL database integration guide
    - 4 PostgreSQL clusters architecture with comprehensive diagrams
    - Overview diagram showing operators, services, poolers, and clusters
    - Individual cluster diagrams with secrets, connections, and patterns

2. **[Operator Comparison](./databases/operator.md)** - CloudNativePG vs Zalando deep dive
    - Core architecture differences (Instance Manager vs Patroni)
    - HA and failover mechanisms with sequence diagrams
    - Feature comparison matrix, strengths, trade-offs
    - Production recommendations and decision matrix

3. **[PostgreSQL Internals Deep Dive](./databases/postgresql_internals_product_db.md)** - PostgreSQL internals using product-db
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

### Testing

1. **[k6 Load Testing](./testing/k6.md)** - Load testing setup and architecture
    - System architecture with filtering
    - Multiple scenarios (5 user personas)
    - Deployment configurations
    - Best practices (v0.6.14+)

### Runbooks & Troubleshooting

1. **[Metrics Audit Fixes](./runbooks/metrics-audit-fixes.md)** - Metrics audit runbook with before/after code, PromQL verification, dashboard impact
2. **[PgCat Prepared Statement Error](./runbooks/troubleshooting/pgcat_prepared_statement_error.md)** - Fix intermittent 500 errors with PgCat connection pooler
3. **[PgCat Read-Only Transaction](./runbooks/troubleshooting/pgcat_read_only_transaction_error.md)** - Fix read-only transaction errors
4. **[PgCat Upstream Connectivity](./runbooks/troubleshooting/pgcat_upstream_connectivity_errors.md)** - Fix upstream connectivity errors
5. **[PostgreSQL Backup/Restore](./runbooks/troubleshooting/postgres_backup_restore.md)** - Backup and restore procedures (CNPG vs Zalando)
6. **[Loki Log Debugging](./runbooks/troubleshooting/loki_kubernetes_logs_debug.md)** - Kubernetes log debugging with Loki

---

## Documentation by Category

### Getting Started

- [Setup Guide](./platform/setup.md) - Complete deployment instructions
- [API Reference](./api/api.md) - API endpoints and adding new microservices

### Observability

#### Metrics
- [Metrics Guide](./observability/metrics/README.md) - Comprehensive metrics documentation
- [PromQL Guide](./observability/metrics/promql-guide.md) - Complete guide to PromQL functions, time range vs rate interval, and counter handling
- [Variables & Regex](./observability/metrics/grafana-variables.md) - Filter patterns
- [Grafana Dashboard Guide](./observability/metrics/grafana-dashboard.md) - Complete SRE/DevOps dashboard reference (34 panels + annotations planning)

#### SLO/SRE
- [SLO Overview](./observability/slo/README.md) - Architecture, SLI definitions, targets
- [Getting Started](./observability/slo/getting_started.md) - Enable SLOs via Helm values
- [Alerting](./observability/slo/alerting.md) - Alert configuration
- [Error Budget Policy](./observability/slo/error_budget_policy.md) - Budget management
- [Annotation-Driven Controller](./observability/slo/annotation-driven-slo-controller.md) - Future approach

#### APM
- [APM Overview](./observability/apm/README.md) - Complete APM system overview
- [APM Architecture](./observability/apm/architecture.md) - System architecture
- [Distributed Tracing](./observability/apm/tracing.md) - Tempo integration
- [Tracing Architecture](./observability/apm/tracing_architecture.md) - Distributed tracing architecture
- [Jaeger Guide](./observability/apm/jaeger.md) - Jaeger UI usage, comparison with Tempo
- [Continuous Profiling](./observability/apm/profiling.md) - Pyroscope setup
- [Log Aggregation](./observability/apm/logging.md) - Loki + Vector
- [VictoriaLogs](./observability/logs/victorialogs/README.md) - VictoriaLogs deployment (single Vector, dual-ship)

### API

- [API Reference](./api/api.md) - Complete API documentation

### Databases

- [Database Guide](./databases/database.md) - PostgreSQL database integration guide
- [Operator Comparison](./databases/operator.md) - CloudNativePG vs Zalando deep dive
- [Architecture](./databases/architecture.md) - Database architecture overview
- [Backup Strategy](./databases/backup.md) - Backup architecture and retention
- [Extensions](./databases/extensions.md) - PostgreSQL extensions
- [Connection Poolers](./databases/pooler.md) - PgBouncer, PgCat, PgDog
- [Replication Strategy](./databases/replication_strategy.md) - Replication strategy
- [PostgreSQL Internals](./databases/postgresql_internals_product_db.md) - Deep dive using product-db

### Platform

- [Setup Guide](./platform/setup.md) - Complete deployment and configuration guide
- [CI/CD](./platform/cicd.md) - CI/CD pipelines and workflows
- [SonarCloud](./platform/sonarcloud.md) - SonarCloud integration

### Secrets

- [Secrets Management](./secrets/secrets-management.md) - Vault + ESO guide for centralized secret management
- [Vault](./secrets/vault.md) - Vault configuration details
- [Backlog (P1/P2)](./secrets/backlog.md) - Pending improvements: bootstrap split, rotation, audit logging, PushSecret, HA templates

### Testing

- [k6 Load Testing](./testing/k6.md) - Complete load testing guide with architecture

### Runbooks

- [Metrics Audit Fixes](./runbooks/metrics-audit-fixes.md) - Before/after metrics audit with PromQL verification
- [PgCat Prepared Statement Error](./runbooks/troubleshooting/pgcat_prepared_statement_error.md) - Fix intermittent 500 errors with connection pooler
- [PgCat Read-Only Transaction](./runbooks/troubleshooting/pgcat_read_only_transaction_error.md) - Fix read-only transaction errors
- [PgCat Upstream Connectivity](./runbooks/troubleshooting/pgcat_upstream_connectivity_errors.md) - Fix upstream connectivity errors
- [PostgreSQL Backup/Restore](./runbooks/troubleshooting/postgres_backup_restore.md) - Backup and restore procedures
- [Loki Log Debugging](./runbooks/troubleshooting/loki_kubernetes_logs_debug.md) - Kubernetes log debugging with Loki

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
- **Monitoring Stack** - Prometheus Operator + Grafana Operator + kube-state-metrics + metrics-server
- **SLO System** - Sloth Operator with PrometheusServiceLevel CRDs
- **APM Stack** - Tempo + Jaeger (tracing), OTel Collector (fan-out), Pyroscope (profiling), Loki + VictoriaLogs + Vector (logging)
- **Secrets Stack** - HashiCorp Vault (dev mode) + External Secrets Operator for centralized secret management
- **k6 Load Testing** - Helm-managed load generators

### Common Tasks

**Deploy everything with GitOps:**

```bash
# Check prerequisites
make prereqs

# Deploy complete stack
make up                      # cluster-up + flux-up + flux-push

# Manage deployments
make sync                    # flux-push + flux-sync
make flux-ui                 # Open Flux Web UI (http://localhost:9080)
make flux-status             # Check sync status
kubectl get helmreleases -A  # Check HelmReleases
kubectl get pods -A          # Check all pods

# Cleanup
make down                    # Delete cluster + registry
```

**Manual Helm deployment (for testing):**

```bash
helm upgrade --install auth charts/mop/ -f charts/mop/values/auth.yaml -n auth --create-namespace
```

**Deploy SLOs:**

```bash
# SLOs are auto-generated by mop Helm chart (slo.enabled: true in HelmRelease)
# Deploy via GitOps:
make flux-push && make flux-sync
```

**Access services:**

- Flux Web UI: <http://localhost:9080> (`make flux-ui`)
- Grafana: <http://localhost:3000> (anonymous/enabled)
- Prometheus: <http://localhost:9090>
- Jaeger UI: <http://localhost:16686>
- API: <http://localhost:8080>

---

## Additional Resources

- **[AGENTS.md](../AGENTS.md)** - AI agent guide for navigating the codebase
- **[README.md](../README.md)** - Project overview and quick start
- **[.cursor/rules/](../.cursor/rules/)** - Development guidelines

---

**Last Updated**: February 2026
