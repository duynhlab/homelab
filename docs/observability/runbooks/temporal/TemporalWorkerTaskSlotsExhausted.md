# TemporalWorkerTaskSlotsExhausted

| | |
|---|---|
| **Severity** | warning |
| **Category** | workflow |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `temporal_worker_task_slots_available` — **Go SDK** gauge |
| **Status** | active |
| **Dashboard** | Temporal → Workers |
| **Local-stack** | present |

## Meaning

`min(temporal_worker_task_slots_available) == 0` — some worker has no free slot
to accept another task. Every executor (workflow, activity, local activity) has a
bounded slot pool; at zero, that worker stops pulling work.

**A limitation to know before you start.** The expression is a **global `min`**
across every reporting worker — 27 series on this cluster from three distinct
sources: Temporal's own system worker (`service_name="worker"`, 21 series),
`checkout-worker` (3) and `order-worker` (3). So the alert tells you *someone* is
saturated and not *who*. Start by finding out:

```promql
min by (service_name, worker_type) (temporal_worker_task_slots_available)
```

## Impact

Throughput drops for that worker's queues. Tasks are not lost — they wait — but
end-to-end saga latency rises and, if it lasts, activities begin hitting their
`StartToClose` timeouts and retrying, which makes it worse.

## Diagnosis

After identifying the worker, decide which of three shapes it is:

```promql
# Is it saturation, or a leak
min by (service_name, worker_type) (temporal_worker_task_slots_available)
sum by (service_name) (rate(temporal_activity_execution_latency_seconds_count[5m]))

# Are activities running long -- slow work holds slots
histogram_quantile(0.95, sum by (le, service_name) (rate(temporal_activity_execution_latency_seconds_bucket[5m])))
```

1. **Genuine load** — task rate is high and slots recover between bursts. Normal.
2. **Slow activities** — the rate is ordinary but latency is high, so each task
   holds its slot far longer than it should. The fix is in the activity's
   dependency, not in the worker.
3. **Stuck tasks** — slots at zero with no throughput at all. Look for activities
   that never complete.

```bash
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal task-queue describe \
  --task-queue <queue> --namespace mop
```

## Mitigation

1. **Slow dependency** → fix the dependency; see
   [TemporalActivityFailureRateHigh](TemporalActivityFailureRateHigh.md).
2. **Genuine sustained load** → scale the worker Deployment, which is the honest
   answer, rather than raising slot counts to hide the queueing.
3. **Temporal's own system worker saturated** → that is a server-side signal, not
   an application one, and belongs with the server alerts.
4. Raising `maxConcurrent*` on a worker whose dependency is slow moves the
   queue from Temporal into the dependency. It does not add capacity.

## Escalation

Warning. Escalate if it coincides with rising activity failures — that
combination is the path to workflow timeouts.

## Related

- [TemporalActivityFailureRateHigh](TemporalActivityFailureRateHigh.md) — slow or
  failing activities are the usual cause.
- [TemporalWorkflowFailureRateHigh](TemporalWorkflowFailureRateHigh.md) — what
  sustained exhaustion eventually produces.

---
_Last updated: 2026-09-05 — created; the temporal alert group had no runbooks at all_
