# CNPGClusterPhysicalReplicationLagCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` |
| **Grafana** | CloudNativePG Cluster Overview |

## Meaning

Physical replication lag **>15 s** for **5 minutes** — significant sync delay
between primary and replicas (`cnpg_pg_replication_lag` is in **seconds**).

## Impact

Failover may lose recent commits not yet replicated. Read replicas serve stale
data. DR promotion (`product-db-replica`) risk if lag persists.

## Diagnosis

Full procedure in
[CNPGClusterPhysicalReplicationLagWarning.md](CNPGClusterPhysicalReplicationLagWarning.md)
plus:

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '5 minutes'
ORDER BY duration DESC;
"
```

## Mitigation

1. Terminate runaway long queries on primary (with approval) if they generate
   excessive WAL.
2. Scale CPU/memory on lagging replica if resource-bound.
3. Increase `max_wal_size` / checkpoint tuning — [CNPGCheckpointPressure.md](CNPGCheckpointPressure.md).
4. For DR context: [cnpg-dr-replica-bootstrap.md](../../../databases/runbooks/cnpg-dr-replica-bootstrap.md).

## Escalation

**P1** if lag sustained >30m or failover imminent.
