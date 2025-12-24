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
├── Chart.yaml             # Chart metadata (version: 0.4.0)
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
4. **Helm values** → `env` → container environment

**Key Point**: Helm values override all previous configuration layers.

### Environment Variables (`env`)

All environment variables are configured in the `env` section:
- Core configuration: SERVICE_NAME, PORT, ENV
- APM config: OTEL_COLLECTOR_ENDPOINT, PYROSCOPE_ENDPOINT
- Logging config: LOG_LEVEL, LOG_FORMAT
- Database configuration: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
- External services: REDIS_HOST, KAFKA_BROKER
- Feature flags, secrets (via `valueFrom.secretKeyRef`)
- Supports Helm templating

**Example**:

```yaml
env:
  - name: SERVICE_NAME
    value: "auth"
  - name: PORT
    value: "8080"
  - name: ENV
    value: "production"
  # Database configuration
  - name: DB_HOST
    value: "auth-db.postgres-operator.svc.cluster.local"
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "auth"
  - name: DB_USER
    value: "auth"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: auth-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
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

InitContainer configuration:
- Uses `migrations.env` for database connection (direct connection, no pooler)
- Uses `migrations.envFrom.secretRef` for DB_PASSWORD from secret
- Builds `FLYWAY_URL` from individual DB env vars
- Runs `flyway migrate` before main container starts

**Example**:

```yaml
migrations:
  enabled: true
  image: ghcr.io/duynhne/auth:v5-init
  imagePullPolicy: IfNotPresent
  env:
    DB_HOST: "auth-db.postgres-operator.svc.cluster.local"  # Direct connection
    DB_PORT: "5432"
    DB_NAME: "auth"
    DB_USER: "auth"
    DB_SSLMODE: "disable"
  envFrom:
    secretRef: "auth-db-secret"  # For DB_PASSWORD
```

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
  # Database configuration
  - name: DB_HOST
    value: "db-host.svc.cluster.local"
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "myservice"
  - name: DB_USER
    value: "myservice"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"

image:
  repository: ghcr.io/duynhne/myservice
  tag: "v5"
  pullPolicy: IfNotPresent
```

---

## Best Practices

- Use `env` for all environment variables (core + service-specific)
- Use Secrets for sensitive data (via `valueFrom.secretKeyRef`)
- Don't hardcode secrets in values files
- Use `migrations.env` for init container database configuration (direct connection, no pooler)
- Main container uses pooler endpoints (if configured), init container uses direct database connection

---

## Related Documentation

- **Configuration**: `services/pkg/config/config.go`
- **Deployment Template**: `charts/templates/deployment.yaml`
- **Service Values**: `charts/values/*.yaml`
- **Deployment Script**: `scripts/06-deploy-microservices.sh`
- **AGENTS.md**: Project structure and conventions

---

**Last Updated**: December 2025 - Version 0.4.0 (Consolidated env configuration)
