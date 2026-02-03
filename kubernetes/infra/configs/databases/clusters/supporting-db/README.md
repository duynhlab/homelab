# Cluster Supporting DB (Zalando Operator)

## Overview

| Property | Value |
|----------|-------|
| **Operator** | Zalando Postgres Operator |
| **Namespace** | `user` |
| **PostgreSQL Version** | 16 |
| **Instances** | 1 (Single instance) |
| **Replication** | N/A (single instance) |
| **Pooler** | PgBouncer (2 instances, transaction mode) |
| **Sidecars** | postgres_exporter (v0.18.1), Vector (v0.52.0) |
| **Databases** | `user`, `notification`, `shipping` (multi-tenant) |

## Endpoints

| Type | Endpoint | Port | Purpose |
|------|----------|------|---------|
| Direct | `supporting-db.user.svc.cluster.local` | 5432 | Direct connection |
| Pooler | `supporting-db-pooler.user.svc.cluster.local` | 5432 | Connection pooling (recommended, requires `sslmode=require`) |
| Metrics | Pod IP | 9187 | postgres_exporter metrics |

### How to Read the Diagrams
- **Color coding**:
  - 🔴 **Red** = Primary/Leader instance (accepts writes)
  - 🟡 **Yellow** = Standby/Sync Replica (synchronous replication)
  - 🟢 **Green** = Read Replica (async) or database schema
  - 🟣 **Purple** = Connection Pooler (PgBouncer, PgDog, PgCat)

## Topology Diagram

```mermaid
flowchart TD
    subgraph Apps["Applications - Multiple Namespaces"]
        UserService["User Service - ns: user"]
        NotificationService["Notification Service - ns: notification"]
        ShippingService["Shipping Service - ns: shipping"]
    end

    subgraph Pooler["PgBouncer Pooler - 2 Instances"]
        PgBouncer1{{"🟣 supporting-db-pooler<br/>Pod 1"}}
        PgBouncer2{{"🟣 supporting-db-pooler<br/>Pod 2"}}
        PoolerSvc["Service: supporting-db-pooler.user.svc:5432"]
    end

    subgraph ZalandoSvc["Zalando Services - Auto-created"]
        DirectSvc["Service: supporting-db.user.svc:5432"]
    end

    subgraph Cluster["supporting-db Cluster - 1 Instance"]
        Primary[("🔴 supporting-db-0<br/>Primary")]
        subgraph Databases["Databases"]
            UserDB[("user")]
            NotificationDB[("notification")]
            ShippingDB[("shipping")]
        end
    end
    
    subgraph Sidecars["Sidecars"]
        Exporter["postgres_exporter:9187"]
        Vector["vector - logs to Loki"]
    end

    UserService --> PoolerSvc
    NotificationService --> PoolerSvc
    ShippingService --> PoolerSvc
    PoolerSvc --> PgBouncer1
    PoolerSvc --> PgBouncer2
    PgBouncer1 --> DirectSvc
    PgBouncer2 --> DirectSvc
    DirectSvc --> Primary
    Primary --- UserDB
    Primary --- NotificationDB
    Primary --- ShippingDB
    Primary --- Exporter
    Primary --- Vector
    
    style Primary fill:#E53935,color:#fff
    style UserDB fill:#66BB6A
    style NotificationDB fill:#66BB6A
    style ShippingDB fill:#66BB6A
    style PgBouncer1 fill:#7E57C2,color:#fff
    style PgBouncer2 fill:#7E57C2,color:#fff
```

## Notes

**Current Configuration:**
- Multi-database cluster serving 3 services across different namespaces
- Cross-namespace user naming: `notification.notification`, `shipping.shipping` for automatic secret distribution
- PgBouncer requires `sslmode=require` for connections
- Conservative memory tuning: `shared_buffers: 64MB`, `work_mem: 4MB` (256MB container limit)
- Extensions: `pg_stat_statements`, `pg_cron`, `pg_trgm`, `pgcrypto`, `pg_stat_kcache`

**Considering:**
- Scale to 2+ instances for HA (currently single instance for cost optimization)
- Separate databases into dedicated clusters if traffic increases significantly
- Enable synchronous replication when HA is added

---

## Deployed Components

The following components are active in `kustomization.yaml`:

### 1. Database Cluster
- **File**: [`instance.yaml`](instance.yaml)
- **Description**: The main PostgreSQL 16 cluster configuration.
- **Spec**: 1 Instance (Single for cost optimization, with `numberOfInstances: 1`).
- **Databases**: Hosted `user`, `notification`, and `shipping` databases.
- **Pooler**: PgBouncer (2 instances, managed via `instance.yaml`).

### 2. Monitoring
- **Queries**: [`configmaps/monitoring-queries.yaml`](configmaps/monitoring-queries.yaml)
- **Exporter**: [`monitoring/pgbouncer-exporter.yaml`](monitoring/pgbouncer-exporter.yaml)

### 3. Logging
- **Config**: [`configmaps/vector-sidecar.yaml`](configmaps/vector-sidecar.yaml) (Vector sidecar for logs).

### 4. Secrets
- **Backup Credentials**: `secrets/pg-backup-rustfs-credentials.yaml`
