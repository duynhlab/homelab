# AI Agent Guide

> **IMPORTANT**: AGENTS.md files are the source of truth for AI agent instructions. Always update the relevant AGENTS.md file when adding or modifying agent guidance.

## Overview

This guide provides comprehensive information for AI agents working with this codebase. Use it to navigate the project structure, understand conventions, and execute common workflows.

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
│   ├── grafana/
│   ├── k6/
│   ├── tempo/             # Grafana Tempo (distributed tracing)
│   ├── pyroscope/         # Pyroscope (continuous profiling)
│   ├── loki/              # Loki (log storage)
│   ├── vector/            # Vector (log collection)
│   ├── kind/              # Kind cluster configuration
│   └── namespaces.yaml
├── scripts/               # Deployment and utility scripts (numbered 01-17)
├── docs/                  # Documentation
├── slo/                   # SLO data files (definitions, generated rules)
├── grafana-dashboard.json # Main Grafana dashboard (32 panels)
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
- `pkg/middleware/prometheus.go` - Prometheus metrics middleware (auto-collects request metrics)
- `pkg/middleware/logging.go` - Structured logging middleware with trace-id correlation
- `pkg/middleware/tracing.go` - OpenTelemetry distributed tracing middleware
- `pkg/middleware/profiling.go` - Pyroscope continuous profiling middleware

#### `charts/` - Helm Chart

Generic Helm chart for deploying all microservices:

```
charts/
├── Chart.yaml             # Chart metadata (name: microservice, version: 0.1.0)
├── values.yaml            # Default values
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
    ├── deployment.yaml    # Deployment template
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
├── prometheus/           # Prometheus configuration
│   ├── configmap.yaml     # Prometheus config (scrape configs, rule_files)
│   ├── deployment.yaml    # Prometheus deployment
│   ├── service.yaml
│   └── rbac.yaml         # RBAC for Prometheus ServiceAccount
├── grafana/              # Grafana configuration
│   ├── configmap-dashboards.yaml
│   ├── configmap-datasources.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── k6/                   # Load testing (scripts and deployments)
│   ├── load-test.js
│   ├── load-test-multiple-scenarios.js
│   ├── deployment-legacy.yaml
│   └── deployment-multiple-scenarios.yaml
└── namespaces.yaml        # Namespace definitions
```

**Note**: Microservices are deployed via Helm chart (`charts/`), not raw YAML manifests.

**Namespaces**:
- `monitoring` - Monitoring components (Prometheus, Grafana, k6, Tempo, Pyroscope, Loki) and SLO system
- `kube-system` - Vector (log collection DaemonSet)
- Service namespaces - Each microservice has its own namespace: `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`

#### `scripts/` - Deployment Scripts

Numbered scripts (01-12) for deployment and operations:

**Deployment Order:**
1. Infrastructure (01-02) → 2. Monitoring (03) → 3. APM (04) → 4. Build & Deploy Apps (05-06) → 5. Load Testing (07) → 6. SLO (08) → 7. Access Setup (09)

**Infrastructure (01-02):**
- `01-create-kind-cluster.sh` - Create Kind Kubernetes cluster
- `02-install-metrics.sh` - Install metrics infrastructure (kube-state-metrics, etc.)

**Monitoring Stack (05):**
- `03-deploy-monitoring.sh` - Deploy Prometheus and Grafana (deploy BEFORE apps to collect metrics immediately)

**APM Stack (14-17) - Required:**
- `04a-deploy-tempo.sh` - Deploy Grafana Tempo (distributed tracing)
- `04b-deploy-pyroscope.sh` - Deploy Pyroscope (continuous profiling)
- `04c-deploy-loki.sh` - Deploy Loki + Vector (log aggregation)
- `04-deploy-apm.sh` - Deploy all APM components (deploy BEFORE apps to collect traces/logs/profiles immediately)

**Build & Deploy Applications (03-04):**
- `05-build-microservices.sh` - Build Docker images for all 9 services
- `06-deploy-microservices.sh` - Deploy all microservices using Helm (`--local` or `--registry`)

**Load Testing (06):**
- `07-deploy-k6-testing.sh` - Deploy k6 load generators (deploy AFTER apps to test them)

**SLO System (09-11) - Required:**
- `08a-validate-slo.sh` - Validate SLO definition files
- `08b-generate-slo-rules.sh` - Generate Prometheus rules using Sloth
- `08-deploy-slo.sh` - Deploy SLO system (validates, generates, deploys)

**Access Setup (07):**
- `09-setup-access.sh` - Setup port-forwarding for services

**Utilities:**
- `10-reload-dashboard.sh` - Reload Grafana dashboard ConfigMap
- `11-diagnose-latency.sh` - Diagnostic script for latency issues
- `12-error-budget-alert.sh` - Error budget alert response script
- `cleanup.sh` - Clean up Kind cluster and resources

**Utilities:**
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

**Structure:**
- `slo/definitions/` - 9 SLO definition YAML files (one per service, source of truth)
- `slo/generated/` - Generated Prometheus rules (gitignored, created by `./scripts/08b-generate-slo-rules.sh`)

**Note**: Generated files are not tracked in git. Run `./scripts/08b-generate-slo-rules.sh` to create them.

#### `k8s/k6/` - Load Testing

- `load-test.js` - Legacy single-scenario load test
- `load-test-multiple-scenarios.js` - Multiple user personas (Browser, Shopping, Registered, API Client, Admin)
- `deployment-legacy.yaml` - Kubernetes deployment for legacy test
- `deployment-multiple-scenarios.yaml` - Kubernetes deployment for multiple scenarios test

---

## Key Files and Locations

### Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| Helm Chart | Microservices deployment chart | `charts/` |
| Helm Values | Per-service configuration | `charts/values/*.yaml` |
| Prometheus Config | Scrape configs, rule files | `k8s/prometheus/configmap.yaml` |
| Grafana Datasources | Prometheus datasource | `k8s/grafana/configmap-datasources.yaml` |
| Grafana Dashboards | Dashboard provisioning | `k8s/grafana/configmap-dashboards.yaml` |
| Dockerfile | Unified build for all services | `services/Dockerfile` |
| Go Modules | Go dependencies | `services/go.mod` |

### Dashboard Files

| File | Purpose | Location |
|------|---------|----------|
| Main Dashboard | 32 panels in 5 row groups | `grafana-dashboard.json` |

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
- **Access**: http://localhost:3000/d/microservices-monitoring-001/ (after port-forward: `kubectl port-forward -n monitoring svc/grafana 3000:3000`)

### Script Files by Category

**Deployment Order:** Infrastructure (01-02) → Monitoring (05) → APM (14-17) → Apps (03-04) → Load Testing (06) → SLO (09-11) → Access (07)

| Category | Scripts | Purpose | Order |
|----------|---------|---------|-------|
| Infrastructure | 01-02 | Cluster setup, metrics installation | 1-2 |
| Monitoring Stack | 05 | Deploy Prometheus & Grafana (BEFORE apps) | 3 |
| APM Stack | 14-17 | Deploy Tempo, Pyroscope, Loki, Vector (BEFORE apps) | 4 |
| Build & Deploy Apps | 03-04 | Build images, deploy services | 5-6 |
| Load Testing | 06 | Deploy k6 load generators (AFTER apps) | 7 |
| SLO System | 09-11 | Validate, generate rules, deploy SLOs (Required) | 8 |
| Access Setup | 07 | Setup port-forwarding | 9 |
| Utilities | 08, 12-13 | Dashboard reload, runbooks | - |

### SLO Files

| File Type | Location | Count |
|-----------|----------|-------|
| SLO Definitions | `slo/definitions/*.yaml` | 9 files (one per service) |
| Generated Rules | `slo/generated/*.yaml` | gitignored (run `./scripts/08b-generate-slo-rules.sh`) |

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
   - Create `slo/definitions/myapp.yaml`
   - Run `./scripts/08a-validate-slo.sh`
   - Run `./scripts/08b-generate-slo-rules.sh`
   - Run `./scripts/08-deploy-slo.sh`

6. **Build and deploy:**
   ```bash
   ./scripts/05-build-microservices.sh
   ./scripts/06-deploy-microservices.sh
   ```

### Updating Grafana Dashboard

1. **Edit dashboard:**
   - Edit `grafana-dashboard.json`
   - Validate JSON syntax
   - Dashboard structure: 32 panels in 5 row groups (see Dashboard Files section above)

2. **Reload dashboard:**
   ```bash
   ./scripts/10-reload-dashboard.sh
   ```
   This script updates the ConfigMap and restarts Grafana to load the new dashboard.

3. **Verify:**
   - Port-forward Grafana: `kubectl port-forward -n monitoring svc/grafana 3000:3000`
   - Open http://localhost:3000
   - Navigate to dashboard UID: `microservices-monitoring-001`
   - Or use direct link: http://localhost:3000/d/microservices-monitoring-001/

**Dashboard Variables Usage:**
- Use `$app` to filter by service (e.g., select "auth" to see only auth service metrics)
- Use `$namespace` to filter by Kubernetes namespace (e.g., select "auth" namespace to see only auth namespace pods)
- Use `$rate` to adjust rate calculation interval (default: 5m, use longer intervals like 1h or 1d for smoother graphs over longer time periods)
- All panels automatically respect these variable filters
- Variables are located at the top of the dashboard for easy access

### Modifying Prometheus Configuration

1. **Edit config:**
   - Edit `k8s/prometheus/configmap.yaml`
   - Add/modify scrape configs or rule files

2. **Apply changes:**
   ```bash
   kubectl apply -f k8s/prometheus/configmap.yaml
   kubectl rollout restart deployment/prometheus -n monitoring
   ```

3. **Verify:**
   - Port-forward Prometheus: `kubectl port-forward -n monitoring svc/prometheus 9090:9090`
   - Check config: http://localhost:9090/config
   - Check targets: http://localhost:9090/targets

### Deploying SLO Changes

1. **Edit SLO definitions:**
   - Edit files in `slo/definitions/*.yaml`

2. **Validate:**
   ```bash
   ./scripts/08a-validate-slo.sh
   ```

3. **Generate rules:**
   ```bash
   ./scripts/08b-generate-slo-rules.sh
   ```

4. **Deploy:**
   ```bash
   ./scripts/08-deploy-slo.sh
   ```

5. **Verify:**
   - Check Prometheus rules: http://localhost:9090/api/v1/rules
   - Check Grafana dashboards (import manually: IDs 14348, 14643)

### Running Load Tests

1. **Deploy k6:**
   ```bash
   ./scripts/07-deploy-k6-testing.sh
   ```

2. **Check load generator pods:**
   ```bash
   kubectl get pods -n monitoring -l app=k6-load-generator
   kubectl logs -n monitoring -l app=k6-load-generator
   ```

3. **Monitor metrics:**
   - View Grafana dashboard for traffic patterns
   - Check Prometheus for metrics: `request_duration_seconds_count`

### Troubleshooting Common Issues

**Dashboard not updating:**
- Restart Grafana: `kubectl rollout restart deployment/grafana -n monitoring`
- Check ConfigMap: `kubectl get configmap grafana-dashboard-json -n monitoring`

**Prometheus not scraping:**
- Check ServiceMonitor: `kubectl get servicemonitor -n {namespace}` (check in each service namespace)
- Check Prometheus targets: http://localhost:9090/targets
- Check pod labels match ServiceMonitor selector

**SLO rules not loading:**
- Check ConfigMaps: `kubectl get configmap -n monitoring prometheus-slo-rules-*`
- Check Prometheus config: http://localhost:9090/config (look for `rule_files`)
- Check Prometheus logs: `kubectl logs deployment/prometheus -n monitoring`

**Metrics not appearing:**
- Verify app has `/metrics` endpoint
- Check Prometheus scrape config includes the service
- Verify labels match (app, namespace, job)

---

## Command Reference

### Deployment Commands

**Deployment Order:** Infrastructure → Monitoring → Apps → Load Testing → APM → SLO → Access

| Script | Command | Purpose | Order |
|--------|---------|---------|-------|
| Create cluster | `./scripts/01-create-kind-cluster.sh` | Create Kind Kubernetes cluster | 1 |
| Install metrics | `./scripts/02-install-metrics.sh` | Install kube-state-metrics | 2 |
| Deploy monitoring | `./scripts/03-deploy-monitoring.sh` | Deploy Prometheus & Grafana (BEFORE apps) | 3 |
| Deploy APM | `./scripts/04-deploy-apm.sh` | Deploy all APM components (BEFORE apps - Tempo, Pyroscope, Loki, Vector) | 4 |
| Build images | `./scripts/05-build-microservices.sh` | Build all 9 service Docker images | 5 |
| Deploy services (local) | `./scripts/06-deploy-microservices.sh --local` | Deploy using local Helm chart | 6 |
| Deploy services (registry) | `./scripts/06-deploy-microservices.sh --registry` | Deploy from OCI registry | 6 |
| Deploy k6 | `./scripts/07-deploy-k6-testing.sh` | Deploy k6 load generators (AFTER apps) | 7 |
| Deploy SLO | `./scripts/08-deploy-slo.sh` | Deploy SLO system (validates, generates, deploys) | 8 |
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
| Validate SLOs | `./scripts/08a-validate-slo.sh` | Validate SLO definition files |
| Generate rules | `./scripts/08b-generate-slo-rules.sh` | Generate Prometheus rules using Sloth |
| Deploy SLOs | `./scripts/08-deploy-slo.sh` | Full SLO deployment (validate + generate + deploy) |

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
| `kubectl port-forward -n monitoring svc/grafana 3000:3000` | Port-forward Grafana |
| `kubectl port-forward -n monitoring svc/prometheus 9090:9090` | Port-forward Prometheus |
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

- **`monitoring`** - Monitoring components (Prometheus, Grafana, k6, Tempo, Pyroscope, Loki) and SLO system
- **`kube-system`** - Vector (log collection DaemonSet)
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
  - 07: Load Testing
  - 08, 08a-b: SLO Management
  - 09: Access Setup
  - 10-12: Utilities

### File Organization Patterns

- **Services**: `services/cmd/{service}/main.go` + `services/internal/{service}/{v1,v2,domain}/`
- **Kubernetes**: `k8s/{component}/{deployment,service}.yaml`
- **Scripts**: `scripts/{number}-{purpose}.sh`
- **SLO**: `slo/definitions/*.yaml` → (generate) → `slo/generated/*.yaml` → (deploy as ConfigMaps)

### Metric Naming Conventions

- **Pattern**: `{domain}_{metric}_{unit}`
- **Examples**:
  - `request_duration_seconds` (histogram)
  - `requests_total` (counter)
  - `requests_in_flight` (gauge)

### Label Requirements

**Required labels for all metrics:**
- `app` - Service name (e.g., `auth`, `user`)
- `namespace` - Kubernetes namespace
- `job=~"microservices"` - Prometheus job filter

**HTTP metrics additional labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (e.g., `/api/v1/users`)
- `code` - HTTP status code (200, 404, 500)

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
- SLO definition: `slo/definitions/{service}.yaml`

**Update monitoring:**
- Dashboard: `grafana-dashboard.json` (32 panels, 5 row groups, UID: microservices-monitoring-001)
- Prometheus config: `k8s/prometheus/configmap.yaml`
- Grafana config: `k8s/grafana/configmap-*.yaml`

**Modify SLOs:**
- Definitions: `slo/definitions/*.yaml`
- Generated rules: `slo/generated/*.yaml` (gitignored, run `./scripts/08b-generate-slo-rules.sh`)

**Load testing:**
- k6 scripts and deployments: `k8s/k6/load-test*.js` and `k8s/k6/deployment-*.yaml`

### Find Scripts by Task

- **Setup cluster**: `01-create-kind-cluster.sh`, `02-install-metrics.sh`
- **Deploy monitoring**: `03-deploy-monitoring.sh` (BEFORE apps)
- **Deploy APM**: `04-deploy-apm.sh` (BEFORE apps - Tempo, Pyroscope, Loki, Vector)
- **Build & deploy apps**: `05-build-microservices.sh`, `06-deploy-microservices.sh`
- **Load testing**: `07-deploy-k6-testing.sh` (AFTER apps)
- **SLO system**: `08-deploy-slo.sh` (Required - validates, generates, deploys)
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

**Last Updated**: Reflects current project structure with Helm chart deployment (December 2024)
