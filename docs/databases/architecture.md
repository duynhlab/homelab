# Database Architecture

All deployed PostgreSQL clusters are managed by CloudNativePG; two serve
workloads and one is a continuously recovering DR cluster.

| Cluster | Namespace | PostgreSQL | Instances | Purpose |
|---|---|---:|---:|---|
| `platform-db` | `platform` | 18.1 | 3 | Platform and supporting-service databases |
| `product-db` | `product` | 18.1 | 3 | Catalog and checkout-domain databases |
| `product-db-replica` | `product` | 18.1 | 1 | Object-store-fed DR copy of `product-db` |

## Current topology

This diagram answers which deployed component owns each connection path. It
does not describe the planned cross-region topology.

```mermaid
flowchart TB
    CNPG["CloudNativePG 1.30.0"]

    subgraph PlatformClients["Platform database clients"]
        PlatformApps["user / notification / shipping / review"]
        DirectPlatform["Temporal / Keycloak"]
    end

    subgraph ProductClients["Product database clients"]
        ProductApps["product / cart / order / checkout / inventory"]
        Payment["payment"]
    end

    PgBouncer["CNPG PgBouncer<br/>platform-db-pooler-rw :5432"]
    PgDog["PgDog<br/>pgdog-product :6432"]
    Platform[("platform-db<br/>3 instances")]
    Product[("product-db<br/>3 instances")]
    DR[("product-db-replica<br/>1 instance")]
    Store[("RustFS object storage")]

    CNPG --> Platform
    CNPG --> Product
    CNPG --> DR
    PlatformApps --> PgBouncer --> Platform
    DirectPlatform --> Platform
    ProductApps --> PgDog --> Product
    Payment --> Product
    Platform -->|"base backups + WAL"| Store
    Product -->|"base backups + WAL"| Store
    Store -->|"continuous recovery"| DR

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    class CNPG,PgBouncer,PgDog platform;
    class PlatformApps,DirectPlatform,ProductApps,Payment service;
    class Platform,Product,DR,Store data;
```

## Cluster behavior

Both operational clusters use synchronous quorum `ANY 1` with
`dataDurability: required`. Each has one primary and two standby instances;
the operator selects actual synchronous/async roles at runtime. CNPG exposes
`-rw`, `-r`, and `-ro` services. The application path may add a pooler as shown
above.

`product-db-replica` is a separate CNPG `Cluster` in continuous recovery from
the `product-db` Barman object store. It is not an additional synchronous
standby and is co-located in the same Kubernetes environment, so it does not
provide region-level isolation. See [disaster recovery](./disaster-recovery.md)
and the [planned cross-region roadmap](./cross-region-dr.md).

## Database inventory

| Cluster | Databases declared or adopted by current manifests |
|---|---|
| `platform-db` | `user`, `notification`, `shipping`, `review`, `keycloak`, `temporal`, `temporal_visibility` |
| `product-db` | `product`, `cart`, `order`, `payment`, `checkout`, `inventory` |
| `product-db-replica` | Physical recovery copy of `product-db` |

Service databases, roles, Secrets, and extensions are reconciled as
per-service resources. See
[declarative role management](./declarative-role-management.md) and
[extensions](./extensions.md).

## Operations

- [Pooler endpoints and ownership](./poolers.md)
- [Backup policy](./backup-policy.md)
- [Emergency recovery](./runbooks/emergency-recovery.md)
- [Database runbooks](./runbooks/README.md)
- [PostgreSQL alert runbooks](../observability/runbooks/postgresql/README.md)

## Manifest evidence

- `kubernetes/infra/controllers/databases/`
- `kubernetes/infra/configs/databases/clusters/`
- `kubernetes/infra/configs/databases-cnpg-dr/`

Older integration diagrams and walkthroughs remain in
[reference/archive](./reference/archive/database-integration-notes.md), clearly
outside the current-truth path.

## References

- [CloudNativePG architecture](https://cloudnative-pg.io/documentation/current/architecture/)
- [CloudNativePG replica clusters](https://cloudnative-pg.io/documentation/current/replica_cluster/)

_Last updated: 2026-08-31._
