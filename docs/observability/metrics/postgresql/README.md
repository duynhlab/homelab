# PostgreSQL Metrics & Monitoring

CloudNativePG metrics, custom query signals, diagnostic workflows, and on-call
runbooks for the platform database layer.

| Quick facts | |
|---|---|
| Clusters | `platform-db` (ns `platform`), `product-db` (ns `product`), DR `product-db-replica` |
| Exporter | CNPG built-in `:9187` — prefix `cnpg_` on all series |
| Custom queries | **9** SQL definitions per cluster ConfigMap |
| Per-db scope | platform: auth, user, notification, shipping, review · product: product, cart, order |
| **Not in per-db queries** | platform: temporal, temporal_visibility · product: payment, checkout |
| Alerts | 53 rules — [alert catalog §4/§4b](../../alerting/alert-catalog.md#4-postgresql--cloudnativepg) |
| Runbooks | [postgresql/](../../runbooks/postgresql/README.md) (one file per alert) |
| Dashboards | pg-query-performance, pg-maintenance, CloudNativePG Cluster Overview |

## Learning path

1. **Architecture** — scrape path + rule layout: [Scrape architecture & rule layout](#scrape-architecture--rule-layout)
   below; full VM topology in [victoriametrics.md](../victoriametrics.md)
2. **Signals** — what each query measures and how to PromQL it:
   built-in metrics [builtin-metrics.md](builtin-metrics.md), custom queries
   [custom-metrics.md](custom-metrics.md)
3. **Runbooks** — per-alert Meaning / Impact / Diagnosis / Mitigation:
   [../runbooks/postgresql/README.md](../../runbooks/postgresql/README.md)
4. **Deep internals** — PostgreSQL concepts with homelab examples:
   [../../databases/001-postgresql-internals.md](../../../databases/001-postgresql-internals.md)
5. **Emergency** — cluster down triage (before runbook detail):
   [../../databases/010.4-emergency-recovery.md](../../../databases/010.4-emergency-recovery.md)

## Document map

| Doc | Purpose |
|-----|---------|
| [builtin-metrics.md](builtin-metrics.md) | CNPG built-in metric inventory (default queries + collector) |
| [custom-metrics.md](custom-metrics.md) | Custom query reference, PromQL, alert/runbook links |
| [signals/capacity-planning.md](signals/capacity-planning.md) | Database/table size signals (no alert) |
| [signals/index-hygiene.md](signals/index-hygiene.md) | Unused index detection (no alert) |

## Metric layers

| Layer | Metrics | Alerts |
|-------|---------|--------|
| CNPG built-in | `cnpg_collector_*`, `cnpg_pg_replication_lag`, `cnpg_pg_settings_*` | Chart rules (HA, offline, connections, …) |
| Custom queries | `cnpg_pg_stat_statements_*`, `cnpg_pg_blocking_queries_*`, … | Deep-signal rules |
| PgDog pooler | `pgdog_*` via `:9090` | — (investigate via connection runbooks) |

Connection alerts and dashboards use built-in **`cnpg_backends_total`** and
**`cnpg_pg_settings_setting{name="max_connections"}`**; see the
[HighConnections runbook](../../runbooks/postgresql/CNPGClusterHighConnectionsCritical.md).

## Scrape architecture & rule layout

Each CNPG cluster runs the built-in exporter on `:9187` (all series prefixed `cnpg_` —
built-in collectors plus custom queries referenced via `spec.monitoring.customQueriesConfigMap`),
scraped by a **per-cluster `PodMonitor`**. PgDog poolers expose OpenMetrics on `:9090` via a
`ServiceMonitor`. VMAgent scrapes both and remote-writes to VMSingle; VMAlert evaluates the
PostgreSQL `PrometheusRule`s. Full VM topology and rule pipeline:
[../victoriametrics.md](../victoriametrics.md).

**Scraped clusters:** only `platform-db` (ns `platform`) and `product-db` (ns `product`) export
metrics. `product-db-replica` is a DR replica and is **not scraped** — its pods carry
`cnpg.io/cluster=product-db-replica`, which no PodMonitor selects (live `cnpg_io_cluster` label
values are exactly `platform-db` and `product-db`).

**Alert rules** — chart-generated per cluster under
`prometheusrules/postgres/{cnpg,cnpg-platform-db}/`, plus `backup-alerts.yaml` and hand-authored
`deep-signals-alerts.yaml`. Full catalog:
[alert-catalog §4/§4b](../../alerting/alert-catalog.md#4-postgresql--cloudnativepg).

**Audit / query-plan logging** — `pgaudit` (`log: "ddl, write"`) and `auto_explain` write to CNPG
pod logs, tailed by the Vector DaemonSet into VictoriaLogs (no separate exporter):
[../../logging/victorialogs.md](../../logging/victorialogs.md).

## References

- [Database integration guide](../../../databases/002-database-integration.md)
- [PgDog operations](../../../databases/runbooks/pgdog-operations.md)
- [PromQL guide](../promql-guide.md)
- [Metrics hub](../README.md)

---
_Last updated: 2026-07-18_
