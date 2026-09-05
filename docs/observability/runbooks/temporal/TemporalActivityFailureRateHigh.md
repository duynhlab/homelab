# TemporalActivityFailureRateHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | workflow |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `temporal_activity_execution_failed_total`, `temporal_activity_execution_latency_seconds_count` — **Go SDK** |
| **Status** | active |
| **Dashboard** | Temporal → Workers |
| **Local-stack** | present |

## Meaning

Failed activity executions as a fraction of all executions. Note the denominator
is the **latency histogram's count**, not a `_completed_total` — the SDK does not
emit one, so the count of observed executions stands in for it. Worth knowing
before "correcting" the expression.

Activities are where a workflow touches the outside world: a gRPC call to
`inventory`, a payment authorisation, a shipping request. So this alert usually
points at a **dependency**, not at Temporal.

## Impact

Activities retry by policy, so a moderate rate is invisible to customers and
merely slow. Sustained failure exhausts the retry policy and fails the workflow —
which is why this alert usually precedes
[TemporalWorkflowFailureRateHigh](TemporalWorkflowFailureRateHigh.md).

## Diagnosis

Find which activity, then which dependency:

```promql
topk(10, sum by (service_name, activity_type) (rate(temporal_activity_execution_failed_total[10m])))
```

```bash
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal workflow show --namespace mop --workflow-id <id>
```

The event history names the activity, its attempt count and the error string —
which is nearly always faster than reading worker logs.

Then check the dependency the activity calls. On this platform the common ones
are `inventory` (gRPC), `payment` → `mockpay`, and `shipping`:

```promql
sum by (service_name) (rate(rpc_server_call_duration_seconds_count{rpc_grpc_status_code!="0"}[5m]))
sum by (service_name) (rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))
```

## Mitigation

1. **One activity type** → the dependency it calls is the suspect. Its own RED
   alerts should agree; if they do not, the fault is in the call, not the callee.
2. **A dependency is genuinely down** → fix that; the activities recover on
   retry without intervention.
3. **All activity types across both workers** → look at the platform:
   [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md).
4. Do not raise retry limits to silence it. The retries are already hiding the
   failure; more of them hides it longer.

## Escalation

Warning. Escalate to whichever service the failing activity calls, not to
Temporal.

## Related

- [TemporalWorkflowFailureRateHigh](TemporalWorkflowFailureRateHigh.md) — what
  this becomes when retries run out.
- [TemporalWorkerTaskSlotsExhausted](TemporalWorkerTaskSlotsExhausted.md) — slow
  activities hold slots and can produce both alerts together.

---
_Last updated: 2026-09-05 — created; the temporal alert group had no runbooks at all_
