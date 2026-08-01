# OrderStuckCancelling

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness / money |
| **Manifest** | [`rfc0021-phase5.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase5.yaml) |
| **Metrics** | `order_cancelling_backlog` |

## Meaning
An order has sat in `cancelling` for over ~25 minutes (the gauge counts
orders older than 15 minutes; the alert holds for 10 more). The
CancellationWorkflow's slowest legitimate leg — the payment unwind — is
bounded in minutes, so by now the workflow is stuck, failed, or was never
started and the cancellation outbox could not start it either.

## Impact
The customer was told their cancellation is in progress. Money may be
mid-unwind: the shipment may already be cancelled while the refund has not
happened. Nothing else in the platform moves an order out of `cancelling` —
only the workflow (→ `cancelled` / `manual_review`) or an operator.

## Diagnosis
### PromQL
```promql
max(order_cancelling_backlog)
max(order_cancellation_outbox_pending)
max(order_cancellation_outbox_failed)
sum by (result) (rate(order_cancellation_start_dispatch_total[5m]))
```
Outbox pending/failed non-zero ⇒ the workflow never started (see
[OrderCancellationOutboxStalled](OrderCancellationOutboxStalled.md)).
Outbox clear ⇒ the workflow exists and is stuck: find it in the Temporal UI.

### SQL
```sql
SELECT id, status, version, cancellation_reason, updated_at
FROM orders WHERE status = 'cancelling'
ORDER BY updated_at;

SELECT * FROM cancellation_requests WHERE status <> 'DISPATCHED';
```

### Temporal
The episode's workflow id is `order-cancellation-<id>-v<epoch>` where the
epoch is on the `cancellation_requests` row. A running workflow with
activity retries shows which step won't converge (payment? shipping?
inventory?); a FAILED workflow means even the manual-review park could not
land (database trouble).

## Recovery
1. Fix the dependency the stuck activity names; the workflow converges on
   its own (all steps retry with compensation-grade budgets).
2. If the workflow is FAILED: the order is still `cancelling`. Re-cancelling
   from the UI/API is safe — a new epoch opens a fresh episode and re-arms
   the outbox row — once the underlying fault is fixed.
3. If it cannot converge, the workflow parks the order in `manual_review`
   by itself; from there follow
   [OrderManualReviewBacklog](OrderManualReviewBacklog.md).
