# Conventions and Standards

This guide documents naming conventions, code standards, and organizational patterns used throughout the codebase.

---

## Namespace Conventions

- **`monitoring`** - Monitoring components and SLO system
- **Service namespaces** - Each microservice has own namespace: `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`
- **`k6`** - K6 load testing
- **`kube-system`** - Vector (log collection)

---

## Script Naming

- **Numbered prefixes (01-12)** - Execution order
- **Format**: `{number}-{purpose}.sh`
- **Categories**: Infrastructure (01-02), Monitoring (02), APM (03), Databases (04), Apps (05-06), Load Testing (07), SLO (08), Access (09), Utilities (10-12)

**Examples:**
- `01-create-kind-cluster.sh` - Infrastructure setup
- `02-deploy-monitoring.sh` - Monitoring deployment
- `06-deploy-microservices.sh` - Application deployment
- `09-setup-access.sh` - Access configuration

---

## File Organization Patterns

### Services
- Service code: `services/cmd/{service}/main.go` + `services/internal/{service}/{v1,v2,core}/`
- Helm values: `charts/values/{service}.yaml`
- SLO CRD: `k8s/sloth/crds/{service}-slo.yaml`
- Migration: `services/migrations/{service}/Dockerfile` + `sql/001__init_schema.sql`

### Kubernetes
- Kubernetes manifests: `k8s/{component}/`
- Scripts: `scripts/{number}-{purpose}.sh`
- SLO: `k8s/sloth/crds/*.yaml` (PrometheusServiceLevel CRDs)

**Example Structure:**
```
services/
├── cmd/
│   └── auth/
│       └── main.go
├── internal/
│   └── auth/
│       ├── web/
│       │   ├── v1/
│       │   └── v2/
│       ├── logic/
│       │   ├── v1/
│       │   └── v2/
│       └── core/
│           ├── domain/
│           └── database.go
└── migrations/
    └── auth/
        ├── Dockerfile
        └── sql/
            └── V1__init_schema.sql
```

---

## Metric Naming Conventions

- **Pattern**: `{domain}_{metric}_{unit}`
- **Examples**: 
  - `request_duration_seconds` (histogram)
  - `requests_total` (counter)
  - `requests_in_flight` (gauge)

**Prometheus Best Practices:**
- Use base units (seconds, bytes, total)
- Use `_total` suffix for counters
- Use `_seconds`, `_bytes` for units
- Use snake_case for metric names

---

## Label Requirements

### Required Labels for Metrics (after Prometheus scrape)

- `job` - Set to `"microservices"` via ServiceMonitor relabeling
- `app` - Service name (from service label)
- `namespace` - Kubernetes namespace (from pod metadata)
- `instance` - Pod IP:port (automatic)

### Application-Level Labels (emitted by app)

- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (e.g., `/api/v1/users`)
- `code` - HTTP status code (200, 404, 500)

**Note**: Applications DO NOT emit `app`, `namespace`, or `job` labels. All service identification labels are injected by Prometheus during scrape via ServiceMonitor `relabelings`.

---

## Go Code Conventions

### Middleware
- **Location**: `services/pkg/middleware/` - Centralized observability middleware
- **Order**: Tracing → Logging → Metrics (see [`docs/apm/ARCHITECTURE.md`](../apm/ARCHITECTURE.md))

### Handlers
- **Structure**: Separate `v1/` and `v2/` directories for API versioning
- **Location**: `services/internal/{service}/web/{v1,v2}/`

### Domain Models
- **Location**: `core/domain/` directory for data structures
- **Pattern**: Domain entities separate from database models

### Database
- **Connection**: `core/database.go` for database connections
- **Pattern**: Centralized connection management

### Memory Leak Prevention
- Always use `defer cancel()` for contexts
- Close channels properly
- Set timeouts for all operations
- Use `sync.WaitGroup` for goroutine coordination

### Configuration
- **Location**: `pkg/config/config.go` for centralized config management
- **Pattern**: Environment variables → config struct → validation

---

## Dashboard Conventions

- **UID**: `microservices-monitoring-001`
- **Variables**: `$app`, `$namespace`, `$rate`
- **Query filters**: Always include `job=~"microservices"` and `namespace=~"$namespace"`

**Dashboard Details**: See [`docs/guides/DASHBOARD_PANELS.md`](DASHBOARD_PANELS.md) for complete dashboard reference (34 panels).

---

## Local Build Verification

**Before pushing code, run:**
```bash
./scripts/00-verify-build.sh
```

### What It Checks

1. Go module synchronization (`go.mod`/`go.sum`)
2. Code formatting (`gofmt`)
3. Static analysis (`go vet`)
4. Build all 9 services
5. Tests (optional - use `--skip-tests` to skip)

### Usage

```bash
# Run all checks including tests
./scripts/00-verify-build.sh

# Skip tests (faster, for quick verification)
./scripts/00-verify-build.sh --skip-tests
```

### If Script Fails

- Fix the reported error
- Re-run the script
- Commit changes only after all checks pass

### Optional: Git Hook Setup

To automatically run verification before each commit:

```bash
# Install git hook
cp .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**Note:** Git hook is optional. You can skip it with `git commit --no-verify` if needed.

### Troubleshooting

- **"go.mod or go.sum changed"**: Run `go mod tidy` and commit the changes
- **"Code not formatted"**: Run `gofmt -w .` to auto-format
- **"Failed to build [service]"**: Check compilation errors in that service
- **"go vet found issues"**: Review and fix the reported issues

---

## Related Documentation

- **[AGENTS.md](../../AGENTS.md)** - Main agent guide with workflow
- **[API_REFERENCE.md](API_REFERENCE.md)** - API endpoints and patterns
- **[DATABASE.md](DATABASE.md)** - Database conventions and patterns
- **[DASHBOARD_PANELS.md](DASHBOARD_PANELS.md)** - Dashboard conventions

