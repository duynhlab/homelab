# Pigsty pg_exporter Monitor Dashboards – Analysis

This document analyzes the Grafana dashboards shipped in the Pigsty [pg_exporter](https://github.com/pgsty/pg_exporter) `monitor/` directory. The analysis supports the PostgreSQL monitoring pilot plan for `supporting-shared-db`.

**Source**: https://github.com/pgsty/pg_exporter/tree/main/monitor  
**README reference**: "There are two monitoring dashboards in the `monitor/` directory."

---

## 1. Monitor Directory Contents

| File | Type | Size | Purpose |
|------|------|------|---------|
| `pgsql-exporter.json` | Dashboard | ~127 KB | Exporter self-monitoring (aliveness, scrape metrics, collectors) |
| `pgrds-instance.json` | Dashboard | ~417 KB | PostgreSQL instance monitoring (RDS/remote with limited metrics) |
| `initdb.sh` | Script | ~21 KB | Init script (not a dashboard) |

---

## 2. Dashboard 1: pgsql-exporter.json

### 2.1 Metadata

| Field | Value |
|-------|-------|
| **Title** | PGSQL Exporter |
| **UID** | `pgsql-exporter` |
| **Description** | PostgreSQL Instance Dashboard |
| **Author** | Ruohang Feng (rh@vonng.com) |
| **License** | AGPLv3 @ https://pigsty.io/docs/about/license |
| **Tags** | Pigsty, PGSQL, Instance |

**Purpose**: Monitors the **pg_exporter process itself** (scrape duration, errors, uptime, collector health), not PostgreSQL databases directly. Useful for observability of the exporter and debugging scrape issues.

### 2.2 Template Variables

| Variable | Query | Description |
|----------|-------|-------------|
| `ins` | `label_values(pg_up, ins)` | Instance identifier (e.g., pg-meta-1) |
| `ip` | `label_values(pg_up{ins="$ins"}, ip)` | IP address of the Postgres instance (hidden) |
| `seq` | `label_values(pg_up{ins="$ins"}, ins)` with regex `/^[a-zA-Z0-9-_]+-(\d+)$/` | Sequence number (hidden) |
| `cls` | `label_values(pg_up{ins="$ins"}, cls)` | Cluster identifier (e.g., pg-meta, pg-test) (hidden) |
| `node` | `label_values(node_uname_info{ip="$ip"}, nodename)` | Node hostname (hidden) |
| `datname` | `label_values(pg_db_age{ins="$ins",datname!~'postgres\|template0\|template1'}, datname)` | Non-trivial database (hidden) |

**Important**: Pigsty uses labels `ins`, `cls`, `ip`. Our Kubernetes setup uses `kubernetes_pod_name`, `cluster_name`, `kubernetes_namespace`. Variable queries must be adapted for our label set.

### 2.3 Panel Titles (by Row)

| Row | Panels |
|-----|--------|
| **Overview** | Export Status (table), Aliveness (timeseries) |
| **Global Status** | Aliveness, Scrape Duration, Global Uptime, Global Error Rate, Instance table |
| **Metrics** | Up Time, Exporter Aliveness, Scrape Duration, Errors Count Per Minute, Scrape Duration (per Server), Scrape Count Per Minute |
| **Collectors** | Query Errors, Metrics Count, Query Duration, Query Cache Hit Rate, Cache TTL |
| **PG Exporter Logs: ${ins}** | Logs per $__interval, Recent Logs (Loki) |

### 2.4 Key PromQL Expressions

| Panel | Expression |
|-------|------------|
| Export Status | `max by (ins) (pg_exporter_agent_up{cls="$cls"})`, `max by (ins) (pgbouncer_exporter_agent_up{cls="$cls"})`, `max by (ins) (pgbackrest_exporter_agent_up{cls="$cls"})`, `pg_exporter_uptime`, `pgbouncer_exporter_uptime` |
| Aliveness | `pg_exporter_agent_up{ins="$ins"}`, `pgbouncer_exporter_agent_up{ins="$ins"}`, `pg_up{ins="$ins"}`, `pgbouncer_up{ins="$ins"}`, `patroni_up{ins="$ins"}`, `pgbackrest_exporter_agent_up{ins="$ins"}` |
| Scrape Duration | `pg_exporter_scrape_duration{}` |
| Global Uptime | `pg_exporter_uptime{}`, `pgbouncer_exporter_uptime{}` |
| Global Error Rate | `increase(pg_exporter_scrape_error_count{}[1m])`, `increase(pgbouncer_exporter_scrape_error_count{}[1m])` |
| Exporter Aliveness | `pg_exporter_agent_up{ins="$ins"}`, `pgbouncer_exporter_agent_up{ins="$ins"}`, `pgbackrest_exporter_agent_up{ins="$ins"}` |
| Scrape Duration (per Server) | `pg_exporter_server_scrape_duration{ins="$ins"}`, `pgbouncer_exporter_server_scrape_duration{ins="$ins"}` |
| Scrape Count Per Minute | `increase(pg_exporter_server_scrape_total_count{ins="$ins"}[1m])`, `increase(pgbouncer_exporter_server_scrape_total_count{ins="$ins"}[1m])` |
| Query Errors | `sum by (query) (increase(pg_exporter_query_scrape_error_count{ins="$ins"}[1m]))` |
| Metrics Count | `sum by (query) (pg_exporter_query_scrape_metric_count{ins="$ins"})`, `sum by (query) (pgbouncer_exporter_query_scrape_metric_count{ins="$ins"})` |
| Query Duration | `increase(pg_exporter_query_scrape_duration{ins="$ins"}[1m]) / increase(pg_exporter_query_scrape_total_count{ins="$ins"}[1m])` |
| Query Cache Hit Rate | `increase(pg_exporter_query_scrape_hit_count{ins="$ins"}[5m]) / increase(pg_exporter_query_scrape_total_count{ins="$ins"}[5m])` |
| Cache TTL | `pg_exporter_query_cache_ttl{ins="$ins"}`, `pgbouncer_exporter_query_cache_ttl{ins="$ins"}` |
| Logs per interval | Loki: `count_over_time(({ip="$ip", src="syslog"} |~ "pg_exporter")[$__interval])` |
| Recent Logs | Loki: `{ip="$ip"} |~ "pg_exporter"` |

### 2.5 Expected Metrics (pgsql-exporter dashboard)

| Metric | Source | Notes |
|--------|--------|-------|
| `pg_up` | pg_exporter built-in | Used for variable `ins`; must have label `ins` |
| `pg_db_age` | pg_exporter collector | Used for `datname` variable |
| `pg_exporter_agent_up` | pg_exporter self-metric | Exporter process alive |
| `pgbouncer_exporter_agent_up` | pg_exporter (9xx collectors) | When pgBouncer target configured |
| `pgbackrest_exporter_agent_up` | pigsty/pgbackrest-exporter | Pigsty-specific; N/A for our stack |
| `pg_exporter_uptime` | pg_exporter self-metric | Seconds since exporter start |
| `pgbouncer_exporter_uptime` | pg_exporter | When pgBouncer target configured |
| `pg_exporter_scrape_duration` | pg_exporter self-metric | Per-scrape duration |
| `pg_exporter_scrape_error_count` | pg_exporter self-metric | Scrape error counter |
| `pg_exporter_server_scrape_duration` | pg_exporter self-metric | Per-database scrape duration |
| `pg_exporter_server_scrape_total_count` | pg_exporter self-metric | Scrape count per server |
| `pg_exporter_query_scrape_error_count` | pg_exporter self-metric | Per-query collector errors |
| `pg_exporter_query_scrape_metric_count` | pg_exporter self-metric | Metrics emitted per query |
| `pg_exporter_query_scrape_duration` | pg_exporter self-metric | Per-query scrape duration |
| `pg_exporter_query_scrape_hit_count` | pg_exporter self-metric | Cache hits |
| `pg_exporter_query_scrape_total_count` | pg_exporter self-metric | Total query scrapes |
| `pg_exporter_query_cache_ttl` | pg_exporter self-metric | Cache TTL per query |
| `patroni_up` | Patroni exporter | Pigsty HA; N/A for Zalando/CNPG |
| `node_uname_info` | node_exporter | For `node` variable; may need different datasource |

**Pilot relevance**: The **pgsql-exporter** dashboard is ideal for monitoring the exporter itself. For supporting-shared-db pilot, we can adapt it by changing variable queries to use `cluster_name`, `kubernetes_pod_name` instead of `ins`, `cls`. Exporter self-metrics are standard in pg_exporter.

---

## 3. Dashboard 2: pgrds-instance.json

### 3.1 Metadata

| Field | Value |
|-------|-------|
| **Title** | PGRDS Instance |
| **UID** | `pgrds-instance` |
| **Description** | PostgreSQL Monitoring for Remote RDS instances (with limited metrics) |
| **Author** | Ruohang Feng (rh@vonng.com) |
| **License** | AGPLv3 @ https://pigsty.io/docs/about/license |

**Purpose**: Full PostgreSQL instance monitoring for RDS or remote instances where Pigsty deploys pg_exporter. Uses **recording rules** (e.g., `pg:ins:*`, `pg:db:*`, `pg:cls:*`) computed by Prometheus from raw pg_exporter metrics.

### 3.2 Template Variables

| Variable | Query | Description |
|----------|-------|-------------|
| `ins` | `label_values(pg_up, ins)` | Instance identifier |
| `ip` | `label_values(pg_up{ins="$ins"}, ip)` | IP address (hidden) |
| `seq` | `label_values(pg_up{ins="$ins"}, ins)` with regex | Sequence number (hidden) |
| `cls` | `label_values(pg_up{ins="$ins"}, cls)` | Cluster (hidden) |
| `node` | `label_values(node_uname_info{ip="$ip"}, nodename)` | Node hostname (hidden) |
| `datname` | `label_values(pg_db_age{ins="$ins", datname!~"template0\|template1\|postgres\|rdsadmin\|polardb_admin"}, datname)` | Database (excludes RDS/PolarDB admin DBs) |

### 3.3 Panel Titles (by Row)

| Row | Panels |
|-----|--------|
| **Overview** | Stat panels: pg_up, active time rate, xact rate, in_recovery, backends, pgBouncer RT, uptime; meta info; replication/sync flags; alerts; DB sizes; connection usage; etc. |
| **Activity** | Transaction Commits/Rollbacks (rate5m), Transaction RT (1m), TPS by Database, Postgres Load, Row Fetched, Row Modified, Locks by Category, Locks, SAGE |
| **Session** | Connection Usage, Idle in Transaction Backends, Backends, New Sessions (increase1m), Backends by State, Backends by Type, Max Conn Lifespan, Backends by Wait Event, Active% (of Session Time), Sessions Failure in 1m |
| **Persist** | LSN Progress (rate1m), Age Usage, Database Cluster Size, Database WAL/Log Size, Checkpoint Scheduled/Requested, Checkpoint Time, BGWriter Buffer Flush/Alloc, Blocks Access 1m, Blocks Hit Ratio, Blocks Read, Blocks Read/Write Time Spent Rate1m |
| **Database** | Database Size, Database Size Delta 10m, TPS by Database, Session by Database, Database Blocks Hit Ratio, Idle in Transaction Backends, Connection Usage, New Sessions (incr1m), Row Fetched, Row Modified |
| **Table & Query** | Table Scan (scan/s), Tuple Read (rows/s), Query Call, Query Time, … |

### 3.4 Key PromQL Expressions (Sample)

| Category | Metrics / Recording Rules |
|----------|---------------------------|
| **Recording rules** | `pg:ins:active_time_rate1m`, `pg:ins:xact_total_rate1m`, `pg:ins:xact_commit_rate1m`, `pg:ins:xact_rollback_rate1m`, `pg:ins:num_backends`, `pg:ins:active_backends`, `pg:ins:ixact_backends`, `pg:ins:tup_fetched_rate1m`, `pg:ins:tup_modified_rate1m`, `pg:ins:age`, `pg:ins:lsn_rate1m`, `pg:ins:timeline`, `pg:ins:xlock_count`, `pg:ins:wlock_count`, `pg:ins:rlock_count` |
| **Database-level rules** | `pg:db:age`, `pg:db:xact_commit_rate1m`, `pg:db:xact_total_rate1m`, `pg:db:active_time_rate1m`, `pg:db:conn_usage`, `pg:db:blks_access_1m`, `pg:db:blks_hit_ratio1m`, `pg:db:blks_read_1m`, `pg:db:blk_read_time_seconds_rate1m`, `pg:db:blk_write_time_seconds_rate1m` |
| **Cluster-level rules** | `pg:cls:active_time_rate1m` |
| **Raw pg_exporter metrics** | `pg_up`, `pg_uptime`, `pg_version`, `pg_in_recovery`, `pg_conf_reload_time`, `pg_is_wal_replay_paused`, `pg_recv_init_lsn`, `pg_repl_lsn`, `pg_sync_standby_enabled`, `pg_pubrel_count`, `pg_sub_id`, `pg_meta_info`, `pg_size_bytes`, `pg_activity_count`, `pg_activity_max_tx_duration`, `pg_activity_max_conn_duration`, `pg_backend_count`, `pg_wait_count`, `pg_lock_count`, `pg_db_sessions`, `pg_db_sessions_abandoned`, `pg_db_sessions_fatal`, `pg_db_sessions_killed`, `pg_db_tup_fetched`, `pg_db_tup_inserted`, `pg_db_tup_updated`, `pg_db_tup_deleted`, `pg_db_active_time`, `pg_db_session_time`, `pg_db_conn_limit`, `pg_db_datid`, `pg_db_is_template`, `pg_db_numbackends`, `pg_bgwriter_*`, `pg_table_tup_read` |
| **PgBouncer (via pg_exporter)** | `pgbouncer:ins:xact_rt_1m` |
| **Alerts** | `ALERTS{ins="$ins", alertstate="firing"}` |

### 3.5 Recording Rules Dependency

The **pgrds-instance** dashboard relies heavily on **Pigsty’s Prometheus recording rules**. These rules aggregate raw pg_exporter metrics (e.g., `pg_db_*`, `pg_stat_*`) into higher-level metrics with prefixes:

- `pg:ins:*` – instance-level (e.g., xact rate, backends, LSN rate)
- `pg:db:*` – database-level (e.g., conn usage, blks hit ratio, active time)
- `pg:cls:*` – cluster-level

**Without these recording rules**, most pgrds-instance panels will show no data. To use this dashboard, we would need to:

1. Port Pigsty’s recording rules to our Prometheus, or  
2. Rewrite panels to use raw pg_exporter metrics directly (more complex PromQL).

---

## 4. Metrics Summary: What pg_exporter Exposes

From the dashboards and pg_exporter design:

| Category | Metrics | Notes |
|----------|---------|-------|
| **Built-in** | `pg_up`, `pg_version`, `pg_in_recovery`, `pg_exporter_build_info` | Always present |
| **Exporter self** | `pg_exporter_agent_up`, `pg_exporter_uptime`, `pg_exporter_scrape_duration`, `pg_exporter_scrape_error_count`, `pg_exporter_server_scrape_*`, `pg_exporter_query_scrape_*`, `pg_exporter_query_cache_ttl` | Exporter health |
| **PgBouncer (9xx collectors)** | `pgbouncer_up`, `pgbouncer_exporter_*`, `pgbouncer:ins:*` | When pgBouncer URL configured |
| **PostgreSQL (YAML collectors)** | `pg_uptime`, `pg_conf_reload_time`, `pg_size_bytes`, `pg_db_age`, `pg_db_*`, `pg_activity_count`, `pg_activity_max_*`, `pg_backend_count`, `pg_wait_count`, `pg_lock_count`, `pg_bgwriter_*`, `pg_table_tup_*`, `pg_recv_init_lsn`, `pg_repl_lsn`, etc. | From pg_exporter.yml config |

---

## 5. Pilot Adaptation Recommendations

### 5.1 pgsql-exporter Dashboard

- **Adaptability**: High. Uses exporter self-metrics that pg_exporter provides.
- **Changes**:
  - Update variable queries: replace `ins`/`cls`/`ip` with `kubernetes_pod_name` or `cluster_name` as appropriate.
  - Remove or hide panels that depend on `patroni_up`, `pgbackrest_exporter_agent_up`, `node_uname_info` if not available.
  - Replace Loki queries (`{ip="$ip"}`) with LogQL matching our logging setup (e.g., `{kubernetes_pod_name=~"$instance"}`) or remove the logs row.
- **Pilot use**: Good for monitoring scrape health, duration, and errors of the supporting-shared-db pg_exporter.

### 5.2 pgrds-instance Dashboard

- **Adaptability**: Low out-of-the-box. Depends on Pigsty recording rules.
- **Options**:
  - **A**: Deploy Pigsty’s recording rules (if compatible with our Prometheus) and adapt variable queries for Kubernetes labels.
  - **B**: Build a simplified dashboard using raw pg_exporter metrics only (no recording rules). Panels would use `pg_up`, `pg_size_bytes`, `pg_activity_count`, `pg_db_*`, etc., with direct PromQL.
  - **C**: Use pgrds-instance as reference and create a new dashboard aligned with our pilot plan (Overview, Connections, DB size, WAL, pg_stat_statements, PgBouncer, Scrape duration).
- **Pilot use**: Option B or C is more practical for the initial pilot without Pigsty’s full stack.

### 5.3 Variable Mapping for Our Stack

| Pigsty variable | Our equivalent | Source query |
|-----------------|----------------|---------------|
| `ins` | Instance / Pod | `label_values(pg_up, kubernetes_pod_name)` or `label_values(pg_up, cluster_name)` |
| `cls` | Cluster | `label_values(pg_up, cluster_name)` |
| `ip` | Optional | May use `instance` or skip |
| `datname` | Database | `label_values(pg_db_age{ins="$ins"}, datname)` (adapt `ins` filter to our label) |

---

## 6. References

- [pg_exporter GitHub](https://github.com/pgsty/pg_exporter)
- [pg_exporter README](https://github.com/pgsty/pg_exporter#readme) – "There are two monitoring dashboards in the `monitor/` directory"
- [Pigsty Demo](https://demo.pigsty.io/ui/) – Live dashboards
- [PostgreSQL Monitoring](./postgresql-monitoring.md) – Our supporting-shared-db pg_exporter pilot context
