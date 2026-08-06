# MicroserviceNoTraffic

| | |
|---|---|
| **Severity** | warning |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Zero requests for 10 minutes, but the service had traffic in the prior hour.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Expected on a rebuilt cluster — read this first
This alert is **correct and self-resolving** after any bounded burst of traffic
(a fresh `make up`, an e2e audit, a browser session, a seed run). There is no
continuous synthetic load on this platform, so "traffic stopped" is the normal
end state of every test, not an incident.

The window is arithmetic, not tuning. With the last request at `t`:

| Time | `rate(...[10m])` | `rate(...[1h])` | Alert |
|---|---|---|---|
| `t` → `t+10m` | > 0 | > 0 | quiet |
| `t+10m` → `t+1h` | 0 | > 0 | **fires** (after `for: 10m`, so from ~`t+20m`) |
| after `t+1h` | 0 | 0 | resolves on its own |

So one traffic burst produces a single ~40-minute warning that clears itself.
`for:` was deliberately **not** lengthened: suppressing this case needs
`for: ≥ 50m`, which would delay a genuine total-traffic-loss signal by the same
50 minutes — trading a known-benign local annoyance for a real production blind
spot. The alert stays `warning` (non-paging on this Alertmanager).

Treat it as real when the service is **supposed** to be under load: after a
deploy that should be serving, or when a sibling service still has traffic and
this one does not. The durable fix is a continuous synthetic probe so silence
becomes meaningful — **not deployed**.

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
