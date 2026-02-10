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

## Cluster Overview

| Cluster | Operator | PostgreSQL | Namespace | HA | Pooler | Services |
|---------|----------|------------|-----------|-----|--------|----------|
| auth-db | Zalando | 17 | auth | 3 nodes | PgBouncer (sidecar) | Auth |
| review-db | Zalando | 16 | review | 1 node | None | Review |
| supporting-shared-db | Zalando | 16 | user | 1 node | PgBouncer (sidecar) | User, Notification, Shipping |
| product-db | CloudNativePG | 18 | product | 3 nodes | PgDog (standalone) | Product |
| transaction-shared-db | CloudNativePG | 18 | cart | 3 nodes | PgCat (standalone) | Cart, Order |

## Related Documentation

- **Database Guide:** [`docs/databases/database.md`](../../../docs/databases/database.md)
- **Poolers Documentation:** [`clusters/README.md`](clusters/README.md)
- **PgCat Troubleshooting:** [`docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md`](../../../docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md)
