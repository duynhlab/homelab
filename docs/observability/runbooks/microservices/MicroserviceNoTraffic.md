# MicroserviceNoTraffic

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Zero requests for 10 minutes, but the service had traffic in the prior hour.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Upstream service stopped calling this service
- Ingress/Service misconfiguration (endpoints removed)
- DNS resolution failure
- Network policy blocking traffic
- Deployment deleted the Service resource

### Investigation
```bash
# Check Service endpoints
kubectl get endpoints -n $NAMESPACE $APP

# Check Service exists
kubectl get svc -n $NAMESPACE $APP

# Check if pods are ready
kubectl get pods -n $NAMESPACE -l app=$APP -o wide

# Check Ingress/route
kubectl get ingress -n $NAMESPACE
```

```promql
# Verify zero traffic
app:http_server_request_duration_seconds:rate5m{app="$APP"}

# Check if the service is still emitting metrics (heartbeat, D-4) -- the apps push
# OTLP and expose no scrape target, so there is no `up` series
count by (app, namespace, k8s_pod_name) (go_goroutine_count{app="$APP"})
```

## Mitigation
1. If endpoints empty: check Service selector matches pod labels
2. If pods not ready: check readiness probe failures
3. If upstream issue: check upstream service health
4. May be expected during maintenance windows -- verify with team
