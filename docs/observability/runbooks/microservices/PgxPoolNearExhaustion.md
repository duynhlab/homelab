# PgxPoolNearExhaustion

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
`pgxpool_acquired_connections` has stayed ≥80% of `pgxpool_max_connections` for 5 minutes (`min_over_time` — sustained, not a spike).

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
slow queries holding conns (check DBClientQueryP95High), pool sized too small for the traffic level, conn leak (missing `Rows.Close`).

### Investigation
```promql
sum by (app) (pgxpool_acquired_connections) / sum by (app) (pgxpool_max_connections)
```

Compare with query p95 and traffic; if latency is flat but the pool is pinned, grow `MaxConnections`; if latency rose first, fix the queries.
