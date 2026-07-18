# MicroserviceGoroutineLeak

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Goroutine count exceeds 1,000 AND is steadily increasing for 15 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Forgotten `defer cancel()` on context
- Unclosed channels (goroutine blocked on send/receive forever)
- HTTP client without timeout (goroutine waiting on response indefinitely)
- Goroutine spawned in loop without bound

### Investigation
```promql
# Current goroutine count
go_goroutine_count{app="$APP"}

# Rate of increase (should be ~0 in healthy state). deriv() not rate() — the alert
# uses deriv() because go_goroutine_count is a gauge (rate() undercounts across dips).
deriv(go_goroutine_count{app="$APP"}[15m])
```

```bash
# Get goroutine dump (if pprof exposed)
kubectl port-forward -n $NAMESPACE svc/$APP 6060:6060
curl http://localhost:6060/debug/pprof/goroutine?debug=2
```

**Grafana panels**: Row 4: Goroutines & Threads

## Mitigation
1. Check Pyroscope goroutine profile for the service
2. Look for goroutines stuck in `runtime.gopark` or `chan receive`
3. Review recent code changes for missing context cancellation
4. Restart the pod as a temporary fix: `kubectl delete pod -n $NAMESPACE $POD_NAME`
