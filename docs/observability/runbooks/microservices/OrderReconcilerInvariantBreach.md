# OrderReconcilerInvariantBreach

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_repairs_total{action="breach"}` |

## Meaning
`increase(order_reconciler_repairs_total{action="breach"}[1h]) > 0`. The reconciler
found a terminal order whose stock disagrees with its outcome in a way **no valid
transition repairs**, and recorded the reason in
`fulfillment_start_requests.reconcile_breach_code`.

Alertable precisely because each breach is reported **once per order**, not once per
pass. A stuck order would otherwise contribute 1,440 increments a day and make one
unresolved incident indistinguishable from a stream of fresh saga failures.

The row is left **unsettled on purpose** so it stays in the backlog until a human
resolves it.

## Impact
Money and stock are inconsistent for at least one order. Which way depends on the
reason code:

| `reconcile_breach_code` | What is wrong |
|---|---|
| `STOCK_CONSUMED` | A **failed** order's reservation is COMMITTED — units were consumed for an order that did not happen. Inventory is short. |
| `STOCK_RETURNED` | A **confirmed** order's stock went back (RELEASED/EXPIRED). The order stands with no stock behind it. Do **not** assume the customer was charged: in the stale-status variant a compensation refunded them and only `failOrder` failed to land. |
| `RESERVATION_MISSING` | A **confirmed** inventory-path order has no reservation at all — the Reserve write was lost or the row was restored away. |
| `FOREIGN_RESERVATION` | The reservation with this order's id is owned by a different order. Refuses to act; suspect an id-scheme violation. |
| `UNKNOWN_RES_STATUS` | inventory-service returned a reservation status this order build does not know. The two services have drifted. |
| `NON_TERMINAL_ORDER` | The candidate query and the repair logic disagree — a code bug, not a data problem. |

## Diagnosis
### PromQL
```promql
increase(order_reconciler_repairs_total{action="breach"}[1h])
max(order_reconciler_backlog)
```

### SQL — the authoritative list
```sql
SELECT f.order_id, o.status, f.participant, f.reconcile_breach_code, o.updated_at, o.total
FROM fulfillment_start_requests f JOIN orders o ON o.id = f.order_id
WHERE f.reconcile_breach_code IS NOT NULL AND f.reconciled_at IS NULL
ORDER BY o.updated_at;
```
The table, not the logs, is the durable record — the reason survives log retention.

### Cross-check each order
```bash
grpcurl -plaintext -d '{"reservation_id":"<order_id>"}' \
  inventory.inventory.svc.cluster.local:9090 inventory.v1.InventoryService/GetReservation
```
Also open `order-fulfillment-<order_id>` in the Temporal UI: the reconciler only
judges an order whose workflow is **closed**, so its history shows what the saga
actually did.

## Mitigation
There is no automatic repair — that is what "breach" means. Per order, decide:
1. `STOCK_CONSUMED` ⇒ the order did not happen, so the units should come back.
   Correct with an inventory adjustment (movement ledger), not by editing balances.
2. `STOCK_RETURNED` ⇒ establish from payment whether the customer was charged
   (`GetPayment`), then either refund or re-reserve and commit.
3. `RESERVATION_MISSING` ⇒ the confirmed order has no stock behind it; reserve and
   commit for it, or fail-and-refund the order.
4. `FOREIGN_RESERVATION` / `UNKNOWN_RES_STATUS` / `NON_TERMINAL_ORDER` ⇒ code or
   contract bug. Do not hand-patch data; open an incident and fix forward.

After resolving, clear the row so it leaves the backlog:
```sql
UPDATE fulfillment_start_requests
SET reconciled_at = now(), reconcile_breach_code = NULL, updated_at = now()
WHERE order_id = <id> AND reconciled_at IS NULL;
```
There is **no API for this yet** — it is deliberate manual SQL, because clearing a
breach is an assertion that a human checked it.

## Escalation
Page immediately. This is a data-integrity incident, not a latency blip. If it
appears during the write cutover, reverting `ORDER_STOCK_PARTICIPANT` to
`product` prevents *new* orders taking the inventory path but does not unwind
orders already pinned to it — the participant is pinned per workflow and the
posture is fix-forward.
