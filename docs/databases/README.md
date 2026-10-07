# Databases

Learn PostgreSQL, understand the database platform deployed by this repository,
or find the right recovery procedure without mixing those three concerns.

| Item | Current state |
|---|---|
| **Operator** | CloudNativePG 1.30.1 |
| **PostgreSQL** | 18.6 |
| **Operational clusters** | `platform-db`, `product-db` |
| **DR cluster** | `product-db-replica` — one instance, co-located recovery copy |
| **Poolers** | CNPG PgBouncer for `platform-db`; PgDog for `product-db` |
| **Backup** | Barman Cloud plugin to RustFS-compatible object storage |
| **Historical operator** | Zalando Postgres Operator — reference only, not deployed |

## Choose a path

### Learn PostgreSQL

The [PostgreSQL internals learning path](./fundamentals/README.md) is an
explanation-first curriculum grounded in the deployed CNPG clusters
([#1137](https://github.com/duynhlab/homelab/issues/1137)): fourteen chapters,
each with one read-only evidence lab. Its README owns the curriculum order,
evidence vocabulary, glossary, and safety boundary.

1. [Learning path overview](./fundamentals/README.md)
2. [Processes and memory](./fundamentals/01-processes-and-memory.md)
3. [Storage, pages, and tuples](./fundamentals/02-storage-pages-and-tuples.md)
4. [Buffer manager and I/O](./fundamentals/03-buffer-manager-and-io.md)
5. [WAL and checkpoints](./fundamentals/04-wal-and-checkpoints.md)
6. [MVCC and snapshots](./fundamentals/05-mvcc-and-snapshots.md)
7. [Locking and wait events](./fundamentals/06-locking-and-wait-events.md)
8. [Vacuum and freezing](./fundamentals/07-vacuum-and-freezing.md)
9. [Query processing](./fundamentals/08-query-processing.md)
10. [Indexes and access methods](./fundamentals/09-indexes-and-access-methods.md)
11. [Schema and integrity](./fundamentals/10-schema-and-integrity.md)
12. [Partitioning and retention](./fundamentals/11-partitioning-and-retention.md)
13. [Replication and slots](./fundamentals/12-replication-and-slots.md)
14. [Backup and PITR](./fundamentals/13-backup-and-pitr.md)
15. [Monitoring and capacity](./fundamentals/14-monitoring-and-capacity.md)

### Understand this homelab

Follow this order after the relevant fundamentals chapter. Configuration claims
are checked against Git at `d421daf3` (2026-10-06); they are not a fresh live-cluster
audit. Historical lab/drill records retain the versions they actually measured.

| Order | Question | Canonical guide |
|---|---|---|
| 1 | What runs, and where do applications connect? | [Architecture](./architecture.md) |
| 2 | How does CNPG bootstrap, reconcile and handle failure? | [CloudNativePG](./cloudnativepg.md) |
| 3 | What limits concurrency, storage and recovery headroom? | [Storage and capacity](./storage-and-capacity.md) |
| 4 | Which connections, identities and privileges are allowed? | [Security and access](./security-and-access.md), then [role management](./declarative-role-management.md) |
| 5 | What changes when connections are pooled? | [Poolers](./poolers.md) |
| 6 | What must survive to recover data? | [Backup policy](./backup-policy.md), [DR](./disaster-recovery.md), then [targets and evidence](./reliability-targets.md) |
| 7 | How do we diagnose and change the platform? | [Troubleshooting](./observability-and-troubleshooting.md), then [maintenance](./runbooks/maintenance-and-upgrades.md) |

Additional platform topics:

- [Extensions](./extensions.md)
- [Database authorization (owner / migrator / runtime)](./authorization.md) — **conventions accepted, not deployed** (RFC-0029)
- [Cross-region DR roadmap](./cross-region-dr.md) — **planned, not
  deployed**

### Operate and recover

Start with [Emergency recovery](./runbooks/emergency-recovery.md) when the failure
mode is not yet known. Task-specific procedures live in the
[runbook index](./runbooks/README.md), including backup/restore, DR replica
bootstrap, pooler operations, credential rotation, and adding a service
database.

| Need | Start here |
|---|---|
| Database is unavailable; cause unknown | [Emergency recovery](./runbooks/emergency-recovery.md) |
| Restart, upgrade, scale, expand storage or maintain a node | [Maintenance and upgrades](./runbooks/maintenance-and-upgrades.md) |
| Restore a backup or prove recovery | [Backup/restore](./runbooks/backup-restore.md), then [drills](./runbooks/restore-and-failover-drills.md) |
| Login breaks after a credential change | [Pooler operations](./runbooks/pooler-operations.md), then the owning [rotation runbook](./runbooks/README.md) |
| Assess remaining platform risks | [Review findings and follow-ups](./reference/platform-review.md) |

### Reference and history

These pages support design study and historical review. They are not current
operating procedures.

- [Operator comparison](./reference/operator-comparison.md)
- [Backup tooling comparison](./reference/backup-tooling-comparison.md)
- [Zalando Postgres Operator](./reference/zalando/operator.md) — **historical,
  not deployed**
- [Further reading](./reference/further-reading.md)
- Historical Zalando procedures are listed separately in the
  [runbook index](./runbooks/README.md).

## Architecture

This diagram answers only how readers should navigate the documentation; the
deployed database topology belongs to the architecture guide.

```mermaid
flowchart LR
    Hub["Database hub"]
    Learn["Learn<br/>stable concepts"]
    Platform["Understand<br/>deployed or planned state"]
    Operate["Operate<br/>current runbooks"]
    Reference["Reference<br/>historical or comparative"]

    Hub --> Learn
    Hub --> Platform
    Hub --> Operate
    Hub -. "background only" .-> Reference

    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    classDef service fill:#cffafe,color:#164e63,stroke:#0891b2;
    classDef worker fill:#fef3c7,color:#78350f,stroke:#d97706;
    classDef external fill:#f1f5f9,color:#334155,stroke:#64748b;
    class Hub platform;
    class Learn service;
    class Platform platform;
    class Operate worker;
    class Reference external;
```

Legend: cyan = learning, purple = platform, amber = operations, slate = reference.

## Document ownership

| Fact or concern | Canonical owner |
|---|---|
| Cluster inventory, namespaces, PostgreSQL/operator versions | `architecture.md` |
| CloudNativePG control plane and operand behavior | `cloudnativepg.md` |
| Storage, memory/concurrency budgets and placement | `storage-and-capacity.md` |
| TLS, HBA, authentication and access boundaries | `security-and-access.md` |
| Backup schedules, retention, and object paths | `backup-policy.md` |
| Recovery paths and DR topology | `disaster-recovery.md` |
| RPO/RTO objectives and measured evidence | `reliability-targets.md` |
| Pooler deployment and connection ownership | `poolers.md` |
| Installed and allowed extension model | `extensions.md` |
| Database, role, and credential reconciliation | `declarative-role-management.md` |
| Who owns objects, who migrates, who serves traffic | `authorization.md` |
| Commands used during operations | [`runbooks/`](./runbooks/README.md) |
| PostgreSQL internal mechanics | `fundamentals/` |
| Symptom-to-signal troubleshooting | `observability-and-troubleshooting.md` |

Architecture decisions remain in [RFC and ADR records](../proposals/README.md);
this area documents the resulting platform and its operation.

## References

- [PostgreSQL documentation](https://www.postgresql.org/docs/current/)
- [CloudNativePG 1.30 documentation](https://cloudnative-pg.io/docs/1.30/)
- [PgDog documentation](https://docs.pgdog.dev/)
