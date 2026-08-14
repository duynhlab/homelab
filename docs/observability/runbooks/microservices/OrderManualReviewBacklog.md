# OrderManualReviewBacklog

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / money — human worklist |
| **Manifest** | [`rfc0021-phase5.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase5.yaml) |
| **Metrics** | `order_manual_review_backlog`, `order_operator_resolve_total` |

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

## Diagnosis — start in the portal
The Admin Portal's order case view is now the diagnosis surface: **Orders →
filter `manual_review` → open the case**. It shows the parked order, the three
external truths read live (payment with `refunded` vs `amount`, the reservation
status, the shipment), where the saga stopped, and the full transition history.
A dependency that did not answer renders as **unavailable**, which is not the
same as "nothing to settle" — treat it as "you do not know yet".

The SQL below is the fallback when the portal or the edge is unavailable.

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
   Nothing checks this step for you — see *Why you are trusted* below.
2. **Move the order to the state the world now matches** with the **Resolve**
   button on the case view, or the endpoint behind it:

   ```bash
   # version comes from the case view (GET .../orders/:id → "version")
   curl -sS -X POST "$BASE/order/v1/protected/orders/$ID/resolve" \
     -H "Authorization: Bearer $STAFF_TOKEN" -H 'Content-Type: application/json' \
     -d '{"target":"cancelled","version":7,"reason":"REFUNDED_MANUALLY",
          "note":"refund 25.98 confirmed in the provider console at 14:02"}'
   ```

   `target` ∈ `confirmed | failed | cancelled | completed` — the FSM's resolve
   set. `reason` ∈ `REFUNDED_MANUALLY`, `STOCK_RELEASED_MANUALLY`,
   `SHIPMENT_CANCELLED_MANUALLY`, `NO_SIDE_EFFECTS`, `WRITTEN_OFF`,
   `OPERATOR_RESOLVED`. The note is **mandatory** and is the audit trail's whole
   point. Full contract: [`docs/api/order.md`](../../../api/order.md#protected-backoffice--rfc-0023-trains-3-and-7).

   Answers you may get, and what each means:

   | Response | Meaning |
   |----------|---------|
   | `201 applied:true` | Recorded. The order leaves the gauge on the next collection cycle |
   | `200 applied:false` | This exact decision was already recorded — a replay wrote nothing. Not a failure |
   | `409 VERSION_CONFLICT` | Your case view is stale. Reload and decide again against what you see then |
   | `409 INVALID_TRANSITION` | The order is no longer parked (someone resolved it), or the target is not in the resolve set |
   | `400 VALIDATION_ERROR` | Missing note, or a reason outside the resolution vocabulary |

3. Confirm with `order_operator_resolve_total{result="applied"}` and the gauge
   dropping. The case view's transition history now carries an `OPERATOR` row
   with your subject, the reason, and your note.

### Why you are trusted (ADR-051)
The endpoint validates the FSM edge, the version you read, and command replay.
It deliberately does **not** call payment, inventory or shipping to veto your
target: the evidence for step 1 often lives in a provider console or a carrier
portal, so the platform cannot check it, and a cross-service veto would make
this command unavailable during exactly the incidents that fill this queue. The
control is the record — which is why the note is mandatory and why the case view
puts the external truths in front of you first. Decide from them, not from
memory. See [ADR-051](../../../proposals/adr/ADR-051-trusted-operator-resolution/).

### Break-glass: the same write by hand
Use only when the portal **and** the edge are unavailable. This skips the FSM and
actor validation, the version precondition, the replay check, and the
`order_operator_resolve_total` counter — so a mistyped id or target lands
silently in a money-bearing table:

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

`OPERATOR_RESOLVED` is deliberately the reason here: it is the unspecific
catch-all, and a row written this way should be distinguishable from one the
validated path produced.

### There is no alert on resolving
Deliberately. An operator draining this queue is the system working as designed,
so a counter exists but nothing pages on it. What is alertable is the queue **not**
draining, which this alert already covers.
