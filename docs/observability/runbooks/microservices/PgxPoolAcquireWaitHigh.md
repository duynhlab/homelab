# PgxPoolAcquireWaitHigh

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
`pgxpool_empty_acquire_total` (acquires that had to wait for a free conn) grows >1/s for 10 minutes — the earliest saturation signal, usually before hard exhaustion.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

**Fires when**: `pgxpool_empty_acquire_total` (acquires that had to wait for a free conn) grows >1/s for 10 minutes — the earliest saturation signal, usually before hard exhaustion.

**Severity**: warning

**Investigation**: `pgxpool_empty_acquire_wait_time_nanoseconds_total` gives the total time spent waiting; divide by `pgxpool_empty_acquire_total` for mean wait per blocked acquire. Same remediation fork as PgxPoolNearExhaustion.
