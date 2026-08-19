# CheckoutAvailabilityUnknownSKU

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness (data) |
| **Manifest** | [`checkout-availability.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/checkout-availability.yaml) |
| **Metrics** | `checkout_availability_check_total{result="unknown_sku"}` |
| **Applies to** | checkout **0.6.0+** · inventory **0.4.0+** (pkg `v0.35.0` added `unknown_sku_ids`) |

## Meaning
Inventory answered, and said it does **not track** one or more of the basket's SKUs —
there is no balance row for them in any warehouse. Checkout **fails closed** on that:
a `503` with `Retry-After`, never *"no longer available"*.
(Contract note — [ADR-053](../../../proposals/adr/ADR-053-untracked-sku-operator-data-not-outage/):
the contracted answer is `409 ITEM_NOT_ORDERABLE` with the requoted session, and
the Backoffice owns the bootstrap this runbook's mitigation currently does by
raw API call. checkout still ships the 503 below until the cutover — runbooks
operate as-built, so the symptoms stay accurate until then.)

This is a **data** problem, not demand. It is also **persistent**: it lasts until
somebody puts the row there.

## Why this is its own alert
Nothing else fires on it, by design:

- the shopper's 503 is not an error at inventory — the RPC **succeeded**;
- [`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md) counts `result="error"`
  only, and deliberately excludes this value from its denominator so a data gap
  cannot dilute the error ratio and suppress that page;
- [`CheckoutAvailabilityRefusingEverything`](CheckoutAvailabilityRefusingEverything.md)
  counts `shortage`, and this is not one.

Before pkg `v0.35.0` this case was *invisible*: an untracked SKU arrived as a
`Shortage` with `available_to_promise = 0` — a quantity claim inventory could not
make — and the shopper was told the item was gone. The contract can say
*"I have no data for this SKU"* now, so the honest answer reaches checkout and
lands here.

## Impact
Every basket touching an untracked SKU is refused with a 503. The items may well be
in stock. Revenue loss with no error rate at inventory to show for it.

## Diagnosis
**The SKU ids are in checkout's logs and on the trace, not in the response body** —
that is deliberate: the body stays opaque, the operator gets the detail.

```bash
# which SKUs?
kubectl -n checkout logs deploy/checkout --tail=200 | grep "does not track"
# span attribute, if you are in Grafana/Tempo:
#   checkout.unknown_sku_ids
```

```promql
sum(increase(checkout_availability_check_total{result="unknown_sku"}[15m]))  # this, not a shortage
checkout:availability_check:rate5m             # the shape by result
```

Then confirm against the authority:

```bash
kubectl -n product exec product-db-1 -c postgres -- \
  psql -U postgres -d inventory -c \
  "SELECT sku_id, warehouse_id, on_hand, reserved, safety_stock
     FROM inventory_balances WHERE sku_id = '<id>';"
```

No rows ⇒ this alert is right. A row at zero ⇒ inventory would have answered
`shortage`, so look at [`CheckoutAvailabilityRefusingEverything`](CheckoutAvailabilityRefusingEverything.md)
instead.

## Mitigation
Add the balance **at inventory**:

1. dev/demo cluster → `kubectl -n inventory exec deploy/inventory -- /app/main seed`
   (refuses anything but `ENV=development`, and only covers demo SKUs 1–13).
2. real correction → an explicit `RECEIVE` movement through inventory's normal write
   path, which keeps the append-only invariant `on_hand == SUM(on_hand_delta)` intact.

**Never reconstruct balances from product-service.** Its numbers stopped moving at the
RFC-0021 W7 write cutover and the column was dropped by migration `000006` in phase 4;
the phase-2 backfill was retired with it. Copying them back would overwrite live stock
with a snapshot of cutover day.

If the count of affected SKUs is large, suspect a **SKU-namespace mismatch** rather
than missing seed data: `sku_id` is the product id as text.

## Escalation
Page. It is customer-facing, it does not self-heal, and the fix needs someone with
write access to inventory. Escalate as a **catalog/inventory data** problem, not an
outage — inventory is healthy and answering correctly.

## References
- [`CheckoutAvailabilityErrors`](CheckoutAvailabilityErrors.md) — inventory unreachable or erroring
- [`CheckoutAvailabilityRefusingEverything`](CheckoutAvailabilityRefusingEverything.md) — rows present, balances at zero
- [`docs/api/inventory.md`](../../../api/inventory.md) — the contract, including `unknown_sku_ids`
- [RFC-0021](../../../proposals/rfc/RFC-0021/)

---
_Last updated: 2026-08-19 — ADR-053 planned-change note; as-built behavior unchanged_
