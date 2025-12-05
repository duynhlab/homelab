# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

# What's next?

## [0.4.1] - 2025-12-05

### Documentation Review and Updates

**Context**: After significant architectural changes (K6 Helm deployment, Sloth Operator SLO management, APM deployment, Grafana Operator migration), all documentation needed comprehensive review and updates.

**Changes**:

1. **AGENTS.md** - Comprehensive review and updates
   - Corrected outdated "Last Updated" date from 2024 to "December 5, 2025"
   - Fixed script numbering references (changed "01-17" to "01-12")
   - Updated `slo/` directory description to reflect removal of `generated/` folder
   - Fixed section numbering inconsistencies (Monitoring Stack, APM Stack, Build & Deploy)
   - Corrected deployment order to "Infrastructure → Monitoring → APM → Apps → Load Testing → SLO → Access"
   - Updated directory structure (`k8s/` section) to show correct hierarchy
   - Fixed namespace conventions (added `k6` namespace)
   - Removed deprecated K6 and bash SLO script references (`08a`, `08b`)
   - Updated workflows for K6, SLO, and microservice management
   - Updated "Quick Navigation" sections

2. **docs/getting-started/SETUP.md** - Updated deployment workflows
   - Changed script reference from `07-deploy-k6-testing.sh` to `07-deploy-k6.sh`
   - Updated Step 4 description to mention "Grafana Operator datasources"
   - Updated Step 7 (K6) to reflect Helm deployment with namespace `k6`
   - Updated Step 8 (SLO) to describe Sloth Operator deployment via Helm
   - Updated verification commands to use `prometheusservicelevels` and `prometheusrules`
   - Updated load testing section to use `k6` namespace

3. **docs/load-testing/K6_LOAD_TESTING.md** - K6 architecture updates
   - Added "Architecture" section explaining Helm-based deployment
   - Updated file structure to reflect new locations (`k6/`, `charts/values/`)
   - Changed script reference to `07-deploy-k6.sh`
   - Updated namespace references from `monitoring` to `k6`
   - Added Helm release checking commands
   - Updated troubleshooting section with Helm-specific commands

4. **docs/slo/GETTING_STARTED.md** - Sloth Operator migration
   - Rewritten to focus on Sloth Kubernetes Operator (v0.15.0)
   - Added "Overview" and "Architecture" sections
   - Removed manual Sloth CLI installation instructions
   - Updated all workflows to use PrometheusServiceLevel CRDs
   - Updated verification commands to check operator, CRDs, and generated rules
   - Updated "Creating a New SLO" section with CRD YAML format
   - Updated metric query examples to use `sloth_service` label
   - Expanded troubleshooting section with operator-specific guidance

5. **docs/slo/*.md** - SLO conceptual documentation
   - Reviewed `SLI_DEFINITIONS.md` - No changes needed (implementation-agnostic)
   - Reviewed `SLO_TARGETS.md` - No changes needed (implementation-agnostic)
   - Reviewed `ALERTING.md` - No changes needed (implementation-agnostic)
   - Reviewed `ERROR_BUDGET_POLICY.md` - No changes needed (implementation-agnostic)

6. **docs/README.md** - Documentation index updates
   - Updated script reference to `07-deploy-k6.sh`
   - Simplified SLO deployment commands (removed `08a`, `08b` scripts)
   - Added "APM" section with 5 documentation files
   - Updated "Key Concepts" to mention Sloth Operator, APM Stack, and k6 Helm
   - Updated "Last Updated" to "December 2025"

7. **docs/apm/*.md** - APM documentation review
   - Reviewed all 5 APM documentation files
   - No changes needed - references to Grafana and datasources are implementation-agnostic

**Impact**: All documentation now accurately reflects the current architecture and deployment workflows. Users can follow documentation without encountering outdated script names, incorrect namespaces, or deprecated commands.

## [0.4.0] - 2025-12-04

### Changed
- **Dashboard File Consolidation**:
  - Removed duplicate `grafana-dashboard.json` from root directory
  - Dashboard source of truth is now `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - Updated `scripts/10-reload-dashboard.sh` to remove unnecessary copy step
  - Updated `AGENTS.md` documentation to reflect single dashboard file location
  - Simplifies dashboard management by maintaining only one file
- **Monitoring Deployment Script**:
  - Added Grafana Operator CRDs status check to `scripts/03-deploy-monitoring.sh`
  - Now displays `Grafana`, `GrafanaDatasource`, and `GrafanaDashboard` resources after deployment
  - Fixed pod wait labels: `app.kubernetes.io/name=grafana-operator` for operator, `app=grafana` for Grafana instance
  - Improved visibility of Grafana Operator managed resources
- **APM Deployment Script Refactoring**:
  - Updated `scripts/04-deploy-apm.sh` to use Grafana Operator datasources
  - Created GrafanaDatasource CRs for APM stack: `datasource-tempo.yaml`, `datasource-loki.yaml`, `datasource-pyroscope.yaml`
  - Removed dependency on legacy `k8s/grafana/` folder
  - APM datasources now managed declaratively via Grafana Operator CRs
  - Deleted empty `k8s/grafana/` folder
- **Namespace Management**:
  - Removed `monitoring` namespace from `k8s/namespaces.yaml`
  - `monitoring` namespace is now created by `scripts/03-deploy-monitoring.sh` only
  - Eliminates duplicate namespace creation and kubectl warnings
- **DevContainer Configuration**:
  - Added Go 1.23 feature to `.devcontainer/devcontainer.json`
  - Ensures consistent Go version across development environments
- **K6 Load Testing Refactoring**:
  - Refactored k6 to use Helm chart (reuse `charts/` like microservices)
  - Created unified `k6/Dockerfile` with ARG pattern (giống `services/Dockerfile`)
  - Build 2 k6 images: `ghcr.io/duynhne/k6:legacy` and `ghcr.io/duynhne/k6:scenarios`
  - Created Helm values: `charts/values/k6-legacy.yaml` and `charts/values/k6-scenarios.yaml`
  - Updated Helm templates: conditional service creation and probes (`.enabled | default true`)
  - New deployment script: `scripts/07-deploy-k6.sh` (replaces `07-deploy-k6-testing.sh`)
  - K6 now deploys to dedicated `k6` namespace (separated from `monitoring`)
  - Deleted old raw YAML deployments and ConfigMap-based approach
  - Created separate GitHub Actions workflow `.github/workflows/build-k6-images.yml` for k6 builds
  - Consistent deployment pattern across all services
- **SLO System Refactoring**:
  - Modernized SLO to use Sloth Operator v0.15.0 (Helm deployment)
  - Replaced bash scripts with PrometheusServiceLevel CRDs (9 services)
  - Operator automatically generates and deploys Prometheus rules
  - Sloth dashboards already deployed via Grafana Operator (IDs 14348, 14643)
  - Clean architecture: `k8s/sloth/{values.yaml, crds/, README.md}`
  - Deleted `scripts/08a-validate-slo.sh`, `scripts/08b-generate-slo-rules.sh`
  - New simple `scripts/08-deploy-slo.sh` wrapper script (Helm-based)
  - Removed manual rule_files from Prometheus ConfigMap
  - `slo/definitions/` kept as source of truth (backup reference)
  - No more `slo/generated/` folder - Sloth Operator handles rule generation
  - CRD-based, Kubernetes-native SLO management

### Fixed
- **Grafana Operator Deployment**:
  - Fixed `BadRequest` error in `k8s/grafana-operator/grafana.yaml`: Removed unsupported `spec.ingress.enabled` field
  - Fixed validation error: Changed boolean values to strings in `spec.config` section
    - `disable_login_form: true` → `disable_login_form: "true"`
    - `auth.anonymous.enabled: true` → `auth.anonymous.enabled: "true"`
  - The Grafana Operator `v1beta1` API requires all config values to be strings, not native YAML booleans
  - Fixed Kustomize security restriction for dashboard file:
    - Copied `grafana-dashboard.json` to `k8s/grafana-operator/dashboards/microservices-dashboard.json`
    - Updated `kustomization.yaml` to reference local file instead of parent directory
    - Kustomize security policy prevents accessing files outside current directory tree
  - Fixed `GrafanaDashboard` API validation errors in all dashboard CRs:
    - Removed unsupported `spec.datasources[0].datasourceUid` field from 3 dashboard files
    - `v1beta1` API only requires `datasourceName`, not `datasourceUid`
    - Affected files: `grafana-dashboard-main.yaml`, `grafana-dashboard-slo-overview.yaml`, `grafana-dashboard-slo-detailed.yaml`
  - For local development, port-forwarding is used: `kubectl port-forward -n monitoring svc/grafana-service 3000:3000`
- **Monitoring Deployment Script**:
  - Fixed typo in `scripts/03-deploy-monitoring.sh` line 2: `Aset -euo pipefail` → `set -euo pipefail`
  - This typo was causing the script to fail immediately with "command not found" error

## [0.4.0] - 2025-12-03

### Changed
- **Project Naming Cleanup**:
  - Replaced all "demo" references with "monitoring" or appropriate values throughout the codebase
  - Updated all 9 SLO definition files: changed `env: "demo"` → `env: "monitoring"`
  - Updated Prometheus config: changed cluster name from `kind-monitoring-demo` → `kind-monitoring`
  - Updated README.md: fixed dashboard title and replaced outdated `demo-loadtest` references with k6 load testing
  - Updated documentation files: SETUP.md title, GETTING_STARTED.md examples, VARIABLES_REGEX.md patterns
  - Updated archive files: GRAFANA_ANNOTATIONS_PLAN.md examples and namespace references
  - Updated METRICS.md: replaced "demo" with "development" in environment descriptions
- **AGENTS.md Dashboard Documentation**:
  - Added comprehensive dashboard documentation section with structure, variables, and usage instructions
  - Documented 32 panels in 5 row groups with detailed descriptions
  - Added dashboard variables usage guide (`$app`, `$namespace`, `$rate`, `$DS_PROMETHEUS`)
  - Enhanced "Updating Grafana Dashboard" workflow with variable usage examples
- **Grafana Operator Migration**:
  - Added `k8s/grafana-operator/` with Helm values, Grafana CR, Prometheus datasource CR, and dashboard manifests
  - Provisioned Sloth SLO dashboards (IDs 14643 & 14348) via `GrafanaDashboard` CRs—no more manual import
  - Updated scripts/03-deploy-monitoring.sh to install the operator and apply CRs automatically
  - Deprecated legacy `k8s/grafana/` manifests and switched scripts/10-reload-dashboard.sh to reapply operator resources
  - Updated documentation (`docs/slo/GETTING_STARTED.md`, `README.md`, `AGENTS.md`) to describe the operator-based workflow
- **Metrics Infrastructure via Helm**:
  - `scripts/02-install-metrics.sh` now installs kube-state-metrics and metrics-server via their Helm charts with versioned values in `k8s/metrics/`
  - `scripts/03-deploy-monitoring.sh` ensures the `monitoring` namespace exists before applying Prometheus and Grafana Operator resources
  - `docs/getting-started/SETUP.md` updated to reflect the Helm-based workflow
- **Helm & Documentation Fixes**:
  - Updated the Helm release workflow summary to instruct `helm install auth ...` (matching the new service naming convention)
  - Cleaned `.claude/skills/devops/SKILL.md` by fixing the `Docker Basics` heading formatting artifact

## [0.3.1] - 2025-12-02

### Changed
- **Documentation Updates**:
  - Updated README.md Technology Stack: Go 1.21 → 1.23, Gorilla Mux → Gin, added APM dependencies (OpenTelemetry, Zap, Pyroscope)
  - Updated README.md Architecture section: Replaced simple diagram with comprehensive 3-layer architecture + APM stack diagram
  - Fixed deployment order in docs/README.md "Deploy Everything" section to match actual sequence
  - Updated AGENTS.md script naming categories to reflect new script numbers (03, 04, 05-06, 07, 08, 09, 10-12)
  - Updated AGENTS.md deployment order comment to reflect correct script numbers
  - Updated AGENTS.md "Last Updated" date from November 2024 to December 2024
- **Documentation Improvements**:
  - Added Quick Summary sections to all APM documentation files (README.md, LOGGING.md, TRACING.md, PROFILING.md, ARCHITECTURE.md)
  - Added Quick Summary sections to all Monitoring documentation files (METRICS.md, VARIABLES_REGEX.md, PROMETHEUS_RATE_EXPLAINED.md, METRICS_LABEL_SOLUTIONS.md, TIME_RANGE_AND_RATE_INTERVAL.md)
  - Each Quick Summary includes: Objectives, Learning Outcomes, Keywords, and Technologies
  - Improves documentation discoverability and helps readers quickly understand what they'll learn
- **k6 Load Test Optimization**:
  - Reduced health check frequency from 100% to 10% of iterations in both test scripts (`load-test.js` and `load-test-multiple-scenarios.js`)
  - 90% reduction in health check traffic (from ~200 to ~20 health checks per iteration cycle with 200 VUs)
  - Health checks are for monitoring, not load testing; Prometheus/Kubernetes probes already handle health monitoring
  - Cleaner Grafana metrics focused on actual business API endpoints

## [0.3.0] - 2025-12-02

### Changed
- **Script Renaming for Deployment Order**:
  - Monitoring: `05-deploy-monitoring.sh` → `03-deploy-monitoring.sh`
  - APM: `17-deploy-apm.sh` → `04-deploy-apm.sh`, `14-deploy-tempo.sh` → `04a-deploy-tempo.sh`, `15-deploy-pyroscope.sh` → `04b-deploy-pyroscope.sh`, `16-deploy-loki.sh` → `04c-deploy-loki.sh`
  - Build: `03-build-microservices.sh` → `05-build-microservices.sh`
  - Deploy apps: `04-deploy-microservices.sh` → `06-deploy-microservices.sh`
  - k6: `06-deploy-k6-testing.sh` → `07-deploy-k6-testing.sh`
  - SLO: `11-deploy-slo.sh` → `08-deploy-slo.sh`, `09-validate-slo.sh` → `08a-validate-slo.sh`, `10-generate-slo-rules.sh` → `08b-generate-slo-rules.sh`
  - Access: `07-setup-access.sh` → `09-setup-access.sh`
  - Utilities: `08-reload-dashboard.sh` → `10-reload-dashboard.sh`, `12-diagnose-latency.sh` → `11-diagnose-latency.sh`, `13-error-budget-alert.sh` → `12-error-budget-alert.sh`
  - Updated all internal script references and documentation (README.md, AGENTS.md, SETUP.md, .claude/commands/deploy.md)
- **Vector Configuration Simplified** (`k8s/vector/configmap.yaml`):
  - Removed complex JSON parsing logic from VRL transforms
  - Simplified to only add labels from pod metadata (service, namespace, pod, container)
  - Added batching (3MB max bytes, 5s timeout) and rate limiting (100 requests/second)
  - Improved label fallbacks: use `pod_name` as service fallback, "system" instead of "unknown" to avoid too many logs in single stream
  - Added `out_of_order_action: accept` to handle out-of-order log events
- **Loki Configuration Enhanced** (`k8s/loki/configmap.yaml`):
  - Increased ingestion limits: 64MB/s rate, 128MB burst (from 16MB/s, 32MB burst)
  - Increased max_streams_per_user: 10000 → 50000
  - Increased per_stream_rate_limit: 3MB → 50MB (with 100MB burst)
  - Increased gRPC message size: 4MB → 10MB (grpc_server_max_recv_msg_size, grpc_server_max_send_msg_size)
  - Added `volume_enabled: true` for log volume queries API support
- **Vector Moved to kube-system Namespace**:
  - Moved Vector DaemonSet from `monitoring` to `kube-system` namespace for better log collection coverage
  - Updated RBAC: Added `nodes` resource permissions to ClusterRole for Vector to read node information
  - Added `VECTOR_SELF_NODE_NAME` environment variable using Kubernetes Downward API (`spec.nodeName`)
  - Enabled Vector API for health checks (port 8686)

### Fixed
- **Vector → Loki Pipeline Issues**:
  - Fixed VRL errors: Changed `string()` to `to_string()` for infallible type conversion in Vector transforms
  - Fixed 429 Too Many Requests: Increased Loki ingestion limits (64MB/s rate, 128MB burst) and per-stream rate limits (3MB → 50MB)
  - Fixed 500 Internal Server Error: Increased gRPC message size limits (4MB → 10MB) and reduced Vector batch size (10MB → 3MB)
  - Fixed per-stream rate limit exceeded: Increased from 3MB to 50MB, improved label fallbacks to avoid too many "unknown" streams
  - Fixed out-of-order events: Added `out_of_order_action: accept` to Vector Loki sink configuration


## [0.2.0] - 2025-12-01

### Changed
- **3-Layer Architecture Refactor**: Refactored all services into web → logic → core layers
  - `web/v1/`, `web/v2/` - HTTP handlers (Gin handlers) with tracing and logging
  - `logic/v1/`, `logic/v2/` - Business logic layer with spans for each operation
  - `core/domain/` - Domain models (moved from `domain/` to `core/domain/`)
  - All 9 services refactored: auth, user, product, cart, order, review, notification, shipping
  - Layer tracing: Each layer creates spans with `layer` attribute for better observability
- **Import Path Update**: Changed module path from `github.com/demo/monitoring-golang` to `github.com/duynhne/monitoring`
  - Updated all Go source files (42 files)
  - Updated `services/go.mod`
  - Updated documentation references
- **Project structure reorganized** for cleaner root directory:
  - Moved Go code (`cmd/`, `internal/`, `pkg/`, `Dockerfile`, `go.mod`, `go.sum`) into `services/` folder
  - Moved `kind/` folder into `k8s/kind/`
  - Renamed service folders: `services/cmd/auth-service/` → `services/cmd/auth/` (and all 9 services)
- Updated GitHub Actions workflows for new paths
- Updated build scripts (`05-build-microservices.sh`, `01-create-kind-cluster.sh`)
- **SLO folder simplified**:
  - `slo/generated/` now gitignored (generated files created on-demand by `./scripts/08b-generate-slo-rules.sh`)
  - SLO definitions remain in `slo/definitions/` as source of truth
- **Service naming simplified** - Removed "-service" suffix everywhere:
  - Service folders: `cmd/auth-service/` → `cmd/auth/`
  - Helm values: `name: auth-service` → `name: auth`
  - SLO definitions: `auth-service.yaml` → `auth.yaml`
  - App labels: `app="auth-service"` → `app="auth"`
  - Alert names: `AuthServiceHighErrorRate` → `AuthHighErrorRate`
  - Service URLs in k6 scripts: `auth-service.auth.svc.cluster.local` → `auth.auth.svc.cluster.local`
  - Kubernetes service names: `svc/auth-service` → `svc/auth`
  - Prometheus SLO ConfigMaps: `prometheus-slo-rules-auth-service` → `prometheus-slo-rules-auth`
  - Go log messages: `"Starting auth-service"` → `"Starting auth"`
  - Updated all documentation (README.md, API_REFERENCE.md, METRICS_LABEL_SOLUTIONS.md, etc.)

### Removed
- `k8s/slo/sloth-job.yaml` - Unused Kubernetes Job for Sloth (scripts run Sloth locally instead)
- `k8s/slo/` folder - Empty after removing sloth-job.yaml
- Old SLO definition files with "-service" suffix (replaced by shorter names)

## [0.1.0] - 2024-11-26

### Added
- Generic Helm chart for microservices deployment (`charts/`)
  - `Chart.yaml` - Chart metadata (version 0.1.0)
  - `values.yaml` - Default configuration values
  - `templates/` - Deployment and Service templates
  - `values/` - Per-service value files (auth, user, product, cart, order, review, notification, shipping, shipping-v2)
- GitHub Actions workflow for Helm chart release (`helm-release.yml`)
  - Automatic chart linting and packaging
  - Push to OCI registry: `oci://ghcr.io/duynhne/charts/microservice`
- Deployment script support for Helm (`06-deploy-microservices.sh`)
  - `--local` mode: Deploy using local chart
  - `--registry` mode: Deploy from OCI registry

### Changed
- Image naming convention simplified
  - Old: `ghcr.io/duynhne/auth-service:latest`
  - New: `ghcr.io/duynhne/auth:latest`
- GitHub Actions `build-images.yml` updated for shorter image names
- Updated documentation (AGENTS.md, SETUP.md, docs/README.md)

### Removed
- Raw Kubernetes YAML manifests for microservices (`k8s/{service-name}/`)
  - Replaced by Helm chart deployment (`charts/`)
- Deleted 9 service folders from `k8s/`: auth-service, user-service, product-service, cart-service, order-service, review-service, notification-service, shipping-service, shipping-service-v2

### Fixed
- Image registry reference updated from `duyne-me` to `duynhne`

---

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 0.2.0 | 2025-12-02 | Vector/Loki pipeline fixes, script renaming for deployment order |
| 0.1.0 | 2024-11-26 | Initial Helm chart release |

---

## Migration Guide

### From v3 to v4

1. **Update image references** in any custom configurations:
   ```yaml
   # Old
   image: ghcr.io/duynhne/auth-service:latest
   
   # New
   image: ghcr.io/duynhne/auth:latest
   ```

2. **Deploy using Helm** instead of raw kubectl:
   ```bash
   # Old
   kubectl apply -f k8s/auth-service/
   
   # New
   helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth
   ```

3. **Or use the deployment script**:
   ```bash
   ./scripts/06-deploy-microservices.sh --local
   ```

