# Database Configuration

This directory contains PostgreSQL database configurations organized by cluster.

## Structure

```
databases/
├── clusters/                    # Per-cluster configurations
│   ├── auth-db/                 # Zalando cluster (3-node HA)
│   │   ├── kustomization.yaml
│   │   ├── instance.yaml
│   │   └── configmaps/
│   │       ├── monitoring-queries.yaml
│   │       └── vector-sidecar.yaml
│   ├── review-db/               # Zalando cluster (single node)
│   │   └── ...
│   ├── supporting-db/           # Zalando cluster (shared DB pattern)
│   │   └── ...
│   ├── product-db/              # CloudNativePG cluster (2-node HA)
│   │   ├── kustomization.yaml
│   │   ├── instance.yaml
│   │   ├── secrets/
│   │   │   └── product-db-secret.yaml
│   │   ├── poolers/
│   │   │   └── helmrelease.yaml  # PgDog
│   │   └── monitoring/
│   │       └── podmonitor-cloudnativepg-product-db.yaml
│   ├── transaction-db/          # CloudNativePG cluster (3-node HA)
│   │   ├── kustomization.yaml
│   │   ├── instance.yaml
│   │   ├── secrets/
│   │   │   ├── transaction-db-secret-cart.yaml
│   │   │   └── transaction-db-secret-order.yaml
│   │   ├── poolers/
│   │   │   ├── configmap.yaml   # PgCat config
│   │   │   ├── deployment.yaml
│   │   │   └── service.yaml
│   │   └── monitoring/
│   │       ├── podmonitor-cloudnativepg-transaction-db.yaml
│   │       └── servicemonitor-pgcat-transaction.yaml
│   └── README.md                # Connection poolers documentation
└── kustomization.yaml           # Root kustomization (includes all clusters)
```

## Cluster Overview

| Cluster | Operator | Namespace | HA | Pooler | Services |
|---------|----------|-----------|-----|--------|----------|
| auth-db | Zalando | auth | 3 nodes | PgBouncer (sidecar) | Auth |
| review-db | Zalando | review | 1 node | None | Review |
| supporting-db | Zalando | user | 1 node | PgBouncer (sidecar) | User, Notification, Shipping |
| product-db | CloudNativePG | product | 2 nodes | PgDog (standalone) | Product |
| transaction-db | CloudNativePG | cart | 3 nodes | PgCat (standalone) | Cart, Order |

## Why Cluster-Centric Organization?

Each cluster folder contains **all resources** for that cluster:
- **Instance**: The PostgreSQL cluster CRD
- **Secrets**: Application database credentials (CloudNativePG only)
- **ConfigMaps**: Monitoring queries, Vector sidecar configs (Zalando only)
- **Poolers**: Connection pooler deployment (if standalone)
- **Monitoring**: PodMonitor/ServiceMonitor for the cluster

**Benefits:**
- Easy to find all resources for a specific cluster
- Clear ownership and dependencies
- Simplified troubleshooting

## Kustomization Order

Each cluster's `kustomization.yaml` applies resources in the correct order:

1. **Secrets/ConfigMaps** - Must exist before cluster creation
2. **Instance** - PostgreSQL cluster CRD
3. **Poolers** - Connection pooler deployment
4. **Monitoring** - PodMonitors/ServiceMonitors (require running cluster)

## Related Documentation

- **Database Guide:** [`docs/guides/DATABASE.md`](../../../docs/guides/DATABASE.md)
- **Poolers Documentation:** [`clusters/README.md`](clusters/README.md)
- **PgCat Troubleshooting:** [`docs/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md`](../../../docs/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md)
