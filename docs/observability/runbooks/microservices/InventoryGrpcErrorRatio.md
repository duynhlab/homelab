# InventoryGrpcErrorRatio

| | |
|---|---|
| **Severity** | warning |
| **Signal** | non-`OK` share of `rpc_server_call_duration_seconds_count{app="inventory"}` > 5% for 10m |
| **Meaning** | More than one in twenty inbound gRPC calls to inventory is answered with a non-`OK` status |

## Read this before escalating

**A non-`OK` status here is not automatically a fault.** Inventory answers a
genuine stock shortage with `FailedPrecondition`, and an unknown SKU with
`FailedPrecondition` + `SKU_NOT_FOUND` — both are *correct* answers that count
against this ratio. A promotion that sells out will push this alert past 5%
while the service is perfectly healthy.

So the first job is classification, not mitigation:

```promql
sum by (outcome) (rate(inventory_reservation_total[5m]))
```

| Dominant outcome | Verdict |
|---|---|
| `insufficient` | **business**, not an incident — real demand exceeded stock. Consider whether the catalog should have stopped selling. |
| `conflict` | idempotent replays — check whether a caller is retrying too aggressively. |
| `unknown_sku` | data gap; [`InventoryReserveUnknownSKU`](InventoryReserveUnknownSKU.md) pages separately and is the alert to work. |
| `error` | infra/logic fault; work [`InventoryReservationInfraErrors`](InventoryReservationInfraErrors.md). |

## Diagnosis

1. **Which method?** Drop the `sum` to see the split — a ratio driven by
   `CheckAvailability` (a read) means something different from one driven by
   `Reserve` (a write on the money path):
   ```promql
   sum by (rpc_method, rpc_response_status_code) (
     rate(rpc_server_call_duration_seconds_count{app="inventory"}[5m]))
   ```
2. **Which status code?** `FAILED_PRECONDITION` = business or data gap (above).
   `UNAVAILABLE` / `INTERNAL` / `DEADLINE_EXCEEDED` = a real fault — go to
   step 3. `INVALID_ARGUMENT` = a caller is sending malformed requests; find it
   by `peer.service` on the span.
3. **Datastore and dependencies.** `kubectl -n product get cluster product-db`,
   the `DBClient*` alerts, and inventory's own logs. Inventory has no
   downstream service calls, so a fault is either its own process or Postgres.
4. **Callers.** Order (saga activities) and checkout (fail-closed availability)
   are the only callers. Checkout answers 503 when inventory is unavailable, so
   a real fault surfaces to shoppers as "try again" — confirm with
   `CheckoutAvailabilityErrors`.

## Mitigation

- **Business shortage:** no platform action. If it is sustained, the finding
  belongs to the catalog/procurement side, not on-call.
- **Real fault:** treat the underlying alert (`InventoryReservationInfraErrors`,
  the CNPG alerts, or `MicroserviceDown`) as the incident — this ratio is a
  symptom view, not a root cause.
- Do **not** raise the 5% threshold to silence shortage traffic; the split by
  `outcome` is the intended way to tell the two apart.

## Related

- [`InventoryReservationInfraErrors`](InventoryReservationInfraErrors.md)
- [`InventoryReserveUnknownSKU`](InventoryReserveUnknownSKU.md)
- [`GrpcServerHighErrorRate`](GrpcServerHighErrorRate.md) — the fleet-wide equivalent
- [`docs/api/inventory.md`](../../../api/inventory.md) — RPCs and status-code contract

_Last updated: 2026-08-07_
