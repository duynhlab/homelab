# Documentation Index

Complete documentation for the Go REST API Monitoring & Observability Platform.

---

## Documentation Structure

```
docs/
├── api/                          # API documentation
│   └── API.md                    # Complete API reference
├── databases/                    # Database documentation
│   ├── DATABASE.md               # PostgreSQL architecture
│   └── POSTGRESQL_INTERNALS_PRODUCT_DB.md  # PostgreSQL internals deep dive
├── observability/                # Observability documentation
│   ├── apm/                      # Application Performance Monitoring
│   │   ├── README.md             # APM overview
│   │   ├── ARCHITECTURE.md       # APM architecture
│   │   ├── TRACING.md            # Distributed tracing (Tempo)
│   │   ├── TRACING_ARCHITECTURE.md # Tracing architecture
│   │   ├── JAEGER.md             # Jaeger UI guide
│   │   ├── LOGGING.md            # Log aggregation (Loki + Vector)
│   │   └── PROFILING.md          # Continuous profiling (Pyroscope)
│   ├── logs/                     # Logging systems
│   │   └── victorialogs/         # VictoriaLogs
│   │       └── README.md
│   ├── metrics/                  # Metrics documentation
│   │   ├── METRICS.md            # Complete metrics guide
│   │   ├── GRAFANA_DASHBOARD.md  # Dashboard reference
│   │   ├── PROMQL_GUIDE.md       # PromQL functions
│   │   ├── VARIABLES_REGEX.md    # Dashboard variables
│   │   ├── METRICS_LABEL.md      # Label configuration
│   │   └── POSTGRES_CUSTOM_METRICS.md
│   └── slo/                      # Service Level Objectives
│       ├── README.md             # SLO overview
│       ├── GETTING_STARTED.md    # Quick start
│       ├── SLI_DEFINITIONS.md    # SLI specifications
│       ├── SLO_TARGETS.md        # SLO targets
│       ├── ALERTING.md           # Alert configuration
│       └── ERROR_BUDGET_POLICY.md
├── platform/                     # Platform/deployment documentation
│   └── SETUP.md                  # GitOps deployment guide
├── runbooks/                     # Operational runbooks
│   └── troubleshooting/          # Troubleshooting guides
│       ├── PGCAT_PREPARED_STATEMENT_ERROR.md
│       ├── PGCAT_READ_ONLY_TRANSACTION_ERROR.md
│       └── PGCAT_UPSTREAM_CONNECTIVITY_ERRORS.md
└── testing/                      # Testing documentation
    └── K6.md                     # k6 load testing guide
```

---

## Learning Path

### Getting Started (New Users)

1. **[Setup Guide](./platform/SETUP.md)** - Complete GitOps deployment guide
   - Quick start (3 commands, 5 minutes)
   - GitOps architecture with Flux Operator
   - Simplified structure (infra/ + apps/, refactored 2026-01-12)
   - Multi-environment support
   - Step-by-step instructions
   - Troubleshooting common issues

2. **[API Reference](./api/API.md)** - API endpoints and adding new microservices
   - Requirements and conventions
   - Step-by-step guide
   - Automatic monitoring setup

### Observability

#### Metrics

1. **[Metrics Guide](./observability/metrics/METRICS.md)** - Complete metrics documentation
   - 6 custom application metrics
   - 32 Grafana dashboard panels
   - Memory leak detection strategy

2. **[PromQL Guide](./observability/metrics/PROMQL_GUIDE.md)** - Complete guide to PromQL functions
   - `rate()` vs `increase()` functions
   - Counter resets handling
   - Time range vs rate interval
   - Best practices and troubleshooting

3. **[Variables & Regex](./observability/metrics/VARIABLES_REGEX.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

4. **[Metrics Labels](./observability/metrics/METRICS_LABEL.md)** - Label configuration guide
   - Kubernetes Downward API
   - ServiceMonitor configuration

5. **[Grafana Dashboard Guide](./observability/metrics/GRAFANA_DASHBOARD.md)** - Complete dashboard reference for SRE/DevOps
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

2. **[SLO Getting Started](./observability/slo/GETTING_STARTED.md)** - Quick start guide
   - Validate definitions
   - Generate rules
   - Deploy to Prometheus

3. **[SLI Definitions](./observability/slo/SLI_DEFINITIONS.md)** - Service Level Indicator specifications
4. **[SLO Targets](./observability/slo/SLO_TARGETS.md)** - SLO targets per service
5. **[Alerting](./observability/slo/ALERTING.md)** - Alert configuration and runbooks
6. **[Error Budget Policy](./observability/slo/ERROR_BUDGET_POLICY.md)** - Budget management guidelines

#### Application Performance Monitoring (APM)

1. **[APM Overview](./observability/apm/README.md)** - Complete APM system overview
    - Distributed tracing with Tempo + Jaeger
    - OpenTelemetry Collector for trace fan-out
    - Continuous profiling with Pyroscope
    - Log aggregation with Loki + Vector + VictoriaLogs
    - Grafana Operator datasource integration

2. **[APM Architecture](./observability/apm/ARCHITECTURE.md)** - System architecture
3. **[Distributed Tracing](./observability/apm/TRACING.md)** - Tempo integration guide
4. **[Tracing Architecture](./observability/apm/TRACING_ARCHITECTURE.md)** - Distributed tracing architecture
5. **[Jaeger Guide](./observability/apm/JAEGER.md)** - Jaeger UI usage, comparison with Tempo
6. **[Continuous Profiling](./observability/apm/PROFILING.md)** - Pyroscope setup
7. **[Log Aggregation](./observability/apm/LOGGING.md)** - Loki + Vector configuration
8. **[VictoriaLogs](./observability/logs/victorialogs/README.md)** - VictoriaLogs deployment and configuration
    - Single Vector architecture (dual-ship to Loki + VictoriaLogs)
    - PostgreSQL auto_explain plan parsing pipeline
    - Verification and troubleshooting

### API Reference

1. **[API Reference](./api/API.md)** - Complete API documentation
    - All 9 microservices
    - Endpoints, models, examples
    - Health checks and metrics

### Databases

1. **[Database Guide](./databases/DATABASE.md)** - PostgreSQL database integration guide
    - 5 PostgreSQL clusters architecture with comprehensive diagrams
    - Overview diagram showing operators, services, poolers, and clusters
    - Individual cluster diagrams with secrets, connections, and patterns

2. **[PostgreSQL Internals Deep Dive](./databases/POSTGRESQL_INTERNALS_PRODUCT_DB.md)** - PostgreSQL internals using product-db
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

1. **[k6 Load Testing](./testing/K6.md)** - Load testing setup and architecture
    - System architecture with filtering
    - Multiple scenarios (5 user personas)
    - Deployment configurations
    - Best practices (v0.6.14+)

### Runbooks & Troubleshooting

1. **[PgCat Prepared Statement Error](./runbooks/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md)** - Fix intermittent 500 errors with PgCat connection pooler
    - Prepared statement parameter mismatch
    - Solution: `prefer_simple_protocol=true`
    - Diagram: Why the error happens

---

## Documentation by Category

### Getting Started

- [Setup Guide](./platform/SETUP.md) - Complete deployment instructions
- [API Reference](./api/API.md) - API endpoints and adding new microservices

### Observability

#### Metrics
- [Metrics Guide](./observability/metrics/METRICS.md) - Comprehensive metrics documentation
- [PromQL Guide](./observability/metrics/PROMQL_GUIDE.md) - Complete guide to PromQL functions, time range vs rate interval, and counter handling
- [Variables & Regex](./observability/metrics/VARIABLES_REGEX.md) - Filter patterns
- [Metrics Labels](./observability/metrics/METRICS_LABEL.md) - Label configuration
- [Grafana Dashboard Guide](./observability/metrics/GRAFANA_DASHBOARD.md) - Complete SRE/DevOps dashboard reference (34 panels + annotations planning)

#### SLO/SRE
- [SLO Overview](./observability/slo/README.md) - System overview
- [Getting Started](./observability/slo/GETTING_STARTED.md) - Setup guide
- [SLI Definitions](./observability/slo/SLI_DEFINITIONS.md) - Indicator specifications
- [SLO Targets](./observability/slo/SLO_TARGETS.md) - Service targets
- [Alerting](./observability/slo/ALERTING.md) - Alert configuration
- [Error Budget Policy](./observability/slo/ERROR_BUDGET_POLICY.md) - Budget management

#### APM
- [APM Overview](./observability/apm/README.md) - Complete APM system overview
- [APM Architecture](./observability/apm/ARCHITECTURE.md) - System architecture
- [Distributed Tracing](./observability/apm/TRACING.md) - Tempo integration
- [Tracing Architecture](./observability/apm/TRACING_ARCHITECTURE.md) - Distributed tracing architecture
- [Jaeger Guide](./observability/apm/JAEGER.md) - Jaeger UI usage, comparison with Tempo
- [Continuous Profiling](./observability/apm/PROFILING.md) - Pyroscope setup
- [Log Aggregation](./observability/apm/LOGGING.md) - Loki + Vector
- [VictoriaLogs](./observability/logs/victorialogs/README.md) - VictoriaLogs deployment (single Vector, dual-ship)

### API

- [API Reference](./api/API.md) - Complete API documentation

### Databases

- [Database Guide](./databases/DATABASE.md) - PostgreSQL database integration guide

### Platform

- [Setup Guide](./platform/SETUP.md) - Complete deployment and configuration guide

### Testing

- [k6 Load Testing](./testing/K6.md) - Complete load testing guide with architecture

### Runbooks

- [PgCat Prepared Statement Error](./runbooks/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md) - Fix intermittent 500 errors with connection pooler

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
