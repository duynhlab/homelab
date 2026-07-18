# Capacity planning signals

Dashboard-only metrics — **no alert** fires on these series. Use for trends,
forecasting, and investigating disk runbooks when active in production. Database
size comes from CNPG's **built-in** `pg_database` query; `pg_table_size` is a
custom query (see [builtin-metrics.md](../builtin-metrics.md) / [custom-metrics.md](../custom-metrics.md)).

## Metrics

| Query | Metric | Labels |
|-------|--------|--------|
| `pg_database` (built-in) | `cnpg_pg_database_size_bytes` | `datname` |
| `pg_table_size` (custom) | `cnpg_pg_table_size_total_bytes`, `table_bytes` | `datname`, `schemaname`, `tablename` |

`pg_table_size` returns **top 30 tables** per target database only.

## PromQL

```promql
# Per-database growth
cnpg_pg_database_size_bytes{cnpg_io_cluster="product-db"}

# Largest tables
topk(20, cnpg_pg_table_size_total_bytes{cnpg_io_cluster="product-db"})
```

## When to act

- Steady growth → plan PVC expansion (production) or VACUUM bloat check —
  [CNPGAutovacuumFallingBehind](../../../runbooks/postgresql/CNPGAutovacuumFallingBehind.md).
- Sudden spike → deploy regression, bulk import, or missing partition strategy.
- Kind homelab: disk **alerts** inactive — use these gauges manually.

## target_databases gap

Per-db table metrics cover platform service DBs and product/cart/order only.
**payment**, **checkout**, **temporal** databases appear in the built-in
`cnpg_pg_database_size_bytes` (cluster-wide `pg_database` query) but not in per-db
top-table lists until added to `target_databases` in the monitoring ConfigMap.

---
_Last updated: 2026-07-18_
