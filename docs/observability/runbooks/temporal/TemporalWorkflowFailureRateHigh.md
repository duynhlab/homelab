# TemporalWorkflowFailureRateHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | workflow |
| **Source** | `kubernetes/infra/configs/temporal/prometheusrule.yaml` |
| **Metrics** | `temporal_workflow_failed_total`, `temporal_workflow_completed_total` — **Go SDK** metrics from the workers |
| **Status** | active |
| **Dashboard** | Temporal → Workers · Temporal Web (`temporal.duynh.me`) |
| **Local-stack** | present |

## Meaning

Failed workflows as a fraction of the workflows that finished. These are **SDK**
metrics emitted by the application workers, not server metrics — so this alert
says the *business logic* is failing, where the server-side alerts say the
platform is.

The two workers on this platform are `checkout-worker` and `order-worker`.

## Impact

A failed workflow is a customer-visible outcome. On this platform that usually
means an order saga that did not complete: stock reserved and not committed, a
payment authorised and not captured, or a checkout that ended without an order.
The saga's compensation path handles the ones it is designed for — the alert is
about the rate exceeding what compensation makes routine.

## Diagnosis

**Go to the workflow, not to the metric.** Temporal keeps full history:

```bash
POD=$(kubectl get pods -n temporal -o name | grep admintools | head -1)
kubectl exec -n temporal ${POD#pod/} -- temporal workflow list \
  --namespace mop --query 'ExecutionStatus="Failed"' --limit 20

kubectl exec -n temporal ${POD#pod/} -- temporal workflow show \
  --namespace mop --workflow-id <id>
```

The namespace is **`mop`**, not `default` — a `temporal` CLI call against
`default` returns "Namespace default is not found", which is not a fault.

```promql
# Which worker, and is it one workflow type or all
sum by (service_name, workflow_type) (rate(temporal_workflow_failed_total[10m]))
sum by (service_name) (rate(temporal_workflow_completed_total[10m]))
```

Then the worker's own logs:

```bash
kubectl logs -n order   -l app=order-fulfillment    --tail=100 | grep -i error
kubectl logs -n checkout -l app=checkout-abandon    --tail=100 | grep -i error
```

## Mitigation

Almost always **application work**, not homelab work:

1. One workflow type failing → the bug is in that workflow's code, in
   `order-service` or `checkout-service`.
2. All workflow types failing at once → suspect the platform instead. Check
   [TemporalServiceErrorRateHigh](TemporalServiceErrorRateHigh.md) and
   [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md); a
   struggling server makes healthy workflows fail.
3. Failures starting right after a deploy → suspect worker versioning. A
   deployment version that never became `Current` leaves workers polling a queue
   that will not serve them.

## Escalation

Warning. Escalate to the owning service repository rather than to platform
on-call, unless the server-side alerts are firing too.

## Related

- [TemporalActivityFailureRateHigh](TemporalActivityFailureRateHigh.md) — a
  failing activity is the usual reason a workflow fails.
- [TemporalServiceErrorRateHigh](TemporalServiceErrorRateHigh.md),
  [TemporalPersistenceErrorRateHigh](TemporalPersistenceErrorRateHigh.md) — the
  platform-side causes to rule out.

---
_Last updated: 2026-09-05 — created; the temporal alert group had no runbooks at all_
