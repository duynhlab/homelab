# OrderStartParticipantUnrecognised

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / cutover |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_fulfillment_start_participant_total{participant,source,result}` |
| **Applies to** | order **1.13.0+** (RFC-0021 P4 removed the product stock branch). On 1.12.x and earlier the resolver fell back to the process's `ORDER_STOCK_PARTICIPANT` and started the saga anyway — the pre-P4 notes below still apply there |

## Meaning
A saga start read a `participant` value this build cannot serve, so **no saga was
started for that order**.

Since RFC-0021 P4 removed the product-service stock branch, `inventory` is the only
servable participant — and the resolver **refuses** rather than substituting one.
It used to fall back to the process's own `ORDER_STOCK_PARTICIPANT`; that flag is
gone, and so is the fallback. Substituting inventory for an order whose row says
otherwise would reserve real stock for an order holding stock elsewhere.

`source` says where each decision came from, and `result` says what happened:

| Label | Meaning |
|---|---|
| `source="recorded"` | The order's row named a branch this build knows. |
| `source="absent"` | Nothing recorded, which every reader of that column means as the **product** path. Pre-P3 orders only. |
| `source="unrecognised"` | **This alert.** A value no build understands; `participant` is empty, because nothing may be guessed for it. |
| `result="started"` | A saga was created. |
| `result="refused"` | The participant cannot be served — no saga, and the order's outbox row goes terminal with `PARTICIPANT_UNSERVABLE`. |

## Impact
The order stays `pending` and nothing will move it. Its outbox row is what carries
the refusal, so the paging signal is
[`FulfillmentStartOutboxFailed`](FulfillmentStartOutboxFailed.md) — work that
runbook for the remedy. This alert is the earlier, quieter signal and tells you
*why*.

A rise in `source="absent", result="refused"` at a worker rollout is a different
story: it means the fleet is serving orders created before the P3 participant
cutover, which should not exist on a drained fleet.

## Diagnosis
### PromQL
```promql
increase(order_fulfillment_start_participant_total{source="unrecognised"}[30m])
sum by (participant, source, result) (rate(order_fulfillment_start_participant_total[15m]))
```

### The offending rows
The dispatcher logs the value it refused (the gRPC transport has no logger by
design, so an inline start's refusal shows up only in the metric):
```logql
{namespace="order"} |= "cannot be served by this build"
```
```sql
SELECT order_id, participant, status, last_error_code, created_at
FROM fulfillment_start_requests
WHERE participant IS DISTINCT FROM 'inventory' AND status <> 'STARTED';
```
`participant IS NULL` is a pre-P3 order. `'product'` is a pre-cutover order. Any
other value was hand-edited or written by a build predating the `CHECK`.

## Mitigation
1. **Establish what actually ran** before touching the column — the history, never
   the row:
   ```bash
   temporal workflow show --workflow-id order-fulfillment-<id> \
     --namespace mop | grep -i -m1 -E 'ReserveInventory|ReserveStock'
   ```
   `ReserveStock` means stock is held at product-service and this build cannot
   finish that saga. `ReserveInventory` with a row saying otherwise means the row
   is wrong: correct the column to `inventory` and requeue.
2. **No workflow at all** → nothing was started, no money moved, no stock held. Take
   the `PARTICIPANT_UNSERVABLE` path in
   [`FulfillmentStartOutboxFailed`](FulfillmentStartOutboxFailed.md): fail the order,
   or keep a build that still has the removed branch polling until such orders drain
   (order 1.12.x is the last one that can).
3. **Counter rising with no rows** → a NEWER order-service is writing a participant
   this build cannot read. Roll the fleet forward, not back: a mixed fleet where one
   half cannot read the other's values refuses every deferred start.
4. Verify the constraint is present — its absence is how an unusable value gets in:
   ```sql
   SELECT conname FROM pg_constraint
   WHERE conname = 'fulfillment_start_requests_participant_check';
   ```

## Prevention
Migration `000010` constrains the column to `('product','inventory')` or NULL, so no
client can write an unreadable value. Beyond that, the invariant is enforced in code
at the one place a saga is created (`fulfillment.Start`), not only at the transports,
so a new start path inherits the refusal instead of having to remember it.

## References
- [`FulfillmentStartOutboxFailed`](FulfillmentStartOutboxFailed.md) — the paging signal and the remedy
- [`OrderParticipantDisagreement`](OrderParticipantDisagreement.md)
- [`docs/api/temporal.md`](../../../api/temporal.md)
- [RFC-0021 cutover rollback](../../../proposals/rfc/RFC-0021/cutover-rollback.md)

---
_Last updated: 2026-08-04_
