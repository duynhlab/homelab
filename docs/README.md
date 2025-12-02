# Documentation Index

Complete documentation for the Go REST API Monitoring & Observability Platform.

---

## Learning Path

### 🚀 Getting Started (New Users)

1. **[Setup Guide](./getting-started/SETUP.md)** - Complete deployment guide
   - Quick start (5 minutes)
   - Step-by-step instructions
   - Troubleshooting common issues

2. **[Adding Services](./getting-started/ADDING_SERVICES.md)** - How to add new microservices
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

14. **[API Reference](./api/API_REFERENCE.md)** - Complete API documentation
    - All 9 microservices
    - Endpoints, models, examples
    - Health checks and metrics

### 🚦 Load Testing

15. **[k6 Load Testing](./load-testing/K6_LOAD_TESTING.md)** - Load testing setup
    - Multiple scenarios
    - Deployment configurations
    - Monitoring load tests

---

## Documentation by Category

### Getting Started
- [Setup Guide](./getting-started/SETUP.md) - Complete deployment instructions
- [Adding Services](./getting-started/ADDING_SERVICES.md) - How to add new microservices

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
- [API Reference](./api/API_REFERENCE.md) - Complete API documentation

### Load Testing
- [k6 Load Testing](./load-testing/K6_LOAD_TESTING.md) - Load testing guide

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
- **SLO System** - Error budgets and burn rate alerts

### Common Tasks

**Deploy everything:**
```bash
./scripts/01-create-kind-cluster.sh
./scripts/02-install-metrics.sh
./scripts/05-build-microservices.sh
./scripts/06-deploy-microservices.sh --local   # Uses local Helm chart
./scripts/03-deploy-monitoring.sh
./scripts/07-deploy-k6-testing.sh
./scripts/09-setup-access.sh
```

**Deploy from OCI registry:**
```bash
./scripts/06-deploy-microservices.sh --registry  # Uses oci://ghcr.io/duynhne/charts/microservice
```

**Manual Helm deployment:**
```bash
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
```

**Deploy SLOs:**
```bash
./scripts/08a-validate-slo.sh
./scripts/08b-generate-slo-rules.sh
./scripts/08-deploy-slo.sh
```

**Access services:**
- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090
- API: http://localhost:8080

---

## Additional Resources

- **[AGENTS.md](../AGENTS.md)** - AI agent guide for navigating the codebase
- **[README.md](../README.md)** - Project overview and quick start
- **[.cursor/rules/](../.cursor/rules/)** - Development guidelines

---

**Last Updated**: November 2024

