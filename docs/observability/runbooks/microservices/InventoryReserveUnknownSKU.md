# InventoryReserveUnknownSKU

| | |
|---|---|
| **Severity** | critical |
| **Signal** | `increase(inventory_reservation_total{outcome="unknown_sku"}[10m]) > 0` |
| **Meaning** | A saga tried to reserve a SKU that has **no balance row in any warehouse** — a data gap on the money path, never customer demand |

## Why this pages

Checkout fails closed on unknown SKUs at session create **and** confirm
(`CheckoutAvailabilityUnknownSKU` covers that layer), so a reservation can
only hit this if the balance row disappeared **between** confirm's
availability check and the saga's `Reserve` — a seeding gap, a bad DELETE, or
a race with warehouse maintenance. The order fails with reason `UNKNOWN_SKU`
(payment voided, nothing reserved, no release needed), so no money or stock
is wrong — but a purchasable product just refused a real customer.

Count-once semantics: any increase is a distinct reservation attempt; no
threshold above zero would be honest.

## Diagnosis

1. The failed order and SKU ids are on the inventory reservation span and in
   order's `order_status_history` (`failure_code = UNKNOWN_SKU`).
2. Confirm the gap: `SELECT * FROM inventory_balances WHERE sku_id = '<id>'`
   (namespace `product`, database `inventory`) — expect zero rows.
3. Find out **how** the product became purchasable without a balance row:
   check `inventory_movements` for a DELETE-adjacent history, and product's
   catalog state.

## Mitigation

- Seed the balance: insert the `inventory_balances` row (or record an
  explicit `RECEIVE` movement) — recovery is inventory-local since the
  RFC-0021 P4 contraction removed the backfill path.
- The failed order does NOT self-heal (terminal). The shopper can re-order
  once the balance exists.

## Related

- `CheckoutAvailabilityUnknownSKU` — the same class one layer earlier
- [inventory.md](../../../api/inventory.md) — tracked/untracked semantics
