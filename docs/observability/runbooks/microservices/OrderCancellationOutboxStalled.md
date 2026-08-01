# OrderCancellationOutboxStalled

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability |
| **Manifest** | [`rfc0021-phase5.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase5.yaml) |
| **Metrics** | `order_cancellation_outbox_oldest_pending_age_seconds`, `order_cancellation_outbox_failed` |

## Meaning
An accepted cancellation whose CancellationWorkflow has not started for over
10 minutes (`OrderCancellationOutboxStalled`), or whose start attempts are
exhausted (`OrderCancellationOutboxFailed`, cap 60 ≈ hours of retries).

The cancel handler flips the order to `cancelling` and arms an outbox row in
one transaction; the inline start closes the row in the common case and the
worker-side dispatcher sweeps the rest. A stalled row means both paths are
failing — almost always Temporal or the order worker.

Unlike the fulfillment twin there is **no payment-token window** behind the
cap: every cancellation activity reads current state server-side, so a late
start is harmless. The cost is purely customer-facing time in `cancelling`.

## Diagnosis
```promql
sum by (result) (rate(order_cancellation_start_dispatch_total[5m]))
```
No series ⇒ the dispatcher isn't running (worker down). `result="error"` ⇒
running and failing (Temporal unreachable, or the worker version serving the
queue does not register `CancellationWorkflow` — check the ADR-030 activation
state: the v1.10.0+ build must be Current).

```sql
SELECT * FROM cancellation_requests WHERE status <> 'DISPATCHED' ORDER BY created_at;
```

## Recovery
1. Restore Temporal / the worker; the dispatcher self-recovers on its next
   sweep (15s) and PENDING rows drain.
2. FAILED rows: nothing retries them. After the fault is fixed, cancel the
   order again — a new episode re-arms the same row with a fresh epoch and
   attempt budget.
3. `OrderStuckCancelling` escalates to critical if orders keep waiting.
