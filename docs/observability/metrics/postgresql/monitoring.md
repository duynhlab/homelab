# PostgreSQL Monitoring

All PostgreSQL on the platform runs on **CloudNativePG (CNPG)**. Each cluster
exposes the CNPG **built-in exporter on `:9187`** (metrics prefixed `cnpg_`) plus
a custom-queries ConfigMap, scraped by a **per-cluster `PodMonitor`**.

## Architecture

```mermaid
flowchart LR
    subgraph databases["CloudNativePG clusters"]
        platformDB["platform-db<br/>platform · 3 instances"]
        productDB["product-db<br/>product · 3 instances"]
        productDR["product-db-replica<br/>product · DR"]
    end

    subgraph poolers["PgDog poolers"]
        platformPgDog["pgdog-platform<br/>OpenMetrics :9090"]
        productPgDog["pgdog-product<br/>OpenMetrics :9090"]
    end

    subgraph discovery["Scrape discovery"]
        cnpgMon["Per-cluster PodMonitor<br/>CNPG exporter :9187<br/>cnpg_* + custom queries"]
        pgdogMon["ServiceMonitors<br/>PgDog :9090"]
    end

    subgraph metrics["VictoriaMetrics"]
        vma["VMAgent<br/>scrape + remote write"]
        vms[("VMSingle :8428")]
        vmop["VM Operator<br/>rule conversion"]
        vmrule["VMRule"]
        vmalert["VMAlert<br/>rule evaluation"]
    end

    platformDB -->|":9187"| cnpgMon
    productDB -->|":9187"| cnpgMon
    productDR -->|":9187"| cnpgMon

    platformPgDog --> pgdogMon
    productPgDog --> pgdogMon

    cnpgMon -->|scrape| vma
    pgdogMon -->|scrape| vma
    vma -->|remote write| vms
    vms -->|"PromQL / MetricsQL"| grafana["Grafana"]

    ruleCRs["PostgreSQL PrometheusRule CRs"] --> vmop --> vmrule --> vmalert
    vmalert -->|query| vms

    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    class platformDB,productDB,productDR,platformPgDog,productPgDog external;
    class cnpgMon,pgdogMon,ruleCRs,vmrule data;
    class vma,vms metric;
    class vmop,vmalert,grafana platform;
```

## Cluster inventory

| Cluster | Namespace | Instances | Databases | Database metrics | Pooler metrics |
|---|---|---|---|---|---|
| `platform-db` | platform | 3 | auth, user, notification, shipping, review, temporal, temporal_visibility | CNPG `:9187` via PodMonitor | `pgdog-platform :9090` |
| `product-db` (+ `product-db-replica` DR) | product | 3 | product, cart, order, payment | CNPG `:9187` via PodMonitor | `pgdog-product :9090` |

## Metric coverage

The CNPG built-in exporter emits `cnpg_collector_*` health/replication/backup
metrics plus every custom query defined in the cluster's monitoring ConfigMap
(CNPG auto-prefixes those with `cnpg_`).

| Metric layer | Source |
|---|---|
| Availability | `cnpg_collector_up` |
| Replication (streaming) | `cnpg_collector_sync_replicas`, `cnpg_pg_replication_lag` |
| WAL status | `cnpg_collector_pg_wal` |
| Backup status | `cnpg_collector_last_available_backup_timestamp`, `cnpg_collector_last_failed_backup_timestamp` |
| pg_stat_statements | custom query (`cnpg_pg_stat_statements_*`) |
| Connection stats | custom query (`cnpg_pg_connection_limits_*`) |
| Lock contention | custom query (`cnpg_pg_locks_count_*`, `cnpg_pg_blocking_queries_*`) |
| Autovacuum / dead tuples | custom query (`cnpg_pg_stat_user_tables_autovacuum_*`) |
| Table / index size | custom query (`cnpg_pg_table_size_*`, `cnpg_pg_stat_user_indexes_*`) |
| Checkpoints | custom query (`cnpg_pg_stat_bgwriter_checkpoints_*`) |
| Database size | custom query (`cnpg_pg_database_size_*`) |
| Pooler metrics | PgDog OpenMetrics `:9090` |

## Exporter: CNPG built-in

- **Used by**: all clusters — the built-in exporter is mandatory for CNPG and cannot be replaced.
- **Port**: `9187`.
- **Format**: postgres_exporter-compatible query format. CNPG prefixes **all** metrics (built-in collectors and custom queries) with `cnpg_`.
- **Custom queries**: a per-cluster ConfigMap referenced from `spec.monitoring.customQueriesConfigMapList`; queries keep their original names and CNPG auto-prefixes the emitted metrics.

> **Retired with the Zalando→CNPG migration.** The former Zalando/Spilo clusters
> and their exporters were removed: the postgres_exporter sidecar (`:9187`) on
> `auth-db`, the Pigsty **pg_exporter** (`:9630`, 600+ metrics) pilot on
> `supporting-shared-db`, and the **pgbouncer-exporter** (`:9127`). The 44
> pg-exporter recording rules and the pg_exporter Grafana dashboards were retired
> along with them. The reference material for that pilot is kept for reference
> only: [pg-exporter-dashboards.md](pg-exporter-dashboards.md),
> [pg-exporter-mapping.md](pg-exporter-mapping.md).

## Custom queries

CNPG clusters define custom queries in a per-cluster monitoring ConfigMap. Queries
keep their original names and CNPG auto-prefixes every emitted metric with `cnpg_`.
Queries with `target_databases` include `current_database() AS datname` to
disambiguate co-located databases on the multi-database clusters (e.g. product,
cart, order, payment on `product-db`).

| Query name | CNPG metric prefix | Purpose |
|---|---|---|
| pg_stat_statements | `cnpg_pg_stat_statements_*` | Top 100 queries by execution time |
| pg_connection_limits | `cnpg_pg_connection_limits_*` | Connection saturation |
| pg_locks_count | `cnpg_pg_locks_count_*` | Lock distribution |
| pg_blocking_queries | `cnpg_pg_blocking_queries_*` | Queries waiting on locks |
| pg_stat_user_tables_autovacuum | `cnpg_pg_stat_user_tables_autovacuum_*` | Dead tuples and vacuum activity |
| pg_table_size | `cnpg_pg_table_size_*` | Table size (top 30) |
| pg_stat_user_indexes | `cnpg_pg_stat_user_indexes_*` | Index usage and size |
| pg_database_size | `cnpg_pg_database_size_*` | Database sizes |
| pg_stat_bgwriter_checkpoints | `cnpg_pg_stat_bgwriter_checkpoints_*` | Checkpoint frequency and I/O |

Per-metric query details (columns, labels, filtering) are documented in
[custom-metrics.md](custom-metrics.md).

### PromQL examples

```promql
# Connection saturation
cnpg_pg_connection_limits_current_connections / cnpg_pg_connection_limits_max_connections

# Dead-tuple ratio
cnpg_pg_stat_user_tables_autovacuum_n_dead_tup

# Top queries by execution time
topk(10, rate(cnpg_pg_stat_statements_time_milliseconds[5m]))

# Database size
cnpg_pg_database_size_size_bytes

# Streaming replication lag (physical)
cnpg_pg_replication_lag
```

## Alert rules

### PostgreSQL `PrometheusRule` layout (`prometheusrules/postgres/`)

CNPG alert rules are chart-generated per cluster (one file per upstream
`cluster-*.yaml` from the [cloudnative-pg/charts](https://github.com/cloudnative-pg/charts)
`cluster` chart), each in the cluster's own namespace:

- **[`postgres/cnpg/`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/cnpg/)** — `product-db` (namespace `product`): the full HA set plus small extras (`CnpgClusterFenced`, `PostgresWALSizeHigh`) and the **global operator-health singleton** (`CNPGOperatorDown`, `CNPGControllerReconcileErrorsSpiking`, namespace `cloudnative-pg`).
- **[`postgres/cnpg-platform-db/`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/cnpg-platform-db/)** — `platform-db` (namespace `platform`): full HA set (offline, fencing, HA, connections, physical + logical replication, disk, WAL); covers auth, supporting services, and Temporal persistence.

Backup alerts (`PostgresBackupTooOld`, `PostgresBackupFailed`) live in
`postgres/backup-alerts.yaml`. The full per-alert catalog with impact is in
[alert-catalog.md](../../alerting/alert-catalog.md#4-postgresql--cloudnativepg).

**Note**: Rules are evaluated by **VMAlert** against **VMSingle**; Grafana Alerting can show read-only rules proxied via VMSingle (see [`docs/observability/metrics/victoriametrics.md`](../victoriametrics.md)). Notifications route through VMAlertmanager (Slack wired, webhook injected out-of-band).

## Audit and query-plan logging

DB audit and query-plan logs do **not** use per-cluster exporters or sidecars.
`pgaudit` (`pgaudit.log = 'ddl, write'`) and `auto_explain` output is written to
the CNPG pod logs, tailed by the cluster-wide **Vector DaemonSet**, and shipped to
**VictoriaLogs** as CNPG-parsed structured records — audit rows carry
`logger: pgaudit` (CNPG parsing strips the literal `AUDIT:` prefix). See
[VictoriaLogs](../../logging/victorialogs.md) for the pipeline.

## References

- [Custom metrics query guide](custom-metrics.md) — CNPG custom queries, columns, PromQL
- [Database Guide](../../../databases/002-database-integration.md) — custom queries configuration
- [Metrics hub](../README.md) — methodology, stack, and coverage
- [PromQL Guide](../promql-guide.md) — PromQL functions and examples
- [Alert Catalog](../../alerting/alert-catalog.md) — every deployed PostgreSQL alert
- Retired reference: [pg-exporter-dashboards.md](pg-exporter-dashboards.md), [pg-exporter-mapping.md](pg-exporter-mapping.md)

---
_Last updated: 2026-07-17 — RFC-0018: platform-db + pgdog-platform inventory; cnpg-platform-db alert ownership._
