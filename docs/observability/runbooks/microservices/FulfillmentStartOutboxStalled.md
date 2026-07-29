# FulfillmentStartOutboxStalled

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability / correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_fulfillment_start_outbox_oldest_age_seconds` |

## Meaning
The oldest PENDING row in `fulfillment_start_requests` has been waiting over
**10 minutes**.

The outbox (ADR-031) commits the order row and the intent to start its saga in one
transaction. The inline start then runs immediately and marks the row DISPATCHED, so
a PENDING row is normal for *milliseconds*. Age beyond that means the inline start
failed **and** the leased dispatcher has not recovered it.

**Age, not count, is the signal** — a burst of pending rows that clears in seconds
is the system working.

## Impact
An order committed but **its saga never started**. The customer sees a created order
that does not progress: no payment authorization, no shipment, no notification, and
the cart is not cleared. The row also holds the checkout's payment token, whose
authorization window is finite — after roughly two hours the honest recovery is to
fail the order rather than start a saga against a stale token.

## Diagnosis
### PromQL
```promql
max(order_fulfillment_start_outbox_oldest_age_seconds)
max(order_fulfillment_start_outbox_pending)
sum by (result) (rate(order_fulfillment_start_dispatch_total[5m]))
```
`dispatch_total` with no series at all ⇒ the dispatcher is not running (worker down);
`result="failed"` ⇒ it is running and failing.

### SQL
```sql
SELECT order_id, status, attempts, next_attempt_at, last_error_code,
       payment_method_cleared, created_at
FROM fulfillment_start_requests
WHERE status = 'PENDING' ORDER BY created_at LIMIT 20;
```
`last_error_code` is a bounded token (a grpcx reason or Temporal error type), never
a message — group by it.

### kubectl / logs
```bash
kubectl logs -n order -l app=order-worker --tail=300 | grep -iE "outbox sweep|recovered a fulfillment start"
kubectl -n temporal get pods
```

## Mitigation
1. Temporal unreachable ⇒ the usual cause. The dispatcher retries with backoff and
   drains by itself once the frontend is healthy. The worker is fail-fast, so also
   confirm it is not crash-looping.
2. `attempts` climbing toward 20 ⇒ the row is heading for FAILED; see
   [FulfillmentStartOutboxFailed](FulfillmentStartOutboxFailed.md).
3. `42703`-style SQL errors in `outbox sweep failed` ⇒ app ahead of its schema; run
   the order migration Job (the `participant` column arrives in **000009**).
4. Never mark rows DISPATCHED by hand to clear the alert — that row is the only
   durable record that the order still needs a saga.

## Escalation
Page. Every minute here is an order the customer believes exists and which is doing
nothing. Related: [FulfillmentStartOutboxFailed](FulfillmentStartOutboxFailed.md).
