# PostgreSQL Clusters

## Cluster Summary

| Cluster | Operator | Namespace | Instances | Replication | Pooler | Pooler Endpoint | Direct Endpoint |
|---------|----------|-----------|-----------|-------------|--------|-----------------|-----------------|
| **platform-db** | CloudNativePG | platform | 3 (1 Primary + 1 Sync + 1 Async Replica) | Sync (ANY 1) | PgDog (`pgdog-platform`) | `pgdog-platform.platform.svc:6432` | `platform-db-rw.platform.svc:5432` |
| **product-db** | CloudNativePG | product | 3 (1 Primary + 1 Sync + 1 Async Replica) | Sync (ANY 1) | PgDog (`pgdog-product`) | `pgdog-product.product.svc:6432` | `product-db-rw.product.svc:5432` |
| **product-db-replica** | CloudNativePG | product | 1 (Designated Primary) | WAL recovery from object store | — | — | `product-db-replica-rw.product.svc:5432` |

---

## Detailed Cluster Documentation

For detailed architecture, configuration, and components of each cluster, please refer to their respective directories:

- **[platform-db](platform-db/)**: Consolidated CNPG cluster (RFC-0018) hosting Auth, User, Notification, Shipping, Review, and Temporal databases. 3-instance HA with PgDog pooler, Barman backup, and monitoring. Temporal connects direct to `platform-db-rw` (no pooler).
- **[product-db](product-db/)**: Consolidated CNPG cluster hosting Product, Cart, Order, Checkout, and Payment databases (payment app connects direct-TLS). Includes PgDog pooler, backup, and monitoring.
- **[product-db-replica](product-db-replica/)**: DR replica cluster; continuously recovers from product-db WAL archive. Promotable to standalone primary. Deployed via Flux **`configs/databases-cnpg-dr`** (`databases-cnpg-dr-local` depends on `databases-local`).

### DR replica troubleshooting

See **[PostgreSQL DRP](../../../../../docs/databases/010-drp.md)** for the
recovery decision flow and DR promotion controls, and
**[HA and DR Architecture Deep-Dive](../../../../../docs/databases/005-ha-dr-deep-dive.md)**
for CNPG recovery internals.

---

## Connection Pooler Comparison

**PgBouncer** (`platform-db-pooler-rw`) and **PgDog** (`pgdog-product`) are the deployed poolers.

| Feature | PgBouncer | PgDog |
|---------|-----------|-------|
| **Architecture** | Single-threaded (C) | Multi-threaded (Rust) |
| **Deployment** | CNPG `Pooler` CR | Helm chart |
| **Read/Write Splitting** | No (pilot: `type: rw`) | Yes (configurable) |
| **Load Balancing** | No | Yes |
| **Multi-Database** | Limited | Yes |
| **Sharding** | No | Production-grade |
| **Monitoring** | PodMonitor | OpenMetrics + Admin DB |
| **SSL Requirement** | Required | Optional |

---

## Explore Internal Cluster PostgreSQL

This section uses **product-db** as a learning vehicle to understand PostgreSQL internals. The same concepts apply whether PostgreSQL runs on Kubernetes (CloudNativePG) or VMs (EC2).

### product-db Topology (Current Configuration)

| Component | Endpoint | Port | Role |
|-----------|----------|------|------|
| **PgDog Pooler** | `pgdog-product.product.svc.cluster.local` | 6432 | Connection pooling, R/W splitting (product, cart, order, payment) |
| **CNPG RW Service** | `product-db-rw.product.svc.cluster.local` | 5432 | Write queries (auto-routes to primary) |
| **CNPG R Service** | `product-db-r.product.svc.cluster.local` | 5432 | Read queries (load-balanced replicas) |
| **CNPG RO Service** | `product-db-ro.product.svc.cluster.local` | 5432 | Read-only (any instance) |
| **Cluster** | 3 instances | - | 1 Primary + 1 Sync Replica + 1 Async Replica |

```mermaid
flowchart LR
    subgraph App["Application Layer"]
        Driver["Go Driver - database/sql"]
    end

    subgraph Pooler["Connection Pooler"]
        PgDog{{"🟣 PgDog<br/>pgdog-product:6432"}}
    end

    subgraph CNPG["CloudNativePG Services"]
        RW["product-db-rw:5432"]
        R["product-db-r:5432"]
    end

    subgraph Cluster["product-db Cluster"]
        Primary[("🔴 Primary")]
        Replica1[("🟢 Replica 1")]
        Replica2[("🟢 Replica 2")]
    end

    Driver --> PgDog
    PgDog --> RW
    PgDog -->|"read routing"| R
    RW --> Primary
    R --> Replica1
    R --> Replica2
    Primary -->|"sync WAL streaming"| Replica1
    Primary -->|"async WAL streaming"| Replica2
    
    style Primary fill:#E53935,color:#fff
    style Replica1 fill:#66BB6A
    style Replica2 fill:#66BB6A
    style PgDog fill:#7E57C2,color:#fff
```

### INSERT/UPDATE in 10 Steps (Preview)

When a Product Service calls `INSERT INTO products (name, price) VALUES ('Widget', 99.99)`:

| Step | Component | What Happens |
|------|-----------|--------------|
| 1 | **Go Driver** | Sends SQL over TCP to PgDog |
| 2 | **PgDog** | Picks a pooled connection, forwards to `product-db-rw` |
| 3 | **Backend Process** | PostgreSQL spawns/reuses a backend process for this connection |
| 4 | **Parser** | Validates SQL syntax, builds parse tree |
| 5 | **Planner** | Creates execution plan (trivial for INSERT) |
| 6 | **Executor** | Begins transaction, acquires locks |
| 7 | **MVCC** | Assigns `xmin` (transaction ID), creates new tuple version |
| 8 | **Buffer Manager** | Loads target heap page into **Shared Buffers**, marks dirty |
| 9 | **WAL Writer** | Writes change to **WAL Buffers**, then to WAL segment on disk |
| 10 | **Commit** | `fsync` WAL to disk, return success to client |

**After commit (async):**
- **Background Writer**: Gradually flushes dirty pages from Shared Buffers to data files
- **Checkpointer**: Periodically forces all dirty pages to disk (recovery point)
- **WAL Sender**: Ships WAL to replicas for replay

### Deep Dive Documentation

For full explanations with detailed diagrams, tables, and EC2/VM mapping, see:

**[PostgreSQL Internals Deep Dive (product-db)](../../../../../docs/databases/001-postgresql-internals.md)**

Topics covered:
- INSERT/UPDATE workflow with sequence diagrams
- Shared Buffers and Buffer Manager
- WAL (Write-Ahead Log) and crash recovery
- MVCC, tuple versioning, and visibility
- Streaming Replication internals
- Storage: files, pages, and on-disk layout
- Autovacuum and bloat control
- CNPG vs EC2/VM operational differences
- Backup/restore, scaling, and sharding concepts

---

## Related Documentation

- **Database Architecture Overview**: [`docs/databases/002-database-integration.md`](../../../../../docs/databases/002-database-integration.md)
- **Pooler deep dive**: [`docs/databases/008-pooler.md`](../../../../../docs/databases/008-pooler.md)
- **Monitoring Setup**: [`docs/observability/metrics/README.md`](../../../../../docs/observability/metrics/README.md)
- **Replication Deep Dive**: [`docs/databases/004-replication-strategy.md`](../../../../../docs/databases/004-replication-strategy.md)
