# Alert-runbook audit — PR docs/postgresql-microservices-runbooks (2026-07-18)

LOCAL tracking (never commit). Kind cluster `homelab`, PG **18.1**, 19/19 Kustomizations
Ready **zero-touch** (no manual nudge). Snapshots in scratchpad: metric-names.json (2058),
rules.json, alerts.json, cnpg-metrics-live.txt (117 cnpg_*), expected-metrics.md.

## Static audit — CLEAN for PR
- All `runbook_url` (51) → target file exists.
- All relative `.md` links inside runbook files resolve.
- Alert↔file coverage complete (33 pg + 19 ms; 2 backup alerts intentionally → postgres-backup-restore.md; no orphans).
- Anchors in PR runbook files resolve (em-dash `--` were checker false-positives).

## Live metric presence — deep-signal source axis CLEAN
All CNPG metrics cited by deep-signal alerts PRESENT in TSDB, incl. `cnpg_pg_database_xid_age`
(built-in) and `cnpg_pg_stat_checkpointer_*` (PG18 ⇒ no version dead-rule). pg_stat_statements
extension present on all product target DBs.

---

## FINDINGS

### 🔴 FIND-1 — platform-db CNPG metrics missing `cnpg_io_cluster` label
- **Evidence:** `cnpg_pg_blocking_queries_blocked_queries`, `cnpg_collector_up`, all cnpg_* on
  ns `platform` have **no** `cnpg_io_cluster` label; ns `product` carries `cnpg_io_cluster="product-db"`.
- **Impact:** deep-signal alerts group `by (cnpg_io_cluster)`; platform-db alerts fire with EMPTY
  cluster label. Every runbook diagnosis keyed on `cnpg_io_cluster="$CLUSTER"` (e.g. CNPGBlockedQueries
  PromQL `...{cnpg_io_cluster="$CLUSTER"}`) returns NOTHING for platform-db.
- **Root cause (CONFIRMED):** `platform-db/instance.yaml:105` sets `enablePodMonitor: true`
  (product-db = `false`). With `true`, CNPG operator generates its OWN PodMonitor `platform-db`
  WITHOUT `podTargetLabels`, colliding with the repo `monitoring/podmonitor.yaml` (same name) and
  winning → platform-db metrics never get `cnpg_io_cluster`/instanceRole/instanceName. product-db
  (`false`) uses only the repo PodMonitor (has `podTargetLabels`) → label present.
- **FIX (owner chose Option A):** set `platform-db/instance.yaml` `enablePodMonitor: false` to match
  product-db (repo already ships `platform-db/monitoring/podmonitor.yaml` with the right `podTargetLabels`).
  Rationale: CNPG API has no field to add target labels; custom PodMonitor via `podTargetLabels` is the
  idiomatic, lower-config way vs `podMonitorRelabelings` (Option B) — and product-db already uses it.
  Re-verify after reconcile: platform-db series gain `cnpg_io_cluster`.
- **Scope:** comprehensive config fix on current PR.
- **Source-confirmed:** CNPG operator **v1.30.0** `pkg/specs/podmonitor.go` `BuildPodMonitor` sets only
  `Selector{cnpg.io/cluster, cnpg.io/podRole=instance}` + `PodMetricsEndpoints` — **never sets
  `PodTargetLabels`**. Matches live operator PodMonitor (`managed-by: cloudnative-pg`, podTargetLabels
  ABSENT, selector has `cnpg.io/podRole: instance`). Clusters are raw `kind: Cluster` (no Helm chart).

### 🟡 FIND-2 — custom query `pg_stat_checkpointer` duplicates + overrides built-in
- Built-in `cnpg-default-monitoring` defines `pg_stat_checkpointer` (runonserver >=17): emits
  checkpoints_timed, checkpoints_req, **restartpoints_timed/req/done, write_time, sync_time,
  buffers_written, stats_reset_time**.
- Custom `product/platform-db-monitoring-queries` ALSO defines `pg_stat_checkpointer`: emits
  checkpoints_timed, checkpoints_req, checkpoint_write_time, checkpoint_sync_time, buffers_checkpoint.
- **TSDB shows only the CUSTOM names win** (`cnpg_pg_stat_checkpointer_checkpoint_write_time`,
  `_buffers_checkpoint`) → custom **shadows** built-in; built-in restartpoints/stats_reset LOST.
- CNPGCheckpointPressure uses checkpoints_req/timed (survive either way) → alert OK, but query is redundant.
- **User directive:** NOTE + evaluate; candidate = drop custom `pg_stat_checkpointer`, adopt built-in
  (check dashboards/panels referencing custom-only `checkpoint_write_time`/`buffers_checkpoint`). (task #8)

### 🟡 FIND-3 — custom query `pg_database_size` redundant with built-in `pg_database`
- Built-in `pg_database` emits `cnpg_pg_database_size_bytes`, `cnpg_pg_database_xid_age`, `cnpg_pg_database_mxid_age`.
- Custom `pg_database_size` emits `cnpg_pg_database_size_size_bytes` (awkward double "size") — DB size only.
- **Candidate = drop custom `pg_database_size`; use built-in `cnpg_pg_database_size_bytes`** (repoint any dashboard). (task #8)

### 🟢 Partial overlap (keep, but docs should note)
- Custom `pg_stat_activity_count` (per-state) / `pg_connection_limits` vs built-in `backends`,
  `backends_waiting` (`cnpg_backends_total`, `cnpg_backends_waiting_total`, `cnpg_backends_max_tx_duration_seconds`).
  Custom adds per-state/per-user granularity — not strict dup.

## Built-in default queries INVENTORY (for docs — "which built-ins exist")
Configmap `cnpg-default-monitoring` (`disableDefaultQueries:false`), 13 queries:
`backends`, `backends_waiting`, `pg_database`, `pg_extensions`, `pg_postmaster`, `pg_replication`,
`pg_replication_slots`, `pg_settings`, `pg_stat_archiver`, `pg_stat_bgwriter`, `pg_stat_checkpointer`,
`pg_stat_database`, `pg_stat_replication`.
Notable built-in metric families live in TSDB:
- pg_stat_database: deadlocks, blks_hit/read, temp_bytes/files, tup_*, xact_commit/rollback, conflicts, blk_read/write_time
- pg_stat_archiver: archived/failed_count, last_*_time, seconds_since_last_*
- pg_stat_bgwriter: buffers_alloc/clean, maxwritten_clean
- pg_database: size_bytes, xid_age, mxid_age
- backends: total, waiting_total, max_tx_duration_seconds
- pg_replication: lag, in_recovery, is_wal_receiver_up, streaming_replicas; slots: active, pg_wal_lsn_diff
- pg_settings: setting ; pg_postmaster: start_time ; pg_extensions: update_available

## Built-in vs custom — keep/drop evaluation (task #8; NOTE-ONLY, owner decides)

Reference map (who uses the custom-only metric names):
- custom `pg_database_size` → `cnpg_pg_database_size_size_bytes` used in custom-metrics.md,
  capacity-planning.md, CNPGClusterLowDiskSpaceWarning.md. Built-in `cnpg_pg_database_size_bytes`
  is referenced NOWHERE. Alert dependency: none.
- custom `pg_stat_checkpointer` → alert CNPGCheckpointPressure uses `checkpoints_req`/`checkpoints_timed`
  (BUILT-IN emits these too ⇒ alert independent of custom). Only CheckpointPressure.md uses custom-only
  `checkpoint_write_time`; `buffers_checkpoint` unused.
- custom `pg_connection_limits` → docs-only refs (CNPGClusterHighConnectionsCritical.md + 3 metrics docs);
  NO alert uses it (HighConnections alert uses built-in `cnpg_backends_total`/`cnpg_pg_settings_setting`).

| Custom query | Verdict | Reason |
|---|---|---|
| pg_stat_checkpointer | **DROP candidate** | overrides built-in (loses restartpoints_*, stats_reset); built-in is superset. Repoint CheckpointPressure.md `checkpoint_write_time`→`write_time` (checkpoints_req unchanged). |
| pg_database_size | **DROP candidate** | built-in `pg_database` gives `size_bytes`(+xid_age,mxid_age). Repoint 3 docs `size_size_bytes`→`size_bytes`. |
| pg_connection_limits | **DROP (optional)** | redundant with built-in `pg_settings`(max_connections)+`backends`; docs-only, no alert. Repoint 4 docs. |
| pg_stat_statements | keep | not built-in |
| pg_stat_activity_count | keep | per-state/per-user detail beyond built-in `backends` total |
| pg_locks_count | keep | not built-in (lock-mode mix) |
| pg_blocking_queries | keep | not built-in (CNPGBlockedQueries alert) |
| pg_stat_user_tables_autovacuum | keep | per-table (built-in pg_stat_database is DB-level) |
| pg_table_size | keep | per-table size |
| pg_stat_user_indexes | keep | per-index usage |
| pg_long_running_transactions | keep | not built-in (long-txn/idle alerts) |
| pg_stat_progress_vacuum | keep | not built-in (vacuum progress) |

**Recommendation:** drop pg_stat_checkpointer + pg_database_size (clear wins, +repoint few docs);
pg_connection_limits optional. Do NOT remove until owner approves. Regardless of removal, docs MUST
gain a "Built-in CNPG metrics available" section (agent report pending).

### 🟡 FIND-4 — built-in metrics undocumented + broken forward-ref (MUST FIX, = user ask)
- `custom-metrics.md:184` says built-in families are "documented in monitoring.md" but `monitoring.md`
  does NOT enumerate the 13 built-in default queries or their metrics → dangling promise; operators
  can't discover available built-ins.
- **FIX:** add "Built-in default queries (cnpg-default-monitoring)" section to `monitoring.md`
  (between L102 `## Exporter: CNPG built-in` and L104 `## Custom queries`) listing 13 queries →
  key `cnpg_*` metrics (pg_stat_database deadlocks/blks_hit/temp_bytes/xact_*, pg_stat_archiver_*,
  pg_database size_bytes/xid_age/mxid_age, backends_{total,waiting_total,max_tx_duration_seconds},
  bgwriter, checkpointer, replication, settings, postmaster, extensions, stat_replication).
  Forward-ref then resolves. Add `pg_stat_database` row to the metric-coverage table.
- NICE: custom-metrics.md:65 reword LowCacheHitRatio/TempFileSpill as built-in `pg_stat_database`
  alerts (pg_stat_statements = drill-down); custom-metrics.md:163/169 note DB-size + checkpointer
  built-in redundancy (FIND-2/3).
- **Catalog count:** "53 rules total" vs "51 (+2 gated)" RECONCILE (53 authored = 51 active + 2 gated);
  optional wording tweak `alert-catalog.md:116` → "53 authored (51 active + 2 gated)". NOT a bug.
- Runbook built-in attribution verified CORRECT (Deadlocks/WALArchive/Wraparound/CacheHit/TempFile).

## MICROSERVICES findings (agent 2)

### 🔴 FIND-5 — OtelMetricsPipelineExportFailures = DEAD alert (wrong metric name)
- Rule `alerts.yaml:67` uses `otelcol_exporter_send_failed_metric_points_total`. Live otelcol
  self-telemetry has **NO `_total`** (`otelcol_exporter_sent_metric_points`,
  `otelcol_receiver_failed_metric_points` — both without _total; `..._total` variants = 0 series).
- ⇒ correct name `otelcol_exporter_send_failed_metric_points`. Current rule never matches → the alert
  guarding OTLP-pipeline blindness NEVER FIRES. **FIX rule + `OtelMetricsPipelineExportFailures.md`.**

### 🟠 FIND-6 — MicroserviceApdexCritical.md wrong severity
- Runbook facts (L5) + body (L16) say `warning`; rule = **critical** (`alerts.yaml` L222-236). Index +
  catalog correct. Misleads paging urgency. Threshold `<0.5`/`for 10m` correct. **FIX runbook → critical.**

### 🟠 FIND-7 — MicroserviceHighMemoryUsage.md stale "coverage gap" claim
- L22-25 claim selector omits `checkout` (unmonitored). Rule selector (`alerts.yaml:276`) already lists
  10 ns incl. checkout. Tells on-call checkout is dark when it isn't. **FIX: remove stale note.**

### 🟠 FIND-8 — GrpcServerHighErrorRate.md wrong status label in PromQL
- Runbook L20 groups by `rpc_grpc_status_code`; rule + recording-rule use `rpc_response_status_code`
  (`alerts.yaml:129`, `recording-rules.yaml:138`). **FIX runbook label.**

### 🟡 FIND-9 — stale cross-refs to non-existent/retired alerts (multiple runbooks)
- `MicroserviceHighLatencyP95.md` L46→`PostgresConnectionSaturation` (none), L47→`MicroserviceGCThrash`
  (retired). `MicroserviceLatencyCritical.md` L20→`PostgresLockContention`+`PostgresConnectionSaturation`
  (none). `MicroserviceAllInstancesDown.md` L39→`PostgresDown` (none; real = CNPGClusterOffline).
  **FIX: repoint to real names (CNPGClusterHighConnectionsWarning/Critical, CNPGClusterOffline) or drop.**

### 🟡 FIND-10 — MicroserviceGoroutineLeak.md rate() on a gauge
- Investigation L27 `rate(go_goroutine_count[15m])`; rule uses `deriv()` deliberately (gauge). **FIX → deriv().**

### 🟡 FIND-11 — duplicated body blocks
- `GrpcServerHighLatencyP95.md` (L7-23 == L25-41) and `OtelMetricsPipelineExportFailures.md`
  (Investigation/Resolution repeated). **FIX: de-dupe.**

### 🔵 FIND-12 — cosmetic
- Catalog §1 (`alert-catalog.md` L48-66): all 19 rows have an extra empty `| |` cell (7 cols vs 6-col
  header) → stray column. **FIX.**
- Facts-table missing `Severity` row in GrpcServerHighErrorRate.md, GrpcServerHighLatencyP95.md,
  OtelMetricsPipelineExportFailures.md (template inconsistency). **FIX.**

MS verified correct: index README (19/19 incl. Apdex=critical), + MicroserviceDown, HighErrorRate,
ErrorRateCritical, NoSuccessfulRequests, HighLatencyP99, NoTraffic, DBClientQueryP95High, DBClientErrorRate,
PgxPoolNearExhaustion, PgxPoolAcquireWaitHigh. Live-firing proven: NoTraffic, NoSuccessfulRequests.

## POSTGRESQL findings (agent 1) — NO sev/for/threshold/source mismatches; all 60 rules exist+evaluate

### 🔴 FIND-1 impact (H1) — 15 PG runbooks' PromQL empty for platform-db until FIND-1 fix
- Deep-signal rules group `by (cnpg_io_cluster)` + 15 runbooks filter `cnpg_io_cluster="$CLUSTER"` →
  empty for platform-db (and the 11 deep-signal alerts may mis-group for platform-db) until FIND-1 fixed.
  Files: CNPGBlockedQueries, CNPGCheckpointPressure, CNPGClusterHACritical, CNPGClusterHighConnectionsCritical,
  CNPGClusterInstancesOnSameNode, CNPGClusterOffline, CNPGClusterPhysicalReplicationLagWarning,
  CNPGDeadlocksIncreasing, CNPGIdleInTransaction, CNPGLongRunningTransaction, CNPGLowCacheHitRatio,
  CNPGTempFileSpill, CNPGTransactionIDWraparound{Warning,Critical}, PostgresWALSizeHigh.
  **Resolution: the FIND-1 enablePodMonitor fix makes these work — no per-runbook note needed post-fix.**

### 🟠 FIND-13 (M1) — physical-replication-lag units mislabelled "ms" (should be "s") + duplicate rule
- `cnpg_pg_replication_lag` is in **seconds**. `CNPGClusterPhysicalReplicationLagCritical.md` + catalog L131
  say ">15 **ms**" (→ >15 s); Warning + catalog L132 say ">1 **ms**" (→ >1 s). Inherited from upstream chart
  `{{ $value }}ms` annotation.
- `cnpg/cluster-physical_replication_lag-warning.yaml` expr is **byte-identical** to
  `cnpg/cluster-high_replication_lag.yaml` (both warning/5m/>1). `CNPGClusterHighReplicationLag.md` claims it
  is "distinct from physical lag ms thresholds" — misleading (same expr). **FIX: units ms→s in 2 runbooks +
  catalog L131/132; fix the "distinct" claim; note duplicate rule.**

### 🟡 FIND-14 (M2) — CNPGClusterLogicalReplicationLagging.md nonexistent metric
- Cites `cnpg_pg_stat_subscription_replication_lag_bytes` (absent; not in rule). Rule uses
  `..._receipt_lag_seconds`/`_apply_lag_seconds`/`_buffered_lag_bytes`. **FIX runbook PromQL.** (inactive rule)

### 🔵 FIND-15 (L1/L2) — PromQL label/selector nits
- `CNPGClusterInstancesOnSameNode.md` uses `exported_node`/`count by(exported_node,...)`; rule uses
  `count by(node)` on kube_pod_info. **FIX → `node`.** (gated)
- `PostgresWALSizeHigh.md` PromQL omits `value="size"` selector on `cnpg_collector_pg_wal` (multi-valued
  `value` label → extra series). **FIX: add `value="size"`.**
- L3 (CNPGAutovacuumFallingBehind progress_vacuum metrics absent) = EXPECTED (only during vacuum); no action.
- L4 catalog "53" is definition count (incl 2 gated; 20/22 armed) — matches FIND-4 wording note; optional.

PG verified correct: index README (all rows incl gated/inactive), catalog §4b (11/11), ~26 runbooks fully
accurate. Confirmed live: xid_age present (wraparound NOT dead), built-in deadlocks/blks/temp/archiver/
checkpointer all present.

## TODO next
- Root-cause FIND-1 (scrape/relabel).
- Per-runbook facts cross-check (sev/threshold/for + metric names) — 52 files.
- Microservices HTTP/gRPC metric-name verify (needs traffic; apps just went Ready).
- Owner evaluation on FIND-2/3 removal.
