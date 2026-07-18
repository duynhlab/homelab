# MicroserviceApdexCritical

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Apdex score drops below 0.5 for 10 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

**Fires when**: Apdex score drops below 0.5 for 10 minutes.

**Severity**: warning

Apdex below 0.5 means the majority of users are experiencing "frustrating" response times (> 2 seconds). This is worse than a simple latency alert because it accounts for the full distribution, not just a percentile.

**Investigation**:

```promql
# Current Apdex
app:http_server_request_duration_seconds:apdex5m{app="$APP"}

# Breakdown: what percentage of requests are satisfied/tolerating/frustrating?
# Satisfied (< 0.5s)
sum(rate(http_server_request_duration_seconds_bucket{app="$APP", le="0.5"}[5m]))
/ sum(rate(http_server_request_duration_seconds_count{app="$APP"}[5m]))

# Frustrating (> 2s)
1 - (
  sum(rate(http_server_request_duration_seconds_bucket{app="$APP", le="2"}[5m]))
  / sum(rate(http_server_request_duration_seconds_count{app="$APP"}[5m]))
)
```

**Resolution**: Follow the latency investigation workflow. Low Apdex usually means widespread latency, not just tail latency.
