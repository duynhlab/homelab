# Database Configuration

This directory contains PostgreSQL database configurations organized by cluster.

## PostgreSQL Kubernetes Operators


| Operator                           | Version | Description                                                                                       | In Use | Releases                                                              |
| ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------- |
| **CloudNativePG**                  | v1.29.0 | Kubernetes-native operator for PostgreSQL with HA, disaster recovery, and declarative management. | ✅      | [Releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) |
| **Zalando Postgres Operator**      | v1.15.1 | Automated HA and operational simplicity for PostgreSQL on Kubernetes. Uses Patroni + Spilo.       | ✅      | [Releases](https://github.com/zalando/postgres-operator/releases)     |
| **Crunchy Data Postgres Operator** | —       | Kubernetes-native operator by Crunchy Data with robust scaling, HA, and backup.                   | ⬜      | —                                                                     |
| **KubeDB PostgreSQL Operator**     | —       | Multi-database Kubernetes operator (part of KubeDB ecosystem).                                    | ⬜      | —                                                                     |
| **StackGres Postgres Operator**    | —       | Opinionated, fully managed PostgreSQL deployments with ease-of-use focus.                         | ⬜      | —                                                                     |


## Cluster Overview


| Cluster              | Operator      | PostgreSQL | Namespace | HA      | Pooler                                    | Services                             |
| -------------------- | ------------- | ---------- | --------- | ------- | ----------------------------------------- | ------------------------------------ |
| auth-db              | Zalando       | 17         | auth      | 3 nodes | PgBouncer (operator-managed, 2 instances) | Auth                                 |
| supporting-shared-db | Zalando       | 16         | user      | 1 node  | PgBouncer (operator-managed, 2 instances) | User, Notification, Shipping, Review |
| cnpg-db              | CloudNativePG | 18.1       | product   | 3 nodes | PgDog v0.39 (`pgdog-cnpg`, 1 replica)     | Product, Cart, Order                 |
| cnpg-db-replica      | CloudNativePG | 18.1       | product   | 1 node  | —                                         | DR (continuous WAL recovery)         |


## Connection Endpoints


| Cluster              | Pooler Endpoint                             | Direct Endpoint                                                              | Notes                                                   |
| -------------------- | ------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------- |
| auth-db              | `auth-db-pooler.auth.svc:5432`              | `auth-db.auth.svc:5432`                                                      | PgBouncer transaction mode, maxDBConnections 240/pooler |
| supporting-shared-db | `supporting-shared-db-pooler.user.svc:5432` | `supporting-shared-db.user.svc:5432`                                         | PgBouncer transaction mode, 4 databases                 |
| cnpg-db              | `pgdog-cnpg.product.svc:6432`               | RW: `cnpg-db-rw.product.svc:5432`, R: `cnpg-db-r.product.svc:5432`          | PgDog with R/W splitting; DBs: product, cart, order     |
| cnpg-db-replica      | —                                           | `cnpg-db-replica-rw.product.svc:5432`                                        | DR only; promotable to standalone primary               |


## Monitoring & Backup


| Cluster              | Metrics Exporter                                                         | Log Shipper              | Backup Method       | Backup Target                                            |
| -------------------- | ------------------------------------------------------------------------ | ------------------------ | ------------------- | -------------------------------------------------------- |
| auth-db              | postgres_exporter v0.18.1 (sidecar, :9187) + PgBouncer exporter v0.11.0 | Vector v0.52.0 (sidecar) | WAL-G               | `s3://pg-backups-zalando/auth-db/`                       |
| supporting-shared-db | pg_exporter (Pigsty) v1.2.0 (sidecar, :9630)                            | Vector v0.52.0 (sidecar) | WAL-G               | `s3://pg-backups-zalando/user-db/`                       |
| cnpg-db              | CNPG built-in (PodMonitor) + PgDog OpenMetrics (:9090)                   | CNPG built-in (stdout)   | Barman Object Store | `s3://pg-backups-cnpg/cnpg-db/`, retention 30d           |
| cnpg-db-replica      | CNPG built-in (PodMonitor)                                               | CNPG built-in (stdout)   | Barman Object Store | `s3://pg-backups-cnpg/cnpg-db-replica/`, retention 7d    |


## Extensions

**Shared across Zalando clusters** (auth-db, supporting-shared-db):

`pg_stat_statements`, `pg_cron`, `pg_trgm`, `pgcrypto`, `pg_stat_kcache`

**cnpg-db** (CloudNativePG, declarative via `extensions.yaml`):

`pgaudit`, `pg_stat_statements`, `auto_explain`, `pgcrypto`, `uuid-ossp`, `sync_replication_slots` (PG 18 native feature)

## Flux layout (local cluster)

| Path | Flux Kustomization | Contents |
|------|--------------------|----------|
| `configs/databases` | `databases-local` | Zalando clusters, `cnpg-db` (+ PgDog, backups, `Backup` on-demand `cnpg-db-initial`) |
| `configs/databases-cnpg-dr` | `databases-cnpg-dr-local` | `cnpg-db-replica` only; `dependsOn: databases-local` |

## Related Documentation

- **Database Guide:** [`docs/databases/002-database-integration.md`](../../../../docs/databases/002-database-integration.md)
- **PostgreSQL DRP:** [`docs/databases/010-drp.md`](../../../../docs/databases/010-drp.md)
- **Poolers Documentation:** [`clusters/README.md`](clusters/README.md)
- **CNPG HA/DR Deep Dive:** [`docs/databases/005-ha-dr-deep-dive.md`](../../../../docs/databases/005-ha-dr-deep-dive.md)
- **PgCat Troubleshooting (legacy):** [`docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md`](../../../../docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md)

