# TemporalScheduleToStartLatencyHigh

Shared by the warning and critical rules of the same name — the procedure is
identical; only the threshold differs.

| | |
|---|---|
| **Severity** | warning at p99 > 200 ms for 10m; critical at p99 > 1 s for 5m |
| **Category** | platform |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `temporal_workflow_task_schedule_to_start_latency_seconds_bucket` — **Go SDK** histogram via OTLP |
| **Status** | active |
| **Dashboard** | Temporal → Workflows (panel "Workflow task schedule-to-start latency") |
| **Local-stack** | present (SDK metric arrives through the same OTLP path); the KEDA half is not — compose has no autoscaler |

## Meaning

Schedule-to-start is the time a workflow task sat in its task queue between the
server scheduling it and a worker actually picking it up. It is the purest
"not enough workers" signal Temporal has: it grows *before* slots are exhausted
and before any error fires. p99 above 200 ms for ten minutes means the queue is
regularly waiting on a poller; above 1 s for five minutes means sagas are
visibly stalling.

The honest qualifier: a brief spike on every deploy is normal — a new version's
pollers take a few seconds to register — and `for: 10m` is what filters that out.

Since [ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/) this
alert has an actuator: KEDA renders one `ScaledObject` per running worker
version and adds replicas from the queue backlog. So the first question is no
longer "how do I add a pod" but "why did the scaler not".

## Impact

End-to-end saga latency rises by the queue wait on every step. Nothing is lost —
tasks wait — but `StartToClose` timeouts on activities start to trip if it
persists, and those retries make the queue longer. The shopper sees orders that
stay `confirming` longer than the budget in
[`OrderSagaNotCompleting`](../microservices/README.md).

## Diagnosis

### PromQL

```promql
# The alert expr, per queue
histogram_quantile(0.99, sum by (le, task_queue) (rate(temporal_workflow_task_schedule_to_start_latency_seconds_bucket[5m])))

# Is the backlog behind it real (server view; note the label is taskqueue, underscore values)
max by (taskqueue) (approximate_backlog_count{job=~".*temporal.*"})

# Did the scaler react — replicas per versioned Deployment
kube_deployment_status_replicas{namespace=~"order|checkout", deployment=~"order-fulfillment.*|checkout-abandon.*"}

# Is KEDA reading the queue at all
keda_scaler_metrics_value{scaler="temporalScaler"}
keda_scaler_detail_errors_total{scaler="temporalScaler"}
```

### Grafana

- **Temporal → Workflows** — the schedule-to-start panel next to the task-slot
  panel: slots at zero *and* rising schedule-to-start is saturation; slots free
  *and* rising schedule-to-start is a polling problem.
- **Temporal → Server** — the backlog panel (`approximate_backlog_count`) tells
  whether tasks are queued at all.

- **Workflows / Async → KEDA — Worker Autoscaling** — what the scaler computed
  per version, what the HPA did, and KEDA's own errors; the first place to look
  when replicas do not follow the backlog.

### kubectl / logs

```bash
Q=<task_queue from the alert>           # order-fulfillment or checkout
NS=order                                # checkout for the checkout queue

# One ScaledObject per running build id, each pointing at its versioned Deployment
kubectl -n "$NS" get scaledobject,hpa
kubectl -n "$NS" describe scaledobject | sed -n '/Status/,$p'

# The controller's view of the versions and their replicas
kubectl -n "$NS" get wd
kubectl -n "$NS" get wrt -o wide

# KEDA operator: connection errors to temporal-frontend show here
kubectl -n keda logs deploy/keda-operator --since=15m | grep -i -E 'temporal|error' | tail -20

# The server's own view of the queue (pollers present?)
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal task-queue describe \
  --task-queue "$Q" --namespace mop
```

Three shapes:

1. **Scaler at its ceiling** — replicas equal `maxReplicaCount` (3) and the
   backlog still grows. Genuine load beyond the ceiling.
2. **Scaler not scaling** — replicas stay at 1 while the backlog is above the
   `targetQueueSize` (5). Look at the `ScaledObject` conditions: `Ready=False`
   means KEDA cannot reach the frontend or the trigger metadata is wrong;
   `Active=False` with a real backlog means the injected `workerDeploymentBuildId`
   does not match the version that has the backlog.
3. **No backlog, high latency** — pollers are the problem, not capacity: the
   worker is up but not polling (crash loop, wrong namespace, `Connection`
   unreachable). `TemporalWorkerRequestErrorRateHigh` usually co-fires.

## Mitigation

1. **Shape 3** → fix the worker's connectivity first; see
   [TemporalWorkerRequestErrorRateHigh](TemporalWorkerRequestErrorRateHigh.md).
2. **Shape 2** → repair the scaler, do not bypass it: a `ScaledObject` with a
   failing trigger is a bug in the template or KEDA's reach to `:7233`. Editing
   the versioned Deployment's replicas by hand is undone by the HPA KEDA owns.
3. **Shape 1** → raise `maxReplicaCount` in
   `kubernetes/apps/<worker-deployment>-scaler.yaml` through a PR; the controller re-renders
   every version's `ScaledObject`. On Kind, check node CPU before you do.
4. Do **not** set `minReplicaCount: 0` on a version that may hold pinned
   workflows — that is the silent stall ADR-055's Floor rule exists to prevent.

## Escalation

Warning is a ticket: capacity tuning. Critical is a page when it coincides with
`TemporalTaskQueueBacklogGrowing` or `OrderSagaNotCompleting` — that combination
means orders are stuck, not just slow. What not to do: `kubectl scale` a
versioned Deployment (the controller and the HPA both revert it within seconds)
or raise worker concurrency to hide queueing behind a slow dependency.

## Related

- [TemporalTaskQueueBacklogGrowing](TemporalTaskQueueBacklogGrowing.md) — the
  server-side twin of this signal.
- [TemporalWorkerTaskSlotsExhausted](TemporalWorkerTaskSlotsExhausted.md) — the
  lagging indicator; slots run out after the queue has already grown.
- [ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/) — why the
  scaler reads backlog and floors at one replica.

```bash
git log --oneline -5 -- kubernetes/apps/order-fulfillment-scaler.yaml kubernetes/apps/checkout-abandon-scaler.yaml
```

---
_Last updated: 2026-09-05 — created with the KEDA scaler it gives a signal to (ADR-055)_
