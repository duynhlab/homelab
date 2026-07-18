# Index hygiene signals

Custom query `pg_stat_user_indexes` — per-index scan counts and size. **No
alert** — use for periodic tuning and capacity reviews.

## Metrics

| Column | Metric | Usage |
|--------|--------|-------|
| `idx_scan` | `cnpg_pg_stat_user_indexes_idx_scan` | COUNTER — zero = unused |
| `index_bytes` | `cnpg_pg_stat_user_indexes_index_bytes` | GAUGE |

## PromQL

```promql
# Unused indexes (never scanned since stats reset)
cnpg_pg_stat_user_indexes_index_bytes{cnpg_io_cluster="product-db"}
  and (cnpg_pg_stat_user_indexes_idx_scan == 0)

# Largest indexes
topk(20, cnpg_pg_stat_user_indexes_index_bytes{cnpg_io_cluster="product-db"})
```

## When to act

- `idx_scan == 0` on large indexes → candidate for drop after verifying no
  unique/FK constraint dependency (use `\d+` / catalog checks in psql).
- High `idx_scan` with poor query performance → wrong index or need composite
  index — correlate with [pg-query-performance dashboard](../../../grafana/README.md)
  and [CNPGLowCacheHitRatio runbook](../../runbooks/postgresql/CNPGLowCacheHitRatio.md).

## Caveats

- Stats reset on restart — confirm uptime before dropping.
- Partial indexes and FK indexes may show low scan but are still required.

---
_Last updated: 2026-07-18_
