# CNPGClusterHighReplicationLag

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` |

## Meaning

`cnpg_pg_replication_lag` **>1 second** for **5 minutes** — distinct from
physical lag ms thresholds; indicates severe replication delay.

## Impact

Large consistency gap primary↔replica. Failover data-loss window up to lag
duration. PgDog read routing may ban all replicas.

## Diagnosis

Same family as
[CNPGClusterPhysicalReplicationLagCritical.md](CNPGClusterPhysicalReplicationLagCritical.md).

## Mitigation

Treat as severe lag — investigate WAL volume, replica resources, network.
Cross-check [PostgresWALSizeHigh.md](PostgresWALSizeHigh.md) and
[CNPGWALArchiveFailing.md](CNPGWALArchiveFailing.md).

## Escalation

**P1** — page if >30s lag during production traffic.
