# MicroserviceHighLatencyP99

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
P99 latency exceeds 2 seconds for 10 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

**Fires when**: P99 latency exceeds 2 seconds for 10 minutes.

**Severity**: warning

P99 captures tail latency -- the worst 1% of requests. High P99 with normal P95 indicates occasional outlier requests.

**Additional causes** (beyond P95 causes):
- Retry storms from downstream clients
- Lock contention in database
- Cold start after idle (first request warming up caches)
