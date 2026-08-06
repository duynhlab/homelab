# MicroserviceNoSuccessfulRequests

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Zero 2xx responses for 10 minutes, but the service had traffic in the prior hour.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Expected on a rebuilt cluster — read this first
Same shape as [`MicroserviceNoTraffic`](MicroserviceNoTraffic.md#expected-on-a-rebuilt-cluster--read-this-first),
and it fires **with** it: no requests at all also means no 2xx. After any
bounded burst of traffic (fresh `make up`, e2e audit, seed) both fire from about
`t+20m` and both resolve on their own once the `[1h]` lookback empties at `t+1h`.
`for:` was not lengthened, for the reason set out there.

Disambiguate before treating it as an incident: if `MicroserviceNoTraffic` is
firing for the same `app`, there is **no traffic** and this alert is a
consequence — follow that runbook. This alert only means "total failure" when
requests are still arriving, i.e. it fires **alone**. That case is real and
paging.

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
