# AI Agent Guide

> **IMPORTANT**: AGENTS.md files are the source of truth for AI agent instructions. Always update the relevant AGENTS.md file when adding or modifying agent guidance. do not add to CLAUDE.md or cursor rules

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
project-monitoring-golang/
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
│   ├── kind/              # Kind cluster configuration
│   └── namespaces.yaml
├── scripts/               # Deployment and utility scripts (numbered 01-13)
├── docs/                  # Documentation
├── slo/                   # SLO data files (definitions, generated rules)
├── k6/                    # k6 load test scripts
├── grafana-dashboard.json # Main Grafana dashboard (32 panels)
├── README.md              # Project overview
├── CHANGELOG.md           # Version changelog
└── AGENTS.md              # This file (source of truth for AI agent instructions)
```

### Directory Details

#### `services/` - Go Application Code

All Go source code is organized under the `services/` directory:

```
services/
├── cmd/                   # Microservice entry points (9 services)
│   ├── auth-service/
│   ├── user-service/
│   ├── product-service/
│   ├── cart-service/
│   ├── order-service/
│   ├── review-service/
│   ├── notification-service/
│   ├── shipping-service/
│   └── shipping-service-v2/
├── internal/              # Domain logic (private packages)
│   ├── auth/
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

**Pattern**: Each service has versioned API endpoints (`/api/v1/*`, `/api/v2/*`) handled in `internal/{service}/v1/` and `internal/{service}/v2/` handlers.

**Shared Code**: `pkg/middleware/prometheus.go` - Prometheus metrics middleware (auto-collects request metrics)

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
./scripts/04-deploy-microservices.sh --local

# From OCI registry
./scripts/04-deploy-microservices.sh --registry

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
├── k6/                   # Load testing deployments
│   ├── deployment-legacy.yaml
│   └── deployment-multiple-scenarios.yaml
└── namespaces.yaml        # Namespace definitions
```

**Note**: Microservices are deployed via Helm chart (`charts/`), not raw YAML manifests.

**Namespaces**:
- `monitoring-demo` - All microservices and monitoring components
- `monitoring` - SLO system (Prometheus rules)

#### `scripts/` - Deployment Scripts

Numbered scripts (01-13) for deployment and operations:

**Infrastructure (01-02):**
- `01-create-kind-cluster.sh` - Create Kind Kubernetes cluster
- `02-install-metrics.sh` - Install metrics infrastructure (kube-state-metrics, etc.)

**Build & Deploy (03-07):**
- `03-build-microservices.sh` - Build Docker images for all 9 services
- `04-deploy-microservices.sh` - Deploy all microservices using Helm (`--local` or `--registry`)
- `05-deploy-monitoring.sh` - Deploy Prometheus and Grafana
- `06-deploy-k6-testing.sh` - Deploy k6 load generators
- `07-setup-access.sh` - Setup port-forwarding for services

**Monitoring (08):**
- `08-reload-dashboard.sh` - Reload Grafana dashboard ConfigMap

**SLO Management (09-11):**
- `09-validate-slo.sh` - Validate SLO definition files
- `10-generate-slo-rules.sh` - Generate Prometheus rules using Sloth
- `11-deploy-slo.sh` - Deploy SLO system (validates, generates, deploys)

**Runbooks (12-13):**
- `12-diagnose-latency.sh` - Diagnostic script for latency issues
- `13-error-budget-alert.sh` - Error budget alert response script

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
- `slo/generated/` - Generated Prometheus rules (gitignored, created by `./scripts/10-generate-slo-rules.sh`)

**Note**: Generated files are not tracked in git. Run `./scripts/10-generate-slo-rules.sh` to create them.

#### `k6/` - Load Testing

- `load-test.js` - Legacy single-scenario load test
- `load-test-multiple-scenarios.js` - Multiple user personas (Browser, Shopping, Registered, API Client, Admin)

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

### Script Files by Category

| Category | Scripts | Purpose |
|----------|---------|---------|
| Infrastructure | 01-02 | Cluster setup, metrics installation |
| Build & Deploy | 03-07 | Build images, deploy services, monitoring, k6, access |
| Monitoring | 08 | Dashboard reload |
| SLO Management | 09-11 | Validate, generate rules, deploy SLOs |
| Runbooks | 12-13 | Diagnostic and alert response scripts |

### SLO Files

| File Type | Location | Count |
|-----------|----------|-------|
| SLO Definitions | `slo/definitions/*.yaml` | 9 files (one per service) |
| Generated Rules | `slo/generated/*.yaml` | gitignored (run `./scripts/10-generate-slo-rules.sh`) |

### Documentation Files

| Document | Location | Purpose |
|----------|----------|---------|
| Metrics Guide | `docs/monitoring/METRICS.md` | Complete metrics documentation |
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
   mkdir -p cmd/new-service
   mkdir -p internal/new-service/{v1,v2,domain}
   ```

2. **Add service code:**
   - `cmd/new-service/main.go` - Entry point
   - `internal/new-service/v1/handler.go` - v1 handlers
   - `internal/new-service/v2/handler.go` - v2 handlers
   - `internal/new-service/domain/model.go` - Domain models

3. **Create Kubernetes manifests:**
   ```bash
   mkdir -p k8s/new-service
   # Create deployment.yaml and service.yaml
   ```

4. **Update build script:**
   - Add service to `scripts/03-build-microservices.sh`
   - Add deployment to `scripts/04-deploy-microservices.sh`

5. **Add SLO definition:**
   - Create `slo/definitions/new-service.yaml`
   - Run `./scripts/09-validate-slo.sh`
   - Run `./scripts/10-generate-slo-rules.sh`
   - Run `./scripts/11-deploy-slo.sh`

6. **Build and deploy:**
   ```bash
   ./scripts/03-build-microservices.sh
   ./scripts/04-deploy-microservices.sh
   ```

### Updating Grafana Dashboard

1. **Edit dashboard:**
   - Edit `grafana-dashboard.json`
   - Validate JSON syntax

2. **Reload dashboard:**
   ```bash
   ./scripts/08-reload-dashboard.sh
   ```

3. **Verify:**
   - Port-forward Grafana: `kubectl port-forward -n monitoring svc/grafana 3000:3000`
   - Open http://localhost:3000
   - Check dashboard UID: `microservices-monitoring-001`

### Modifying Prometheus Configuration

1. **Edit config:**
   - Edit `k8s/prometheus/configmap.yaml`
   - Add/modify scrape configs or rule files

2. **Apply changes:**
   ```bash
   kubectl apply -f k8s/prometheus/configmap.yaml
   kubectl rollout restart deployment/prometheus -n monitoring-demo
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
   ./scripts/09-validate-slo.sh
   ```

3. **Generate rules:**
   ```bash
   ./scripts/10-generate-slo-rules.sh
   ```

4. **Deploy:**
   ```bash
   ./scripts/11-deploy-slo.sh
   ```

5. **Verify:**
   - Check Prometheus rules: http://localhost:9090/api/v1/rules
   - Check Grafana dashboards (import manually: IDs 14348, 14643)

### Running Load Tests

1. **Deploy k6:**
   ```bash
   ./scripts/06-deploy-k6-testing.sh
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

| Script | Command | Purpose |
|--------|---------|---------|
| Create cluster | `./scripts/01-create-kind-cluster.sh` | Create Kind Kubernetes cluster |
| Install metrics | `./scripts/02-install-metrics.sh` | Install kube-state-metrics |
| Build images | `./scripts/03-build-microservices.sh` | Build all 9 service Docker images |
| Deploy services (local) | `./scripts/04-deploy-microservices.sh --local` | Deploy using local Helm chart |
| Deploy services (registry) | `./scripts/04-deploy-microservices.sh --registry` | Deploy from OCI registry |
| Deploy monitoring | `./scripts/05-deploy-monitoring.sh` | Deploy Prometheus & Grafana |
| Deploy k6 | `./scripts/06-deploy-k6-testing.sh` | Deploy k6 load generators |
| Setup access | `./scripts/07-setup-access.sh` | Setup port-forwarding |

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
| Reload dashboard | `./scripts/08-reload-dashboard.sh` | Reload Grafana dashboard ConfigMap |

### SLO Commands

| Script | Command | Purpose |
|--------|---------|---------|
| Validate SLOs | `./scripts/09-validate-slo.sh` | Validate SLO definition files |
| Generate rules | `./scripts/10-generate-slo-rules.sh` | Generate Prometheus rules using Sloth |
| Deploy SLOs | `./scripts/11-deploy-slo.sh` | Full SLO deployment (validate + generate + deploy) |

### Runbook Commands

| Script | Command | Purpose |
|--------|---------|---------|
| Diagnose latency | `./scripts/12-diagnose-latency.sh` | Analyze latency issues |
| Error budget alert | `./scripts/13-error-budget-alert.sh` | Respond to error budget alerts |

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

- **`monitoring`** - Monitoring components (Prometheus, Grafana, k6) and SLO system
- **Service namespaces** - Each microservice has its own namespace:
  - `auth` - auth
  - `user` - user
  - `product` - product
  - `cart` - cart
  - `order` - order
  - `review` - review
  - `notification` - notification
  - `shipping` - shipping, shipping-v2

### Script Naming

- **Numbered prefixes (01-13)** - Execution order and categorization
- **Format**: `{number}-{purpose}.sh`
- **Categories**:
  - 01-02: Infrastructure
  - 03-07: Build & Deploy
  - 08: Monitoring
  - 09-11: SLO Management
  - 12-13: Runbooks

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
- Dashboard: `grafana-dashboard.json`
- Prometheus config: `k8s/prometheus/configmap.yaml`
- Grafana config: `k8s/grafana/configmap-*.yaml`

**Modify SLOs:**
- Definitions: `slo/definitions/*.yaml`
- Generated rules: `slo/generated/*.yaml` (gitignored, run `./scripts/10-generate-slo-rules.sh`)

**Load testing:**
- k6 scripts: `k6/load-test*.js`
- Deployments: `k8s/k6/deployment-*.yaml`

### Find Scripts by Task

- **Setup cluster**: `01-create-kind-cluster.sh`, `02-install-metrics.sh`
- **Build & deploy**: `03-build-microservices.sh`, `04-deploy-microservices.sh`, `05-deploy-monitoring.sh`
- **Load testing**: `06-deploy-k6-testing.sh`
- **Dashboard**: `08-reload-dashboard.sh`
- **SLO**: `09-validate-slo.sh`, `10-generate-slo-rules.sh`, `11-deploy-slo.sh`
- **Troubleshooting**: `12-diagnose-latency.sh`, `13-error-budget-alert.sh`

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
- **Cursor Rules**: `.cursor/rules/` - Development guidelines (Go, Kubernetes, Grafana, Prometheus, SLO)
- **Claude Commands**: `.claude/commands/` - AI workflow commands (plan, implement, analyze, deploy, document)

---

**Last Updated**: Reflects current project structure with Helm chart deployment (November 2024)
