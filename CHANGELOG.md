# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Project structure reorganized** for cleaner root directory:
  - Moved Go code (`cmd/`, `internal/`, `pkg/`, `Dockerfile`, `go.mod`, `go.sum`) into `services/` folder
  - Moved `kind/` folder into `k8s/kind/`
- Updated GitHub Actions workflows for new paths
- Updated build scripts (`03-build-microservices.sh`, `01-create-kind-cluster.sh`)
- **SLO folder simplified**:
  - `slo/generated/` now gitignored (generated files created on-demand by `./scripts/10-generate-slo-rules.sh`)
  - SLO definitions remain in `slo/definitions/` as source of truth
- **Service naming simplified** - Removed "-service" suffix everywhere:
  - Helm values: `name: auth-service` → `name: auth`
  - SLO definitions: `auth-service.yaml` → `auth.yaml`
  - App labels: `app="auth-service"` → `app="auth"`
  - Alert names: `AuthServiceHighErrorRate` → `AuthHighErrorRate`
  - Updated all documentation to reflect new naming

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
- Deployment script support for Helm (`04-deploy-microservices.sh`)
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
   ./scripts/04-deploy-microservices.sh --local
   ```

