# Database Configuration

This directory contains PostgreSQL database configurations organized by cluster.

## PostgreSQL Kubernetes operators
As an alternative to deploying Postgres manually, you can also use one of several ready-made Postgres operators. Here’s a look at five popular options:

| Operator Name | Description | In Use |
|--------------|-------------|--------|
| **CloudNativePG** | A Kubernetes-native operator designed to manage PostgreSQL clusters in cloud-native environments. It supports the deployment, scaling, and management of PostgreSQL clusters with a focus on high availability (HA) and disaster recovery. | ✅ |
| **Crunchy Data Postgres Operator** | Another Kubernetes-native operator for managing PostgreSQL clusters, built by the creators of Crunchy PostgreSQL. It provides robust features for scaling, high availability, and backup management. | ⬜ |
| **Zalando Postgres Operator** | Designed to run and manage PostgreSQL clusters in Kubernetes with a focus on automated high availability and operational simplicity. | ✅ |
| **KubeDB PostgreSQL Operator** | An open-source Kubernetes operator focused on managing databases at scale, including PostgreSQL. It is part of the KubeDB ecosystem, which supports a range of databases beyond just PostgreSQL. | ⬜ |
| **StackGres Postgres Operator** | A PostgreSQL operator that emphasizes fully managed PostgreSQL deployments within Kubernetes environments. It's known for providing a more opinionated approach to PostgreSQL management with a focus on ease of use and automation. | ⬜ |


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

- **Database Guide:** [`docs/databases/DATABASE.md`](../../../docs/databases/DATABASE.md)
- **Poolers Documentation:** [`clusters/README.md`](clusters/README.md)
- **PgCat Troubleshooting:** [`docs/runbooks/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md`](../../../docs/runbooks/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md)
