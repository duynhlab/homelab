# MicroserviceErrorRateCritical

| | |
|---|---|
| **Severity** | critical |
| **Category** | errors |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml` |
| **Metrics** | `http_server_request_duration_seconds_count` (5xx share) |
| **Status** | active |
| **Dashboard** | Microservices → the service RED board |

## Meaning

The 5xx share of `http_server_request_duration_seconds_count` exceeds 15% of
total traffic for 5 minutes. This is the critical tier above
[MicroserviceHighErrorRate](MicroserviceHighErrorRate.md) (5%): same signal,
same investigation, but at 15% roughly one request in seven is failing — this
is a major failure in progress, not a degradation to study.

## Impact

A significant portion of users are being served errors right now. Whichever
journeys touch this service — login, browse, checkout — are failing for a
large fraction of attempts. Mitigation (usually a rollback) takes priority
over root-causing; the catalog stance is "rollback/mitigation now".

## Diagnosis

### PromQL

```promql
# Alert expr
(
  sum by (app, namespace) (rate(http_server_request_duration_seconds_count{app!="", http_response_status_code=~"5.."}[5m]))
  / sum by (app, namespace) (rate(http_server_request_duration_seconds_count{app!=""}[5m]))
) > 0.15

# Ready-made error ratio (recording rule)
app:http_server_request_duration_seconds:error_ratio5m{app="$APP"}

# Which route is failing — one endpoint or all of them?
app_route:http_server_request_duration_seconds:error_rate5m{app="$APP"}

# Which status codes exactly?
sum by (http_response_status_code) (rate(http_server_request_duration_seconds_count{app="$APP", http_response_status_code=~"5.."}[5m]))
```

### Grafana

- **Microservices → the service RED board** — does the error-rate step line up
  with a deploy annotation or a dependency's incident?

### kubectl / logs

```bash
APP=<app label>; NS=<namespace label>
kubectl -n "$NS" get pods -l app="$APP"          # crash-looping? partial rollout?
kubectl -n "$NS" rollout history deploy/"$APP"   # did a deploy just land?
kubectl -n "$NS" logs deploy/"$APP" --since=10m | grep -iE "error|panic" | head -50
```

### VictoriaLogs / traces

Pull the failing requests with `{app="$APP"}` filtered to 5xx/error lines,
take a `trace_id`, and open it in Tempo — the failing span names the culprit:
its own handler (panic, nil deref), the database
([DBClientErrorRate](DBClientErrorRate.md) co-firing?), or a downstream
gRPC callee.

## Mitigation

1. If the error rate started with a deploy, roll back first, diagnose later:
   revert the image pin in `kubernetes/apps/services/<app>.yaml` and let Flux
   reconcile. If not identified within 10 minutes, rolling back the most
   recent deployment is the default move.
2. If one route is failing and the rest are healthy, and that route can be
   degraded (a non-critical feature), prefer degrading it over a full
   rollback.
3. If the trace blames a dependency (DB, downstream service), work that
   component's runbook — restarting this service will not help.

## Escalation

Page — this severity exists to interrupt someone. It stays a page until the
error ratio is back under the 5% warning threshold. **Do not** `kubectl
rollout undo` directly on the cluster: Flux will re-apply the pinned version
and silently re-break the service minutes later — the rollback must go through
the GitOps pin. And do not restart pods in a loop hoping the errors clear;
each restart resets the evidence (in-memory state, logs) while the failing
version keeps running.

## Related

- [MicroserviceHighErrorRate](MicroserviceHighErrorRate.md) — the 5% warning
  tier; usually fired first.
- [MicroserviceNoSuccessfulRequests](MicroserviceNoSuccessfulRequests.md) —
  the end state if this keeps climbing.
- [DBClientErrorRate](DBClientErrorRate.md) — DB errors surfacing as 5xx.

```bash
git log --oneline -5 -- kubernetes/apps/services/
```

---
_Last updated: 2026-08-19 — rewritten to the canonical template (was a stub)_
