# CheckoutAvailabilityRefusingEverything

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness |
| **Manifest** | [`checkout-availability.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/checkout-availability.yaml) |
| **Metrics** | `checkout_availability_check_total{result}` |
| **Applies to** | checkout **0.5.0+** |

## Meaning
Inventory has refused **more than 95%** of baskets for 30 minutes. It is answering —
this is not an outage (that is
[`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md)) — it is answering
*"no"* to almost everything.

**Genuine stockouts do not look like this.** Balances sitting at zero, or a
`safety_stock` at or above `on_hand`, do.

A **missing** balance row is a different alert now:
[`CheckoutAvailabilityUnknownSKU`](CheckoutAvailabilityUnknownSKU.md). If rows are
absent rather than zero, stop here and read that one — it names the SKUs.

## Why this alert exists at all
A shortage is a legitimate business answer, so nothing else complains about one — but
*"every basket is short"* is not a demand shape. It is balances at zero, or a policy
mistake, and without this alert it would look like quiet, healthy traffic.

**It used to be broader, and it should not be widened back.** This alert was
originally the guard for a contract gap: `CheckAvailability` returned only
`{can_fulfill, shortages}`, so a SKU with no balance row arrived as a `Shortage` at
`available_to_promise = 0` — a quantity claim inventory could not make — and hid in
this ratio. pkg `v0.35.0` added `unknown_sku_ids`, so that case now has
[its own alert](CheckoutAvailabilityUnknownSKU.md) and its own fix, and this
expression is back to meaning what its name says. If this alert is silent while
checkout is refusing everything, the answer is almost certainly the other alert —
not a wider selector here.

## Impact
Baskets are refused at the funnel. Customers see "no longer available" and requote
forever. Revenue loss with no error rate to show for it.

## Diagnosis
**Query the table. Do not infer availability from the answer** — that is the whole
point above.

```bash
# a known-good product id: is there a row at all, and what is on hand?
kubectl -n product exec product-db-1 -c postgres -- \
  psql -U postgres -d inventory -c \
  "SELECT sku_id, on_hand, reserved, safety_stock FROM inventory_balances ORDER BY sku_id LIMIT 20;"

# how many catalog products have NO inventory row (the invisible failure)
kubectl -n product exec product-db-1 -c postgres -- psql -U postgres -d product -t -c \
  "SELECT count(*) FROM products;"
```

Compare the two counts. `sku_id` is the **product id as text** — a mismatch in that
mapping is the classic cause and looks exactly like a global stockout.

```promql
checkout:availability_check:rate5m   # confirm shortage, not error
```

## Mitigation
1. **Rows missing entirely** → wrong alert; see
   [`CheckoutAvailabilityUnknownSKU`](CheckoutAvailabilityUnknownSKU.md).
2. **Rows present, `on_hand` zero** → this may be real. Confirm against the business
   before treating it as a bug; if the platform was seeded without stock (a fresh
   cluster does not seed inventory), seed it.
3. **`safety_stock` at or above `on_hand`** → available-to-promise is zero by policy,
   not by shortage. Check whether that was intended.

Do **not** work around this by moving checkout back to product for availability — see
[`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md) § Mitigation for why
that path is gone and why reviving it would serve stale numbers.

## Escalation
Ticket, not a page: the failure is a data problem and the fix is a seed or an
adjustment, not an incident response. Escalate to a page if it coincides with a
deploy of inventory-service, or if `inventory_balances` is empty in a cluster that
was serving orders — that is data loss, not a gap.

## References
- [`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md)
- [`docs/api/inventory.md`](../../../api/inventory.md) — the contract, including this gap
- [RFC-0021](../../../proposals/rfc/RFC-0021/)

---
_Last updated: 2026-08-05_
