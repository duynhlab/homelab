# AI Agent Guide

> **IMPORTANT**: AGENTS.md files are the source of truth for AI agent instructions. Always update the relevant AGENTS.md file when adding or modifying agent guidance.

## Overview

This guide provides comprehensive information for AI agents working with this codebase. Use it to navigate the project structure, understand conventions, and execute common workflows.

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
# Architecture diagram
flowchart TD
    A[Component A] --> B[Component B]
    B --> C[Component C]
```

```mermaid
# Sequence diagram
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

## Quick Navigation

- [Project Structure](#project-structure-for-agent-navigation) - Directory organization and purpose
- [Key Files](#key-files-and-locations) - Important files by category
- [Common Workflows](#common-workflows) - Step-by-step guides for frequent tasks
- [Command Reference](#command-reference) - Scripts and commands organized by purpose
- [Conventions](#conventions-and-standards) - Naming, namespace, and pattern standards
- [Quick Lookup](#quick-navigation) - Find files by purpose

---

## Project Structure for Agent Navigation

### Root Directory

```
monitoring/
├── services/              # All Go application code
│   ├── cmd/               # Microservice entry points (9 services)
│   ├── internal/          # Domain logic (private packages)
│   ├── pkg/               # Shared packages (public)
│   ├── Dockerfile         # Unified Dockerfile for all services
│   ├── go.mod
│   └── go.sum
├── charts/                # Helm chart for microservices deployment
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values/            # Per-service values (auth.yaml, user.yaml, etc.)
│   └── templates/
├── k8s/                   # Kubernetes manifests
│   ├── prometheus/
│   │   ├── values.yaml             # kube-prometheus-stack Helm values
│   │   └── servicemonitor-microservices.yaml  # Single ServiceMonitor for all services
│   ├── grafana-operator/
│   ├── sloth/             # Sloth Operator (SLO management)
│   ├── tempo/             # Grafana Tempo (distributed tracing)
│   ├── pyroscope/         # Pyroscope (continuous profiling)
│   ├── loki/              # Loki v3.6.2 (log storage with pattern ingestion)
│   ├── vector/            # Vector (log collection)
│   ├── kind/              # Kind cluster configuration
│   └── namespaces.yaml
├── scripts/               # Deployment and utility scripts (numbered 01-12)
├── docs/                  # Documentation
├── slo/                   # SLO data files (backup definitions)
├── k6/                    # K6 load testing (Dockerfile + scripts)
├── README.md              # Project overview
├── CLAUDE.md              # Link to  AGENTS.md for Claude (Anthropic) still uses CLAUDE.md
├── CHANGELOG.md           # Version changelog
└── AGENTS.md              # This file (source of truth for AI agent instructions)
```

### Directory Details

#### `services/` - Go Application Code

All Go source code is organized under the `services/` directory:

```
services/
├── cmd/                   # Microservice entry points (9 services)
│   ├── auth/
│   ├── user/
│   ├── product/
│   ├── cart/
│   ├── order/
│   ├── review/
│   ├── notification/
│   ├── shipping/
│   └── shipping-v2/
├── internal/              # Domain logic (private packages)
│   ├── auth/
│   │   ├── web/           # HTTP handlers layer
│   │   │   ├── v1/
│   │   │   └── v2/
│   │   ├── logic/         # Business logic layer
│   │   │   ├── v1/
│   │   │   └── v2/
│   │   └── core/          # Core domain layer
│   │       └── domain/
│   ├── user/
│   ├── product/
│   ├── cart/
│   ├── order/
│   ├── review/
│   ├── notification/
│   └── shipping/
├── pkg/                   # Shared packages
│   └── middleware/
├── Dockerfile
├── go.mod
└── go.sum
```

**Services** (9 microservices):
- `auth` - Authentication API (v1/v2)
- `user` - User management API (v1/v2)
- `product` - Product catalog API (v1/v2)
- `cart` - Shopping cart API (v1/v2)
- `order` - Order management API (v1/v2)
- `review` - Product reviews API (v1/v2)
- `notification` - Notifications API (v1/v2)
- `shipping` - Shipping API (v1 only)
- `shipping-v2` - Enhanced shipping API (v2 only)

**Pattern**: Each service has versioned API endpoints (`/api/v1/*`, `/api/v2/*`) with 3-layer architecture:
- `web/v1/`, `web/v2/` - HTTP handlers (Gin handlers)
- `logic/v1/`, `logic/v2/` - Business logic layer
- `core/domain/` - Domain models

**Shared Code**: 
- `pkg/middleware/prometheus.go` - Prometheus metrics middleware (collects metrics with `method`, `path`, `code` labels; `app`, `namespace` added by Prometheus during scrape)
- `pkg/middleware/logging.go` - Structured logging middleware with trace-id correlation
- `pkg/middleware/tracing.go` - OpenTelemetry distributed tracing middleware
- `pkg/middleware/profiling.go` - Pyroscope continuous profiling middleware

#### `charts/` - Helm Chart

Generic Helm chart for deploying all microservices:

```
charts/
├── Chart.yaml             # Chart metadata (name: microservice, version: 0.2.0)
├── values.yaml            # Default values (includes extraEnv pattern)
├── values/                # Per-service value overrides
│   ├── auth.yaml
│   ├── user.yaml
│   ├── product.yaml
│   ├── cart.yaml
│   ├── order.yaml
│   ├── review.yaml
│   ├── notification.yaml
│   ├── shipping.yaml
│   └── shipping-v2.yaml
└── templates/
    ├── _helpers.tpl       # Template helpers
    ├── deployment.yaml    # Deployment template (unified env block)
    └── service.yaml       # Service template
```

**Usage:**
```bash
# Local deployment
./scripts/06-deploy-microservices.sh --local

# From OCI registry
./scripts/06-deploy-microservices.sh --registry

# Manual Helm install
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
```

**OCI Registry:** `oci://ghcr.io/duynhne/charts/microservice`

#### `k8s/` - Kubernetes Manifests

Kubernetes manifests for monitoring and infrastructure components:

```
k8s/
├── prometheus/           # Prometheus Operator configuration
│   ├── values.yaml       # kube-prometheus-stack Helm values
│   └── servicemonitor-microservices.yaml  # Single ServiceMonitor for all services
├── grafana-operator/     # Grafana Operator resources
│   ├── README.md         # Helm install instructions
│   ├── values.yaml       # Operator Helm values
│   ├── grafana.yaml      # Grafana CR (anonymous auth, dark theme)
│   ├── datasource-*.yaml # Datasource CRs (Prometheus, Tempo, Loki, Pyroscope)
│   └── dashboards/       # Kustomize (ConfigMap + GrafanaDashboard CRs)
├── sloth/                # Sloth Operator (SLO management)
│   ├── values.yaml       # Helm values for Sloth Operator
│   ├── README.md
│   └── crds/             # PrometheusServiceLevel CRDs (9 services)
├── tempo/                # Grafana Tempo (distributed tracing)
├── pyroscope/            # Pyroscope (continuous profiling)
├── loki/                 # Loki v3.6.2 (log storage with pattern ingestion)
├── vector/               # Vector (log collection with self-monitoring)
│   ├── configmap.yaml    # Vector config (internal_metrics + prometheus_exporter)
│   ├── service.yaml      # Expose metrics on port 9090
│   ├── servicemonitor.yaml # Auto-discovery for Prometheus
│   └── rbac.yaml         # Permissions for log collection
├── kind/                 # Kind cluster configuration
└── namespaces.yaml       # Namespace definitions
```

**Note**: Microservices are deployed via Helm chart (`charts/`), not raw YAML manifests. Grafana is managed via the Grafana Operator (`k8s/grafana-operator/`).

**Namespaces**:
- `monitoring` - Monitoring components (Prometheus, Grafana, Tempo, Pyroscope, Loki) and SLO system
- `kube-system` - Vector (log collection DaemonSet)
- `k6` - K6 load testing
- Service namespaces - Each microservice has its own namespace: `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`

#### `scripts/` - Deployment Scripts

Numbered scripts (01-12) for deployment and operations:

**Deployment Order:**
1. Infrastructure (01-02) → 2. Monitoring (03) → 3. APM (04) → 4. Build & Deploy Apps (05-06) → 5. Load Testing (07) → 6. SLO (08) → 7. Access Setup (09)

**Infrastructure (01-02):**
- `01-create-kind-cluster.sh` - Create Kind Kubernetes cluster
- `02-install-metrics.sh` - Install metrics infrastructure (kube-state-metrics, etc.)

**Monitoring Stack (03):**
- `03-deploy-monitoring.sh` - Deploy Prometheus and install Grafana Operator (BEFORE apps to collect metrics immediately)

**APM Stack (04) - Required:**
- `04a-deploy-tempo.sh` - Deploy Grafana Tempo v2.9.0 (distributed tracing with metrics-generator for TraceQL rate() queries)
- `04b-deploy-pyroscope.sh` - Deploy Pyroscope (continuous profiling)
- `04c-deploy-loki.sh` - Deploy Loki + Vector (log aggregation)
- `04-deploy-apm.sh` - Deploy all APM components (deploy BEFORE apps to collect traces/logs/profiles immediately)

**APM Configuration:**
- Tracing sampling: 10% (production), 100% (development) - configurable via `OTEL_SAMPLE_RATE`
- Request filtering: health/metrics endpoints automatically skipped
- Graceful shutdown: automatic span flushing on termination
- Service detection: automatic from Kubernetes pod metadata

**Build & Deploy Applications (05-06):**
- `05-build-microservices.sh` - Build Docker images for all 9 services
- `06-deploy-microservices.sh` - Deploy all microservices using Helm (`--local` or `--registry`)

**Load Testing (07):**
- `07-deploy-k6.sh` - Deploy k6 load generators via Helm (deploy AFTER apps to test them)

**SLO System (08) - Required:**
- `08-deploy-slo.sh` - Deploy Sloth Operator and SLO CRDs (automatic validation & rule generation)

**Access Setup (09):**
- `09-setup-access.sh` - Setup port-forwarding for services

**Utilities:**
- `10-reload-dashboard.sh` - Reapply Grafana Operator dashboards (microservices + SLO)
- `11-diagnose-latency.sh` - Diagnostic script for latency issues
- `12-error-budget-alert.sh` - Error budget alert response script
- `cleanup.sh` - Clean up Kind cluster and resources

#### `docs/` - Documentation

- `METRICS.md` - Comprehensive metrics documentation (32 panels, 6 custom metrics)
- `K6_LOAD_TESTING.md` - k6 load testing setup
- `SETUP.md` - Step-by-step deployment guide
- `API_REFERENCE.md` - API endpoint documentation
- `PROMETHEUS_RATE_EXPLAINED.md` - Prometheus rate() and increase() explained
- `slo/` - SLO documentation (6 files):
  - `README.md` - SLO system overview
  - `GETTING_STARTED.md` - SLO setup guide
  - `SLI_DEFINITIONS.md` - SLI specifications
  - `SLO_TARGETS.md` - SLO targets per service
  - `ALERTING.md` - Alert configuration
  - `ERROR_BUDGET_POLICY.md` - Error budget management

#### `slo/` - SLO Data Files

**Note**: SLO definitions have been migrated to PrometheusServiceLevel CRDs in `k8s/sloth/crds/*.yaml`, managed by Sloth Operator. This directory is now empty.

#### `k6/` - Load Testing

```
k6/
├── Dockerfile                           # Unified Dockerfile (ARG-based)
├── load-test.js                         # Legacy load test script
└── load-test-multiple-scenarios.js      # Multiple scenarios script
```

**K6 Deployment**: Helm-based (reuses `charts/`)
- Build 2 images: `ghcr.io/duynhne/k6:legacy`, `ghcr.io/duynhne/k6:scenarios`
- Deploy to `k6` namespace
- Helm values: `charts/values/k6-legacy.yaml`, `charts/values/k6-scenarios.yaml`
- Health checks disabled: K6 is a load testing tool with no HTTP health endpoint

#### `k8s/sloth/` - SLO Management (Sloth Operator)

```
k8s/sloth/
├── values.yaml           # Helm values for Sloth Operator
├── README.md             # Deployment instructions
└── crds/                 # PrometheusServiceLevel CRDs (9 services)
    ├── auth-slo.yaml
    ├── user-slo.yaml
    ├── product-slo.yaml
    ├── cart-slo.yaml
    ├── order-slo.yaml
    ├── review-slo.yaml
    ├── notification-slo.yaml
    ├── shipping-slo.yaml
    └── shipping-v2-slo.yaml
```

**Sloth Operator**: Kubernetes-native SLO management
- Helm deployment: `sloth/sloth` chart v0.15.0
- Automatic Prometheus rule generation
- PrometheusServiceLevel CRDs (one per service)
- No more bash scripts for validation/generation

---

## Key Files and Locations

### Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| Helm Chart | Microservices deployment chart | `charts/` |
| Helm Values | Per-service configuration | `charts/values/*.yaml` |
| Prometheus Operator Values | kube-prometheus-stack Helm values | `k8s/prometheus/values.yaml` |
| ServiceMonitor | Auto-discovery for all microservices | `k8s/prometheus/servicemonitor-microservices.yaml` |
| Grafana Datasources | Prometheus datasource | `k8s/grafana-operator/datasource-prometheus.yaml` |
| Grafana Dashboards | Operator-managed dashboards (microservices + SLO + Vector) | `k8s/grafana-operator/dashboards/` (`microservices-dashboard.json` is the source of truth) |
| Dockerfile | Unified build for all services | `services/Dockerfile` |
| Go Modules | Go dependencies | `services/go.mod` |

### Dashboard Files

| File | Purpose | Location |
|------|---------|----------|
| Main Dashboard | 32 panels in 5 row groups | `k8s/grafana-operator/dashboards/microservices-dashboard.json` |
| Vector Dashboard | Vector self-monitoring (ID: 21954) | `k8s/grafana-operator/dashboards/grafana-dashboard-vector.yaml` |
| SLO Overview | SLO summary dashboard (ID: 14643) | `k8s/grafana-operator/dashboards/grafana-dashboard-slo-overview.yaml` |
| SLO Detailed | Detailed SLO metrics (ID: 14348) | `k8s/grafana-operator/dashboards/grafana-dashboard-slo-detailed.yaml` |

**Dashboard Details:**
- **UID**: `microservices-monitoring-001`
- **Title**: "Microservices Monitoring & Performance Applications"
- **Structure**: 32 panels organized in 5 row groups:
  1. **📊 Overview & Key Metrics** (12 panels) - Response time percentiles (P50, P95, P99), Total RPS, Success RPS (2xx), Error RPS (4xx/5xx), Success Rate %, Error Rate %, Apdex Score, Total Requests, Up Instances, Restarts
  2. **🚀 Traffic & Requests** (4 panels) - Status code distribution (pie chart), Total requests by endpoint (pie chart), Request rate by endpoint (time series), RPS by endpoint
  3. **⚠️ Errors & Performance** (5 panels) - Request rate by HTTP method + endpoint, Error rate by HTTP method + endpoint, Response time per endpoint (P95, P50, P99)
  4. **🔧 Go Runtime & Memory** (6 panels) - Heap allocated memory, Heap in-use memory, Process memory (RSS), Goroutines & threads, GC duration, GC frequency (memory leak detection)
  5. **🖥️ Resources & Infrastructure** (5 panels) - Total memory per service, Total CPU per service, Total network traffic per service, Total requests in flight per service, Total memory allocations per service
- **Variables**:
  - `$app` - Multi-select service filter (auth, user, product, cart, order, review, notification, shipping) with "All" option
  - `$namespace` - Multi-select namespace filter (with regex to exclude kube-* and default namespaces)
  - `$rate` - Rate interval selector (1m, 2m, 3m, 5m, 10m, 30m, 1h, 2h, 4h, 8h, 16h, 1d, 2d, 3d, 5d, 7d) - default: 5m
  - `$DS_PROMETHEUS` - Prometheus datasource selector
- **Access**: http://localhost:3000/d/microservices-monitoring-001/ (after port-forward: `kubectl port-forward -n monitoring svc/grafana-service 3000:3000`)

### Script Files by Category

**Deployment Order:** Infrastructure → Monitoring → APM → Apps → Load Testing → SLO → Access

| Category | Scripts | Purpose | Order |
|----------|---------|---------|-------|
| Infrastructure | 01-02 | Cluster setup, metrics installation | 1-2 |
| Monitoring Stack | 03 | Deploy Prometheus & Grafana (BEFORE apps) | 3 |
| APM Stack | 04, 04a-c | Deploy Tempo, Pyroscope, Loki, Vector (BEFORE apps) | 4 |
| Build & Deploy Apps | 05-06 | Build images (including k6), deploy services | 5-6 |
| Load Testing | 07 | Deploy k6 load generators via Helm (AFTER apps) | 7 |
| SLO System | 08 | Deploy Sloth Operator and SLO CRDs (Required) | 8 |
| Access Setup | 09 | Setup port-forwarding | 9 |
| Utilities | 10-12 | Dashboard reload, runbooks | - |

### SLO Files

| File Type | Location | Count |
|-----------|----------|-------|
| SLO CRDs | `k8s/sloth/crds/*.yaml` | 9 PrometheusServiceLevel CRDs (active) |

**Note**: SLO definitions are managed by Sloth Operator via PrometheusServiceLevel CRDs in `k8s/sloth/crds/*.yaml`.

### Documentation Files

| Document | Location | Purpose |
|----------|----------|---------|
| Metrics Guide | `docs/monitoring/METRICS.md` | Complete metrics documentation |
| APM Guide | `docs/apm/README.md` | APM system overview |
| Tracing Guide | `docs/apm/TRACING.md` | Distributed tracing guide |
| Logging Guide | `docs/apm/LOGGING.md` | Structured logging guide |
| Profiling Guide | `docs/apm/PROFILING.md` | Continuous profiling guide |
| SLO Guide | `docs/slo/README.md` | SLO system overview |
| Setup Guide | `docs/getting-started/SETUP.md` | Deployment instructions |
| API Reference | `docs/api/API_REFERENCE.md` | API endpoints |
| k6 Load Testing | `docs/load-testing/K6_LOAD_TESTING.md` | Load testing guide |
| Docs Index | `docs/README.md` | Complete documentation index |

---

## Common Workflows

### Adding a New Microservice

1. **Create service structure:**
   ```bash
   mkdir -p services/cmd/myapp
   mkdir -p services/internal/myapp/web/{v1,v2}
   mkdir -p services/internal/myapp/logic/{v1,v2}
   mkdir -p services/internal/myapp/core/domain
   ```

2. **Add service code:**
   - `services/cmd/myapp/main.go` - Entry point
   - `services/internal/myapp/web/v1/handler.go` - v1 HTTP handlers
   - `services/internal/myapp/web/v2/handler.go` - v2 HTTP handlers
   - `services/internal/myapp/logic/v1/service.go` - v1 business logic
   - `services/internal/myapp/logic/v2/service.go` - v2 business logic
   - `services/internal/myapp/core/domain/model.go` - Domain models

3. **Create Helm values file:**
   ```bash
   cp charts/values/auth.yaml charts/values/myapp.yaml
   # Edit myapp.yaml with service-specific values
   ```

4. **Update build script:**
   - Add service to `scripts/05-build-microservices.sh`
   - Add deployment to `scripts/06-deploy-microservices.sh`

5. **Add SLO definition:**
   - Create PrometheusServiceLevel CRD: `k8s/sloth/crds/myapp-slo.yaml`
   - Apply: `kubectl apply -f k8s/sloth/crds/myapp-slo.yaml`

6. **Build and deploy:**
   ```bash
   ./scripts/05-build-microservices.sh
   ./scripts/06-deploy-microservices.sh
   ```

### Updating Grafana Dashboard

1. **Edit dashboard JSON:**
   - Update `k8s/grafana-operator/dashboards/microservices-dashboard.json` (32 panels / 5 row groups).
   - Keep UID `microservices-monitoring-001`.

2. **Reload dashboards via Grafana Operator:**
   ```bash
   ./scripts/10-reload-dashboard.sh
   ```
   The script reapplies `k8s/grafana-operator/dashboards/` (ConfigMap + `GrafanaDashboard` CR). The Grafana Operator automatically reconciles the new JSON.

3. **Verify:**
   - Port-forward Grafana: `kubectl port-forward -n monitoring svc/grafana-service 3000:3000`
   - Open http://localhost:3000/d/microservices-monitoring-001/

**Dashboard Variables Usage:**
- `$app`: filter by service
- `$namespace`: filter by Kubernetes namespace
- `$rate`: Prometheus rate interval selector (default 5m)
- All panels respect these filters automatically.

### Modifying Prometheus Configuration

**Note**: Since v0.5.0, Prometheus is managed by Prometheus Operator. Configuration is via Helm values and ServiceMonitor CRDs.

1. **Edit Prometheus Operator values:**
   - Edit `k8s/prometheus/values.yaml` (retention, resources, etc.)
   
2. **Update via Helm:**
   ```bash
   helm upgrade prometheus-kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n monitoring \
     -f k8s/prometheus/values.yaml
   ```

3. **Add/modify service discovery:**
   - Edit `k8s/prometheus/servicemonitor-microservices.yaml`
   - Apply: `kubectl apply -f k8s/prometheus/servicemonitor-microservices.yaml`

4. **Verify:**
   - Port-forward Prometheus: `kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090`
   - Check config: http://localhost:9090/config
   - Check targets: http://localhost:9090/targets
   - Check ServiceMonitors: `kubectl get servicemonitors -A`

### Deploying SLO Changes

1. **Edit SLO CRDs:**
   - Edit PrometheusServiceLevel CRDs in `k8s/sloth/crds/*.yaml`

2. **Apply changes:**
   ```bash
   kubectl apply -f k8s/sloth/crds/
   ```

3. **Verify:**
   - Check PrometheusServiceLevels: `kubectl get prometheusservicelevels -n monitoring`
   - Check generated rules: `kubectl get prometheusrules -n monitoring`
   - Check Prometheus rules: http://localhost:9090/api/v1/rules
   - View SLO dashboards in Grafana (folder: SLO)

### Running Load Tests

1. **Deploy k6:**
   ```bash
   ./scripts/07-deploy-k6.sh
   # Or deploy specific variant:
   # ./scripts/07-deploy-k6.sh legacy
   # ./scripts/07-deploy-k6.sh scenarios
   ```

2. **Check load generator pods:**
   ```bash
   kubectl get pods -n k6
   kubectl logs -n k6 -l app=k6-legacy -f
   kubectl logs -n k6 -l app=k6-scenarios -f
   ```

3. **Monitor metrics:**
   - View Grafana dashboard for traffic patterns
   - Check Prometheus for metrics: `request_duration_seconds_count`

### Troubleshooting Common Issues

**Dashboard not updating:**
- Re-apply dashboards: `kubectl apply -k k8s/grafana-operator/dashboards/`
- Check GrafanaDashboard status: `kubectl get grafanadashboards -n monitoring`
- Inspect Grafana Operator logs: `kubectl logs -n monitoring deployment/grafana-operator`

**Prometheus not scraping:**
- Check ServiceMonitor: `kubectl get servicemonitor -n monitoring` (single ServiceMonitor for all services)
- Check namespace labels: `kubectl get ns --show-labels | grep monitoring=enabled`
- Check Prometheus targets: http://localhost:9090/targets
- Check Prometheus Operator logs: `kubectl logs -n monitoring -l app.kubernetes.io/name=kube-prometheus-stack-operator`
- Verify pod labels exist: `kubectl get pods -n <namespace> --show-labels`

**SLO rules not loading:**
- Check PrometheusServiceLevels: `kubectl get prometheusservicelevels -n monitoring`
- Check generated PrometheusRules: `kubectl get prometheusrules -n monitoring`
- Check Sloth Operator logs: `kubectl logs -n monitoring -l app=sloth -c sloth --tail=50`
- Check Prometheus rules API: http://localhost:9090/api/v1/rules

**Sloth PrometheusRule Validation Failure (`GEN OK = false`):**
- **Symptom**: PrometheusServiceLevels show `GEN OK = false`, `READY SLOS = 0`, Sloth logs show "admission webhook denied the request: Rules are not valid"
- **Root Cause**: Prometheus Operator ValidatingWebhookConfiguration rejects Sloth-generated PrometheusRules
- **Investigation Steps**:
  1. Check if webhook exists: `kubectl get validatingwebhookconfigurations | grep prometheus`
  2. Test manual PrometheusRule creation to isolate issue
  3. Check Sloth debug logs: Enable `sloth.debug.enabled: true` in `k8s/sloth/values.yaml`
- **Solution**: Remove problematic webhook validation:
  ```bash
  kubectl get validatingwebhookconfigurations kube-prometheus-stack-admission -o yaml > /tmp/webhook-backup.yaml
  kubectl delete validatingwebhookconfigurations kube-prometheus-stack-admission
  kubectl delete pod -n monitoring -l app=sloth  # Restart Sloth to clear cache
  ```
- **Verify**: `kubectl get prometheusservicelevels -n monitoring` should show `GEN OK = true` for all SLOs
- **Impact**: Without this fix, no SLO rules are generated, error budget tracking and burn rate alerts won't work
- **Note**: This is a known compatibility issue between Sloth Operator and Prometheus Operator webhook validation

**Sloth commonPlugins DNS Issues (Kind cluster):**
- **Symptom**: Git-sync container CrashLoopBackOff with "Could not resolve host: github.com"
- **Cause**: Kind cluster lacks external DNS resolution for fetching sloth-common-sli-plugins
- **Fix**: Disable `commonPlugins` in `k8s/sloth/values.yaml`: `commonPlugins.enabled: false`
- **Impact**: Custom SLO definitions work fine without common plugins (we use explicit Prometheus queries)

**Metrics not appearing:**
- Verify app has `/metrics` endpoint
- Check Prometheus scrape config includes the service
- Verify labels match (app, namespace, job)

---

## Command Reference

### Deployment Commands

**Deployment Order:** Infrastructure → Monitoring → APM → Apps → Load Testing → SLO → Access

| Script | Command | Purpose | Order |
|--------|---------|---------|-------|
| Create cluster | `./scripts/01-create-kind-cluster.sh` | Create Kind Kubernetes cluster | 1 |
| Install metrics | `./scripts/02-install-metrics.sh` | Install kube-state-metrics | 2 |
| Deploy monitoring | `./scripts/03-deploy-monitoring.sh` | Deploy Prometheus & Grafana (BEFORE apps) | 3 |
| Deploy APM | `./scripts/04-deploy-apm.sh` | Deploy all APM components (BEFORE apps - Tempo, Pyroscope, Loki, Vector) | 4 |
| Build images | `./scripts/05-build-microservices.sh` | Build all 9 service Docker images | 5 |
| Deploy services (local) | `./scripts/06-deploy-microservices.sh --local` | Deploy using local Helm chart | 6 |
| Deploy services (registry) | `./scripts/06-deploy-microservices.sh --registry` | Deploy from OCI registry | 6 |
| Deploy k6 | `./scripts/07-deploy-k6.sh` | Deploy k6 load generators via Helm (AFTER apps) | 7 |
| Deploy SLO | `./scripts/08-deploy-slo.sh` | Deploy Sloth Operator and SLO CRDs | 8 |
| Setup access | `./scripts/09-setup-access.sh` | Setup port-forwarding | 9 |

### Helm Commands

| Command | Purpose |
|---------|---------|
| `helm list -A` | List all Helm releases |
| `helm upgrade --install <name> charts/ -f charts/values/<service>.yaml -n <ns>` | Install/upgrade service |
| `helm uninstall <name> -n <namespace>` | Uninstall a service |
| `helm pull oci://ghcr.io/duynhne/charts/microservice` | Pull chart from OCI registry |

### Monitoring Commands

| Script | Command | Purpose |
|--------|---------|---------|
| Reload dashboard | `./scripts/10-reload-dashboard.sh` | Reload Grafana dashboard ConfigMap |

### SLO Commands

| Script | Command | Purpose |
|--------|---------|---------|
| Deploy SLOs | `./scripts/08-deploy-slo.sh` | Full SLO deployment via Sloth Operator (Helm) |

**Note**: Validation and rule generation are now handled automatically by Sloth Operator. No more manual bash scripts.

### Runbook Commands

| Script | Command | Purpose |
|--------|---------|---------|
| Diagnose latency | `./scripts/11-diagnose-latency.sh` | Analyze latency issues |
| Error budget alert | `./scripts/12-error-budget-alert.sh` | Respond to error budget alerts |

### kubectl Shortcuts

| Command | Purpose |
|---------|---------|
| `kubectl get pods -n {namespace}` | List pods in namespace (e.g., auth, user, monitoring) |
| `kubectl logs -l app={service-name} -n {namespace}` | View service logs |
| `kubectl port-forward -n monitoring svc/grafana-service 3000:3000` | Port-forward Grafana |
| `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | Port-forward Prometheus |
| `kubectl rollout restart deployment/{name} -n {namespace}` | Restart deployment |

### Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| API (via port-forward) | http://localhost:8080 | - |

---

## Conventions and Standards

### Namespace Conventions

- **`monitoring`** - Monitoring components (Prometheus, Grafana, Tempo, Pyroscope, Loki) and SLO system
- **`kube-system`** - Vector (log collection DaemonSet)
- **`k6`** - K6 load testing
- **Service namespaces** - Each microservice has its own namespace:
  - `auth` - auth service
  - `user` - user service
  - `product` - product service
  - `cart` - cart service
  - `order` - order service
  - `review` - review service
  - `notification` - notification service
  - `shipping` - shipping and shipping-v2 services

### Script Naming

- **Numbered prefixes (01-12)** - Execution order and categorization
- **Format**: `{number}-{purpose}.sh`
- **Categories**:
  - 01-02: Infrastructure
  - 03: Monitoring Stack
  - 04, 04a-c: APM Stack
  - 05-06: Build & Deploy Apps
  - 07: Load Testing (K6)
  - 08: SLO Management (Sloth Operator)
  - 09: Access Setup
  - 10-12: Utilities

### File Organization Patterns

- **Services**: `services/cmd/{service}/main.go` + `services/internal/{service}/{v1,v2,domain}/`
- **Kubernetes**: `k8s/{component}/{deployment,service}.yaml`
- **Scripts**: `scripts/{number}-{purpose}.sh`
- **SLO**: `k8s/sloth/crds/*.yaml` (PrometheusServiceLevel CRDs managed by Sloth Operator)

### Metric Naming Conventions

- **Pattern**: `{domain}_{metric}_{unit}`
- **Examples**:
  - `request_duration_seconds` (histogram)
  - `requests_total` (counter)
  - `requests_in_flight` (gauge)

### Label Requirements

**Required labels for metrics (after Prometheus scrape):**
- `job` - Scrape job name - **Added by ServiceMonitor relabeling** (set to `"microservices"` for all services)
- `app` - Service name (e.g., `auth`, `user`) - **Added by ServiceMonitor relabeling** (from service label)
- `service` - Original service name - **Added by ServiceMonitor relabeling** (from Kubernetes service metadata)
- `namespace` - Kubernetes namespace - **Added by ServiceMonitor relabeling** (from pod metadata)
- `instance` - Pod IP:port - **Added by Prometheus** (automatic)

**Application-level labels (emitted by app):**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (e.g., `/api/v1/users`)
- `code` - HTTP status code (200, 404, 500)

**Important Notes:**
- Since v0.5.0, applications DO NOT emit `app`, `namespace`, or `job` labels
- All service identification labels are injected by Prometheus during scrape via ServiceMonitor `relabelings`
- `job="microservices"` is set via relabeling (not Kubernetes label) to enable dashboard filtering
- Alternative: Let `job` default to service name (see `docs/monitoring/METRICS_LABEL_SOLUTIONS.md` for Option B)

### Go Code Conventions

- **Middleware**: `services/pkg/middleware/prometheus.go` - Centralized metrics collection
- **Handlers**: Separate `v1/` and `v2/` directories for API versioning
- **Domain models**: `domain/` directory for data structures
- **Memory leak prevention**: Always use `defer cancel()`, close channels, set timeouts

### Dashboard Conventions

- **UID**: `microservices-monitoring-001`
- **Variables**: `$app`, `$namespace`, `$rate`
- **Panel descriptions**: Concise and actionable
- **Query filters**: Always include `job=~"microservices"` and `namespace=~"$namespace"`

---

## Quick Navigation

### Find Files by Purpose

**Add a new service:**
- Service code: `services/cmd/{service}/`, `services/internal/{service}/`
- Helm values: `charts/values/{service}.yaml`
- SLO CRD: `k8s/sloth/crds/{service}-slo.yaml`

**Update monitoring:**
- Dashboard JSON: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
- Prometheus Operator values: `k8s/prometheus/values.yaml`
- ServiceMonitor: `k8s/prometheus/servicemonitor-microservices.yaml`
- Grafana Operator resources: `k8s/grafana-operator/` (Grafana CR, datasources, dashboards)

**Modify SLOs:**
- Edit CRDs: `k8s/sloth/crds/*.yaml` (PrometheusServiceLevel CRDs)
- Apply: `kubectl apply -f k8s/sloth/crds/`

**Load testing:**
- K6 scripts: `k6/load-test.js`, `k6/load-test-multiple-scenarios.js`
- K6 Dockerfile: `k6/Dockerfile`
- K6 Helm values: `charts/values/k6-legacy.yaml`, `charts/values/k6-scenarios.yaml`

### Find Scripts by Task

- **Setup cluster**: `01-create-kind-cluster.sh`, `02-install-metrics.sh`
- **Deploy monitoring**: `03-deploy-monitoring.sh` (BEFORE apps)
- **Deploy APM**: `04-deploy-apm.sh` (BEFORE apps - Tempo, Pyroscope, Loki, Vector)
- **Build & deploy apps**: `05-build-microservices.sh`, `06-deploy-microservices.sh`
- **Load testing**: `07-deploy-k6.sh` (AFTER apps)
- **SLO system**: `08-deploy-slo.sh` (Sloth Operator + CRDs)
- **Access setup**: `09-setup-access.sh`
- **Utilities**: `10-reload-dashboard.sh`, `11-diagnose-latency.sh`, `12-error-budget-alert.sh`

### Find Documentation by Topic

- **Metrics**: `docs/monitoring/METRICS.md`
- **SLO**: `docs/slo/README.md`, `docs/slo/GETTING_STARTED.md`
- **API**: `docs/api/API_REFERENCE.md`
- **Setup**: `docs/getting-started/SETUP.md`
- **k6**: `docs/load-testing/K6_LOAD_TESTING.md`
- **Docs Index**: `docs/README.md`

---

## Additional Resources

- **Project README**: `README.md` - Project overview and quick start
- **Claude Commands**: `.claude/commands/` - AI workflow commands (plan, implement, analyze, deploy, document)
- **Claude Skills**: `.claude/skill/` - Skill

---

**Last Updated**: December 8, 2025 - Tempo v2.9.0 with metrics-generator for TraceQL rate() queries (v0.6.8)
