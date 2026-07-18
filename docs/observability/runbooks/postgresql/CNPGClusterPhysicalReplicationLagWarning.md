# CNPGClusterPhysicalReplicationLagWarning

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db`, `product-db-replica` (DR) |
| **Grafana** | CloudNativePG Cluster Overview |

## Meaning

Physical replication lag **>1 s** (chart expr on `cnpg_pg_replication_lag`, which
is in **seconds**) for **5 minutes** on any instance.

## Impact

Replicas slightly behind primary — `-r` / `-ro` reads may be stale. Minor
failover RPO exposure.

## Diagnosis

```promql
cnpg_pg_replication_lag{cnpg_io_cluster="$CLUSTER"}
```

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "SELECT * FROM pg_stat_replication;"
kubectl top pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER"
```

Check long queries, network, disk IO on replicas. PgDog bans lagging replicas —
see [PgDog operations](../../../databases/runbooks/pgdog-operations.md).

## Mitigation

1. Monitor — sub-second lag often transient on Kind.
2. Optimize long-running queries on primary.
3. Enable `wal_compression` if network-bound (CNPG parameters).
4. For sustained lag see critical runbook.

## Escalation

Ticket unless lag grows toward critical (>15s).
