# MicroserviceNoSuccessfulRequests

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Zero 2xx responses for 10 minutes, but the service had traffic in the prior hour.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Complete application failure (all requests returning 5xx)
- Misconfigured routing (Ingress/Service pointing to wrong port)
- Database connection pool exhausted
- Panic recovery returning 500 for every request

### Investigation
```promql
# Check status code distribution
sum by (http_response_status_code) (rate(http_server_request_duration_seconds_count{app="$APP"}[5m]))

# Is there traffic at all?
app:http_server_request_duration_seconds:rate5m{app="$APP"}
```

## Mitigation
1. If all 5xx: follow `MicroserviceErrorRateCritical` runbook
2. If no traffic at all: follow `MicroserviceNoTraffic` runbook
3. If all 4xx: check for authentication/authorization issues
