# CNPGLowCacheHitRatio

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_statements` (drill-down) |
| **Grafana** | pg-query-performance |

## Meaning

Shared-buffer hit ratio below **90%** for **15 minutes** under meaningful load
(`blks_hit + blks_read > 50/s`). Working set may exceed `shared_buffers` or a
large scan is evicting hot pages.

## Impact

More reads from disk → higher latency and IO pressure. Not always an incident —
batch jobs can temporarily drop hit ratio — but sustained low ratio under OLTP
load hurts SLOs.

## Diagnosis

### PromQL

```promql
sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_database_blks_hit[5m]))
/ clamp_min(
    sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_database_blks_hit[5m]))
    + sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_database_blks_read[5m])), 1)
```

Per-query cache miss (use `queryid`, not full `query` label in tickets):

```promql
topk(10,
  rate(cnpg_pg_stat_statements_shared_blks_read{cnpg_io_cluster="$CLUSTER"}[5m])
)
```

### VictoriaLogs

Search for `auto_explain` entries on CNPG pods — plans with large `Seq Scan` or
high `Buffers: shared read` indicate offenders.

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "SHOW shared_buffers;"
```

## Mitigation

1. Identify top `shared_blks_read` queries via pg-query-performance dashboard.
2. Add or fix indexes; reduce `SELECT *` on wide tables.
3. Increase `shared_buffers` only after confirming working-set size (avoid
   over-allocating on Kind nodes).
4. Separate batch/analytics workload from OLTP if a scan dominates.

## Escalation

Ticket for tuning; page only if latency SLO burn-rate alerts co-fire.
