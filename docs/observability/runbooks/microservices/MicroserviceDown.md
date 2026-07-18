# MicroserviceDown

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
A previously seen `go_goroutine_count` heartbeat disappears and remains absent for 2 minutes. The apps push OTLP (SDK -> otel-collector -> vmagent), so there is no scraped `up` series. VictoriaMetrics staleness adds about 5 minutes before the 2-minute hold begins, making effective detection roughly 5-7 minutes (accepted in RFC-0014 D-4).

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Pod crashed (OOMKilled, application panic, segfault)
- Pod evicted (node resource pressure)
- Deployment rollout in progress
- NetworkPolicy or collector outage breaking the OTLP push path (SDK -> otel-collector -> vmagent)

### Investigation
```bash
# Check pod status
kubectl get pods -n $NAMESPACE -l app=$APP

# Check events
kubectl describe pod -n $NAMESPACE $POD_NAME

# Check recent logs
kubectl logs -n $NAMESPACE -l app=$APP --tail=100

# Check if deployment rollout in progress
kubectl rollout status deployment/$APP -n $NAMESPACE
```

```promql
# Verify: which pods stopped emitting metrics? (heartbeat absence, D-4)
count by (app, namespace, k8s_pod_name) (last_over_time(go_goroutine_count{app="$APP"}[15m]))
  unless count by (app, namespace, k8s_pod_name) (go_goroutine_count{app="$APP"})

# Check restart history
increase(kube_pod_container_status_restarts_total{namespace="$NAMESPACE", pod=~"$APP.*"}[1h])
```

## Mitigation
1. If rollout in progress: wait for completion, monitor new pods
2. If OOMKilled: check Pyroscope heap profiles, increase memory limits
3. If CrashLoopBackOff: check application logs for startup errors
4. If network issue: check NetworkPolicy and Service endpoints
