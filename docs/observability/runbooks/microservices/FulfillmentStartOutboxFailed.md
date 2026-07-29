# FulfillmentStartOutboxFailed

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_fulfillment_start_outbox_failed` |

## Meaning
At least one outbox row is **FAILED**: the dispatcher burned its attempt cap
(~20 claims, roughly two hours of backoff) without starting the saga.

FAILED is **terminal and nothing retries it** — by design. Requeuing is a deliberate
human act, because by this point the payment token has been cleared and starting a
saga would authorize against the demo fallback token rather than the customer's
instrument. The dispatcher refuses such a row instead of trusting an operator to
remember that.

## Impact
The order is stuck `pending` **permanently** and no automation will ever move it.
The customer has an order that will never ship and was never charged.

## Diagnosis
### PromQL
```promql
max(order_fulfillment_start_outbox_failed)
sum by (result) (rate(order_fulfillment_start_dispatch_total[1h]))
```

### SQL — the worklist
```sql
SELECT f.order_id, f.attempts, f.last_error_code, f.payment_method_cleared,
       o.status, o.total, f.created_at
FROM fulfillment_start_requests f JOIN orders o ON o.id = f.order_id
WHERE f.status = 'FAILED' ORDER BY f.created_at;
```
Group by `last_error_code` first: one code across many rows is an outage, many
different codes is per-order data.

## Mitigation
Per row, choose one — do not blanket-requeue:

1. **Preferred: fail the order and let the customer retry.** The authorization
   window has almost certainly passed, so a late saga would charge against a stale
   or absent token.
   ```sql
   UPDATE orders SET status = 'failed', updated_at = now() WHERE id = <id>;
   ```
   The reconciler then settles any stock the order was holding.

2. **Requeue only if the failure was infrastructural and recent** and
   `payment_method_cleared = false`:
   ```sql
   UPDATE fulfillment_start_requests
   SET status = 'PENDING', attempts = 0, next_attempt_at = now(), last_error_code = NULL
   WHERE order_id = <id> AND status = 'FAILED' AND payment_method_cleared = false;
   ```
   With `payment_method_cleared = true` the dispatcher will refuse the row; that
   guard is intentional, so do not clear the flag to work around it.

## Escalation
Page. Then check the deploy/incident timeline — a batch of FAILED rows with the same
`last_error_code` usually maps to one Temporal outage longer than two hours, which
is its own incident.
