# MicroserviceNoSuccessfulRequests

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Zero 2xx responses for 10 minutes, but the service had traffic in the prior hour.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Meaning after 2026-08-24 — this one is not benign
If this fires, **requests are arriving and none of them are succeeding.** It no
longer fires on an idle cluster, so there is nothing to disambiguate before
acting.

That used to be the operator's job. The expression guarded on
`rate(total[1h]) > 0` — *had* traffic — which made its condition a strict
**superset** of [`MicroserviceNoTraffic`](MicroserviceNoTraffic.md)'s: no
requests at all also means no 2xx, so every time that warning fired this
critical fired with it and paged. On a platform with bursty traffic and no
continuous synthetic load, that was every gate run — measured at **8**
`(app, namespace)` pairs on an idle cluster. The old runbook told you to check
whether `MicroserviceNoTraffic` was firing for the same `app` and, if so, to
treat this page as a consequence.

The guard is now `rate(total[10m]) > 0` — traffic **now** — so the alert fires
only in the case that same paragraph called "real and paging". Idleness stays
with `MicroserviceNoTraffic` (warning, non-paging); a service receiving nothing
at all is covered at critical by `MicroserviceDown`,
`MicroserviceAllInstancesDown` and the edge's `EdgeUpstreamUnhealthy` /
`Edge5xxRatioCritical`.

First question, then: **what status codes is it returning?**

```bash
# What the service itself reports, by code
curl -s "$VM/api/v1/query" --data-urlencode \
  'query=sum by (http_response_status_code) (rate(http_server_request_duration_seconds_count{app="'"$APP"'"}[10m]))'
```

Nothing but `5..` points at the application; nothing but `4..` points at the
callers or the route (a path that no longer exists will do it); nothing but
`3..` means the "success" class needs widening rather than the service being
broken — see the note beside the expression in `alerts.yaml`.

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
