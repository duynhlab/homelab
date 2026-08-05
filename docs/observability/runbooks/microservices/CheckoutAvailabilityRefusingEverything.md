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

**Genuine stockouts do not look like this.** A missing backfill, a SKU-id mismatch, or
balances sitting at zero do.

## Why this alert exists at all
It guards a **contract gap**, and the gap is the reason a data problem here is
otherwise invisible:

> `inventory.v1/CheckAvailability` returns `{can_fulfill, shortages}`. There is no way
> for it to say *"I have no data for this SKU"* — and `can_fulfill = false` is also the
> zero value of the response.

So an absent inventory row is indistinguishable, on the wire, from a real zero. It
reads as a **definite, customer-facing "out of stock"**, and a shortage is a
legitimate business answer, so nothing else complains. The phase-2 shadow compare used
to catch exactly this (`result="missing|unknown"`) and it was removed with the
product-availability path it compared against.

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
1. **Missing rows** → run the inventory backfill (`Job inventory-backfill`; see the
   RFC-0021 cutover doc) and re-check the counts.
2. **Rows present, `on_hand` zero** → this may be real. Confirm against the business
   before treating it as a bug; if the platform was seeded without stock (a fresh
   cluster does not seed inventory), seed it.
3. **`safety_stock` at or above `on_hand`** → available-to-promise is zero by policy,
   not by shortage. Check whether that was intended.

Do **not** work around this by moving checkout back to product for availability — see
[`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md) § Mitigation for why
that path is gone and why reviving it would serve stale numbers.

## Escalation
Ticket, not a page: the failure is a data problem and the fix is a backfill, not an
incident response. Escalate to a page if it coincides with a deploy of
inventory-service or with the backfill Job failing.

## References
- [`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md)
- [`docs/api/inventory.md`](../../../api/inventory.md) — the contract, including this gap
- [RFC-0021](../../../proposals/rfc/RFC-0021/)

---
_Last updated: 2026-08-05_
