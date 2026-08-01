# OrderManualReviewBacklog

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / money — human worklist |
| **Manifest** | [`rfc0021-phase5.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase5.yaml) |
| **Metrics** | `order_manual_review_backlog` |

## Meaning
Orders are parked in `manual_review`. The state exists for exactly one
reason: a workflow could **not** honestly assert a terminal status because
side effects are unaccounted for — a compensation exhausted its retries, a
refund was declined by the provider, or the ambiguous-pivot seam fired
(ConfirmOrder committed but lost its ack while the saga compensated).

The gauge is deliberately un-aged and unwindowed: a pending human decision
must never quietly age out of the number an operator watches.

## Impact
Money or stock is in an unverified state per parked order. Nothing
automatic touches these orders — the reconciler skips `manual_review` on
purpose (repairing under an operator's feet is worse than parking).

## Diagnosis — what stopped, per order
```sql
-- The worklist, oldest first
SELECT id, manual_review_reason, failure_code, updated_at, version
FROM orders WHERE status = 'manual_review' ORDER BY updated_at;

-- What the workflow was doing when it gave up (bounded tokens)
SELECT stage, last_successful_step, last_error_code, updated_at
FROM order_processing_projection WHERE order_id = $ID;

-- The full audit trail
SELECT from_status, to_status, reason_code, actor_type, command_id, created_at
FROM order_status_history WHERE order_id = $ID ORDER BY created_at;
```
Cross-check the external truths by hand: the payment row (payment-service —
was the refund declined? `refunded_minor` vs `amount_minor`), the
reservation (`GetReservation` — RESERVED, COMMITTED, RELEASED?), the
shipment status.

## Recovery — the operator decision tree
1. **Finish the missing side effect by hand** (a refund via the payment
   surface, a release/RETURN via inventory's admin commands, a shipment
   cancel). The workflows' writes are idempotent, so nothing double-moves.
2. **Move the order to the state the world now matches.** P5 ships no
   operator endpoint yet (follow-up); the documented v1 path applies the
   resolve command by hand, following the same discipline the repository
   enforces — history row and guarded update in ONE transaction:

   ```sql
   BEGIN;
   SELECT status, version FROM orders WHERE id = $ID FOR UPDATE; -- expect manual_review, $V
   INSERT INTO order_status_history
     (order_id, from_status, to_status, reason_code, actor_type, actor_id, note, command_id)
   VALUES
     ($ID, 'manual_review', '<target>', 'OPERATOR_RESOLVED', 'OPERATOR',
      '<your-id>', '<what you verified>', 'resolve:' || $ID || ':v' || $V || ':<target>');
   UPDATE orders SET status = '<target>', version = version + 1, updated_at = NOW()
   WHERE id = $ID AND status = 'manual_review' AND version = $V;
   COMMIT;
   ```
   `<target>` ∈ `confirmed | failed | cancelled | completed` — the FSM's
   resolve set. Write the note; it is the audit trail's whole point.
3. The order leaves the gauge on the next collection cycle.
