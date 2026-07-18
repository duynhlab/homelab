# CNPGClusterHighReplicationLag

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` |

## Meaning

`cnpg_pg_replication_lag` **>1 second** for **5 minutes**. Note: this chart rule
shares the same expr/threshold as `CNPGClusterPhysicalReplicationLagWarning`
(both `>1s` warning on `cnpg_pg_replication_lag`) — a duplicate emitted by the
CNPG chart. The critical escalation is `CNPGClusterPhysicalReplicationLagCritical`
(`>15s`).

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
