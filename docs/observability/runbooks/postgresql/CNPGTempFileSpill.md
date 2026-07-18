# CNPGTempFileSpill

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_statements` (`temp_blks_*`) |
| **Grafana** | pg-query-performance |

## Meaning

Fires when cluster temp file write rate exceeds **5 MB/s** for **15 minutes**
(`rate(cnpg_pg_stat_database_temp_bytes[10m]) > 5e6`).

## Impact

Sorts and hashes spill to disk when they exceed `work_mem` — queries become much
slower and disk IO spikes. Often missing indexes or oversized sorts in reports.

## Diagnosis

### PromQL

```promql
sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_database_temp_bytes[10m]))
topk(10, rate(cnpg_pg_stat_statements_temp_blks_written{cnpg_io_cluster="$CLUSTER"}[5m]))
```

### VictoriaLogs

`auto_explain` plans showing `Sort Method: external merge` or `HashAggregate`
with high disk usage.

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "SHOW work_mem;"
```

## Mitigation

1. Find offending queries by `temp_blks_written` in pg-query-performance.
2. Add indexes to avoid large sorts; rewrite queries with unnecessary `ORDER BY`
   / `DISTINCT`.
3. Raise `work_mem` **per session** or for specific roles — avoid global increase
   without calculating `max_connections × work_mem`.
4. See [CNPGLowCacheHitRatio.md](CNPGLowCacheHitRatio.md) if scans dominate.

## Escalation

Ticket unless co-firing with disk or latency critical alerts.
