# OrderReconcilerPassTruncated

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / observability |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_passes_truncated_total` |

## Meaning
A pass returned a **full batch** (200 candidates), so it did not examine every
unsettled order in its 24h window.

On a healthy platform this set is nearly empty — the scan returns only orders whose
stock has not been confirmed to agree — so hitting the cap means something is wrong
at volume, not that the platform is busy.

## Impact
`order_reconciler_backlog` becomes a **lower bound** rather than a count while this
is firing, so every threshold read from it understates the problem. Progress still
happens (settled orders leave the scan, and known breaches are ordered last so they
cannot starve fresh work), but slowly.

## Diagnosis
### PromQL
```promql
increase(order_reconciler_passes_truncated_total[30m])
max(order_reconciler_backlog)                                  # the true size
sum by (action) (rate(order_reconciler_repairs_total[15m]))
```

### SQL
```sql
SELECT count(*) FILTER (WHERE reconcile_breach_code IS NOT NULL) AS breaches,
       count(*)                                                  AS unsettled
FROM fulfillment_start_requests WHERE reconciled_at IS NULL;
```

## Mitigation
1. `breaches` ≈ `unsettled` ⇒ a mass invariant failure; treat as
   [OrderReconcilerInvariantBreach](OrderReconcilerInvariantBreach.md) at scale and
   page. Known breaches sort last, so fresh work is still reached, but the volume
   itself is the incident.
2. Mostly non-breach ⇒ the repair path is failing or deferring in bulk; see
   [OrderReconcilerDependencyUnreadable](OrderReconcilerDependencyUnreadable.md).
3. Genuine backlog after an outage ⇒ it drains on its own at 200 orders/minute.
   Confirm the count is falling before doing anything else.

## Escalation
Page if the backlog is not falling pass over pass, or if the truncation coincides
with a write cutover — a cutover that produces hundreds of unsettled orders should
be rolled back to `ORDER_STOCK_PARTICIPANT=product` for **new** sagas while the
existing ones are worked through.
