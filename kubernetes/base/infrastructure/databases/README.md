# Database Operators

## Overview

The database layer includes:
- **Zalando Postgres Operator** (v1.15.1): Manages review-db, auth-db, supporting-db
- **CloudNativePG Operator** (v1.28.0): Manages product-db, transaction-db

## Installation Method

Currently installed via Helm (transitioning to Flux HelmRelease):

```bash
# Zalando Postgres Operator
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm upgrade --install postgres-operator postgres-operator-charts/postgres-operator \
  --namespace postgres-operator \
  --create-namespace

# CloudNativePG Operator
helm repo add cloudnative-pg https://cloudnative-pg.io/charts/
helm upgrade --install cloudnative-pg cloudnative-pg/cloudnative-pg \
  --namespace cloudnative-pg \
  --create-namespace \
  --values k8s/postgres-operator/cloudnativepg/values.yaml
```

## Database Clusters (Phase 3)

Database cluster CRDs will be migrated in Phase 3 with idempotent strategy:
- `auth-db` (Zalando)
- `review-db` (Zalando)
- `supporting-db` (Zalando)
- `product-db` (CloudNativePG)
- `transaction-db` (CloudNativePG)

## Connection Poolers

- **PgBouncer**: Used by auth service
- **PgCat**: Used by product, cart, order services

See existing configurations:
- `k8s/postgres-operator/zalando/`
- `k8s/postgres-operator/cloudnativepg/`
- `k8s/postgres-operator/pgcat/`
