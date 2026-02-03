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
│   │   ├── metrics.md            # Complete metrics guide
│   │   ├── grafana_dashboard.md  # Dashboard reference
│   │   ├── promql_guide.md       # PromQL functions
│   │   ├── variables_regex.md    # Dashboard variables
│   │   ├── metrics_label.md      # Label configuration
│   │   └── POSTGRES_CUSTOM_metrics.md
│   └── slo/                      # Service Level Objectives
│       ├── README.md             # SLO overview
│       ├── getting_started.md    # Quick start
│       ├── sli_definitions.md    # SLI specifications
│       ├── slo_targets.md        # SLO targets
│       ├── alerting.md           # Alert configuration
│       └── error_budget_policy.md
├── platform/                     # Platform/deployment documentation
│   └── setup.md                  # GitOps deployment guide
├── runbooks/                     # Operational runbooks
│   └── troubleshooting/          # Troubleshooting guides
│       ├── pgcat_prepared_statement_error.md
│       ├── pgcat_read_only_transaction_error.md
│       └── pgcat_upstream_connectivity_errors.md
└── testing/                      # Testing documentation
    └── k6.md                     # k6 load testing guide
```

---

## Learning Path

### Getting Started (New Users)

1. **[Setup Guide](./platform/setup.md)** - Complete GitOps deployment guide
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

1. **[Metrics Guide](./observability/metrics/metrics.md)** - Complete metrics documentation
   - 6 custom application metrics
   - 32 Grafana dashboard panels
   - Memory leak detection strategy

2. **[PromQL Guide](./observability/metrics/promql_guide.md)** - Complete guide to PromQL functions
   - `rate()` vs `increase()` functions
   - Counter resets handling
   - Time range vs rate interval
   - Best practices and troubleshooting

3. **[Variables & Regex](./observability/metrics/variables_regex.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

4. **[Metrics Labels](./observability/metrics/metrics_label.md)** - Label configuration guide
   - Kubernetes Downward API
   - ServiceMonitor configuration

5. **[Grafana Dashboard Guide](./observability/metrics/grafana_dashboard.md)** - Complete dashboard reference for SRE/DevOps
    - All 34 panels with query analysis and troubleshooting
    - PromQL patterns and best practices (Google SRE, Prometheus docs)
    - Before/After comparisons for updated panels (Status Code, Apdex, 4xx/5xx)
    - SRE runbooks and incident response scenarios
    - Grafana Annotations planning (planned feature)

#### Service Level Objectives (SLO)

1. **[SLO Documentation](./observability/slo/README.md)** - Complete SLO system overview
   - SLI definitions
   - Error budgets
   - Burn rate alerts

2. **[SLO Getting Started](./observability/slo/getting_started.md)** - Quick start guide
   - Validate definitions
   - Generate rules
   - Deploy to Prometheus

3. **[SLI Definitions](./observability/slo/sli_definitions.md)** - Service Level Indicator specifications
4. **[SLO Targets](./observability/slo/slo_targets.md)** - SLO targets per service
5. **[Alerting](./observability/slo/alerting.md)** - Alert configuration and runbooks
6. **[Error Budget Policy](./observability/slo/error_budget_policy.md)** - Budget management guidelines

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
    - All 9 microservices
    - Endpoints, models, examples
    - Health checks and metrics

### Databases

1. **[Database Guide](./databases/database.md)** - PostgreSQL database integration guide
    - 5 PostgreSQL clusters architecture with comprehensive diagrams
    - Overview diagram showing operators, services, poolers, and clusters
    - Individual cluster diagrams with secrets, connections, and patterns

2. **[PostgreSQL Internals Deep Dive](./databases/postgresql_internals_product_db.md)** - PostgreSQL internals using product-db
    - INSERT/UPDATE workflow with sequence diagrams
    - Shared Buffers and Buffer Manager explained
    - WAL (Write-Ahead Log) and crash recovery
    - MVCC, tuple versioning, and visibility
    - Streaming Replication internals (WAL sender/receiver, lag)
    - Storage: files, pages, and on-disk layout
    - Autovacuum and bloat control
    - CNPG vs EC2/VM operational differences
    - Backup/restore, scaling, and sharding concepts
    - Cross-namespace secrets visualization for supporting-db
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

1. **[PgCat Prepared Statement Error](./runbooks/troubleshooting/pgcat_prepared_statement_error.md)** - Fix intermittent 500 errors with PgCat connection pooler
    - Prepared statement parameter mismatch
    - Solution: `prefer_simple_protocol=true`
    - Diagram: Why the error happens

---

## Documentation by Category

### Getting Started

- [Setup Guide](./platform/setup.md) - Complete deployment instructions
- [API Reference](./api/api.md) - API endpoints and adding new microservices

### Observability

#### Metrics
- [Metrics Guide](./observability/metrics/metrics.md) - Comprehensive metrics documentation
- [PromQL Guide](./observability/metrics/promql_guide.md) - Complete guide to PromQL functions, time range vs rate interval, and counter handling
- [Variables & Regex](./observability/metrics/variables_regex.md) - Filter patterns
- [Metrics Labels](./observability/metrics/metrics_label.md) - Label configuration
- [Grafana Dashboard Guide](./observability/metrics/grafana_dashboard.md) - Complete SRE/DevOps dashboard reference (34 panels + annotations planning)

#### SLO/SRE
- [SLO Overview](./observability/slo/README.md) - System overview
- [Getting Started](./observability/slo/getting_started.md) - Setup guide
- [SLI Definitions](./observability/slo/sli_definitions.md) - Indicator specifications
- [SLO Targets](./observability/slo/slo_targets.md) - Service targets
- [Alerting](./observability/slo/alerting.md) - Alert configuration
- [Error Budget Policy](./observability/slo/error_budget_policy.md) - Budget management

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

### Platform

- [Setup Guide](./platform/setup.md) - Complete deployment and configuration guide

### Testing

- [k6 Load Testing](./testing/k6.md) - Complete load testing guide with architecture

### Runbooks

- [PgCat Prepared Statement Error](./runbooks/troubleshooting/pgcat_prepared_statement_error.md) - Fix intermittent 500 errors with connection pooler

---

## Quick Reference

### Key Concepts

- **GitOps** - Declarative infrastructure managed via Flux Operator
- **Flux Operator** - Kubernetes-native GitOps reconciliation engine
- **Kustomize** - Simplified structure (direct manifests in infra/ + apps/, refactored 2026-01-12)
- **OCI Registry** - `localhost:5050` (local), stores Kubernetes manifests as artifacts
- **Helm Chart** - Generic chart for all microservices (`charts/`)
- **HelmRelease CRDs** - Flux manages Helm deployments declaratively
- **32 Grafana Panels** - Complete monitoring dashboard
- **6 Custom Metrics** - Application-level metrics
- **9 Microservices** - All services with v1 API (canonical)
- **Monitoring Stack** - Prometheus Operator + Grafana Operator + kube-state-metrics + metrics-server
- **SLO System** - Sloth Operator with PrometheusServiceLevel CRDs
- **APM Stack** - Tempo + Jaeger (tracing), OTel Collector (fan-out), Pyroscope (profiling), Loki + VictoriaLogs + Vector (logging)
- **k6 Load Testing** - Helm-managed load generators

### Common Tasks

**Deploy everything with GitOps:**

```bash
# Check prerequisites
make prereqs

# Deploy complete stack (3 commands)
./scripts/kind-up.sh        # Create Kind cluster + OCI registry
./scripts/flux-up.sh         # Bootstrap Flux Operator
./scripts/flux-push.sh       # Deploy all infrastructure + apps

# Manage deployments
./scripts/flux-sync.sh       # Trigger reconciliation
./scripts/flux-ui.sh         # Open Flux Web UI (http://localhost:9080)
flux get kustomizations      # Check sync status
kubectl get helmreleases -A  # Check HelmReleases
kubectl get pods -A          # Check all pods

# Cleanup
./scripts/kind-down.sh       # Delete cluster + registry
```

**Manual Helm deployment (for testing):**

```bash
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
```

**Deploy SLOs:**

```bash
# SLOs are deployed automatically via Flux (part of configs-local)
flux reconcile kustomization configs-local --with-source  # Manual trigger
```

**Access services:**

- Flux Web UI: <http://localhost:9080> (./scripts/flux-ui.sh)
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

**Last Updated**: January 2026
