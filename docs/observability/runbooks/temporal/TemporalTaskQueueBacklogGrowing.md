# TemporalTaskQueueBacklogGrowing

| | |
|---|---|
| **Severity** | warning |
| **Category** | platform |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `approximate_backlog_count` — **Temporal server** gauge (matching service), scraped through the chart's ServiceMonitors |
| **Status** | active |
| **Dashboard** | Temporal → Server (panel "Task-queue backlog (server view)") |
| **Local-stack** | present — the compose twin scrapes the server too, but nothing scales there |

## Meaning

`max by (taskqueue) (approximate_backlog_count) > 10` for 10 minutes — more than
ten tasks have been waiting in one queue for ten minutes. The label is the
server's `taskqueue` (no underscore in the name, underscores in the value:
`order_fulfillment`), which is *not* the SDK's `task_queue` label used by the
schedule-to-start rule.

Ten is twice the `targetQueueSize` (5) that the KEDA `ScaledObject` scales on
([ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/)). A backlog
that size for that long therefore means one of three things: the scaler is at
`maxReplicaCount`, it is not rendered for the version that owns the backlog, or
its poll against the frontend is failing. A healthy scaler keeps this alert quiet.

`load.js` (`make e2e-load`) is the one path that has produced a non-zero backlog
on this platform (peaks of 20–36 with the worker drained); a load run *will*
push this over 10 briefly, and `for: 10m` is what separates a drill from a
stuck queue.

## Impact

Work is durable — nothing is lost — but every saga step behind the queue waits.
Sustained, this turns into `TemporalScheduleToStartLatencyHigh` at critical and
then into activity timeouts and retries. For the order queue that is orders
parked in `confirming`; for the checkout queue it is abandoned-checkout timers
firing late, which is tolerable for far longer.

## Diagnosis

### PromQL

```promql
# The alert expr
max by (taskqueue) (approximate_backlog_count{job=~".*temporal.*"})

# How old is the oldest waiting task
max by (taskqueue) (approximate_backlog_age_seconds{job=~".*temporal.*"})

# Is anyone polling: worker-side poll counters (SDK label task_queue)
sum by (task_queue) (rate(temporal_workflow_task_queue_poll_succeed_total[5m]))
sum by (task_queue) (rate(temporal_workflow_task_queue_poll_empty_total[5m]))

# Did replicas follow the backlog
kube_deployment_status_replicas{namespace=~"order|checkout", deployment=~"order-fulfillment.*|checkout-abandon.*"}

# KEDA's own view: the value it computed and any scaler errors
keda_scaler_metrics_value{scaler="temporalScaler"}
rate(keda_scaler_detail_errors_total{scaler="temporalScaler"}[5m])
```

### Grafana

- **Temporal → Server** — backlog and backlog age side by side: a growing age
  with a flat count means the queue is starved of pollers, not flooded.
- **Kubernetes → Workloads** — replicas of the versioned worker Deployments over
  the same window.

- **Workflows / Async → KEDA — Worker Autoscaling** — what the scaler computed
  per version, what the HPA did, and KEDA's own errors; the first place to look
  when replicas do not follow the backlog.

### kubectl / logs

```bash
Q=<taskqueue from the alert, e.g. order_fulfillment>
NS=order                                 # checkout for the checkout queue

# Which versions exist, which is Current, which is draining
kubectl -n "$NS" get wd -o wide

# One ScaledObject and one HPA per running version; Ready/Active conditions
kubectl -n "$NS" get scaledobject,hpa
kubectl -n "$NS" get scaledobject -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.triggers[0].metadata.workerDeploymentBuildId}{"\t"}{.status.conditions[*].type}={.status.conditions[*].status}{"\n"}{end}'

# The WorkerResourceTemplate's per-version apply status
kubectl -n "$NS" get wrt -o yaml | sed -n '/status:/,$p'

# KEDA operator errors (frontend unreachable, bad metadata)
kubectl -n keda logs deploy/keda-operator --since=15m | grep -i -E 'temporal|error' | tail -20

# The server's own description of the queue, per version
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal task-queue describe \
  --task-queue order-fulfillment --namespace mop --report-stats
```

Read the results as:

1. **Replicas at `maxReplicaCount` (3), backlog still growing** — real load
   beyond the ceiling.
2. **Replicas at 1, `ScaledObject` `Active=False`** — KEDA sees no backlog for
   the build id it was told about. Usually the backlog belongs to a *different*
   version (a draining one) or the template did not get its trigger metadata
   injected — the `""` sentinel keys must be present in
   `kubernetes/apps/<worker-deployment>-scaler.yaml`.
3. **`ScaledObject` `Ready=False`** — the poll fails: `temporal-frontend:7233`
   unreachable from the `keda` namespace, wrong Temporal namespace, or the
   FrontendGlobalWorkerDeploymentReadRPS budget (50 per namespace) is being
   hit — at two scalers polling every 15 s that would need something else to be
   hammering the API.
4. **No pollers at all** (poll counters flat, age climbing) — the worker itself is
   down or misconnected; see
   [TemporalWorkerRequestErrorRateHigh](TemporalWorkerRequestErrorRateHigh.md).

## Mitigation

1. Shape 4 → restore the worker first; scaling cannot help a queue nobody polls.
2. Shape 3 → fix KEDA's reach (NetworkPolicy is ingress-only on this platform,
   so look at the frontend Service and KEDA operator logs), or the trigger
   metadata in the template. Restarting `keda-operator` re-registers every
   trigger.
3. Shape 2 → confirm the backlog's version with `--report-stats`; a draining
   version keeps `minReplicaCount: 1` by design and drains at that speed.
4. Shape 1 → raise `maxReplicaCount` by PR in the scaler template; never by
   editing the rendered `ScaledObject` (the controller re-applies it).
5. Do **not** patch the `WorkerDeployment` replicas to chase the backlog: the
   HPA KEDA owns will fight it, and the two controllers alternate.

## Escalation

Warning is a ticket while `TemporalScheduleToStartLatencyHigh` stays below
critical. Page when both fire together on the order queue, or when the age keeps
climbing with pollers present — that is a stuck queue, not a slow one. What not
to do: `kubectl scale` a versioned Deployment, or drop the Floor to zero on a
version that may hold pinned workflows.

## Related

- [TemporalScheduleToStartLatencyHigh](TemporalScheduleToStartLatencyHigh.md) —
  the worker-side view of the same wait.
- [TemporalWorkerTaskSlotsExhausted](TemporalWorkerTaskSlotsExhausted.md) — when
  the pollers exist but every slot is busy.
- [k6 — Building a Temporal backlog](../../../testing/k6.md#building-a-temporal-backlog)
  — how to produce this condition on purpose and watch the scaler answer it.

```bash
git log --oneline -5 -- kubernetes/apps/order-fulfillment-scaler.yaml kubernetes/infra/controllers/keda/helmrelease.yaml
```

---
_Last updated: 2026-09-05 — created with the KEDA scaler it gives a signal to (ADR-055)_
