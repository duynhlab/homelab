# Documentation Index

Complete documentation for the Go REST API Monitoring & Observability Platform.

---

## Learning Path

### 🚀 Getting Started (New Users)

1. **[Setup Guide](./guides/SETUP.md)** - Complete deployment guide
   - Quick start (5 minutes)
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

4. **[Prometheus Rate Explained](./monitoring/PROMETHEUS_RATE_EXPLAINED.md)** - Understanding `rate()` and `increase()`
   - Counter resets
   - Time range vs rate interval
   - Best practices

5. **[Time Range & Rate Interval](./monitoring/TIME_RANGE_AND_RATE_INTERVAL.md)** - Dashboard variables guide
   - When to use different intervals
   - Smoothing vs responsiveness

6. **[Variables & Regex](./monitoring/VARIABLES_REGEX.md)** - Dashboard variable patterns
   - Filter configurations
   - Multi-select patterns

7. **[Metrics Label Solutions](./monitoring/METRICS_LABEL_SOLUTIONS.md)** - Label configuration guide
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

22. **[Error Handling](./guides/ERROR_HANDLING.md)** - Error handling patterns

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

25. **[Dashboard Panels Guide](./guides/DASHBOARD_PANELS.md)** - Complete dashboard reference for SRE/DevOps
    - All 34 panels with query analysis and troubleshooting
    - PromQL patterns and best practices (Google SRE, Prometheus docs)
    - Before/After comparisons for updated panels (Status Code, Apdex, 4xx/5xx)
    - SRE runbooks and incident response scenarios

### 🚦 k6 Load Testing

23. **[k6 Load Testing](./k6/K6_LOAD_TESTING.md)** - Load testing setup and architecture
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
- [Prometheus Rate Explained](./monitoring/PROMETHEUS_RATE_EXPLAINED.md) - Understanding rate functions
- [Time Range & Rate Interval](./monitoring/TIME_RANGE_AND_RATE_INTERVAL.md) - Dashboard variables
- [Variables & Regex](./monitoring/VARIABLES_REGEX.md) - Filter patterns
- [Metrics Label Solutions](./monitoring/METRICS_LABEL_SOLUTIONS.md) - Label configuration

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
- [Error Handling](./guides/ERROR_HANDLING.md) - Error handling patterns
- [Database Guide](./guides/DATABASE.md) - PostgreSQL database integration guide
- [Tracing Architecture](./guides/TRACING_ARCHITECTURE.md) - Distributed tracing architecture
- [Dashboard Panels Guide](./guides/DASHBOARD_PANELS.md) - Complete SRE/DevOps dashboard reference (34 panels)

### k6 Load Testing
- [k6 Load Testing](./k6/K6_LOAD_TESTING.md) - Complete load testing guide with architecture

### Archive
- [Microservices Refactoring](./archive/MICROSERVICES_REFACTORING.md) - Historical architecture document
- [Grafana Annotations Plan](./archive/GRAFANA_ANNOTATIONS_PLAN.md) - Planning document
- [Deployment Plan](./archive/plan.deploy.md) - Historical deployment plan
- [API Architecture](./archive/api.md) - Architecture planning document

---

## Quick Reference

### Key Concepts
- **Helm Chart** - Generic chart for all microservices (`charts/`)
- **OCI Registry** - `oci://ghcr.io/duynhne/charts/microservice`
- **32 Grafana Panels** - Complete monitoring dashboard
- **6 Custom Metrics** - Application-level metrics
- **9 Microservices** - All services with v1/v2 APIs
- **Monitoring Stack** - Prometheus Operator + Grafana Operator + kube-state-metrics + metrics-server
- **SLO System** - Sloth Operator with PrometheusServiceLevel CRDs
- **APM Stack** - Tempo + Jaeger (tracing), OTel Collector (fan-out), Pyroscope (profiling), Loki + Vector (logging)
- **k6 Load Testing** - Helm-managed load generators

### Common Tasks

**Deploy everything:**
```bash
./scripts/01-create-kind-cluster.sh      # Step 1: Infrastructure
./scripts/02-deploy-monitoring.sh        # Step 2: Monitoring + metrics (BEFORE apps)
./scripts/03-deploy-apm.sh               # Step 3: APM (BEFORE apps)
./scripts/04-deploy-databases.sh         # Step 4: Databases (BEFORE apps)
./scripts/06-deploy-microservices.sh     # Step 5: Deploy (from OCI registry, images built by GitHub Actions)
./scripts/07-deploy-k6.sh               # Step 6: Load testing (AFTER apps)
./scripts/08-deploy-slo.sh               # Step 7: SLO system
./scripts/09-setup-access.sh             # Step 8: Access setup
```

**Manual Helm deployment:**
```bash
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
```

**Deploy SLOs:**
```bash
./scripts/07-deploy-slo.sh
```

**Access services:**
- Grafana: http://localhost:3000 (admin/admin)
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

