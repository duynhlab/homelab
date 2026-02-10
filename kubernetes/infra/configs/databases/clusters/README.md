# PostgreSQL Clusters

## Cluster Summary

| Cluster | Operator | Namespace | Instances | Replication | Pooler | Pooler Endpoint | Direct Endpoint |
|---------|----------|-----------|-----------|-------------|--------|-----------------|-----------------|
| **auth-db** | Zalando | auth | 3 (1 Leader + 2 Standbys) | Streaming (async) | PgBouncer (2 pods) | `auth-db-pooler.auth.svc:5432` | `auth-db.auth.svc:5432` |
| **supporting-shared-db** | Zalando | user | 1 | N/A | PgBouncer (2 pods) | `supporting-shared-db-pooler.user.svc:5432` | `supporting-shared-db.user.svc:5432` |
| **review-db** | Zalando | review | 1 | N/A | None | N/A | `review-db.review.svc:5432` |
| **product-db** | CloudNativePG | product | 3 (1 Primary + 2 Replicas) | Async | PgDog (1 pod) | `pgdog-product.product.svc:6432` | `product-db-rw.product.svc:5432` |
| **transaction-shared-db** | CloudNativePG | cart | 3 (1 Primary + 2 Replicas) | Synchronous | PgCat (2 pods) | `pgcat.cart.svc:5432` | `transaction-shared-db-rw.cart.svc:5432` |

---

## Detailed Cluster Documentation

For detailed architecture, configuration, and components of each cluster, please refer to their respective directories:

- **[auth-db](auth-db/README.md)**: Authentication service database.
- **[supporting-shared-db](supporting-shared-db/README.md)**: Shared database for User, Notification, and Shipping services.
- **[review-db](review-db/README.md)**: Review service database.
- **[product-db](product-db/README.Md)**: Product service database (includes backup architecture).
- **[transaction-shared-db](transaction-shared-db/README.md)**: Transaction (cart/order) service database.

---

## Connection Pooler Comparison

| Feature | PgBouncer (Zalando) | PgDog | PgCat |
|---------|---------------------|-------|-------|
| **Architecture** | Single-threaded (C) | Multi-threaded (Rust) | Multi-threaded (Rust) |
| **Deployment** | Operator-managed | Helm chart | Kubernetes manifests |
| **Read/Write Splitting** | No | Yes (configurable) | Yes (enabled) |
| **Load Balancing** | No | Yes | Yes |
| **Multi-Database** | Limited | Yes | Yes |
| **Sharding** | No | Production-grade | Experimental |
| **Monitoring** | Basic | OpenMetrics + Admin DB | Prometheus + Admin DB |
| **SSL Requirement** | Required | Optional | Optional |

---

## Explore Internal Cluster PostgreSQL

This section uses **product-db** as a learning vehicle to understand PostgreSQL internals. The same concepts apply whether PostgreSQL runs on Kubernetes (CloudNativePG) or VMs (EC2).

### Product-db Topology (Current Configuration)

| Component | Endpoint | Port | Role |
|-----------|----------|------|------|
| **PgDog Pooler** | `pgdog-product.product.svc.cluster.local` | 6432 | Connection pooling, routes to RW |
| **CNPG RW Service** | `product-db-rw.product.svc.cluster.local` | 5432 | Write queries (auto-routes to primary) |
| **CNPG R Service** | `product-db-r.product.svc.cluster.local` | 5432 | Read queries (load-balanced replicas) |
| **CNPG RO Service** | `product-db-ro.product.svc.cluster.local` | 5432 | Read-only (any instance) |
| **Cluster** | 3 instances | - | 1 Primary + 2 Replicas (async replication) |

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
    Primary -->|"async WAL streaming"| Replica1
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

**[PostgreSQL Internals Deep Dive (product-db)](../../../../docs/databases/postgresql_internals_product_db.md)**

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

- **Database Architecture Overview**: [`docs/databases/database.md`](../../../../docs/databases/database.md)
- **PgCat Troubleshooting**: [`docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md`](../../../../docs/runbooks/troubleshooting/pgcat_prepared_statement_error.md)
- **Monitoring Setup**: [`docs/observability/metrics/metrics.md`](../../../../docs/observability/metrics/metrics.md)
- **Replication Deep Dive**: [`docs/databases/replication_strategy.md`](../../../../docs/databases/replication_strategy.md)
