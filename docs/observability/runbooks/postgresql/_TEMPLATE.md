# AlertName

| | |
|---|---|
| **Severity** | warning / critical |
| **Source** | chart / deep-signal / homelab-extra |
| **Clusters** | `platform-db` (ns `platform`), `product-db` (ns `product`) |
| **Custom queries** | list related `cnpg_pg_*` custom metrics, or — |
| **Grafana** | pg-maintenance / pg-query-performance / CloudNativePG Cluster Overview |

## Meaning

What fires and when (threshold, `for` duration, metric source).

## Impact

Business and operational consequence if ignored.

## Diagnosis

### PromQL

```promql
# Alert expr + drill-down queries (VictoriaMetrics)
```

### Grafana

- **CloudNativePG Cluster Overview** — HA, replication, connections
- **pg-maintenance** — locks, autovacuum, long transactions, checkpointer
- **pg-query-performance** — pg_stat_statements, cache, temp spill

### kubectl / psql

```bash
# Set cluster context from alert labels
export NAMESPACE=platform   # or product
export CLUSTER=platform-db  # or product-db

kubectl get pods -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER" -o wide
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "..."
```

### VictoriaLogs

When query tuning is involved: search CNPG pod logs for `auto_explain` plans or
`pgaudit` rows correlated by time window.

## Mitigation

Safe immediate actions, tuning parameters (with caution), links to procedural
runbooks when needed:

- [Emergency recovery](../../../databases/010.4-emergency-recovery.md)
- [PgDog operations](../../../databases/runbooks/pgdog-operations.md)
- [Backup restore](../../../databases/runbooks/postgres-backup-restore.md)

## Escalation

When to page further, when **not** to kill backends, and when to open an
incident vs ticket-only follow-up.
