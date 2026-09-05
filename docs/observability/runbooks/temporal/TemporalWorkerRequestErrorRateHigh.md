# TemporalWorkerRequestErrorRateHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | workflow |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `temporal_request_failure_total`, `temporal_request_total` — **Go SDK** client metrics |
| **Status** | active |
| **Dashboard** | Temporal → Workers |
| **Local-stack** | present |

## Meaning

More than 5% of the SDK's **requests to the Temporal server** are failing. This
is the client's view of the same surface
[TemporalServiceErrorRateHigh](TemporalServiceErrorRateHigh.md) watches from the
server: poll calls, task completions, workflow starts.

When both fire, they are one incident. When only this one fires, suspect the
path between worker and frontend rather than the frontend itself.

## Impact

Workers retry, so the immediate effect is delay rather than failure. What it
costs is throughput: tasks sit in queues longer, and a saga that should finish in
seconds takes minutes.

## Diagnosis

```promql
topk(10, sum by (service_name, operation) (rate(temporal_request_failure_total[5m])))
sum by (service_name) (rate(temporal_request_total[5m]))
```

```bash
kubectl logs -n order    -l app=order-fulfillment --tail=100 | grep -i 'fail\|error'
kubectl logs -n checkout -l app=checkout-abandon  --tail=100 | grep -i 'fail\|error'
```

### The failure mode this platform has actually seen

Workers logging, at `warn` level and with **zero** `error` lines and zero
restarts:

```
Failed to poll for task.
  Error: task queue is not ready to process polls from this deployment
         version, try again shortly
```

That is **not a worker fault.** It is the server refusing polls because matching
could not register the worker's deployment version — and matching could not
because history could not acquire its shards. The workers are behaving correctly:
poll, back off, retry.

Confirm from the server side before touching the worker:

```bash
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal worker deployment list --namespace mop
kubectl get workerdeployment -A
```

An empty deployment list, or a `WorkerDeployment` CR with an empty `CURRENT`
column, confirms it. Go to
[TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md).

Other error strings worth recognising: `context deadline exceeded` and
`stream terminated by RST_STREAM with error code: CANCEL` are the same story seen
at the gRPC layer.

## Mitigation

1. **Server struggling** → fix the server. The workers need no change.
2. **One worker only, others fine** → look at that pod: its network path, its
   `TEMPORAL_HOSTPORT`, its restart history.
3. Restarting workers to "clear" this rarely helps and loses in-flight task
   progress.

## Escalation

Warning. Escalate with the server-side evidence attached — a worker alert without
it invites someone to debug the wrong repository.

## Related

- [TemporalServiceErrorRateHigh](TemporalServiceErrorRateHigh.md) — the same
  surface from the server side.
- [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md) — the
  root cause in the sequence above.
- [TemporalServerDown](TemporalServerDown.md)

---
_Last updated: 2026-09-05 — created; the temporal alert group had no runbooks at all_
