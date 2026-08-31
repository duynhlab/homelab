# Database Runbooks

Task-focused operations and troubleshooting for CloudNativePG clusters, PgDog
poolers, backups, and RFC-0012 service-database lifecycle.

## Day-2 operations

| When to use | Runbook |
|---|---|
| Add a service database to `product-db` (RFC-0012 triplet) | [add-service-database.md](./add-service-database.md) |
| Rotate a `product-db` service password end-to-end | [rotate-cnpg-service-password.md](./rotate-cnpg-service-password.md) |
| Unknown database outage or recovery path | [emergency-recovery.md](./emergency-recovery.md) |
| Pooler ops — PgDog (`pgdog-product`) + CNPG PgBouncer (`platform-db-pooler-rw`) | [pooler-operations.md](./pooler-operations.md) |
| Bootstrap or promote `product-db-replica` | [cnpg-dr-replica-bootstrap.md](./cnpg-dr-replica-bootstrap.md) |
| Backup health, manual backup, restore, PITR | [backup-restore.md](./backup-restore.md) |
| Rehearse restore, failover, or DR promotion | [restore-and-failover-drills.md](./restore-and-failover-drills.md) |

## Reference / historical

| When to use | Runbook |
|---|---|
| Zalando operator HA scaling (pre-CNPG) | [ha-scaling.md](../reference/zalando/ha-scaling.md) |
| `preparedDatabases` first-init fragility | [prepared-databases.md](../reference/zalando/prepared-databases.md) |
| Endpoints → ConfigMaps pattern | [endpoints-to-configmaps.md](../reference/zalando/endpoints-to-configmaps.md) |

## Related

- [Database hub](../README.md)
- [Emergency recovery](./emergency-recovery.md) — start here when a cluster is down
- [PostgreSQL alert runbooks](../../observability/runbooks/postgresql/README.md) — per-alert on-call guides
- [Backup policy](../backup-policy.md) — current schedule and retention

---

_Last updated: 2026-08-31._
