# Documentation Index

Complete documentation for the Go REST API Monitoring & Observability Platform.

---

## Learning Path

### Getting Started (New Users)

1. **[Setup Guide](./guides/SETUP.md)** - Complete GitOps deployment guide
   - Quick start (3 commands, 5 minutes)
   - GitOps architecture with Flux Operator
   - Simplified structure (infra/ + apps/, refactored 2026-01-12)
   - Multi-environment support
   - Step-by-step instructions
   - Troubleshooting common issues

2. **[API Reference](./guides/API_REFERENCE.md)** - API endpoints and adding new microservices
   - Requirements and conventions
   - Step-by-step guide
   - Automatic monitoring setup

### 📊 Monitoring & Metrics

3. **[Metrics Guide](./monitoring/METRICS.md)** - Complete metrics documentation
   - 6 custom application metrics
   - 32 Grafana dashboard panels
   - Memory leak detection strategy

4. **[PromQL Guide](./monitoring/PROMQL_GUIDE.md)** - Complete guide to PromQL functions
   - `rate()` vs `increase()` functions
   - Counter resets handling
   - Time range vs rate interval
   - Best practices and troubleshooting

5. **[Variables & Regex](./monitoring/VARIABLES_REGEX.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

7. **[Metrics Labels](./monitoring/METRICS_LABEL.md)** - Label configuration guide
   - Kubernetes Downward API
   - ServiceMonitor configuration

### 🎯 Service Level Objectives (SLO)

8. **[SLO Documentation](./slo/README.md)** - Complete SLO system overview
   - SLI definitions
   - Error budgets
   - Burn rate alerts

9. **[SLO Getting Started](./slo/GETTING_STARTED.md)** - Quick start guide
   - Validate definitions
   - Generate rules
   - Deploy to Prometheus

10. **[SLI Definitions](./slo/SLI_DEFINITIONS.md)** - Service Level Indicator specifications
11. **[SLO Targets](./slo/SLO_TARGETS.md)** - SLO targets per service
12. **[Alerting](./slo/ALERTING.md)** - Alert configuration and runbooks
13. **[Error Budget Policy](./slo/ERROR_BUDGET_POLICY.md)** - Budget management guidelines

### 🔌 API Reference

14. **[API Reference](./guides/API_REFERENCE.md)** - Complete API documentation
    - All 9 microservices
    - Endpoints, models, examples
    - Health checks and metrics

### 🔍 Application Performance Monitoring (APM)

16. **[APM Overview](./apm/README.md)** - Complete APM system overview
    - Distributed tracing with Tempo + Jaeger
    - OpenTelemetry Collector for trace fan-out
    - Continuous profiling with Pyroscope
    - Log aggregation with Loki + Vector
    - Grafana Operator datasource integration

17. **[APM Architecture](./apm/ARCHITECTURE.md)** - System architecture
18. **[Distributed Tracing](./apm/TRACING.md)** - Tempo integration guide
19. **[Jaeger Guide](./apm/JAEGER.md)** - Jaeger UI usage, comparison with Tempo
20. **[Continuous Profiling](./apm/PROFILING.md)** - Pyroscope setup
21. **[Log Aggregation](./apm/LOGGING.md)** - Loki + Vector configuration

### 💻 Development Guides

21. **[Setup Guide](./guides/SETUP.md)** - Complete deployment and configuration guide
    - Step-by-step deployment instructions
    - Configuration management (.env, environment variables, Helm values)
    - Local development setup
    - Troubleshooting common issues

22. **[Error Handling](./guides/API_REFERENCE.md#error-handling)** - Error handling patterns

23. **[Database Guide](./guides/DATABASE.md)** - PostgreSQL database integration guide
    - 5 PostgreSQL clusters architecture with comprehensive diagrams
    - Overview diagram showing operators, services, poolers, and clusters
    - Individual cluster diagrams with secrets, connections, and patterns
    - Cross-namespace secrets visualization for supporting-db
    - Connection patterns (direct, PgBouncer, PgCat)
    - Environment variables and Helm configuration
    - Database verification and troubleshooting
    - Monitoring and best practices

24. **[Tracing Architecture](./guides/TRACING_ARCHITECTURE.md)** - Distributed tracing architecture

25. **[Grafana Dashboard Guide](./guides/GRAFANA_DASHBOARD.md)** - Complete dashboard reference for SRE/DevOps
    - All 34 panels with query analysis and troubleshooting
    - PromQL patterns and best practices (Google SRE, Prometheus docs)
    - Before/After comparisons for updated panels (Status Code, Apdex, 4xx/5xx)
    - SRE runbooks and incident response scenarios
    - Grafana Annotations planning (planned feature)

### k6 Load Testing

23. **[k6 Load Testing](./k6/README.md)** - Load testing setup and architecture
    - System architecture with filtering
    - Multiple scenarios (5 user personas)
    - Deployment configurations
    - Best practices (v0.6.14+)

---

## Documentation by Category

### Getting Started
- [Setup Guide](./guides/SETUP.md) - Complete deployment instructions
- [API Reference](./guides/API_REFERENCE.md) - API endpoints and adding new microservices

### Monitoring
- [Metrics Guide](./monitoring/METRICS.md) - Comprehensive metrics documentation
- [PromQL Guide](./monitoring/PROMQL_GUIDE.md) - Complete guide to PromQL functions, time range vs rate interval, and counter handling
- [Variables & Regex](./monitoring/VARIABLES_REGEX.md) - Filter patterns
- [Metrics Labels](./monitoring/METRICS_LABEL.md) - Label configuration

### SLO/SRE
- [SLO Overview](./slo/README.md) - System overview
- [Getting Started](./slo/GETTING_STARTED.md) - Setup guide
- [SLI Definitions](./slo/SLI_DEFINITIONS.md) - Indicator specifications
- [SLO Targets](./slo/SLO_TARGETS.md) - Service targets
- [Alerting](./slo/ALERTING.md) - Alert configuration
- [Error Budget Policy](./slo/ERROR_BUDGET_POLICY.md) - Budget management

### API
- [API Reference](./guides/API_REFERENCE.md) - Complete API documentation

### APM
- [APM Overview](./apm/README.md) - Complete APM system overview
- [APM Architecture](./apm/ARCHITECTURE.md) - System architecture
- [Distributed Tracing](./apm/TRACING.md) - Tempo integration
- [Jaeger Guide](./apm/JAEGER.md) - Jaeger UI usage, comparison with Tempo
- [Continuous Profiling](./apm/PROFILING.md) - Pyroscope setup
- [Log Aggregation](./apm/LOGGING.md) - Loki + Vector

### Development Guides
- [Setup Guide](./guides/SETUP.md) - Complete deployment and configuration guide
- [Error Handling](./guides/API_REFERENCE.md#error-handling) - Error handling patterns
- [Database Guide](./guides/DATABASE.md) - PostgreSQL database integration guide
- [Tracing Architecture](./guides/TRACING_ARCHITECTURE.md) - Distributed tracing architecture
- [Grafana Dashboard Guide](./guides/GRAFANA_DASHBOARD.md) - Complete SRE/DevOps dashboard reference (34 panels + annotations planning)

### k6 Load Testing
- [k6 Load Testing](./k6/README.md) - Complete load testing guide with architecture

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
- **9 Microservices** - All services with v1/v2 APIs
- **Monitoring Stack** - Prometheus Operator + Grafana Operator + kube-state-metrics + metrics-server
- **SLO System** - Sloth Operator with PrometheusServiceLevel CRDs
- **APM Stack** - Tempo + Jaeger (tracing), OTel Collector (fan-out), Pyroscope (profiling), Loki + Vector (logging)
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
# SLOs are deployed automatically via Flux
flux reconcile kustomization slo-stack --with-source  # Manual trigger
```

**Access services:**
- Flux Web UI: http://localhost:9080 (./scripts/flux-ui.sh)
- Grafana: http://localhost:3000 (anonymous/enabled)
- Prometheus: http://localhost:9090
- Jaeger UI: http://localhost:16686
- API: http://localhost:8080

---

## Additional Resources

- **[AGENTS.md](../AGENTS.md)** - AI agent guide for navigating the codebase
- **[README.md](../README.md)** - Project overview and quick start
- **[.cursor/rules/](../.cursor/rules/)** - Development guidelines

---

**Last Updated**: December 2025

