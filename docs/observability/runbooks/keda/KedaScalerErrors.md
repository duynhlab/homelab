# KedaScalerErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | platform |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/keda/alerts.yaml` |
| **Metrics** | `keda_scaler_detail_errors_total` (KEDA 2.20 name — `keda_scaler_errors_total` does not exist) |
| **Status** | active |
| **Dashboard** | Workflows / Async → KEDA — Worker Autoscaling (panel "Scaler errors") |
| **Local-stack** | not present — compose runs no KEDA |

## Meaning

A trigger on one `ScaledObject` has returned an error on every poll for five
minutes. Here the only trigger type is `temporal`, so the failing call is
`DescribeTaskQueueEnhanced` against `temporal-frontend.temporal.svc:7233` for
one worker version's task queue. While the trigger errors, KEDA keeps that
version at its last replica count; the backlog it should drain is invisible.

Labels tell you where: `exported_namespace` (order / checkout), `scaledObject`
(the controller's hashed per-version name), `scaler` (`temporalScaler`).

## Impact

One worker version stops following load. If it is the Current version, the
queue grows and `TemporalTaskQueueBacklogGrowing` follows; if it is a draining
version, nothing visible happens (it sits at `minReplicaCount: 1` anyway) and
the alert is mostly telling you a build id the server no longer knows is still
being polled.

## Diagnosis

### PromQL

```promql
# The alert expr
sum by (exported_namespace, scaledObject, scaler) (rate(keda_scaler_detail_errors_total[5m]))

# Is it every scaler (frontend / network) or one (bad metadata for one version)
count by (scaler) (rate(keda_scaler_detail_errors_total[5m]) > 0)

# Latency of the calls that do succeed
max by (scaler, scaledObject) (keda_scaler_metrics_latency_seconds{exported_namespace=~"order|checkout"})
# (a GAUGE of the last fetch, not a histogram — keda_scaler_metrics_latency_seconds_bucket
#  does not exist; verified against pkg/metricscollector/prommetrics.go at v2.20.2)

# Is the frontend itself unhappy
sum(rate(service_error_with_type{job=~".*temporal.*"}[5m]))
```

### Grafana

- **Workflows / Async → KEDA — Worker Autoscaling** — "Scaler errors" says which
  ScaledObject; "Scaler metric latency p95" says whether the frontend is slow
  for the calls that do succeed.

### kubectl / logs

```bash
NS=order                                         # or checkout
SO=<scaledObject from the alert>

# Conditions: Ready=False carries the trigger's error text
kubectl -n "$NS" describe scaledobject "$SO" | sed -n '/Conditions/,/Events/p'

# The injected metadata — must be the server-side name, a real build id, and mop
kubectl -n "$NS" get scaledobject "$SO" -o jsonpath='{.spec.triggers[0].metadata}{"\n"}'

# Does that build id still exist on the server
kubectl -n "$NS" get wd -o wide
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal worker deployment describe \
  --name "$NS/<worker-deployment>" --namespace mop

# The operator's own words
kubectl -n keda logs deploy/keda-operator --since=15m | grep -i -E "temporal|error" | tail -30

# Reachability from the keda namespace (NetworkPolicy is ingress-only here, so
# a failure is DNS, the Service, or the frontend itself)
kubectl -n keda run probe --rm -it --restart=Never --image=busybox:1.37 -- \
  nc -zv temporal-frontend.temporal.svc.cluster.local 7233
```

Read the results as:

1. **Every scaler errors, frontend unreachable** — network or the frontend
   Service; `TemporalServerDown` or `TemporalServiceErrorRateHigh` usually
   co-fires.
2. **One scaler errors with "build id not found" / "deployment not found"** —
   the version was deleted on the server side but its `ScaledObject` copy is
   still there. The controller removes the copy with the Deployment
   (`deleteDelay` 24h); until then the poll fails harmlessly. Confirm with
   `kubectl -n "$NS" get wrt -o yaml` (per-version apply status).
3. **Metadata wrong** — `workerDeploymentName` / `workerDeploymentBuildId` /
   `namespace` empty or hardcoded. Empty means the controller did not inject
   (template missing the `""` sentinel keys); hardcoded means the webhook was
   bypassed. Fix the template, never the rendered object.
4. **Resource exhausted / rate limited** — the frontend's 50 RPS per-namespace
   budget. Two scalers at 15 s cannot reach it; something else is calling the
   API.

## Mitigation

1. Shape 1 → fix the frontend first; the scaler recovers on its next poll.
2. Shape 2 → nothing, unless the copy outlives its Deployment: then
   `kubectl -n "$NS" get wrt -o yaml` and check the controller logs for the
   failed delete.
3. Shape 3 → edit `kubernetes/apps/<worker-deployment>-scaler.yaml` by PR; the
   controller re-renders every version's `ScaledObject`.
4. Shape 4 → find the other caller before touching KEDA's `pollingInterval`.
5. Do not `kubectl delete scaledobject` to clear the error — the controller
   re-applies it within a reconcile and the HPA history is lost.

## Escalation

Ticket, unless the failing version is Current and
`TemporalTaskQueueBacklogGrowing` co-fires — then it is the page. What not to
do: hand-edit trigger metadata on the rendered `ScaledObject` (Server-Side
Apply reverts it) or raise the WorkerDeployment's replicas to compensate while
leaving the broken trigger in place.

## Related

- [KedaScaledObjectErrors](KedaScaledObjectErrors.md) — the object itself, not
  its trigger.
- [TemporalTaskQueueBacklogGrowing](../temporal/TemporalTaskQueueBacklogGrowing.md)
  — the downstream symptom.
- [ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/) — the `""`
  sentinel rule and the poll budget.

```bash
git log --oneline -5 -- kubernetes/apps/order-fulfillment-scaler.yaml kubernetes/apps/checkout-abandon-scaler.yaml
```

---
_Last updated: 2026-09-05 — created with the KEDA install (ADR-055)_
