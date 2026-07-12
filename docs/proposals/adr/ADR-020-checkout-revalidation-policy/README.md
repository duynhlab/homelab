# ADR-020: Product is the price authority at checkout; stock is checked, never reserved

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-12 | [RFC-0015](../../rfc/RFC-0015/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

Cart stores `product_price` denormalized at add-to-cart time and — before
checkout-service — was treated as the pricing authority at order creation.
Nothing re-validated against product-service between "add to cart" (possibly
days ago) and "place order": a price change silently charged the old price
(documented gap in `docs/api/microservices.md`). Separately, product-service
owns inventory (RFC-0003) and the saga's `ReserveStock` is the only
reservation writer.

## Decision

We will make **product-service the price authority at checkout time**:
`POST /sessions` (and, from P2, confirm) reads prices through the new
cache-bypassing `product.v1/GetProducts` batch RPC and locks them into the
session snapshot (`unit_price_minor`). Cart remains the **item-list
authority** only; its denormalized price is carried per line
(`cart_price_minor`) purely to flag `price_changed` for the UX. A product
missing from the catalog keeps its line flagged; confirm-time re-validation
(P2) is the gate that blocks it.

Stock is **checked, not reserved**: `available_qty < quantity` fails fast
(`409 STOCK_UNAVAILABLE` at confirm), while the authoritative claim remains
the saga's idempotent `ReserveStock`.

## Alternatives considered

### Keep cart as the pricing authority
- Pros: zero new RPCs; today's behavior.
- Cons: perpetuates the silent stale-price charge — the exact gap RFC-0015
  exists to close.
- Rejected: the funnel must be honest at the money moment.

### Re-read prices from the product cache (Cache-Aside path)
- Pros: cheaper reads.
- Cons: the cache exists for browsing; serving a possibly-stale price to the
  checkout money-path re-opens the gap with extra steps.
- Rejected: checkout reads bypass the cache by design (`GetProducts` hits the
  DB row).

### Soft-reserve stock at checkout
- Pros: fewer confirm-time failures.
- Cons: two writers on the reservation ledger; breaks RFC-0003's
  single-owner semantics; a TOCTOU window remains anyway between quote and
  confirm.
- Rejected: the saga compensates cleanly; the accepted TOCTOU window is named
  in the RFC.

## Consequences

- Positive: prices shown at checkout are the prices charged; price drift is a
  first-class `price_changed` UX signal, not a silent discrepancy; inventory
  ownership stays single-writer.
- Negative / accepted: two extra gRPC hops on session create (and confirm);
  a deliberate cache-bypass load on product's DB (bounded: one batch read per
  create/confirm); the check-not-reserve TOCTOU window stands, closed by the
  saga's `ReserveStock` + compensation.

## References

- [RFC-0015](../../rfc/RFC-0015/) §Price & stock re-validation policy
- [RFC-0003](../../rfc/RFC-0003/) — inventory single-owner
- `product-service/internal/logic/v1.GetProductsByIDs` (cache-bypass note)

_Last updated: 2026-07-12_
