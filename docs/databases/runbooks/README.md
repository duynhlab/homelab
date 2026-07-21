# Database Runbooks

Task-focused operations and troubleshooting for CloudNativePG clusters, PgDog
poolers, backups, and RFC-0012 service-database lifecycle.

## Day-2 operations

| When to use | Runbook |
|---|---|
| Add a service database to `product-db` (RFC-0012 triplet) | [add-service-database.md](./add-service-database.md) |
| Rotate a `product-db` service password end-to-end | [rotate-cnpg-service-password.md](./rotate-cnpg-service-password.md) |
| PgDog pooler ops (`pgdog-platform`, `pgdog-product`) | [pgdog-operations.md](./pgdog-operations.md) |
| Bootstrap or promote `product-db-replica` | [cnpg-dr-replica-bootstrap.md](./cnpg-dr-replica-bootstrap.md) |
| Backup health, manual backup, restore, PITR | [postgres-backup-restore.md](./postgres-backup-restore.md) |

## Reference / historical

| When to use | Runbook |
|---|---|
| Zalando operator HA scaling (pre-CNPG) | [zalando-ha-scaling.md](./zalando-ha-scaling.md) |
| `preparedDatabases` first-init fragility | [prepared-databases.md](./prepared-databases.md) |
| Endpoints → ConfigMaps pattern | [endpoints-to-configmaps.md](./endpoints-to-configmaps.md) |

## Related

- [Emergency recovery](../010.4-emergency-recovery.md) — start here when a cluster is down
- [PostgreSQL alert runbooks](../../observability/runbooks/postgresql/README.md) — per-alert on-call guides
- [Backup strategy](../006-backup-strategy.md) — architecture and retention

---

_Last updated: 2026-07-21 — Consolidated runbooks under domain hubs._
