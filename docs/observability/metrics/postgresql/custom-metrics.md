# PostgreSQL Custom Metrics — query reference

Every custom monitoring query the CNPG exporter runs, what it watches, why it
matters operationally, and how to query and alert on it.

| Quick facts | |
|---|---|
| Source | CNPG built-in exporter (`:9187`), per-cluster custom-queries ConfigMap |
| Clusters | `platform-db` (ns `platform`), `product-db` (ns `product`) — identical query set |
| Live queries | **12** (see reference below) |
| Metric prefix | `cnpg_` — the exporter prepends it to every series (`cnpg_pg_stat_statements_calls`) |
| Related alerts | [`alert-catalog.md` §4/§4b](../../alerting/alert-catalog.md#4-postgresql--cloudnativepg) |

## Overview

All PostgreSQL runs on **CloudNativePG**. Beyond the built-in `cnpg_collector_*`
health metrics, each cluster loads a custom-queries ConfigMap
(`spec.monitoring.customQueriesConfigMapList`) that turns hand-written SQL into
Prometheus metrics. This page documents that custom set — it is the source of
truth for the `pg-query-performance` and `pg-maintenance` Grafana boards and the
deep-signal alerts.

## Naming convention

The exporter maps `{query_name}_{column_name}` → metric, then CNPG prepends
`cnpg_`. A column with `usage: LABEL` becomes a label; `COUNTER`/`GAUGE` become
the value.

- Query `pg_stat_statements`, column `calls` → **`cnpg_pg_stat_statements_calls`**.

> Every PromQL example below uses the live `cnpg_`-prefixed name. Series carry
> `cnpg_io_cluster` (`platform-db`/`product-db`) and `namespace`; filter or group
> by `cnpg_io_cluster` to separate clusters.

## Custom query reference

`[per-db]` = runs against each `target_databases` entry and carries a `datname`
label. `[cluster]` = runs once per instance (instance-wide view).

### Query performance

#### `pg_stat_statements` `[per-db]`

- **What** — top 100 statements per database, ordered by total execution time
  (excludes utility/`BEGIN`/`COMMIT`/`SAVEPOINT` noise and the `postgres` db).
- **Columns** — labels `user, datname, queryid, query`; counters `calls`,
  `time_milliseconds` (total exec time), `rows`, `shared_blks_{hit,read,dirtied,written}`,
  `local_blks_*`, `temp_blks_{read,written}`, `blk_read_time`, `blk_write_time`
  (PG17+ `shared_blk_*_time`, live only with `track_io_timing=on`).
- **Why** — the single most useful tuning signal: find slow, chatty, cache-missing,
  or disk-spilling queries. Requires the `pg_stat_statements` extension (CNPG
  enables it automatically).
- **PromQL**
  ```promql
  # Top 10 statements by exec time /s
  topk(10, sum by (queryid, query) (rate(cnpg_pg_stat_statements_time_milliseconds{cnpg_io_cluster="platform-db"}[5m])))
  # Mean latency per call
  rate(cnpg_pg_stat_statements_time_milliseconds[5m]) / clamp_min(rate(cnpg_pg_stat_statements_calls[5m]), 1)
  # Per-query cache hit ratio
  rate(cnpg_pg_stat_statements_shared_blks_hit[5m]) / clamp_min(rate(cnpg_pg_stat_statements_shared_blks_hit[5m]) + rate(cnpg_pg_stat_statements_shared_blks_read[5m]), 1)
  ```
- **Alerts** — `CNPGLowCacheHitRatio`, `CNPGTempFileSpill` (via `pg_stat_database`); board: `pg-query-performance`.

### Sessions & contention

#### `pg_stat_activity_count` `[cluster]`

- **What** — backend count grouped by database, connection `state`, and user.
- **Columns** — labels `datname, state, usename`; gauge `count`.
- **Why** — see connection mix (active vs idle vs `idle in transaction`) and which
  user/db is holding connections; complements pooler metrics.
- **PromQL** — `sum by (state) (cnpg_pg_stat_activity_count_count{cnpg_io_cluster="platform-db"})`

#### `pg_connection_limits` `[cluster]`

- **What** — current vs maximum connections.
- **Columns** — gauges `max_connections`, `current_connections`.
- **Why** — connection saturation ends in refused clients. Feeds the chart
  `CNPGClusterHighConnections` alerts.
- **PromQL** — `cnpg_pg_connection_limits_current_connections / cnpg_pg_connection_limits_max_connections`

#### `pg_locks_count` `[cluster]`

- **What** — held locks grouped by database and lock `mode`.
- **Columns** — labels `datname, mode`; gauge `count`.
- **Why** — a spike in `ExclusiveLock`/`RowExclusiveLock` (or growth overall) flags
  contention before it becomes a stall.
- **PromQL** — `sum by (mode) (cnpg_pg_locks_count_count{cnpg_io_cluster="platform-db"})`

#### `pg_blocking_queries` `[cluster]`

- **What** — count of sessions currently **waiting on a lock** held by another.
- **Columns** — gauge `blocked_queries` (cluster-level; no per-pid detail).
- **Why** — the clearest lock-contention signal; sustained >0 means queries are stuck.
- **PromQL** — `max by (cnpg_io_cluster) (cnpg_pg_blocking_queries_blocked_queries)`
- **Alert** — `CNPGBlockedQueries`.

#### `pg_long_running_transactions` `[cluster]`

- **What** — instance-wide age of the oldest transaction and idle-in-transaction
  sessions (from `pg_stat_activity`).
- **Columns** — gauges `oldest_transaction_seconds`, `oldest_idle_in_transaction_seconds`,
  `idle_in_transaction_count`, `longest_active_query_seconds`.
- **Why** — long/idle transactions pin dead tuples (blocking VACUUM) and hold back
  xid freezing → the root cause of bloat and wraparound. The classic Senior-DBA signal.
- **PromQL** — `max by (cnpg_io_cluster) (cnpg_pg_long_running_transactions_oldest_transaction_seconds)`
- **Alerts** — `CNPGLongRunningTransaction`, `CNPGIdleInTransaction`; board: `pg-maintenance`.

### Autovacuum, bloat & maintenance

#### `pg_stat_user_tables_autovacuum` `[per-db]`

- **What** — per-table live/dead tuples and vacuum/analyze counts.
- **Columns** — labels `datname, schemaname, relname`; gauges `n_dead_tup`,
  `n_live_tup`; counters `autovacuum_count`, `autoanalyze_count`.
- **Why** — a high dead/(dead+live) ratio means autovacuum is falling behind → bloat,
  slower scans, wasted disk.
- **PromQL**
  ```promql
  cnpg_pg_stat_user_tables_autovacuum_n_dead_tup
    / clamp_min(cnpg_pg_stat_user_tables_autovacuum_n_dead_tup + cnpg_pg_stat_user_tables_autovacuum_n_live_tup, 1)
  ```
- **Alert** — `CNPGAutovacuumFallingBehind`.

#### `pg_stat_progress_vacuum` `[per-db]`

- **What** — live progress of **running** VACUUM/autovacuum operations. Emits rows
  only while a vacuum is in flight (usually none).
- **Columns** — labels `datname, pid, relname, phase`; gauges `heap_blks_total`,
  `heap_blks_scanned`, `heap_blks_vacuumed`, `index_vacuum_count`, `num_dead_item_ids`.
- **Why** — answers "is a big table vacuuming right now, and how far along?" during an
  incident; distinguishes a stuck vacuum from a slow one.
- **PromQL** — `cnpg_pg_stat_progress_vacuum_heap_blks_scanned / clamp_min(cnpg_pg_stat_progress_vacuum_heap_blks_total, 1)`

#### `pg_table_size` `[per-db]`

- **What** — top 30 tables by size (heap + indexes + TOAST).
- **Columns** — labels `datname, schemaname, tablename`; gauges `total_bytes`,
  `table_bytes`.
- **Why** — capacity planning and spotting unexpected growth / bloat.
- **PromQL** — `topk(20, cnpg_pg_table_size_total_bytes{cnpg_io_cluster="platform-db"})`

#### `pg_stat_user_indexes` `[per-db]`

- **What** — per-index scan counts and size.
- **Columns** — labels `datname, schemaname, relname, indexrelname`; counters
  `idx_scan`, `idx_tup_read`, `idx_tup_fetch`; gauge `index_bytes`.
- **Why** — `idx_scan == 0` marks **unused indexes** — dead weight that slows writes
  and wastes space; drop candidates.
- **PromQL** — `cnpg_pg_stat_user_indexes_index_bytes and (cnpg_pg_stat_user_indexes_idx_scan == 0)`

### Storage & checkpoints

#### `pg_database_size` `[cluster]`

- **What** — size of each database.
- **Columns** — label `datname`; gauge `size_bytes`.
- **Why** — per-database growth trends and disk forecasting.
- **PromQL** — `cnpg_pg_database_size_size_bytes{cnpg_io_cluster="platform-db"}`

#### `pg_stat_checkpointer` `[cluster]`

- **What** — checkpoint activity from `pg_stat_checkpointer` (PG17+).
- **Columns** — counters `checkpoints_timed`, `checkpoints_req`,
  `checkpoint_write_time`, `checkpoint_sync_time`, `buffers_checkpoint`.
- **Why** — when `checkpoints_req` outpaces `checkpoints_timed`, checkpoints are being
  forced by WAL pressure (`max_wal_size` too small) rather than the timeout — a tuning
  signal.
- **PromQL** — `rate(cnpg_pg_stat_checkpointer_checkpoints_req[30m]) > rate(cnpg_pg_stat_checkpointer_checkpoints_timed[30m])`
- **Alert** — `CNPGCheckpointPressure`.

> **Not custom queries.** Replication lag (`cnpg_pg_replication_lag`), WAL
> (`cnpg_collector_pg_wal`), backups (`cnpg_collector_last_*_backup_timestamp`),
> xid/mxid age (`cnpg_pg_database_xid_age`/`mxid_age`) and per-database
> `pg_stat_database` come from CNPG's **built-in** collectors, documented in
> [`monitoring.md`](monitoring.md).

> **No latency heatmap.** `pg_stat_statements` exposes totals + calls only (no
> per-bucket histogram), so a true query-latency-distribution heatmap is not
> derivable from these metrics — the boards chart mean/total exec time instead.

## Configuration reference

Custom queries live in a per-cluster ConfigMap referenced from the CNPG `Cluster`
`spec.monitoring.customQueriesConfigMapList`:

- **platform-db** — `kubernetes/infra/configs/databases/clusters/platform-db/configmaps/monitoring-queries.yaml`
- **product-db** — `kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml`

Each query:

```yaml
query_name:
  query: "SELECT ..."
  target_databases:          # optional — run per database and add a datname label
    - "auth"
  metrics:
    - column_name:
        usage: "COUNTER|GAUGE|LABEL"
        description: "..."
```

- **`target_databases`** — the exporter runs the query once per listed database and
  labels the result with `datname`. Omit it for an instance-wide query
  (e.g. `pg_stat_activity`, `pg_stat_checkpointer`). The ConfigMap carries the
  `cnpg.io/reload: ""` label, so edits are hot-reloaded without a pod restart.
- **`usage`** — `LABEL` → Prometheus label; `COUNTER`/`GAUGE` → metric value.

## Verification

> **CNPG pod model.** No exporter sidecar — the instance manager serves `:9187`
> from the `postgres` container; custom queries come from the ConfigMap, not a
> mounted `queries.yaml`.

```bash
# New custom metrics present in the store (both clusters):
kubectl -n monitoring port-forward svc/vmsingle-victoria-metrics 8428:8428 &
curl -s 'http://localhost:8428/api/v1/label/__name__/values' | tr ',' '\n' \
  | grep -E 'cnpg_pg_(stat_statements|locks_count|blocking_queries|long_running_transactions|stat_progress_vacuum|stat_user_tables_autovacuum|stat_checkpointer)'

# Straight from an instance's exporter:
kubectl exec -n platform platform-db-1 -c postgres -- \
  curl -s http://localhost:9187/metrics | grep '^cnpg_pg_long_running_transactions'
```

If a query is missing, check the instance-manager log for SQL errors and confirm
the ConfigMap is referenced:

```bash
kubectl logs -n platform platform-db-1 -c postgres | grep -i 'monitoring\|error'
kubectl get cluster -n platform platform-db -o jsonpath='{.spec.monitoring.customQueriesConfigMapList}'
```

## Related documentation

- [`monitoring.md`](monitoring.md) — CNPG exporter overview + built-in collector metrics
- [`alert-catalog.md`](../../alerting/alert-catalog.md#4-postgresql--cloudnativepg) — PostgreSQL alerts (chart set + deep-signal set)
- [`docs/databases/002-database-integration.md`](../../../databases/002-database-integration.md) — database integration
- [`promql-guide.md`](../promql-guide.md) — PromQL functions and examples

---
_Last updated: 2026-07-18 (documented all 12 live custom queries; removed stale pg_replication/pg_postmaster)_
