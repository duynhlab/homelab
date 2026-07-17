# Database Configuration

This directory contains PostgreSQL database configurations organized by cluster.

## PostgreSQL Kubernetes Operators


| Operator                           | Version | Description                                                                                       | In Use | Releases                                                              |
| ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------- |
| **CloudNativePG**                  | v1.30.0 | Kubernetes-native operator for PostgreSQL with HA, disaster recovery, and declarative management. Now hosts **all** Postgres clusters. | ✅      | [Releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) |
| **Zalando Postgres Operator**      | v1.15.1 | Patroni + Spilo operator. Previously ran `auth-db` and `supporting-shared-db`; **migrated to CloudNativePG** and no longer deployed (kept for reference in [`docs/databases/003.2-operator-zalando.md`](../../../../docs/databases/003.2-operator-zalando.md)). | ⬜      | [Releases](https://github.com/zalando/postgres-operator/releases)     |
| **Crunchy Data Postgres Operator** | —       | Kubernetes-native operator by Crunchy Data with robust scaling, HA, and backup.                   | ⬜      | —                                                                     |
| **KubeDB PostgreSQL Operator**     | —       | Multi-database Kubernetes operator (part of KubeDB ecosystem).                                    | ⬜      | —                                                                     |
| **StackGres Postgres Operator**    | —       | Opinionated, fully managed PostgreSQL deployments with ease-of-use focus.                         | ⬜      | —                                                                     |


## Cluster Overview

Three CloudNativePG clusters (two operational + one DR), two PgDog poolers
([RFC-0018](../../../../docs/proposals/rfc/RFC-0018/)).


| Cluster              | Operator      | PostgreSQL | Namespace | HA      | Pooler                                    | Services                             |
| -------------------- | ------------- | ---------- | --------- | ------- | ----------------------------------------- | ------------------------------------ |
| platform-db          | CloudNativePG | 18.1       | platform  | 3 nodes (1 primary + 1 sync + 1 async) | PgDog v0.39 (`pgdog-platform`) | Auth, User, Notification, Shipping, Review, Temporal |
| product-db              | CloudNativePG | 18.1       | product   | 3 nodes (1 primary + 1 sync + 1 async) | PgDog v0.39 (`pgdog-product`) | Product, Cart, Order, Payment (payment app: direct-TLS) |
| product-db-replica      | CloudNativePG | 18.1       | product   | 1 node  | —                                         | DR (continuous WAL recovery)         |


## Connection Endpoints


| Cluster              | Pooler Endpoint                             | Direct Endpoint                                                              | Notes                                                   |
| -------------------- | ------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------- |
| platform-db          | `pgdog-platform.platform.svc:6432`               | RW: `platform-db-rw.platform.svc:5432`, R: `platform-db-r.platform.svc:5432`          | PgDog; DBs: auth, user, notification, shipping, review; Temporal direct to RW |
| product-db              | `pgdog-product.product.svc:6432`               | RW: `product-db-rw.product.svc:5432`, R: `product-db-r.product.svc:5432`          | PgDog with R/W splitting; DBs: product, cart, order, payment (payment app: direct-TLS) |
| product-db-replica      | —                                           | `product-db-replica-rw.product.svc:5432`                                        | DR only; promotable to standalone primary               |


## Monitoring & Backup


All CNPG clusters expose the built-in exporter on `:9187` (scraped by a
per-cluster `PodMonitor`); pgaudit + `auto_explain` logs go to stdout and are
picked up by the cluster-wide Vector DaemonSet → VictoriaLogs. Backups use the
**Barman Cloud Plugin** (per-cluster `ObjectStore`) into a single bucket
`pg-backups-cnpg` with per-cluster prefixes, and a `ScheduledBackup` (daily
02:00 + every 6h).

| Cluster              | Metrics Exporter                                                         | Log Shipper              | Backup Method       | Backup Target                                            |
| -------------------- | ------------------------------------------------------------------------ | ------------------------ | ------------------- | -------------------------------------------------------- |
| platform-db          | CNPG built-in :9187 (PodMonitor) + PgDog OpenMetrics :9090              | CNPG stdout → Vector DaemonSet | Barman Cloud Plugin + ObjectStore | `s3://pg-backups-cnpg/platform-db/`, retention 30d           |
| product-db              | CNPG built-in :9187 (PodMonitor) + PgDog OpenMetrics :9090              | CNPG stdout → Vector DaemonSet | Barman Cloud Plugin + ObjectStore | `s3://pg-backups-cnpg/product-db/`, retention 30d           |
| product-db-replica      | CNPG built-in :9187 (PodMonitor)                                        | CNPG stdout → Vector DaemonSet | Barman Cloud Plugin + ObjectStore | `s3://pg-backups-cnpg/product-db-replica/`, retention 7d    |


## Extensions

All CNPG clusters load `pgaudit`, `pg_stat_statements`, and `auto_explain` via
`shared_preload_libraries`. Per-database extensions are declared declaratively
per service in each cluster's `services/*.yaml` (RFC-0012 triplets):

`pgaudit`, `pg_stat_statements`, `auto_explain`, `pgcrypto`, `uuid-ossp`, `sync_replication_slots` (PG 18 native feature)

## Flux layout (local cluster)

| Path | Flux Kustomization | Contents |
|------|--------------------|----------|
| `controllers/databases/cnpg-barman-plugin` | `cnpg-barman-plugin-local` | Barman Cloud Plugin deployment + `ObjectStore` CRD, applied before CNPG clusters |
| `configs/databases` | `databases-local` | CNPG clusters — `platform-db`, `product-db` (+ PgDog poolers, backups, on-demand `*-initial` Backups) |
| `configs/databases-cnpg-dr` | `databases-cnpg-dr-local` | `product-db-replica` only; `dependsOn: databases-local` |

## Related Documentation

- **Database Guide:** [`docs/databases/002-database-integration.md`](../../../../docs/databases/002-database-integration.md)
- **PostgreSQL DRP:** [`docs/databases/010-drp.md`](../../../../docs/databases/010-drp.md)
- **Poolers Documentation:** [`clusters/README.md`](clusters/README.md)
- **CNPG HA/DR Deep Dive:** [`docs/databases/005-ha-dr-deep-dive.md`](../../../../docs/databases/005-ha-dr-deep-dive.md)
- **PgCat Troubleshooting (legacy):** [`docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md`](../../../../docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md)
