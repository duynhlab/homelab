# Database Configuration

This directory contains PostgreSQL database configurations organized by cluster.

## PostgreSQL Kubernetes Operators


| Operator                           | Version | Description                                                                                       | In Use | Releases                                                              |
| ---------------------------------- | ------- | ------------------------------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------- |
| **CloudNativePG**                  | v1.30.0 | Kubernetes-native operator for PostgreSQL with HA, disaster recovery, and declarative management. Now hosts **all** Postgres clusters. | ✅      | [Releases](https://github.com/cloudnative-pg/cloudnative-pg/releases) |
| **Zalando Postgres Operator**      | v1.15.1 | Patroni + Spilo operator. Previously ran `auth-db` and `supporting-shared-db`; **migrated to CloudNativePG** and no longer deployed (kept for reference in [`docs/databases/reference/zalando/operator.md`](../../../../docs/databases/reference/zalando/operator.md)). | ⬜      | [Releases](https://github.com/zalando/postgres-operator/releases)     |
| **Crunchy Data Postgres Operator** | —       | Kubernetes-native operator by Crunchy Data with robust scaling, HA, and backup.                   | ⬜      | —                                                                     |
| **KubeDB PostgreSQL Operator**     | —       | Multi-database Kubernetes operator (part of KubeDB ecosystem).                                    | ⬜      | —                                                                     |
| **StackGres Postgres Operator**    | —       | Opinionated, fully managed PostgreSQL deployments with ease-of-use focus.                         | ⬜      | —                                                                     |


## Cluster Overview

Three CloudNativePG clusters (two operational + one DR), with one CNPG
PgBouncer pooler and one PgDog pooler
([RFC-0018](../../../../docs/proposals/rfc/RFC-0018/)).


| Cluster              | Operator      | PostgreSQL | Namespace | HA      | Pooler                                    | Services                             |
| -------------------- | ------------- | ---------- | --------- | ------- | ----------------------------------------- | ------------------------------------ |
| platform-db          | CloudNativePG | 18.1       | platform  | 3 nodes (1 primary + 1 sync + 1 async) | CNPG PgBouncer `Pooler` (`platform-db-pooler-rw`, ADR-026) | User, Notification, Shipping, Review, Keycloak, Temporal |
| product-db              | CloudNativePG | 18.1       | product   | 3 nodes (1 primary + 1 sync + 1 async) | PgDog v0.39 (`pgdog-product`) | Product, Cart, Order, Checkout, Inventory, Payment (payment app: direct-TLS) |
| product-db-replica      | CloudNativePG | 18.1       | product   | 3 nodes (designated primary + 2 cascading) | —                                         | DR (continuous WAL recovery)         |


## Connection Endpoints


| Cluster              | Pooler Endpoint                             | Direct Endpoint                                                              | Notes                                                   |
| -------------------- | ------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------- |
| platform-db          | `platform-db-pooler-rw.platform.svc:5432`        | RW: `platform-db-rw.platform.svc:5432`, R: `platform-db-r.platform.svc:5432`          | PgBouncer (ADR-026, port 5432 not 6432); service DBs pooled, Temporal and Keycloak direct to RW |
| product-db              | `pgdog-product.product.svc:6432`               | RW: `product-db-rw.product.svc:5432`, R: `product-db-r.product.svc:5432`          | PgDog with R/W splitting; payment app connects direct-TLS |
| product-db-replica      | —                                           | `product-db-replica-rw.product.svc:5432`                                        | DR only; promotable to standalone primary               |


## Monitoring & Backup


All CNPG clusters expose the built-in exporter on `:9187` (scraped by a
per-cluster `PodMonitor`); pgaudit + `auto_explain` logs go to stdout and are
picked up by the cluster-wide Vector DaemonSet → VictoriaLogs. Backups use the
**Barman Cloud Plugin** (per-cluster `ObjectStore`) into a single bucket
`pg-backups-cnpg` with per-cluster prefixes. The two writable clusters run daily
02:00 + every-6h `ScheduledBackup`s; `product-db-replica` runs one daily backup
of its own (`target: primary`) so its prefix is a restorable chain and its
retention pass has something to act on. The `30d`/`7d` values are Barman
**recovery windows**, not plain retention.

| Cluster              | Metrics Exporter                                                         | Log Shipper              | Backup Method       | Backup Target                                            |
| -------------------- | ------------------------------------------------------------------------ | ------------------------ | ------------------- | -------------------------------------------------------- |
| platform-db          | CNPG built-in :9187 (PodMonitor) + PgBouncer PodMonitor              | CNPG stdout → Vector DaemonSet | Barman Cloud Plugin + ObjectStore (daily + every-6h `ScheduledBackup`) | `s3://pg-backups-cnpg/platform-db/`, recovery window 30d           |
| product-db              | CNPG built-in :9187 (PodMonitor) + PgDog OpenMetrics :9090              | CNPG stdout → Vector DaemonSet | Barman Cloud Plugin + ObjectStore (daily + every-6h `ScheduledBackup`) | `s3://pg-backups-cnpg/product-db/`, recovery window 30d           |
| product-db-replica      | CNPG built-in :9187 (PodMonitor)                                        | CNPG stdout → Vector DaemonSet | Barman Cloud Plugin + ObjectStore (daily `ScheduledBackup`, `target: primary`) | `s3://pg-backups-cnpg/product-db-replica/`, recovery window 7d    |


## Extensions

The two operational clusters load `pgaudit`, `pg_stat_statements`, and
`auto_explain` via `shared_preload_libraries`. Per-database extensions are
declared in service `Database` resources (RFC-0012 triplets):

`pgaudit`, `pg_stat_statements`, `pgcrypto`, and `uuid-ossp`. `auto_explain` is
preload-only; `sync_replication_slots` is a PostgreSQL setting, not an extension.

## Flux layout (local cluster)

| Path | Flux Kustomization | Contents |
|------|--------------------|----------|
| `controllers/databases/cnpg-barman-plugin` | `cnpg-barman-plugin-local` | Barman Cloud Plugin deployment + `ObjectStore` CRD, applied before CNPG clusters |
| `configs/databases` | `databases-local` | CNPG clusters — `platform-db`, `product-db` (+ PgBouncer/PgDog poolers, backups, on-demand `*-initial` Backups) |
| `configs/databases-cnpg-dr` | `databases-cnpg-dr-local` | `product-db-replica` only; `dependsOn: databases-local` |

## Related Documentation

- **Database Guide:** [`docs/databases/architecture.md`](../../../../docs/databases/architecture.md)
- **PostgreSQL DRP:** [`docs/databases/disaster-recovery.md`](../../../../docs/databases/disaster-recovery.md)
- **Poolers Documentation:** [`docs/databases/poolers.md`](../../../../docs/databases/poolers.md)
- **CNPG HA/DR Deep Dive:** [`docs/databases/disaster-recovery.md`](../../../../docs/databases/disaster-recovery.md)
