# Database Integration Guide
## Table of Contents

1. [Quick Summary](#quick-summary) - Clusters, poolers overview
2. [Database Architecture](#database-architecture) - 2 operational clusters + DR overview diagram + tables
3. [CloudNativePG Operator](#cloudnativepg-operator) - Operator features, per-cluster details, connection patterns, monitoring
4. [Connection Poolers](#connection-poolers) - PgBouncer + PgDog (deployed) + configuration
5. [Related Documentation](#related-documentation) - Links to other docs
6. [Troubleshooting](#troubleshooting) - Common issues and solutions

> **Migration note.** All PostgreSQL now runs on **CloudNativePG**. The Zalando
> operator (previously `auth-db` + `supporting-shared-db`) has been retired; auth,
> user, notification, shipping, review, and Temporal persistence now live on the
> consolidated **`platform-db`** cluster (RFC-0018). Zalando internals are kept
> for reference only in
> [003.2 — Zalando Operator Deep Dive](./003.2-operator-zalando.md).

> **Per-cluster details** (topology diagrams, endpoints, components): See each cluster's README in [`kubernetes/infra/configs/databases/clusters/`](../../kubernetes/infra/configs/databases/clusters/README.md)

---
## Quick Summary

| Operator                   | Version   | Cluster Name      | PostgreSQL Ver. | Nodes      | Pooler Type              | Pooler Details                    |
|----------------------------|-----------|-------------------|-----------------|------------|--------------------------|------------------------------------|
| CloudNativePG Operator     | v1.30.0   | platform-db              | 18              | 3 (HA)     | PgDog (`pgdog-platform`) | auth, user, notification, shipping, review; sync (ANY 1). Temporal connects direct (no pooler) |
| CloudNativePG Operator     | v1.30.0   | product-db               | 18              | 3 (HA)     | PgDog (`pgdog-product`)  | product, cart, order; sync (ANY 1). payment also lives here but connects direct-TLS (bypasses PgDog) |
| CloudNativePG Operator     | v1.30.0   | product-db-replica       | 18              | 1          | —                        | DR replica; object-store recovery    |
---

## Database Architecture

### Overview

All PostgreSQL runs on **CloudNativePG** (v1.30.0): **2 operational clusters** +
**1 DR replica** (**3 clusters total**) — **platform-db** (ns `platform`, auth +
supporting services + Temporal persistence), **product-db** (primary, ns `product`)
with **product-db-replica** as disaster recovery. Application traffic for
**auth**, **user**, **notification**, **shipping**, and **review** shares
**platform-db** through the **PgDog** pooler `pgdog-platform`; the **Temporal**
server connects **directly** to `platform-db-rw.platform:5432`. **product**,
**cart**, and **order** share **product-db** through **`pgdog-product`**;
**payment** also stores its `payment` database on **product-db** but connects
**directly over TLS** (see below), not through PgDog. Backups use the **Barman
Cloud Plugin** to an S3-compatible object store.

```mermaid
flowchart TB
    subgraph Operator["PostgreSQL Operator"]
        CloudNativePG["CloudNativePG Operator v1.30.0<br/>3 clusters (platform-db, product-db,<br/>product-db-replica)"]
    end

    subgraph PlatformApps["Platform services"]
        AuthSvc["Auth — ns auth"]
        UserSvc["User — ns user"]
        NotificationSvc["Notification — ns notification"]
        ShippingSvc["Shipping — ns shipping"]
        ReviewSvc["Review — ns review"]
        TemporalSvc["Temporal — ns temporal"]
    end

    subgraph ProductApps["Product services"]
        ProductSvc["Product — ns product"]
        CartSvc["Cart — ns cart"]
        OrderSvc["Order — ns order"]
        PaymentSvc["Payment — ns payment"]
    end

    subgraph Poolers["PgDog poolers"]
        PgDogPlatform["pgdog-platform<br/>auth, user, notification,<br/>shipping, review"]
        PgDogProduct["pgdog-product<br/>product, cart, order"]
    end

    subgraph Clusters["PostgreSQL Clusters (CloudNativePG, PG 18)"]
        subgraph PlatformCluster["platform-db — HA: 3 instances"]
            PlatPrimary[("Primary")]
            PlatReplica1[("Sync Replica")]
            PlatReplica2[("Async Replica")]
        end

        subgraph ProductCluster["product-db — HA: 3 instances"]
            ProductPrimary[("Primary")]
            ProductReplica1[("Sync Replica")]
            ProductReplica2[("Async Replica")]
        end

        subgraph ProductDR["product-db-replica — DR: 1 instance"]
            ProductDRNode[("Designated primary<br/>object-store recovery")]
        end
    end

    subgraph ObjectStore["Backup / DR (Barman Cloud Plugin)"]
        Bucket[("Object store WAL archive<br/>s3://pg-backups-cnpg (per-cluster prefixes)")]
    end

    subgraph ProductSvcEP["product-db Services — Auto-created"]
        ProductRW["product-db-rw — Primary Endpoint"]
        ProductR["product-db-r — Read Endpoint"]
    end

    CloudNativePG --> PlatformCluster
    CloudNativePG --> ProductCluster
    CloudNativePG --> ProductDR

    ProductRW --> ProductPrimary
    ProductR --> ProductReplica1
    ProductR --> ProductReplica2

    AuthSvc -->|via pooler| PgDogPlatform
    UserSvc -->|via pooler| PgDogPlatform
    NotificationSvc -->|via pooler| PgDogPlatform
    ShippingSvc -->|via pooler| PgDogPlatform
    ReviewSvc -->|via pooler| PgDogPlatform
    TemporalSvc -->|direct :5432| PlatPrimary
    PgDogPlatform --> PlatPrimary

    ProductSvc -->|via pooler| PgDogProduct
    CartSvc -->|via pooler| PgDogProduct
    OrderSvc -->|via pooler| PgDogProduct
    PgDogProduct --> ProductRW
    PgDogProduct --> ProductR
    PaymentSvc -->|direct TLS| ProductRW

    PlatPrimary -.->|Sync ANY 1 + async| PlatReplica1
    PlatPrimary -.->|Sync ANY 1 + async| PlatReplica2
    ProductPrimary -.->|Sync ANY 1 + async| ProductReplica1
    ProductPrimary -.->|Sync ANY 1 + async| ProductReplica2
    ProductPrimary -.->|WAL archive| Bucket
    PlatPrimary -.->|WAL archive| Bucket
    ProductDRNode -.->|Continuous recovery| Bucket
```

### Database Cluster HA Summary

All clusters run on **CloudNativePG**; every service database is provisioned by
a declarative RFC-0012 triplet (`ExternalSecret` + `DatabaseRole` + `Database`),
so credentials come from OpenBAO via ESO rather than being operator-generated.

| Cluster         | Database      | Owner        | Secret NS         | Secret Source              | Direct Connection                              | Pooler     | Instances                  | HA Pattern            | Namespace |
|----------------|--------------|--------------|-------------------|----------------------------|------------------------------------------------|------------|----------------------------|-----------------------|-----------|
| platform-db    | auth         | auth         | auth, platform    | ESO (`platform-db-secret`) | `platform-db-rw.platform:5432`                 | PgDog (`pgdog-platform`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | platform  |
| platform-db    | user         | user         | user, platform    | ESO (`platform-db-user-secret`) | `platform-db-rw.platform:5432`            | PgDog (`pgdog-platform`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | platform  |
| platform-db    | notification | notification | notification, platform | ESO (`platform-db-notification-secret`) | `platform-db-rw.platform:5432` | PgDog (`pgdog-platform`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | platform  |
| platform-db    | shipping     | shipping     | shipping, platform | ESO (`platform-db-shipping-secret`) | `platform-db-rw.platform:5432`          | PgDog (`pgdog-platform`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | platform  |
| platform-db    | review       | review       | review, platform  | ESO (`platform-db-review-secret`) | `platform-db-rw.platform:5432`            | PgDog (`pgdog-platform`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | platform  |
| platform-db    | temporal, temporal_visibility | temporal | temporal, platform | ESO (`platform-db-temporal-secret`) | `platform-db-rw.platform:5432` (direct, **not** PgDog) | — (direct) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | platform  |
| product-db     | product      | product      | product           | ESO (`product-db-secret`)  | `product-db-rw.product:5432`                   | PgDog (`pgdog-product`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | product   |
| product-db     | cart         | cart         | cart              | ESO (`product-db-cart-secret`) | `product-db-rw.product:5432`               | PgDog (`pgdog-product`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | cart      |
| product-db     | order        | order        | order             | ESO (`product-db-order-secret`) | `product-db-rw.product:5432`              | PgDog (`pgdog-product`) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | order     |
| product-db     | payment      | payment      | product + payment | ESO (`product-db-payment-secret`) | `product-db-rw.product:5432` (direct TLS, **not** PgDog) | — (direct) | 3 (1 primary + 1 sync + 1 async) | CNPG sync (ANY 1) | payment |
| product-db-replica | —        | —            | product           | —                          | —                                              | —          | 1 (DR replica)             | Object-store recovery | product   |

### Pooler Summary

| Cluster         | App Endpoint (via Pooler)              | Pooler     | Mode      | Notes                   |
|-----------------|----------------------------------------|------------|-----------|-------------------------|
| platform-db     | `pgdog-platform.platform.svc.cluster.local:6432` | PgDog | Standalone | 5 pooled DBs: auth, user, notification, shipping, review. **Temporal bypasses this pooler** — direct to `platform-db-rw` |
| product-db      | `pgdog-product.product:6432`           | PgDog      | Standalone| Single entry point for product, cart, order; R/W split to `product-db-rw` / `product-db-r`. **payment bypasses this pooler** — connects direct-TLS to `product-db-rw` |
| product-db-replica | —                                   | —          | —         | DR only; apps use primary `product-db` after promotion / failover drill |


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
| **platform-db**    | auth, user, notification, shipping, review, temporal, temporal_visibility | 3 (1 primary + 1 sync + 1 async) | Synchronous quorum (ANY 1)    |
| **product-db**     | product, cart, order, payment | 3 (1 primary + 1 sync + 1 async) | Synchronous quorum (ANY 1)    |
| **product-db-replica**| — (DR standby)           | 1                                | Continuous recovery from archive |

---
### Clusters

#### platform-db

Consolidated **CloudNativePG** cluster for **auth**, **user**, **notification**,
**shipping**, **review**, and **Temporal** persistence (RFC-0018 — merges the
former `auth-db`, `shared-db`, and `temporal-db` tiers).

- **3 instances** (1 primary + 1 sync + 1 async replica), **synchronous quorum** `ANY 1`, PostgreSQL 18 — namespace **`platform`**
- **Databases**: `auth`, `user`, `notification`, `shipping`, `review`, `temporal`, `temporal_visibility`
- **Pooler**: **PgDog** (HelmRelease `pgdog-platform`), endpoint **`pgdog-platform.platform.svc.cluster.local:6432`** — auth, user, notification, shipping, and review services use this single entry point
- **Temporal (direct, not pooled)**: the Temporal server connects **directly to `platform-db-rw.platform:5432`** (no PgDog); credentials from `platform-db-temporal-secret` (OpenBAO path `platform-db/temporal`)
- **Roles & databases**: declarative RFC-0012 triplets under `services/`; OpenBAO compat paths `auth-db/*` and `shared-db/*` for app creds (see [openbao.md](../secrets/openbao.md))
- **Backup**: Barman Cloud Plugin → `s3://pg-backups-cnpg/platform-db/`, retention 30d

> **Manifests**: [`kubernetes/infra/configs/databases/clusters/platform-db/`](../../kubernetes/infra/configs/databases/clusters/platform-db/)

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

### Features & Capabilities

**High Availability:**
- Operator-driven HA with automatic failover (< 30 seconds) via native Instance Manager
- Kubernetes API as sole coordination layer (no DCS, no Patroni, no etcd)
- Quorum-based failover available for synchronous replication clusters

**Replication:**
- **platform-db** and **product-db**: synchronous quorum (**ANY 1**) with required durability across replicas
- **product-db-replica**: standby fed from object-store WAL archive (DR)
- Logical replication slot synchronization for CDC clients where configured

**Performance Tuning:**
- Production-ready PostgreSQL parameters (memory, WAL, query planner, parallelism, autovacuum, logging)
- Optimized resource limits
- SSD-optimized settings

**Multi-Database Support:**
- **platform-db** hosts auth, supporting services, and Temporal persistence on one HA cluster
- **product-db** hosts `product`, `cart`, `order`, and `payment` on one cluster (payment connects direct-TLS, not via PgDog)
- **PgBouncer** (`platform-db-pooler-rw`) pools auth, user, notification, shipping, and review on **`platform-db`**
- **PgDog** (`pgdog-product`) provides multi-database routing and read/write splitting on **`product-db`**

### Connection Patterns

> **Deep Dive**: For detailed architecture, trade-offs, and configuration of **PgBouncer** and **PgDog**, see [`docs/databases/008-pooler.md`](./008-pooler.md).

#### PgBouncer (platform-db)

**Endpoint**: `platform-db-pooler-rw.platform.svc.cluster.local:5432`

- **Role**: CNPG-native pooler for **auth**, **user**, **notification**, **shipping**, and **review** application traffic.
- **Topology**: `type: rw` — all pooled traffic goes to **`platform-db-rw`** (no read replica split in the ADR-026 pilot).

#### PgDog (product-db)

**Endpoint**: `pgdog-product.product.svc.cluster.local:6432`

- **Role**: Pooler entry point for **product**, **cart**, and **order** application traffic.
- **Topology**: Routes writes to **`product-db-rw`**, read workload to **`product-db-r`**, per database definitions in the PgDog Helm values.
- **Pooling Mode**: `transaction` (per upstream database config).


### Configuration

**Key Configuration Parameters:**
- `instances`: **3** for **`platform-db`** and **`product-db`** (1 primary + 2 replicas); **1** for **`product-db-replica`** (DR)
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
and `supporting-shared-db`. Both were **migrated to CloudNativePG** and consolidated
into **`platform-db`** (RFC-0018); the Zalando operator is
no longer deployed. Consequently the platform no longer uses:

- **PgBouncer sidecars** — replaced by standalone **PgDog** poolers (`pgdog-platform`, `pgdog-product`).
- **Zalando-generated secrets** (`*.credentials.postgresql.acid.zalan.do`) and cross-namespace secret injection — replaced by RFC-0012 declarative triplets (OpenBAO → ESO).
- **WAL-G backups** to `pg-backups-zalando` — replaced by the **Barman Cloud Plugin** into `pg-backups-cnpg` (see [006 — Backup Strategy](./006-backup-strategy.md)).
- **Patroni/Spilo runtime** (`patronictl`, `runit`/`sv`, the operator UI).

Zalando operator internals, HA model, and operational commands are kept for
learning in [003.2 — Zalando Operator Deep Dive](./003.2-operator-zalando.md)
and the operator comparison in [003 — Operator Comparison](./003-operator-comparison.md).

---

## Connection Poolers

### Overview

Connection poolers solve the "too many connections" problem by reusing PostgreSQL connections, allowing applications to handle 1000+ client connections with only 25-50 database connections. The **deployed poolers** are **PgBouncer** on **`platform-db`** (`platform-db-pooler-rw`) and **PgDog** on **`product-db`** (`pgdog-product`). Temporal on `platform-db` and the payment app on `product-db` connect direct to the cluster RW service, bypassing the pooler.

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

| Criteria | PgBouncer | PgDog |
|----------|-----------|-------|
| **Architecture** | Single-threaded (C) | Multi-threaded (Rust) |
| **Performance (<50 conn)** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐ Very Good |
| **Performance (>50 conn)** | ⭐⭐ Degrades | ⭐⭐⭐⭐⭐ Excellent |
| **Load Balancing** | ❌ No | ✅ Yes (read replicas) |
| **Automatic Failover** | ❌ No | ✅ Yes |
| **Sharding** | ❌ No | ✅ Yes (production-grade) |
| **Monitoring** | Admin DB + PodMonitor | OpenMetrics + Admin DB |
| **Zalando Integration** | ✅ Built-in sidecar (historical) | ❌ Standalone |
| **CloudNativePG Fit** | ✅ `Pooler` CR | ✅ Standalone Helm |
| **Complexity** | ⭐⭐ Simple | ⭐⭐⭐⭐ Advanced |

### When to Use Each Pooler

**PgBouncer (deployed on platform-db):**
- CNPG-native `Pooler` CR with `type: rw` and transaction pooling
- Best fit for simple pooling without read replica routing

**Use PgDog (deployed on product-db) when:**
- ✅ **CloudNativePG** clusters without a built-in pooler (both operational clusters today)
- ✅ Multi-database routing on a shared cluster (e.g. product + cart + order on product-db)
- ✅ Read/write splitting to `-rw` / `-r` services with LSN-aware replica selection (see chart values)
- ✅ Prepared statements in transaction mode (extended protocol) where configured
- ✅ Future-proofing for advanced features (sharding, pub/sub) per project needs

### Current Implementation

#### PgBouncer (platform-db)

**Deployment:** CNPG `Pooler` CR `platform-db-pooler-rw` in namespace `platform` (see `kubernetes/infra/configs/databases/clusters/platform-db/poolers/pooler.yaml`)

**Service Endpoint:**
- `platform-db-pooler-rw.platform.svc.cluster.local:5432`

**Monitoring:** PodMonitor enabled on the `Pooler` CR

#### PgDog (product-db)

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
   pgx uses client-side prepared statements / simple protocol, fully compatible with PgBouncer and PgDog transaction pooling.

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
> For pooler-specific DSN and rotation checks, see [pgdog-operations.md](./runbooks/pgdog-operations.md).


---

## Related Documentation

- **[Backup Strategy](./006-backup-strategy.md)** - Backup architecture, retention, bucket layout
- **[Backup/Restore Runbook](./runbooks/postgres-backup-restore.md)** - Restore procedures (CNPG vs Zalando)
- **[Setup Guide](../platform/setup.md)** - Complete deployment and configuration guide
- **[Error Envelope](../api/api.md#error-envelope)** - Shared API error contract for database failures
- **[API Reference](../api/api.md)** - API endpoints using database
- **[PgDog operations](./runbooks/pgdog-operations.md)** - Day-2 pooler ops for `pgdog-product`

## Troubleshooting

### Transaction pooler + prepared statements

Applies when an app connects through a **transaction-mode pooler** (PgBouncer or PgDog) and still uses a driver that caches server-side prepared statements (for example legacy `lib/pq`).

**Problem:** Intermittent 500 errors with message `pq: bind message supplies X parameters, but prepared statement requires Y`.

**Root Cause:** The driver caches prepared statements per connection. When the pooler reuses backend connections across transactions, old prepared statements may conflict with new queries.

**Solution:** Use **pgx/v5** (platform standard) or add `prefer_simple_protocol=true` to the PostgreSQL DSN to disable prepared statements.

```go
return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s&prefer_simple_protocol=true",
    c.User, c.Password, c.Host, c.Port, c.Name, c.SSLMode,
)
```

**Why This Works:**
- `prefer_simple_protocol=true` forces simple query protocol (no prepared statement cache)
- pgx is the supported driver — see [Go PostgreSQL driver (pgx)](#go-postgresql-driver-pgx) above

**Pooler ops:** Validate DSN endpoints and chart values via [pgdog-operations.md](./runbooks/pgdog-operations.md) for `product-db`; PgBouncer settings live in the `Pooler` CR for `platform-db`.

### Zalando `CreateFailed` leaves per-service databases uncreated (historical)

> **No longer applies.** Zalando has been removed; CNPG creates databases
> declaratively via RFC-0012 triplets (`Database` CRs). Kept for reference.

**Problem:** App migrations fail with `database "…" does not exist` even though the Zalando cluster is `Running`.

**Root Cause:** The Zalando operator creates the databases from `spec.databases` only during a *successful first-time* init. On a slow spilo cold boot the operator's DB-connection retry window can expire first → the cluster goes `CreateFailed`; later syncs bring up Patroni and roles but never (re)create the databases.

**Mitigation:** See [003.2 Zalando operator deep dive](./003.2-operator-zalando.md#first-init-fragility-and-the-ensure-databases-job) and [runbooks/prepared-databases.md](./runbooks/prepared-databases.md).

---

_Last updated: 2026-07-17 — RFC-0018 platform-db consolidation: 3 CNPG clusters (platform-db, product-db, product-db-replica), 2 PgDog poolers (pgdog-platform, pgdog-product); Temporal on platform-db with Barman backups._


