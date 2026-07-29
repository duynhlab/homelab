# OrderInventoryCommitLagHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | latency / correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_inventory_commit_lag_seconds_{bucket,sum,count}` |

## Meaning
p99 of the time between the **ConfirmOrder pivot** and **CommitInventory settling**
has exceeded 5 minutes for 15m.

CommitInventory is **mandatory-forward**: once the pivot succeeds the order is
confirmed, so a commit failure is an inconsistency to repair — never a reason to
roll back a confirmed order and refund a customer whose stock is fine. The activity
therefore retries within an elapsed bound instead of failing the saga.

**Right-censored by construction:** an order whose commit *never* settles
contributes **no observation at all**. So a rising p99 is the mild symptom; orders
that exhausted the bound disappear from this histogram and surface as
[OrderReconcilerBacklogNotDraining](OrderReconcilerBacklogNotDraining.md) instead.
Read the two together — the backlog is the severe signal.

No series at all before the write cutover is **normal**: with
`ORDER_STOCK_PARTICIPANT=product` no workflow takes the inventory branch.

## Impact
Confirmed orders are holding merely-RESERVED stock. Available-to-promise is
understated for that long, so other customers may be refused stock that is
effectively already sold — and if the retry bound expires, the units stay reserved
until the reconciler commits them.

## Diagnosis
### PromQL
```promql
histogram_quantile(0.99, sum by (le) (rate(order_inventory_commit_lag_seconds_bucket[5m])))
sum(rate(order_inventory_commit_lag_seconds_count[5m]))      # are commits landing at all?
sum by (participant, result) (rate(order_stock_reservation_total[5m]))
max(order_reconciler_backlog)                                 # the censored tail
```
A **falling** `_count` with a rising p99 is the dangerous shape: commits are not
completing rather than completing slowly.

### kubectl / logs
```bash
kubectl logs -n order -l app=order-worker --tail=300 | grep -i "CommitInventory"
kubectl -n inventory logs -l app=inventory --tail=200
```
`CommitInventory failed after the pivot` at Error level means the retry budget was
exhausted for that order.

### Temporal
Open a slow `order-fulfillment-<order_id>`: the activity's attempt count and last
failure show whether inventory is rejecting (business error) or timing out.

## Mitigation
1. Inventory slow but healthy ⇒ usually its database. Follow the inventory-service
   and PostgreSQL runbooks; the saga converges on its own once latency recovers.
2. Inventory **rejecting** (`INVALID_TRANSITION`, `NOT_FOUND`) ⇒ that is an
   invariant breach, not slowness. Expect
   [OrderReconcilerInvariantBreach](OrderReconcilerInvariantBreach.md) and treat it
   as critical.
3. Do not terminate the workflows to clear the lag: terminating between the pivot
   and the commit is exactly the case the reconciler exists to clean up, and it
   creates work rather than removing it.

## Escalation
Page if `_count` falls toward zero while orders are still being confirmed — that
means no commit is landing at all, and every confirmed order is accruing stranded
stock.
