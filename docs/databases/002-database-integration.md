# Database Integration Guide
## Table of Contents

1. [Quick Summary](#quick-summary) - Clusters, poolers overview
2. [Database Architecture](#database-architecture) - 4 operational clusters + DR overview diagram + tables
3. [CloudNativePG Operator](#cloudnativepg-operator) - Operator features, per-cluster details, connection patterns, monitoring
4. [Connection Poolers](#connection-poolers) - PgDog (active); PgBouncer / PgCat (comparison) + configuration
5. [Related Documentation](#related-documentation) - Links to other docs
6. [Troubleshooting](#troubleshooting) - Common issues and solutions

> **Migration note.** All PostgreSQL now runs on **CloudNativePG**. The Zalando
> operator (previously `auth-db` + `supporting-shared-db`) has been retired; its
> databases moved to the CNPG `auth-db` and `shared-db` clusters. Zalando
> internals are kept for reference only in
> [003.2 — Zalando Operator Deep Dive](./003.2-operator-zalando.md).

> **Per-cluster details** (topology diagrams, endpoints, components): See each cluster's README in [`kubernetes/infra/configs/databases/clusters/`](../../kubernetes/infra/configs/databases/clusters/README.md)

---
## Quick Summary

| Operator                   | Version   | Cluster Name      | PostgreSQL Ver. | Nodes      | Pooler Type              | Pooler Details                    |
|----------------------------|-----------|-------------------|-----------------|------------|--------------------------|------------------------------------|
| CloudNativePG Operator     | v1.30.0   | product-db               | 18              | 3 (HA)     | PgDog (`pgdog-product`)  | product, cart, order; sync (ANY 1). payment also lives here but connects direct-TLS (bypasses PgDog) |
| CloudNativePG Operator     | v1.30.0   | product-db-replica       | 18              | 1          | —                        | DR replica; object-store recovery    |
| CloudNativePG Operator     | v1.30.0   | auth-db                  | 18              | 3 (HA)     | PgDog (`pgdog-auth`)     | auth; sync (ANY 1)                   |
| CloudNativePG Operator     | v1.30.0   | shared-db                | 18              | 1          | PgDog (`pgdog-shared`)   | user, notification, shipping, review |
| CloudNativePG Operator     | v1.30.0   | temporal-db              | 18              | 1          | —                        | Temporal server backing store (namespace `temporal`); no backups / no WAL archiving |
---

## Database Architecture

### Overview

All PostgreSQL runs on **CloudNativePG** (v1.30.0): **4 operational clusters** +
**1 DR replica** (**5 clusters total**) — **product-db** (primary, ns `product`)
with **product-db-replica** as disaster recovery, **auth-db** (ns `auth`),
**shared-db** (ns `user`), and **temporal-db** (the Temporal server's backing
store, ns `temporal`). Application traffic for **product**, **cart**, and
**order** shares **product-db** through the **PgDog** pooler `pgdog-product`;
**payment** also stores its `payment` database on **product-db** but connects
**directly over TLS** (see below), not through PgDog. **auth** uses the
`pgdog-auth` pooler; **user/notification/shipping/review** share **shared-db**
via the `pgdog-shared` pooler. Backups use the **Barman Cloud Plugin** to an
S3-compatible object store.

```mermaid
flowchart TB
    subgraph Operator["PostgreSQL Operator"]
        CloudNativePG["CloudNativePG Operator v1.30.0<br/>5 clusters (product-db, product-db-replica,<br/>auth-db, shared-db, temporal-db)"]
    end

    subgraph Services["Microservices by Namespace"]
        AuthSvc["Auth Service - namespace: auth"]
        ProductSvc["Product Service - namespace: product"]
        CartSvc["Cart Service - namespace: cart"]
        OrderSvc["Order Service - namespace: order"]
        PaymentSvc["Payment Service - namespace: payment"]
        ReviewSvc["Review Service - namespace: review"]
        UserSvc["User Service - namespace: user"]
        NotificationSvc["Notification Service - namespace: notification"]
        ShippingSvc["Shipping Service - namespace: shipping"]
    end

    subgraph Poolers["PgDog Poolers"]
        PgDogAuth["pgdog-auth"]
        PgDogShared["pgdog-shared"]
        PgDogProduct["pgdog-product<br/>product, cart, order"]
    end

    subgraph Clusters["PostgreSQL Clusters (CloudNativePG, PG 18)"]
        subgraph ProductCluster["product-db - HA: 3 instances"]
            ProductPrimary[("Primary")]
            ProductReplica1[("Sync Replica")]
            ProductReplica2[("Async Replica")]
        end

        subgraph ProductDR["product-db-replica - DR: 1 instance"]
            ProductDRNode[("Designated primary<br/>object-store recovery")]
        end

        subgraph AuthCluster["auth-db - HA: 3 instances"]
            AuthPrimary[("Primary")]
            AuthReplica1[("Sync Replica")]
            AuthReplica2[("Async Replica")]
        end

        SharedDB[("shared-db - 1 instance<br/>DBs: user, notification, shipping, review")]
        TemporalDB[("temporal-db - 1 instance<br/>DBs: temporal, temporal_visibility")]
    end

    subgraph ObjectStore["Backup / DR (Barman Cloud Plugin)"]
        Bucket[("Object store WAL archive<br/>s3://pg-backups-cnpg (per-cluster prefixes)")]
    end

    subgraph ProductSvcEP["product-db Services - Auto-created"]
        ProductRW["product-db-rw - Primary Endpoint"]
        ProductR["product-db-r - Read Endpoint"]
    end

    CloudNativePG --> ProductCluster
    CloudNativePG --> ProductDR
    CloudNativePG --> AuthCluster
    CloudNativePG --> SharedDB
    CloudNativePG --> TemporalDB

    ProductRW --> ProductPrimary
    ProductR --> ProductReplica1
    ProductR --> ProductReplica2

    AuthSvc -->|via pooler| PgDogAuth
    PgDogAuth --> AuthPrimary
    ProductSvc -->|via pooler| PgDogProduct
    CartSvc -->|via pooler| PgDogProduct
    OrderSvc -->|via pooler| PgDogProduct
    PgDogProduct --> ProductRW
    PgDogProduct --> ProductR
    PaymentSvc -->|direct TLS| ProductRW
    ReviewSvc -->|via pooler| PgDogShared
    UserSvc -->|via pooler| PgDogShared
    NotificationSvc -->|via pooler| PgDogShared
    ShippingSvc -->|via pooler| PgDogShared
    PgDogShared --> SharedDB

    AuthPrimary -.->|Sync ANY 1 + async| AuthReplica1
    AuthPrimary -.->|Sync ANY 1 + async| AuthReplica2
    ProductPrimary -.->|Sync ANY 1 + async| ProductReplica1
    ProductPrimary -.->|Sync ANY 1 + async| ProductReplica2
    ProductPrimary -.->|WAL archive| Bucket
    ProductDRNode -.->|Continuous recovery| Bucket
```

### Database Cluster HA Summary

All clusters run on **CloudNativePG**; every service database is provisioned by
a declarative RFC-0012 triplet (`ExternalSecret` + `DatabaseRole` + `Database`),
so credentials come from OpenBAO via ESO rather than being operator-generated.

| Cluster         | Database      | Owner        | Secret NS         | Secret Source              | Direct Connection                              | Pooler     | Instances                  | HA Pattern            | Namespace |
|----------------|--------------|--------------|-------------------|----------------------------|------------------------------------------------|------------|----------------------------|-----------------------|-----------|
| product-db     | product      | product      | product           | ESO (`product-db-secret`)  | `product-db-rw.product:5432`                   | PgDog (`pgdog-product`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | product   |
| product-db     | cart         | cart         | cart              | ESO (`product-db-cart-secret`) | `product-db-rw.product:5432`               | PgDog (`pgdog-product`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | cart      |
| product-db     | order        | order        | order             | ESO (`product-db-order-secret`) | `product-db-rw.product:5432`              | PgDog (`pgdog-product`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | order     |
| product-db     | payment      | payment      | product + payment | ESO (`product-db-payment-secret`) | `product-db-rw.product:5432` (direct TLS, **not** PgDog) | — (direct) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | payment |
| product-db-replica | —        | —            | product           | —                          | —                                              | —          | 1 (DR replica)             | Object-store recovery | product   |
| auth-db        | auth         | auth         | auth              | ESO (`auth-db-secret`)     | `auth-db-rw.auth:5432`                         | PgDog (`pgdog-auth`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | auth      |
| shared-db      | user         | user         | user              | ESO (`shared-db-secret`)   | `shared-db-rw.user:5432`                       | PgDog (`pgdog-shared`) | 1 (single instance)      | Single (no HA)        | user      |
| shared-db      | notification | notification | notification      | ESO (`shared-db-notification-secret`) | `shared-db-rw.user:5432`            | PgDog (`pgdog-shared`) | 1 (single instance)      | Single (no HA)        | user      |
| shared-db      | shipping     | shipping     | shipping          | ESO (`shared-db-shipping-secret`) | `shared-db-rw.user:5432`                | PgDog (`pgdog-shared`) | 1 (single instance)      | Single (no HA)        | user      |
| shared-db      | review       | review       | review            | ESO (`shared-db-review-secret`) | `shared-db-rw.user:5432`                  | PgDog (`pgdog-shared`) | 1 (single instance)      | Single (no HA)        | user      |
| temporal-db    | temporal, temporal_visibility | temporal | temporal    | Auto (CNPG `temporal-db-app`) | `temporal-db-rw.temporal:5432`              | — (direct) | 1 (single instance)        | Single (no HA)        | temporal  |

### Pooler Summary

| Cluster         | App Endpoint (via Pooler)              | Pooler     | Mode      | Notes                   |
|-----------------|----------------------------------------|------------|-----------|-------------------------|
| product-db      | `pgdog-product.product:6432`           | PgDog      | Standalone| Single entry point for product, cart, order; R/W split to `product-db-rw` / `product-db-r`. **payment bypasses this pooler** — connects direct-TLS to `product-db-rw` |
| product-db-replica | —                                   | —          | —         | DR only; apps use primary `product-db` after promotion / failover drill |
| auth-db         | `pgdog-auth.auth:6432`                 | PgDog      | Standalone| DB: auth                |
| shared-db       | `pgdog-shared.user:6432`               | PgDog      | Standalone| 4 databases: user, notification, shipping, review |
| temporal-db     | —                                      | —          | —         | Temporal server connects directly; no pooler tier |


---

## CloudNativePG Operator

### Overview

**CloudNativePG Operator** (v1.30.0) is a Kubernetes-native operator for PostgreSQL with its own built-in Instance Manager for high availability. It does **not** use Patroni -- the operator itself handles failover, promotion, and lifecycle management through the Kubernetes API.

**Key Features:**
- Kubernetes-native CRDs for cluster management
- Operator-driven HA with automatic failover (< 30 seconds) via Instance Manager
- PostgreSQL 18 (default image)
- Built-in `postgres_exporter` sidecar for metrics
- Support for synchronous replication
- Logical replication slot synchronization
- Production-ready performance tuning

| Cluster            | Database(s)                 | Instances                       | Replication Type              |
|--------------------|-----------------------------|----------------------------------|-------------------------------|
| **product-db**     | product, cart, order, payment | 3 (1 primary + 1 sync + 1 async) | Synchronous quorum (ANY 1)    |
| **product-db-replica**| — (DR standby)           | 1                                | Continuous recovery from archive |
| **auth-db**        | auth                        | 3 (1 primary + 1 sync + 1 async) | Synchronous quorum (ANY 1)    |
| **shared-db**      | user, notification, shipping, review | 1                       | Single instance (no HA)       |
| **temporal-db**    | temporal, temporal_visibility (Temporal backing store) | 1    | Single instance (no HA / no backups) |

---
### Clusters

#### product-db

Consolidated **CloudNativePG** cluster for **product**, **cart**, and **order** (replaces the former split of separate CNPG clusters for catalog vs checkout).

- **3 instances** (1 primary + 2 replicas), **synchronous quorum** `ANY 1` with required durability (see cluster `spec.postgresql.synchronous` in manifests)
- **Databases**: `product`, `cart`, `order`, `payment` on the same cluster; cluster lives in namespace **`product`**
- **Pooler**: **PgDog** (HelmRelease `pgdog-product`), unified endpoint **`pgdog-product.product:6432`** — product, cart, and order services use this single entry point; PgDog routes writes to `product-db-rw` and read traffic to `product-db-r` per pool/database config
- **payment (direct TLS, not pooled)**: the `payment` database also lives on `product-db`, but payment-service connects **directly to `product-db-rw.product:5432` over TLS** (`sslmode=require`; CNPG serves its own certs). Its config refuses cleartext DB and PgDog terminates no TLS yet, so payment bypasses the pooler. PgDog already carries payment backend entries — move payment behind the pooler once PgDog TLS lands. Its credentials come from `product-db-payment-secret` (present in both the `product` and `payment` namespaces).
- **Extensions**: preloaded via `shared_preload_libraries` — pgaudit, pg_stat_statements, auto_explain; created via the `Database` CR in each service triplet — pgaudit, pg_stat_statements, pgcrypto, uuid-ossp (product), pgaudit, pg_stat_statements (cart, order, payment). auto_explain is preload-only (no SQL control file), so it is never in a Database resource.
- **Roles & databases**: declarative per-service triplets under `services/` — see [012 — Declarative Role & Database Management](./012-declarative-role-management.md)
- **Features**: Logical replication slot sync for CDC (Debezium, Kafka Connect) where enabled

> **Manifests, backup, pooler**: [`kubernetes/infra/configs/databases/clusters/product-db/`](../../kubernetes/infra/configs/databases/clusters/product-db/)

#### product-db-replica

- **1 instance**, DR replica cluster continuously recovering from **`product-db`** WAL in object storage (not an application pooler target in steady state)
- **Namespace**: `product`

> **DR replica manifests**: [`kubernetes/infra/configs/databases/clusters/product-db-replica/`](../../kubernetes/infra/configs/databases/clusters/product-db-replica/)

**Note on HA Architecture:**
- CloudNativePG does **not** use Patroni. It has its own native [Instance Manager](https://cloudnative-pg.io/docs/1.28/instance_manager/) that handles failover and lifecycle.
- The operator uses Kubernetes API as the sole coordination layer -- no DCS, no etcd required.
- For a conceptual comparison with Zalando's Patroni-based HA, see [Operator Comparison](./003-operator-comparison.md).

#### auth-db

- **3 instances** (1 primary + 1 sync + 1 async replica), **synchronous quorum** `ANY 1`, PostgreSQL 18 — migrated from the former Zalando `auth-db`.
- **Database**: `auth`; cluster lives in namespace **`auth`**
- **Pooler**: **PgDog** (HelmRelease `pgdog-auth`), endpoint **`pgdog-auth.auth:6432`**
- **Roles & databases**: declarative RFC-0012 triplet under `services/` (initdb-reuse — the `auth` role/database created by `bootstrap.initdb` is adopted by the triplet)
- **Backup**: Barman Cloud Plugin → `s3://pg-backups-cnpg/auth-db/`, retention 30d

> **Manifests**: [`kubernetes/infra/configs/databases/clusters/auth-db/`](../../kubernetes/infra/configs/databases/clusters/auth-db/)

#### shared-db

- **1 instance** (single, no HA), PostgreSQL 18 — migrated from the former Zalando `supporting-shared-db`.
- **Databases**: `user`, `notification`, `shipping`, `review` (shared-database pattern); cluster lives in namespace **`user`**
- **Pooler**: **PgDog** (HelmRelease `pgdog-shared`), endpoint **`pgdog-shared.user:6432`**
- **Roles & databases**: declarative RFC-0012 triplets under `services/` (`user` is an initdb-reuse triplet; notification/shipping/review are normal triplets with cross-namespace `ExternalSecret`s)
- **Backup**: Barman Cloud Plugin → `s3://pg-backups-cnpg/shared-db/`, retention 30d

> **Manifests**: [`kubernetes/infra/configs/databases/clusters/shared-db/`](../../kubernetes/infra/configs/databases/clusters/shared-db/)

#### temporal-db

- **1 instance** (single, no HA), PostgreSQL 18, namespace **`temporal`**
- **Databases**: `temporal` (via `bootstrap.initdb`) + `temporal_visibility` (via `postInitSQL`)
- **No pooler and no backup** — the Temporal server connects directly to `temporal-db-rw.temporal:5432`.

> **Manifests**: [`kubernetes/infra/configs/databases/clusters/temporal-db/`](../../kubernetes/infra/configs/databases/clusters/temporal-db/)

### Features & Capabilities

**High Availability:**
- Operator-driven HA with automatic failover (< 30 seconds) via native Instance Manager
- Kubernetes API as sole coordination layer (no DCS, no Patroni, no etcd)
- Quorum-based failover available for synchronous replication clusters

**Replication:**
- **product-db**: synchronous quorum (**ANY 1**) with required durability across replicas; third replica may follow asynchronously per operator behavior
- **product-db-replica**: standby fed from object-store WAL archive (DR)
- Logical replication slot synchronization for CDC clients where configured

**Performance Tuning:**
- Production-ready PostgreSQL parameters (memory, WAL, query planner, parallelism, autovacuum, logging)
- Optimized resource limits
- SSD-optimized settings

**Multi-Database Support:**
- **product-db** hosts `product`, `cart`, `order`, and `payment` on one cluster (payment connects direct-TLS, not via PgDog)
- **PgDog** provides multi-database routing and read/write splitting to CNPG `-rw` / `-r` services (replaces the former **PgCat** deployment for cart/order in active GitOps)

### Connection Patterns

> **Deep Dive**: For detailed architecture, trade-offs, and configuration of **PgDog**, **PgBouncer**, and **PgCat** (comparison / legacy), see [`docs/databases/008-pooler.md`](./008-pooler.md).

#### PgDog (unified pooler for product-db)

**Endpoint**: `pgdog-product.product:6432` (short form inside cluster: `pgdog-product.product.svc.cluster.local:6432`)

- **Role**: Single pooler entry point for **product**, **cart**, and **order** application traffic.
- **Topology**: Routes writes to **`product-db-rw`**, read workload to **`product-db-r`**, per database definitions in the PgDog Helm values.
- **Pooling Mode**: `transaction` (per upstream database config).

**Historical note:** Cart and order previously used a standalone **PgCat** service (`pgcat.cart`); that path is no longer the documented active stack for CNPG — see [Connection Poolers](#connection-poolers) for comparison context.


### Configuration

**Key Configuration Parameters:**
- `instances`: **3** for **`product-db`** (1 primary + 2 replicas); **1** for **`product-db-replica`** (DR)
- `postgresql.parameters`: PostgreSQL configuration parameters
- `postgresql.synchronous`: Synchronous replication settings on **`product-db`** (e.g. `method: any`, `number: 1`)
- `replicationSlots.highAvailability.synchronizeLogicalDecoding`: Logical replication slot sync
- `resources`: CPU and memory limits
- `storage.size`: Persistent volume size

**Role, Database & Secret Management (RFC-0012):**
- Every service database is a **per-service triplet** — `ExternalSecret` +
  `DatabaseRole` + `Database` in one file under
  `clusters/product-db/services/<name>.yaml` ([ADR-013](../proposals/adr/ADR-013-per-service-db-triplet/))
- Credentials flow OpenBAO → ESO → `kubernetes.io/basic-auth` Secret
  (`cnpg.io/reload: "true"`); no credential exists in any manifest, and the
  PgDog pooler receives passwords via Flux `valuesFrom`
  ([ADR-014](../proposals/adr/ADR-014-pooler-credentials-valuesfrom/))
- `bootstrap.initdb` in `instance.yaml` is a structural placeholder (product);
  the product triplet adopts it — from-scratch builds and restores converge
- Concepts and semantics: [012 — Declarative Role & Database Management](./012-declarative-role-management.md);
  recipes: [add a service database](./runbooks/add-service-database.md),
  [rotate a password](./runbooks/rotate-cnpg-service-password.md)

### Monitoring

#### PodMonitor Setup

CloudNativePG clusters use **PodMonitor** CRDs to enable Prometheus scraping of `postgres_exporter` sidecars.

**Key Elements:**
- **Selector**: Matches pods with label `cnpg.io/cluster: <cluster>` (e.g. `product-db`, `product-db-replica`) per `PodMonitor`
- **Port**: `metrics` (exposed by postgres_exporter sidecar)
- **Interval**: 15s scrape interval
- **Labels**: Captures cluster, role (primary/replica), instance name

**Key Metrics:**
- `pg_up` - Database availability
- `pg_stat_database_*` - Database statistics
- `pg_stat_activity_*` - Active connections
- `pg_replication_*` - Replication lag

---
## Zalando Postgres Operator (retired)

The platform previously ran two Zalando (Patroni/Spilo) clusters — `auth-db`
and `supporting-shared-db`. Both were **migrated to CloudNativePG** (now the
`auth-db` and `shared-db` clusters described above) and the Zalando operator is
no longer deployed. Consequently the platform no longer uses:

- **PgBouncer sidecars** — replaced by standalone **PgDog** poolers (`pgdog-auth`, `pgdog-shared`, `pgdog-product`).
- **Zalando-generated secrets** (`*.credentials.postgresql.acid.zalan.do`) and cross-namespace secret injection — replaced by RFC-0012 declarative triplets (OpenBAO → ESO).
- **WAL-G backups** to `pg-backups-zalando` — replaced by the **Barman Cloud Plugin** into `pg-backups-cnpg` (see [006 — Backup Strategy](./006-backup-strategy.md)).
- **Patroni/Spilo runtime** (`patronictl`, `runit`/`sv`, the operator UI).

Zalando operator internals, HA model, and operational commands are kept for
learning in [003.2 — Zalando Operator Deep Dive](./003.2-operator-zalando.md)
and the operator comparison in [003 — Operator Comparison](./003-operator-comparison.md).

---

## Connection Poolers

### Overview

Connection poolers solve the "too many connections" problem by reusing PostgreSQL connections, allowing applications to handle 1000+ client connections with only 25-50 database connections. The **only pooler deployed** in this repo is **PgDog** — three standalone Helm releases: `pgdog-product` (product-db: product, cart, order — the payment app connects direct-TLS past it), `pgdog-auth` (auth-db), and `pgdog-shared` (shared-db). **PgBouncer** (previously the Zalando sidecar) and **PgCat** (previously used for cart/order) appear below only for **comparison** — neither is deployed anymore.

**Why Use Connection Poolers?**
- PostgreSQL has limited connections (`max_connections` typically 100-200)
- Each connection consumes ~10MB memory
- Opening/closing connections is expensive (network overhead)
- High connection churn causes performance degradation

**Benefits:**
- ✅ **Reduce Connection Overhead**: Reuse connections instead of creating new ones
- ✅ **Lower Memory Usage**: Fewer PostgreSQL connections = less memory
- ✅ **Better Performance**: Faster connection establishment (from pool)
- ✅ **Connection Limits**: Handle 1000+ client connections with 25-50 PostgreSQL connections

### Comparison Matrix

| Criteria | PgBouncer | PgCat | PgDog |
|----------|-----------|-------|-------|
| **Architecture** | Single-threaded (C) | Multi-threaded (Rust) | Multi-threaded (Rust) |
| **Performance (<50 conn)** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐ Very Good | ⭐⭐⭐⭐ Very Good |
| **Performance (>50 conn)** | ⭐⭐ Degrades | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐⭐ Excellent |
| **Load Balancing** | ❌ No | ✅ Yes (read replicas) | ✅ Yes (multiple strategies) |
| **Automatic Failover** | ❌ No | ✅ Yes | ✅ Yes |
| **Sharding** | ❌ No | ✅ Yes (experimental) | ✅ Yes (production-grade) |
| **Monitoring** | Admin DB only | Prometheus + Admin DB | OpenMetrics + Admin DB |
| **Zalando Integration** | ✅ Built-in sidecar | ❌ Standalone | ❌ Standalone |
| **CloudNativePG Fit** | ❌ No built-in | ✅ Standalone | ✅ Standalone |
| **Complexity** | ⭐⭐ Simple | ⭐⭐⭐ Moderate | ⭐⭐⭐⭐ Advanced |

### When to Use Each Pooler

**PgBouncer (comparison only — no longer deployed):**
- Best fit for low-to-medium connection counts (<50 concurrent) and simple pooling needs (no load balancing, sharding)
- Was the built-in Zalando sidecar before the CNPG migration

**PgCat (comparison only — no longer deployed):**
- A Rust pooler with read-replica load balancing and multi-database routing
- Previously fronted cart/order against CNPG

**Use PgDog (the deployed pooler) when:**
- ✅ **CloudNativePG** clusters without a built-in pooler (all three clusters today)
- ✅ Multi-database routing on a shared cluster (e.g. product + cart + order on product-db)
- ✅ Read/write splitting to `-rw` / `-r` services with LSN-aware replica selection (see chart values)
- ✅ Prepared statements in transaction mode (extended protocol) where configured
- ✅ Future-proofing for advanced features (sharding, pub/sub) per project needs

### Current Implementation

PgDog runs as three standalone Helm releases — `pgdog-product` (ns `product`),
`pgdog-auth` (ns `auth`), and `pgdog-shared` (ns `user`) — all on the same
chart, port `6432`, OpenMetrics `9090`. The `pgdog-product` release is detailed
below; `pgdog-auth` and `pgdog-shared` follow the same shape for their
respective databases.

#### PgDog (product-db — product, cart, order, payment)

**Deployment:** Helm chart (`helm.pgdog.dev/pgdog`) via Flux HelmRelease `pgdog-product` in namespace `product`

**Key Configuration (see `kubernetes/infra/configs/databases/clusters/product-db/poolers/helmrelease.yaml`):**
- **replicas**: 3 (PDB `minAvailable: 2`)
- **port**: 6432 (PostgreSQL protocol)
- **openMetricsPort**: 9090 (Prometheus metrics)
- **Databases**: `product`, `cart`, `order`, `payment` — each with `poolMode: transaction`, `poolSize`, and replica hosts pointing at `product-db-r` / primary at `product-db-rw` (the payment *app* connects direct-TLS to `product-db-rw:5432`, bypassing the pooler)

**Service Endpoint:**
- `pgdog-product.product.svc.cluster.local:6432`

**Monitoring:**
- OpenMetrics: Port 9090 (`/metrics` endpoint)
- ServiceMonitor: Enabled in Helm values when configured

**Why PgDog for product-db:**
- CloudNativePG has no first-party pooler; one chart fronts all three app databases
- Read/write splitting and replica awareness without running separate pooler stacks per workload
- Aligns with consolidated cluster topology (single CNPG cluster + single pooler tier)

## Go PostgreSQL driver (pgx)

All microservices use **pgx/v5** as the PostgreSQL driver.

**Driver Comparison:**

| Feature | lib/pq | pgx/v5 |
|---------|--------|--------|
| GitHub Stars | 9.8k | 13.2k |
| Maintenance | Maintenance mode (since 2023) | Actively maintained |
| Prepared Statements | Server-side (cached on PostgreSQL) | Client-side / Simple protocol |
| Connection Pooling | Manual (`sql.DB` config) | Built-in (`pgxpool`) |
| Binary Protocol | Limited | Full support |
| PostgreSQL Types | Basic | Extended (JSONB, arrays, hstore) |
| Performance | Good | Better (native binary protocol) |

**Why pgx Instead of lib/pq?**

1. **Connection Pooler Compatibility**: lib/pq uses server-side prepared statements which cause errors with transaction pooling:
   ```
   pq: bind message supplies 1 parameters, but prepared statement "" requires 2
   ```
   pgx uses client-side prepared statements / simple protocol, fully compatible with PgCat/PgBouncer.

2. **Active Development**: pgx is actively maintained with regular updates, while lib/pq is in maintenance mode since 2023.

3. **Better Performance**: pgx implements PostgreSQL's binary protocol natively.

4. **Native Connection Pool**: `pgxpool.Pool` is designed for PostgreSQL, providing better control than `sql.DB` generic pool.

**Code Example:**

```go
import (
    "context"
    "github.com/jackc/pgx/v5/pgxpool"
)

func Connect(ctx context.Context) (*pgxpool.Pool, error) {
    dsn := "postgresql://user:pass@host:5432/db?sslmode=disable&pool_max_conns=25"
    return pgxpool.New(ctx, dsn)
}
```

> [!NOTE]
> See [pgcat_prepared_statement_error.md](../runbooks/troubleshooting/pgcat_prepared_statement_error.md) for detailed troubleshooting.


---

## Related Documentation

- **[Backup Strategy](./006-backup-strategy.md)** - Backup architecture, retention, bucket layout
- **[Backup/Restore Runbook](../runbooks/troubleshooting/postgres_backup_restore.md)** - Restore procedures (CNPG vs Zalando)
- **[Setup Guide](../platform/setup.md)** - Complete deployment and configuration guide
- **[Error Handling](../api/api.md#error-handling)** - Database error handling patterns
- **[API Reference](../api/api.md)** - API endpoints using database
- **[PgCat Prepared Statement Error](../runbooks/troubleshooting/pgcat_prepared_statement_error.md)** - Legacy: intermittent 500 errors when fronting PostgreSQL with **PgCat** in transaction mode

## Troubleshooting

### PgCat + Prepared Statements Issue (legacy pooler)

Applies when applications connect through **PgCat** in transaction pooling mode. **Current `product-db` traffic uses PgDog** (`pgdog-product`), which is configured for extended/prepared statement behavior in chart values — treat this section as historical unless you still run PgCat.

**Problem:** Intermittent 500 errors with message `pq: bind message supplies X parameters, but prepared statement requires Y` when using PgCat in transaction pooling mode.

**Root Cause:** Go's `database/sql` driver caches prepared statements per connection. When PgCat reuses connections across transactions, old prepared statements may conflict with new queries.

**Solution:** Add `prefer_simple_protocol=true` to PostgreSQL DSN to disable prepared statements completely.

```go
// cart-service/internal/core/database.go
// order-service/internal/core/database.go
return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s&prefer_simple_protocol=true",
    c.User, c.Password, c.Host, c.Port, c.Name, c.SSLMode,
)
```

**Why This Works:**
- `binary_parameters=yes` only disables binary encoding but **still uses prepared statements** (insufficient)
- `prefer_simple_protocol=true` forces the driver to use simple query protocol (no prepared statements)
- Simple protocol sends query + parameters in one message (no caching, no reuse conflicts)

**Affected services (legacy):** Cart, Order when routed via **PgCat**; with **PgDog** as the unified pooler for **`product-db`**, prefer validating DSN and pooler settings against `pgdog-product` instead.

**See:** [Full troubleshooting guide](../runbooks/troubleshooting/pgcat_prepared_statement_error.md) with diagrams and testing instructions.

### Zalando `CreateFailed` leaves per-service databases uncreated (historical)

> **No longer applies.** Zalando has been removed; CNPG creates databases
> declaratively via RFC-0012 triplets (`Database` CRs). Kept for reference.

**Problem:** App migrations fail with `database "…" does not exist` even though the Zalando cluster is `Running`.

**Root Cause:** The Zalando operator creates the databases from `spec.databases` only during a *successful first-time* init. On a slow spilo cold boot the operator's DB-connection retry window can expire first → the cluster goes `CreateFailed`; later syncs bring up Patroni and roles but never (re)create the databases.

**Mitigation:** See [003.2 Zalando operator deep dive](./003.2-operator-zalando.md#first-init-fragility-and-the-ensure-databases-job) and [runbooks/prepared-databases.md](./runbooks/prepared-databases.md).

---

_Last updated: 2026-07-11 — Reflect Zalando→CloudNativePG migration: all clusters (product-db, product-db-replica, auth-db, shared-db, temporal-db) on CNPG with PgDog poolers and Barman backups._


