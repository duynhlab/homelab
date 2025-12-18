# Microservices Helm Chart

Generic Helm chart for deploying all 9 microservices in the monitoring project.

## Quick Start

```bash
# Local deployment (all services)
./scripts/06-deploy-microservices.sh --local

# From OCI registry
./scripts/06-deploy-microservices.sh --registry

# Manual single service deployment
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
```

**OCI Registry**: `oci://ghcr.io/duynhne/charts/microservice`

---

## Chart Structure

```
charts/
├── Chart.yaml             # Chart metadata (version: 0.3.0)
├── values.yaml            # Default values template
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
    ├── _helpers.tpl
    ├── deployment.yaml    # Includes initContainer for migrations
    └── service.yaml
```

---

## Configuration

### Configuration Priority

1. Default values (hardcoded in `pkg/config/config.go`)
2. `.env` file (local development only)
3. Environment variables (Kubernetes runtime)
4. **Helm values** → `env`/`extraEnv` → container environment

**Key Point**: Helm values override all previous configuration layers.

### `env` vs `extraEnv`

**`env`** - Core configuration (common across all services):
- SERVICE_NAME, PORT, ENV
- APM config (OTEL_COLLECTOR_ENDPOINT, PYROSCOPE_ENDPOINT)
- Logging config (LOG_LEVEL, LOG_FORMAT)
- Supports Helm templating

**`extraEnv`** - Service-specific variables:
- Database connections (DB_HOST, DB_USER, DB_PASSWORD)
- External services (REDIS_HOST, KAFKA_BROKER)
- Feature flags, secrets (via `valueFrom.secretKeyRef`)
- No Helm templating (YAML passthrough)

**Example**:

```yaml
env:
  - name: SERVICE_NAME
    value: "auth"
  - name: PORT
    value: "8080"

extraEnv:
  - name: DB_HOST
    value: "auth-db.postgres-operator.svc.cluster.local"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: auth-db-secret
        key: password
```

---

## Database Migrations

Enable Flyway init container for automatic database migrations:

```yaml
migrations:
  enabled: true
  image: ghcr.io/duynhne/auth:v5-init
  imagePullPolicy: IfNotPresent
```

InitContainer automatically:
- Passes all `DB_*` environment variables from `extraEnv`
- Builds `FLYWAY_URL` from individual DB env vars
- Runs `flyway migrate` before main container starts

---

## Per-Service Values

Minimal service configuration:

```yaml
# charts/values/myservice.yaml
name: myservice

env:
  - name: SERVICE_NAME
    value: "myservice"
  - name: PORT
    value: "8080"
  - name: ENV
    value: "production"
  - name: OTEL_COLLECTOR_ENDPOINT
    value: "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"
  - name: PYROSCOPE_ENDPOINT
    value: "http://pyroscope.monitoring.svc.cluster.local:4040"

image:
  repository: ghcr.io/duynhne/myservice
  tag: "v5"
  pullPolicy: IfNotPresent

extraEnv:
  - name: DB_HOST
    value: "db-host.svc.cluster.local"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password
```

---

## Best Practices

- Use `env` for core configuration common across services
- Use `extraEnv` for service-specific dependencies (databases, queues, caches)
- Use Secrets for sensitive data (via `valueFrom.secretKeyRef`)
- Don't hardcode secrets in values files
- Don't use Helm templating in `extraEnv`

---

## Related Documentation

- **Configuration**: `services/pkg/config/config.go`
- **Deployment Template**: `charts/templates/deployment.yaml`
- **Service Values**: `charts/values/*.yaml`
- **Deployment Script**: `scripts/06-deploy-microservices.sh`
- **AGENTS.md**: Project structure and conventions

---

**Last Updated**: December 2025 - Version 0.3.0 (InitContainer support)
