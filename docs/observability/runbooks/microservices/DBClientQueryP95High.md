# DBClientQueryP95High

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
P95 of `db_client_operation_duration_seconds_bucket{pgx_operation_type="query"}` exceeds 100ms for 10 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
missing index / plan regression, lock contention, pooler queueing, N+1 patterns, server CPU/IO pressure.

### Investigation
```promql
# Which service, and how bad
histogram_quantile(0.95, sum by (app, le)
  (rate(db_client_operation_duration_seconds_bucket{pgx_operation_type="query"}[5m])))
```

Then pivot server-side: `pg_stat_statements` (top statements by mean time), `cnpg_pg_blocking_queries`, and the otelpgx query span (trace) for the exact SQL name. Note the buckets are DB-scale (`obsx.DBDurationBuckets`, pkg ≥ v0.24.0) — with older pkg the quantile is meaningless (everything in one bucket).
