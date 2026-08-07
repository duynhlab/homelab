# InventoryReservationInfraErrors

| | |
|---|---|
| **Severity** | warning |
| **Signal** | `sum(increase(inventory_reservation_total{outcome="error"}[15m])) > 0` (count-once, no debounce) |
| **Meaning** | The reservation write path is failing for reasons that are **not** a business rejection — infra, storage, or an unhandled state |

## Why this fires

`inventory_reservation_total` splits every reservation command by
(`operation`, `outcome`). `operation` is `reserve` \| `release` \| `commit`;
the alert sums across all three, so read the label to see which command is
failing. Eight of the nine outcome values are expected traffic and are
excluded from this alert:

| `outcome` | Meaning | Alerted by |
|---|---|---|
| `ok` | applied | — |
| `replayed` | same idempotency key, same payload — a retry doing nothing | — |
| `insufficient` | genuine shortage, ATP too low | order saga → `OUT_OF_STOCK` |
| `conflict` | same idempotency key, **divergent** payload | — (a caller bug; watch if sustained) |
| `concurrency` | lock or serialization abort — retryable | — |
| `invalid_transition` | command against a reservation in the wrong state | — |
| `not_found` | release/commit for a reservation that does not exist | — |
| `unknown_sku` | no balance row in any warehouse | [`InventoryReserveUnknownSKU`](InventoryReserveUnknownSKU.md) |
| **`error`** | **anything the domain did not classify** | **this alert** |

So `error` is the residual bucket: a DB CHECK violation (the oversell backstop
tripping), a storage fault, a transaction abort, or an error no domain sentinel
matched. Because every *known* rejection has its own outcome value, anything
landing here is always actionable — there is no benign steady state.

Stock is the money path: inventory is the only authority for ATP since the
RFC-0021 P4 contraction, so a failing reservation write fails orders outright.

## Diagnosis

1. **Read the SQLSTATE.** The reservation span carries the pgx error; in
   VictoriaLogs:
   `{app="inventory"} |~ "reservation" | json | level="error"`. A `23514`
   (check violation) means the oversell backstop
   (`inventory_balances_reserved_lte_on_hand`) refused a write — that is a
   correctness guard doing its job, and the reservation arithmetic upstream is
   the bug.
2. **Separate DB fault from logic fault.** Check product-db:
   `kubectl -n product get cluster product-db` and the
   `CNPG*` / `DBClientErrorRate` alerts. A pooler or primary problem shows up
   across services, not just inventory.
3. **Check the rate against traffic.** `inventory:reservation:rate5m` by
   outcome — a burst of `error` alongside normal `ok` volume points at
   specific SKUs; a total stall points at the datastore.

## Mitigation

- **DB fault:** follow the CNPG runbook for the failing cluster. Inventory
  fails closed, so orders fail rather than oversell — no compensating action
  is needed for reservations that never happened.
- **Check violation:** do not relax the constraint. Find the reservation whose
  arithmetic exceeded `on_hand` (`SELECT * FROM inventory_reservations WHERE
  sku_id = …` plus the balance row) and fix the release/commit path that
  leaked. The constraint is the last line against overselling.
- **Unhandled transition:** capture the state and open a fix in
  `inventory-service`; the reservation is not left half-applied (every write is
  one transaction).

## Related

- [`InventoryReserveUnknownSKU`](InventoryReserveUnknownSKU.md) — the data-gap sibling
- [`InventoryGrpcErrorRatio`](InventoryGrpcErrorRatio.md) — the RPC-level view of the same failures
- [`docs/api/inventory.md`](../../../api/inventory.md) — reservation contract and outcomes
- [Alert catalog § 9](../../alerting/alert-catalog.md) — RFC-0021 order-side stock

_Last updated: 2026-08-07_
