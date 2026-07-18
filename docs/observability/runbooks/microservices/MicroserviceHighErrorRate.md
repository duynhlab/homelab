# MicroserviceHighErrorRate

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
5xx error rate exceeds 5% of total traffic for 5 minutes.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Application bug (nil pointer, unhandled error)
- Downstream dependency failure (database, external API)
- Resource exhaustion (connection pool, file descriptors)
- Bad deployment (new code with regression)

### Investigation
```promql
# Error rate by service
app:http_server_request_duration_seconds:error_ratio5m{app="$APP"}

# Error rate by endpoint (find the hot path)
app_route:http_server_request_duration_seconds:error_rate5m{app="$APP"} > 0

# Was there a deployment recently?
kube_pod_container_status_restarts_total{namespace="$NAMESPACE"}
```

```bash
# Check application logs for errors
kubectl logs -n $NAMESPACE -l app=$APP --tail=200 | grep -i error

# Check recent deployments
kubectl rollout history deployment/$APP -n $NAMESPACE
```

**Grafana panels to check**:
- Row 1: Error Rate %
- Row 3: Server Errors (5xx), Error Rate by Method and Endpoint

## Mitigation
1. Identify failing endpoint from per-endpoint error rate
2. Search the `trace_id` field in VictoriaLogs for the error logs, then open the linked trace in Tempo (traces<->logs correlation). Exemplars are not available -- VictoriaMetrics does not support them (RFC-0014 D-14)
3. If new deployment: rollback with `kubectl rollout undo`
4. If DB issue: check PostgreSQL alerts
