# Database Configuration

This directory contains PostgreSQL database configurations organized by cluster.

## PostgreSQL Kubernetes Operators


| Operator                           | Version | Description                                                                                       | In Use | Releases                                                              |
| ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------- |
| **CloudNativePG**                  | v1.28.1 | Kubernetes-native operator for PostgreSQL with HA, disaster recovery, and declarative management. | ✅      | [Releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) |
| **Zalando Postgres Operator**      | v1.15.1 | Automated HA and operational simplicity for PostgreSQL on Kubernetes. Uses Patroni + Spilo.       | ✅      | [Releases](https://github.com/zalando/postgres-operator/releases)     |
| **Crunchy Data Postgres Operator** | —       | Kubernetes-native operator by Crunchy Data with robust scaling, HA, and backup.                   | ⬜      | —                                                                     |
| **KubeDB PostgreSQL Operator**     | —       | Multi-database Kubernetes operator (part of KubeDB ecosystem).                                    | ⬜      | —                                                                     |
| **StackGres Postgres Operator**    | —       | Opinionated, fully managed PostgreSQL deployments with ease-of-use focus.                         | ⬜      | —                                                                     |


## Cluster Overview


| Cluster               | Operator      | PostgreSQL | Namespace | HA      | Pooler                                    | Services                             |
| --------------------- | ------------- | ---------- | --------- | ------- | ----------------------------------------- | ------------------------------------ |
| auth-db               | Zalando       | 17         | auth      | 3 nodes | PgBouncer (operator-managed, 2 instances) | Auth                                 |
| supporting-shared-db  | Zalando       | 16         | user      | 1 node  | PgBouncer (operator-managed, 2 instances) | User, Notification, Shipping, Review |
| product-db            | CloudNativePG | 18.1       | product   | 3 nodes | PgDog v0.39 (standalone, 1 replica)       | Product                              |
| transaction-shared-db | CloudNativePG | 18.1       | cart      | 3 nodes | PgCat v1.2.0 (standalone, 2 replicas)     | Cart, Order                          |


## Connection Endpoints


| Cluster               | Pooler Endpoint                             | Direct Endpoint                                                                          | Notes                                                   |
| --------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| auth-db               | `auth-db-pooler.auth.svc:5432`              | `auth-db.auth.svc:5432`                                                                  | PgBouncer transaction mode, maxDBConnections 240/pooler |
| supporting-shared-db  | `supporting-shared-db-pooler.user.svc:5432` | `supporting-shared-db.user.svc:5432`                                                     | PgBouncer transaction mode, 4 databases                 |
| product-db            | `pgdog-product.product.svc:6432`            | RW: `product-db-rw.product.svc:5432`, R: `product-db-r.product.svc:5432`                 | PgDog with read/write splitting                         |
| transaction-shared-db | `pgcat.cart.svc:5432`                       | RW: `transaction-shared-db-rw.cart.svc:5432`, R: `transaction-shared-db-r.cart.svc:5432` | PgCat with read/write splitting, sync replication       |


## Monitoring & Backup


| Cluster               | Metrics Exporter                                                        | Log Shipper              | Backup Method       | Backup Target                                               |
| --------------------- | ----------------------------------------------------------------------- | ------------------------ | ------------------- | ----------------------------------------------------------- |
| auth-db               | postgres_exporter v0.18.1 (sidecar, :9187) + PgBouncer exporter v0.11.0 | Vector v0.52.0 (sidecar) | WAL-G               | `s3://pg-backups-zalando/auth-db/`                          |
| supporting-shared-db  | pg_exporter (Pigsty) v1.2.0 (sidecar, :9630)                            | Vector v0.52.0 (sidecar) | WAL-G               | `s3://pg-backups-zalando/user-db/`                          |
| product-db            | CNPG built-in (PodMonitor) + PgDog OpenMetrics (:9090)                  | CNPG built-in (stdout)   | Barman Object Store | `s3://pg-backups-cnpg/product-db/`, retention 30d           |
| transaction-shared-db | CNPG built-in (PodMonitor) + PgCat Prometheus (:9930)                   | CNPG built-in (stdout)   | Barman Object Store | `s3://pg-backups-cnpg/transaction-shared-db/`, retention 7d |


## Extensions

**Shared across Zalando clusters** (auth-db, supporting-shared-db):

`pg_stat_statements`, `pg_cron`, `pg_trgm`, `pgcrypto`, `pg_stat_kcache`

**product-db** (CloudNativePG, declarative via `extensions.yaml`):

`pgaudit`, `pg_stat_statements`, `auto_explain`, `pgcrypto`, `uuid-ossp`

**transaction-shared-db** (CloudNativePG):

`pgaudit`, `pg_stat_statements` + `sync_replication_slots` (PG 18 native feature for logical replication slot sync)

## Related Documentation

- **Database Guide:** `[docs/databases/database.md](../../../docs/databases/database.md)`
- **Poolers Documentation:** `[clusters/README.md](clusters/README.md)`
- **PgCat Troubleshooting:** `[docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md](../../../docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md)`

