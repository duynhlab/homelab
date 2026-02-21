# pg_exporter (Pigsty) Prometheus Metric Mapping

> **Source**: Config files from [pgsty/pg_exporter](https://github.com/pgsty/pg_exporter) (main branch)  
> **URL format**: `https://raw.githubusercontent.com/pgsty/pg_exporter/main/config/{filename}.yml`  
> **Note**: Configs live in `config/`, not `config/collector/`

## Metric Naming Convention

Full Prometheus metric format: **`{namespace}_{column_name}`**

- **namespace** = `name` field from collector config (metric prefix)
- **column_name** = `rename` if specified, else the SQL column alias
- **LABEL** columns → Prometheus labels (not separate metrics)
- **DISCARD** columns → not exported

---

## 1. 0110-pg.yml – Basic Info

| Field | Value |
|-------|-------|
| **Collector names** | `pg_primary_only`, `pg_replica_only` |
| **Namespace** | `pg` |
| **Tags** | `cluster`, `primary` / `cluster`, `replica` |

### Key metrics (GAUGE/COUNTER)

| Column | Usage | Full metric name |
|--------|-------|------------------|
| timestamp | GAUGE | `pg_timestamp` |
| uptime | GAUGE | `pg_uptime` |
| boot_time | GAUGE | `pg_boot_time` |
| lsn | COUNTER | `pg_lsn` |
| insert_lsn | COUNTER | `pg_insert_lsn` |
| write_lsn | COUNTER | `pg_write_lsn` |
| flush_lsn | COUNTER | `pg_flush_lsn` |
| receive_lsn | COUNTER | `pg_receive_lsn` |
| replay_lsn | COUNTER | `pg_replay_lsn` |
| reload_time | GAUGE | `pg_reload_time` |
| conf_reload_time | GAUGE | `pg_conf_reload_time` |
| last_replay_time | GAUGE | `pg_last_replay_time` |
| lag | GAUGE | `pg_lag` |
| is_in_recovery | GAUGE | `pg_is_in_recovery` |
| is_wal_replay_paused | GAUGE | `pg_is_wal_replay_paused` |

---

## 2. 0130-pg_setting.yml – Settings

| Field | Value |
|-------|-------|
| **Collector name** | `pg_setting` |
| **Namespace** | `pg_setting` |
| **Tags** | `cluster` |

### Key metrics (all GAUGE)

| Column | Usage | Full metric name |
|--------|-------|------------------|
| max_connections | GAUGE | `pg_setting_max_connections` |
| max_prepared_transactions | GAUGE | `pg_setting_max_prepared_transactions` |
| max_locks_per_transaction | GAUGE | `pg_setting_max_locks_per_transaction` |
| max_worker_processes | GAUGE | `pg_setting_max_worker_processes` |
| max_parallel_workers | GAUGE | `pg_setting_max_parallel_workers` |
| max_parallel_workers_per_gather | GAUGE | `pg_setting_max_parallel_workers_per_gather` |
| max_parallel_maintenance_workers | GAUGE | `pg_setting_max_parallel_maintenance_workers` |
| max_replication_slots | GAUGE | `pg_setting_max_replication_slots` |
| max_wal_senders | GAUGE | `pg_setting_max_wal_senders` |
| block_size | GAUGE | `pg_setting_block_size` |
| wal_block_size | GAUGE | `pg_setting_wal_block_size` |
| segment_size | GAUGE | `pg_setting_segment_size` |
| wal_segment_size | GAUGE | `pg_setting_wal_segment_size` |
| shared_buffers | GAUGE | `pg_setting_shared_buffers` |
| work_mem | GAUGE | `pg_setting_work_mem` |
| maintenance_work_mem | GAUGE | `pg_setting_maintenance_work_mem` |
| effective_cache_size | GAUGE | `pg_setting_effective_cache_size` |
| min_wal_size | GAUGE | `pg_setting_min_wal_size` |
| max_wal_size | GAUGE | `pg_setting_max_wal_size` |
| checkpoint_timeout | GAUGE | `pg_setting_checkpoint_timeout` |
| checkpoint_completion_target | GAUGE | `pg_setting_checkpoint_completion_target` |
| autovacuum | GAUGE | `pg_setting_autovacuum` |
| autovacuum_max_workers | GAUGE | `pg_setting_autovacuum_max_workers` |
| ... | | *(30+ more)* |

---

## 3. 0210-pg_repl.yml – Replication

| Field | Value |
|-------|-------|
| **Collector names** | `pg_repl_12`, `pg_repl_10` |
| **Namespace** | `pg_repl` |
| **Tags** | `cluster` |

### Labels

| Column | Usage |
|--------|-------|
| appname | LABEL |
| usename | LABEL |
| address | LABEL |
| pid | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| client_port | GAUGE | `pg_repl_client_port` |
| state | GAUGE | `pg_repl_state` |
| sync_state | GAUGE | `pg_repl_sync_state` |
| sync_priority | GAUGE | `pg_repl_sync_priority` |
| backend_xmin | COUNTER | `pg_repl_backend_xmin` |
| lsn | COUNTER | `pg_repl_lsn` |
| sent_diff | GAUGE | `pg_repl_sent_diff` |
| write_diff | GAUGE | `pg_repl_write_diff` |
| flush_diff | GAUGE | `pg_repl_flush_diff` |
| replay_diff | GAUGE | `pg_repl_replay_diff` |
| sent_lsn | COUNTER | `pg_repl_sent_lsn` |
| write_lsn | COUNTER | `pg_repl_write_lsn` |
| flush_lsn | COUNTER | `pg_repl_flush_lsn` |
| replay_lsn | COUNTER | `pg_repl_replay_lsn` |
| write_lag | GAUGE | `pg_repl_write_lag` |
| flush_lag | GAUGE | `pg_repl_flush_lag` |
| replay_lag | GAUGE | `pg_repl_replay_lag` |
| time | COUNTER | `pg_repl_time` |
| launch_time | COUNTER | `pg_repl_launch_time` |
| reply_time | GAUGE | `pg_repl_reply_time` *(PG12+)* |

---

## 4. 0310-pg_size.yml – Database Size

| Field | Value |
|-------|-------|
| **Collector name** | `pg_size` |
| **Namespace** | `pg_size` |
| **Tags** | `cluster` |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL (database or `wal`, `log`) |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| bytes | GAUGE | `pg_size_bytes` |

---

## 5. 0330-pg_bgwriter.yml – Background Writer

| Field | Value |
|-------|-------|
| **Collector names** | `pg_bgwriter_17`, `pg_bgwriter_10` |
| **Namespace** | `pg_bgwriter` |
| **Tags** | `cluster` |

### Key metrics (PG 9.4–16)

| Column | Usage | Full metric name |
|--------|-------|------------------|
| checkpoints_timed | COUNTER | `pg_bgwriter_checkpoints_timed` |
| checkpoints_req | COUNTER | `pg_bgwriter_checkpoints_req` |
| checkpoint_write_time | COUNTER | `pg_bgwriter_checkpoint_write_time` |
| checkpoint_sync_time | COUNTER | `pg_bgwriter_checkpoint_sync_time` |
| buffers_checkpoint | COUNTER | `pg_bgwriter_buffers_checkpoint` |
| buffers_clean | COUNTER | `pg_bgwriter_buffers_clean` |
| buffers_backend | COUNTER | `pg_bgwriter_buffers_backend` |
| maxwritten_clean | COUNTER | `pg_bgwriter_maxwritten_clean` |
| buffers_backend_fsync | COUNTER | `pg_bgwriter_buffers_backend_fsync` |
| buffers_alloc | COUNTER | `pg_bgwriter_buffers_alloc` |
| reset_time | GAUGE | `pg_bgwriter_reset_time` |

### Key metrics (PG 17+)

| Column | Usage | Full metric name |
|--------|-------|------------------|
| buffers_clean | COUNTER | `pg_bgwriter_buffers_clean` |
| maxwritten_clean | COUNTER | `pg_bgwriter_maxwritten_clean` |
| buffers_alloc | COUNTER | `pg_bgwriter_buffers_alloc` |
| reset_time | GAUGE | `pg_bgwriter_reset_time` |

---

## 6. 0331-pg_checkpointer.yml – Checkpointer

| Field | Value |
|-------|-------|
| **Collector names** | `pg_checkpointer_18`, `pg_checkpointer_17`, `pg_checkpointer_10` |
| **Namespace** | `pg_checkpointer` |
| **Tags** | `cluster` |

### Key metrics (with rename)

| Column | rename | Usage | Full metric name |
|--------|-------|-------|------------------|
| num_timed / checkpoints_timed | timed | COUNTER | `pg_checkpointer_timed` |
| num_requested / checkpoints_req | req | COUNTER | `pg_checkpointer_req` |
| num_done | done | COUNTER | `pg_checkpointer_done` *(PG18+)* |
| checkpoint_write_time | write_time | COUNTER | `pg_checkpointer_write_time` |
| checkpoint_sync_time | sync_time | COUNTER | `pg_checkpointer_sync_time` |
| buffers_checkpoint | buffers_written | COUNTER | `pg_checkpointer_buffers_written` |
| restartpoints_timed | — | COUNTER | `pg_checkpointer_restartpoints_timed` |
| restartpoints_req | — | COUNTER | `pg_checkpointer_restartpoints_req` |
| restartpoints_done | — | COUNTER | `pg_checkpointer_restartpoints_done` |
| slru_written | — | COUNTER | `pg_checkpointer_slru_written` *(PG18+)* |
| reset_time | — | GAUGE | `pg_checkpointer_reset_time` |

---

## 7. 0390-pg_wal.yml – WAL

| Field | Value |
|-------|-------|
| **Collector names** | `pg_wal_18`, `pg_wal_14` |
| **Namespace** | `pg_wal` |
| **Tags** | `cluster` |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| records | COUNTER | `pg_wal_records` |
| fpi | COUNTER | `pg_wal_fpi` |
| bytes | COUNTER | `pg_wal_bytes` |
| buffers_full | COUNTER | `pg_wal_buffers_full` |
| write | COUNTER | `pg_wal_write` *(PG14–17)* |
| sync | COUNTER | `pg_wal_sync` *(PG14–17)* |
| write_time | COUNTER | `pg_wal_write_time` *(PG14–17)* |
| sync_time | COUNTER | `pg_wal_sync_time` *(PG14–17)* |
| reset_time | GAUGE | `pg_wal_reset_time` |

---

## 8. 0410-pg_activity.yml – Activity / Connections

| Field | Value |
|-------|-------|
| **Collector name** | `pg_activity` |
| **Namespace** | `pg_activity` |
| **Tags** | `cluster` |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |
| state | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| count | GAUGE | `pg_activity_count` |
| max_duration | GAUGE | `pg_activity_max_duration` |
| max_tx_duration | GAUGE | `pg_activity_max_tx_duration` |
| max_conn_duration | GAUGE | `pg_activity_max_conn_duration` |

---

## 9. 0450-pg_lock.yml – Locks

| Field | Value |
|-------|-------|
| **Collector name** | `pg_lock` |
| **Namespace** | `pg_lock` |
| **Tags** | `cluster` |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |
| mode | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| count | GAUGE | `pg_lock_count` |

---

## 10. 0460-pg_query.yml – pg_stat_statements

| Field | Value |
|-------|-------|
| **Collector names** | `pg_query_17`, `pg_query_13`, `pg_query_10` |
| **Namespace** | `pg_query` |
| **Tags** | `cluster`, `extension:pg_stat_statements` |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |
| query | LABEL (queryid) |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| calls | COUNTER | `pg_query_calls` |
| rows | COUNTER | `pg_query_rows` |
| exec_time | COUNTER | `pg_query_exec_time` |
| io_time | COUNTER | `pg_query_io_time` |
| wal_bytes | COUNTER | `pg_query_wal_bytes` *(PG13+)* |
| sblk_hit | COUNTER | `pg_query_sblk_hit` |
| sblk_read | COUNTER | `pg_query_sblk_read` |
| sblk_dirtied | COUNTER | `pg_query_sblk_dirtied` |
| sblk_written | COUNTER | `pg_query_sblk_written` |

---

## 11. 0610-pg_db.yml – Database Stats

| Field | Value |
|-------|-------|
| **Collector names** | `pg_db_18`, `pg_db_14`, `pg_db_12`, `pg_db_10` |
| **Namespace** | `pg_db` |
| **Tags** | `cluster` |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| datid | GAUGE | `pg_db_datid` |
| age | GAUGE | `pg_db_age` |
| numbackends | GAUGE | `pg_db_numbackends` |
| xact_commit | COUNTER | `pg_db_xact_commit` |
| xact_rollback | COUNTER | `pg_db_xact_rollback` |
| xact_total | COUNTER | `pg_db_xact_total` |
| blks_read | COUNTER | `pg_db_blks_read` |
| blks_hit | COUNTER | `pg_db_blks_hit` |
| blks_access | COUNTER | `pg_db_blks_access` |
| tup_returned | COUNTER | `pg_db_tup_returned` |
| tup_fetched | COUNTER | `pg_db_tup_fetched` |
| tup_inserted | COUNTER | `pg_db_tup_inserted` |
| tup_updated | COUNTER | `pg_db_tup_updated` |
| tup_deleted | COUNTER | `pg_db_tup_deleted` |
| tup_modified | COUNTER | `pg_db_tup_modified` |
| conflicts | COUNTER | `pg_db_conflicts` |
| temp_files | COUNTER | `pg_db_temp_files` |
| temp_bytes | COUNTER | `pg_db_temp_bytes` |
| deadlocks | COUNTER | `pg_db_deadlocks` |
| blk_read_time | COUNTER | `pg_db_blk_read_time` |
| blk_write_time | COUNTER | `pg_db_blk_write_time` |
| session_time | COUNTER | `pg_db_session_time` *(PG14+)* |
| active_time | COUNTER | `pg_db_active_time` *(PG14+)* |
| ixact_time | COUNTER | `pg_db_ixact_time` *(PG14+)* |
| sessions | COUNTER | `pg_db_sessions` *(PG14+)* |
| sessions_abandoned | COUNTER | `pg_db_sessions_abandoned` *(PG14+)* |
| sessions_fatal | COUNTER | `pg_db_sessions_fatal` *(PG14+)* |
| sessions_killed | COUNTER | `pg_db_sessions_killed` *(PG14+)* |
| reset_time | GAUGE | `pg_db_reset_time` |

---

## 12. 0700-pg_table.yml – Table Stats

| Field | Value |
|-------|-------|
| **Collector names** | `pg_table_18`, `pg_table_16`, `pg_table_13`, `pg_table_10` |
| **Namespace** | `pg_table` |
| **Tags** | *(per-database)* |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |
| relname | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| relid | GAUGE | `pg_table_relid` |
| kind | GAUGE | `pg_table_kind` |
| pages | GAUGE | `pg_table_pages` |
| tuples | GAUGE | `pg_table_tuples` |
| seq_scan | COUNTER | `pg_table_seq_scan` |
| seq_tup_read | COUNTER | `pg_table_seq_tup_read` |
| idx_scan | COUNTER | `pg_table_idx_scan` |
| idx_tup_fetch | COUNTER | `pg_table_idx_tup_fetch` |
| n_tup_ins | COUNTER | `pg_table_n_tup_ins` |
| n_tup_upd | COUNTER | `pg_table_n_tup_upd` |
| n_tup_del | COUNTER | `pg_table_n_tup_del` |
| n_tup_mod | COUNTER | `pg_table_n_tup_mod` |
| n_live_tup | GAUGE | `pg_table_n_live_tup` |
| n_dead_tup | GAUGE | `pg_table_n_dead_tup` |
| vacuum_count | COUNTER | `pg_table_vacuum_count` |
| autovacuum_count | COUNTER | `pg_table_autovacuum_count` |
| heap_blks_read | COUNTER | `pg_table_heap_blks_read` |
| heap_blks_hit | COUNTER | `pg_table_heap_blks_hit` |
| idx_blks_read | COUNTER | `pg_table_idx_blks_read` |
| idx_blks_hit | COUNTER | `pg_table_idx_blks_hit` |

---

## 13. 0710-pg_index.yml – Index Stats

| Field | Value |
|-------|-------|
| **Collector name** | `pg_index` |
| **Namespace** | `pg_index` |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |
| idxname | LABEL |
| relname | LABEL |
| relid | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| relpages | GAUGE | `pg_index_relpages` |
| reltuples | GAUGE | `pg_index_reltuples` |
| idx_scan | COUNTER | `pg_index_idx_scan` |
| idx_tup_read | COUNTER | `pg_index_idx_tup_read` |
| idx_tup_fetch | COUNTER | `pg_index_idx_tup_fetch` |
| idx_blks_read | COUNTER | `pg_index_idx_blks_read` |
| idx_blks_hit | COUNTER | `pg_index_idx_blks_hit` |

---

## 14. 0810-pg_table_size.yml – Table Size

| Field | Value |
|-------|-------|
| **Collector name** | `pg_table_size` |
| **Namespace** | `pg_table_size` (defaults to branch name) |
| **Note** | Slow query, TTL 300s |

### Labels

| Column | Usage |
|--------|-------|
| datname | LABEL |
| relname | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| bytes | GAUGE | `pg_table_size_bytes` |
| relsize | GAUGE | `pg_table_size_relsize` |
| indexsize | GAUGE | `pg_table_size_indexsize` |
| toastsize | GAUGE | `pg_table_size_toastsize` |

---

## 15. 0910-pgbouncer_list.yml – PgBouncer List

| Field | Value |
|-------|-------|
| **Collector name** | `pgbouncer_list` |
| **Namespace** | `pgbouncer_list` |
| **Tags** | `pgbouncer` |

### Labels

| Column | Usage |
|--------|-------|
| list | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| items | GAUGE | `pgbouncer_list_items` |

---

## 16. 0920-pgbouncer_database.yml – PgBouncer Database

| Field | Value |
|-------|-------|
| **Collector names** | `pgbouncer_database_124`, `pgbouncer_database_123`, `pgbouncer_database_116`, `pgbouncer_database_108` |
| **Namespace** | `pgbouncer_database` |
| **Tags** | `pgbouncer` |

### Labels (with rename)

| Column | rename | Usage |
|--------|--------|-------|
| name | datname | LABEL |
| host | — | LABEL |
| port | — | LABEL |
| database | real_datname | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| pool_size | GAUGE | `pgbouncer_database_pool_size` |
| min_pool_size | GAUGE | `pgbouncer_database_min_pool_size` *(1.16+)* |
| reserve_pool_size | reserve_pool | GAUGE | `pgbouncer_database_reserve_pool` |
| server_lifetime | GAUGE | `pgbouncer_database_server_lifetime` |
| max_connections | GAUGE | `pgbouncer_database_max_connections` |
| current_connections | GAUGE | `pgbouncer_database_current_connections` |
| max_client_connections | GAUGE | `pgbouncer_database_max_client_connections` *(1.24+)* |
| current_client_connections | GAUGE | `pgbouncer_database_current_client_connections` *(1.24+)* |
| paused | GAUGE | `pgbouncer_database_paused` |
| disabled | GAUGE | `pgbouncer_database_disabled` |

---

## 17. 0930-pgbouncer_stat.yml – PgBouncer Stat

| Field | Value |
|-------|-------|
| **Collector names** | `pgbouncer_stat_124`, `pgbouncer_stat_123`, `pgbouncer_stat_108` |
| **Namespace** | `pgbouncer_stat` |
| **Tags** | `pgbouncer` |

### Labels

| Column | rename | Usage |
|--------|--------|-------|
| database | datname | LABEL |

### Key metrics

| Column | Usage | Full metric name |
|--------|-------|------------------|
| total_xact_count | COUNTER | `pgbouncer_stat_total_xact_count` |
| total_query_count | COUNTER | `pgbouncer_stat_total_query_count` |
| total_received | COUNTER | `pgbouncer_stat_total_received` |
| total_sent | COUNTER | `pgbouncer_stat_total_sent` |
| total_xact_time | COUNTER | `pgbouncer_stat_total_xact_time` |
| total_query_time | COUNTER | `pgbouncer_stat_total_query_time` |
| total_wait_time | COUNTER | `pgbouncer_stat_total_wait_time` |
| avg_xact_count | GAUGE | `pgbouncer_stat_avg_xact_count` |
| avg_query_count | GAUGE | `pgbouncer_stat_avg_query_count` |
| avg_recv | GAUGE | `pgbouncer_stat_avg_recv` |
| avg_sent | GAUGE | `pgbouncer_stat_avg_sent` |
| avg_xact_time | GAUGE | `pgbouncer_stat_avg_xact_time` |
| avg_query_time | GAUGE | `pgbouncer_stat_avg_query_time` |
| avg_wait_time | GAUGE | `pgbouncer_stat_avg_wait_time` |

---

## 18. 0940-pgbouncer_pool.yml – PgBouncer Pool

| Field | Value |
|-------|-------|
| **Collector names** | `pgbouncer_pool_124`, `pgbouncer_pool_118`, `pgbouncer_pool_116`, `pgbouncer_pool_108` |
| **Namespace** | `pgbouncer_pool` |
| **Tags** | `pgbouncer` |

### Labels

| Column | rename | Usage |
|--------|--------|-------|
| database | datname | LABEL |
| user | — | LABEL |
| pool_mode | — | LABEL |
| load_balance_hosts | — | LABEL *(1.24+)* |

### Key metrics (with rename)

| Column | rename | Usage | Full metric name |
|--------|-------|-------|------------------|
| cl_active | active_clients | GAUGE | `pgbouncer_pool_active_clients` |
| cl_waiting | waiting_clients | GAUGE | `pgbouncer_pool_waiting_clients` |
| cl_active_cancel_req | active_cancel_clients | GAUGE | `pgbouncer_pool_active_cancel_clients` |
| cl_waiting_cancel_req | cancel_clients | GAUGE | `pgbouncer_pool_cancel_clients` |
| sv_active | active_servers | GAUGE | `pgbouncer_pool_active_servers` |
| sv_idle | idle_servers | GAUGE | `pgbouncer_pool_idle_servers` |
| sv_used | used_servers | GAUGE | `pgbouncer_pool_used_servers` |
| sv_tested | tested_servers | GAUGE | `pgbouncer_pool_tested_servers` |
| sv_login | login_servers | GAUGE | `pgbouncer_pool_login_servers` |
| maxwait | — | GAUGE | `pgbouncer_pool_maxwait` |
| maxwait_us | — | GAUGE | `pgbouncer_pool_maxwait_us` |

---

## Quick Reference: Namespace → File

| Namespace | Config file | Purpose |
|-----------|-------------|---------|
| `pg` | 0110-pg.yml | Basic instance info (primary/replica) |
| `pg_setting` | 0130-pg_setting.yml | PostgreSQL settings |
| `pg_repl` | 0210-pg_repl.yml | Replication (pg_stat_replication) |
| `pg_size` | 0310-pg_size.yml | Database/WAL/log size |
| `pg_bgwriter` | 0330-pg_bgwriter.yml | Background writer |
| `pg_checkpointer` | 0331-pg_checkpointer.yml | Checkpointer |
| `pg_wal` | 0390-pg_wal.yml | WAL stats |
| `pg_activity` | 0410-pg_activity.yml | Connections by state |
| `pg_lock` | 0450-pg_lock.yml | Lock counts |
| `pg_query` | 0460-pg_query.yml | pg_stat_statements |
| `pg_db` | 0610-pg_db.yml | Database stats |
| `pg_table` | 0700-pg_table.yml | Table stats |
| `pg_index` | 0710-pg_index.yml | Index stats |
| `pg_table_size` | 0810-pg_table_size.yml | Table size |
| `pgbouncer_list` | 0910-pgbouncer_list.yml | PgBouncer lists |
| `pgbouncer_database` | 0920-pgbouncer_database.yml | PgBouncer databases |
| `pgbouncer_stat` | 0930-pgbouncer_stat.yml | PgBouncer stats |
| `pgbouncer_pool` | 0940-pgbouncer_pool.yml | PgBouncer pools |

---

## Built-in Metrics (from exporter binary)

Not from YAML config:

- `pg_up` – 1 if scrape succeeded
- `pg_version` – PostgreSQL version
- `pg_in_recovery` – 1 if replica
- `pg_exporter_build_info` – exporter build info
- `pg_exporter_*` – exporter self-metrics (disable with `--disable-intro`)

---

*Generated from pgsty/pg_exporter main branch config files.*
