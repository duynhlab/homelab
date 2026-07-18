# CNPGAutovacuumFallingBehind

| | |
|---|---|
| **Severity** | warning |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_user_tables_autovacuum`, `pg_stat_progress_vacuum` |
| **Grafana** | pg-maintenance (Dead tuples / Autovacuum row) |

## Meaning

Fires when a table has dead/(dead+live) **>20%** and `n_dead_tup > 1000` for
**30 minutes** (`cnpg_pg_stat_user_tables_autovacuum_*`).

## Impact

Autovacuum cannot reclaim dead tuple space fast enough → table bloat, sequential
scans slow down, indexes swell, disk usage grows. Often caused by long
transactions pinning old row versions.

## Diagnosis

### PromQL

```promql
cnpg_pg_stat_user_tables_autovacuum_n_dead_tup
/ clamp_min(
    cnpg_pg_stat_user_tables_autovacuum_n_dead_tup
    + cnpg_pg_stat_user_tables_autovacuum_n_live_tup, 1)
```

```promql
# Live vacuum progress (only while vacuum runs)
cnpg_pg_stat_progress_vacuum_heap_blks_scanned
/ clamp_min(cnpg_pg_stat_progress_vacuum_heap_blks_total, 1)
```

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -d "$DB" -c "
SELECT schemaname, relname, n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze, autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC LIMIT 20;
"

kubectl exec -n "$NAMESPACE" "services/${CLUSTER}-rw" -- psql -c "
SELECT * FROM pg_stat_progress_vacuum;
"
```

Check [CNPGLongRunningTransaction.md](CNPGLongRunningTransaction.md) and
[CNPGIdleInTransaction.md](CNPGIdleInTransaction.md) for blockers.

## Mitigation

1. End long / idle-in-transaction sessions blocking vacuum.
2. Per-table tuning: lower `autovacuum_vacuum_scale_factor` for hot tables
   (via `ALTER TABLE ... SET (...)`).
3. Manual `VACUUM (ANALYZE)` during maintenance window for worst tables.
4. If autovacuum never runs — check `autovacuum_max_workers` and disk IO.

## Escalation

Ticket for sustained bloat on non-critical tables; page if disk or latency SLOs
burn alongside `PostgresWALSizeHigh` or connection alerts.
