# OrderProjectionWritesFailing

| | |
|---|---|
| **Severity** | warning |
| **Category** | UX / observability |
| **Manifest** | [`rfc0021-phase5.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase5.yaml) |
| **Metrics** | `order_projection_write_failures_total`, `order_saga_complete_failures_total` |

## Meaning
Two best-effort tails of the order workflows are failing:

- `order_projection_write_failures_total` — stage writes to
  `order_processing_projection` keep exhausting their (deliberately tiny,
  ~7s) budget. One lost write self-heals at the next boundary; a steady rate
  means the projection table is dark.
- `order_saga_complete_failures_total` (alert `OrderCompleteFailures`) — the
  fulfillment tail cannot record `confirmed → completed`. A **legal mid-tail
  cancellation is not counted here** — this series only moves when the write
  itself failed after retries.

## Impact
UX-only, by design: `orders.status` is the money-bearing truth and never
depends on either write. While this fires, `/details` renders a stale or
missing `processing` block (the SPA shows blocks as degraded/absent), and
completed-but-unrecorded orders sit at `confirmed` — settlement-correct
(the reconciler treats confirmed and completed identically) but the status
ladder degrades.

## Diagnosis
Both series come from the worker's workflow code; the writes go to the order
database. So the usual suspects are the order DB (locks, disk, the
projection table's CHECK after a bad deploy) or a schema drift where the
worker image is newer than the applied migrations.

```sql
SELECT count(*) FROM order_processing_projection;      -- does the table exist / accept reads?
SELECT id, status, completed_at FROM orders
WHERE status = 'confirmed' AND completed_at IS NULL
ORDER BY updated_at DESC LIMIT 20;                      -- completes that never landed
```

## Recovery
1. Fix the database fault; both series stop climbing on their own (the
   projection self-heals at each next boundary; completes only apply to
   orders whose tail runs after the fix).
2. Orders stuck at `confirmed` whose tail already finished stay `confirmed`
   — harmless. If the ladder matters for a specific order, the operator
   resolve path in [OrderManualReviewBacklog](OrderManualReviewBacklog.md)
   documents the by-hand command discipline.
