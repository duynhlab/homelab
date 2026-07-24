# ADR-027: inventory-service is the platform's sole stock authority

Extract stock (warehouse, balance, reservation, movement) out of product-service
into a dedicated inventory-service, superseding RFC-0003's "product owns
inventory" stance.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-24 | [RFC-0021](../../rfc/RFC-0021/) | [RFC-0021 research.md](../../rfc/RFC-0021/research.md) |

> **Every decision is a tradeoff.** A clean bounded context for stock costs a new
> service, database, NetworkPolicy/Kyverno surface, and a new east-west hop on the
> money path — accepted in exchange for an independent write/concurrency lifecycle,
> a real reservation and movement model, and the migration discipline the platform
> exists to practise.

> **Foundation shipped, authority not yet cut over.** inventory-service is deployed
> (local-stack + cluster) and its `inventory.v1` gRPC contract is **Implemented**,
> but it has **no live caller**: product-service remains the live stock authority
> today. Inventory *becomes* the sole authority incrementally through RFC-0021
> phases 2–4. This ADR records the decision; it does not assert a completed cutover.

## Context

product-service owns two bounded contexts with opposite profiles: a read-heavy
catalog (price, media, review aggregation, served through a Valkey cache-aside
layer) and a write/concurrency-heavy stock surface. Stock lives as
`products.stock_quantity` plus a `stock_reservations` ledger, and `ReserveStock`
decrements the column in place inside the order saga
([product.md](../../../api/product.md)). One database and one blast radius are
shared between catalog browsing and the money path; there is no warehouse model,
no reservation-expiry story, and no movement ledger that separates a physical
change from a reserved change.

RFC-0003 ratified product as the inventory owner and named a dedicated
inventory-service as its own escalation path ("Alternative (b)"). The 2026-07-23
code audit in [RFC-0021 research.md](../../rfc/RFC-0021/research.md) verified the
above against fresh `main` and re-opened the decision. This ADR is the reversal
RFC-0003 anticipated.

## Decision

We will make **inventory-service the single authoritative writer of stock** —
warehouses, per-`(sku, warehouse)` balances (`on_hand`/`reserved`/`safety_stock`),
the reservation FSM, warehouse allocation, and the append-only movement ledger.
product-service keeps catalog, price, publish lifecycle, media, and review
aggregation, and must not own on-hand, reservations, or allocation.

- **Identity:** an opaque immutable `sku_id`; the initial migration maps one
  product to one sellable SKU (`sku_id = product_id`), leaving room for a future
  variant model without a contract break.
- **Contract:** an additive `inventory.v1` gRPC package
  (`BatchGetAvailability`, `CheckAvailability`, `Reserve`, `Release`, `Commit`,
  `GetReservation`), served internally on `:9090` with no Kong route. Its
  data/behaviour model is recorded in [ADR-028](../ADR-028-inventory-reservation-model/).
- **Realized incrementally (RFC-0021):** phase 1 ships the foundation (service,
  schema, contract, GitOps, local-stack) with **no live write traffic**; phase 2
  moves checkout's availability *reads* onto inventory behind a flag; phase 3
  moves the order saga's *writes* (`Reserve`/`Release`/`Commit`, with `Commit` a
  post-pivot mandatory-forward step); phase 4 removes stock from product after
  usage reaches zero. **Product stays the live stock authority until the phase-4
  cutover.**

## Alternatives considered

Full analysis in
[RFC-0021 research.md § Alternatives](../../rfc/RFC-0021/research.md#alternatives):

- **(a) Keep RFC-0003 (product owns stock)** — zero cost, shipped saga contract
  untouched; but the catalog/stock blast radius and no-expiry reservations stay
  accepted forever and the platform never exercises bounded-context extraction,
  workflow versioning, or mandatory-forward semantics. Rejected.
- **(c) Hybrid read-model** (product keeps writes; inventory serves a projection
  for reads) — a smaller step that decouples read scaling, but adds a staleness
  boundary without solving write-path ownership; RFC-0003 already judged it
  premature. Rejected.

## Consequences

**Gain:** a clean stock bounded context with its own database, scaling, and blast
radius; a real warehouse/reservation/movement model; and a production-grade
expand → migrate → contract migration the platform is built to practise.

**Accept (the cost):**
- **Foundation only, so far.** inventory-service is deployed and its contract is
  Implemented, but has **no live caller**; product remains the live stock
  authority. The value is realized only as phases 2–4 land — do not describe the
  cutover as current.
- A new service, database (triplet on the existing `product-db` CNPG cluster),
  NetworkPolicy, and Kyverno surface, plus a new east-west hop on the money path.
- A migration with a controlled write-cutover window (phase 3) and workflow
  versioning carried until old order histories drain.
- Two overlapping stock surfaces during the migration: product's
  `stock_quantity`/`ReserveStock`/`ReleaseStock` stay authoritative and documented
  until phase 4 removes them at usage-zero.

**RFC-0003 is superseded** by RFC-0021; its stock semantics
(`available → reserved → sold/released`) carry forward into the inventory
reservation FSM ([ADR-028](../ADR-028-inventory-reservation-model/)).

**Revisit trigger:** if the phase-2/3 shadow-compare or cutover reveals the
extraction cannot hold the ATP invariant under load, or if a variant/SKU model
forces a contract change, re-open here.

**docs/api sync (API-touching, this PR):** [product.md](../../../api/product.md)
Design-record row already points RFC-0003 → RFC-0021; this PR adds
[inventory.md](../../../api/inventory.md) as the `inventory.v1` contract and lists
it in the [service-contracts rollup](../../../api/README.md#service-contracts)
marked *deployed, no live caller*.

## Related

- [RFC-0021](../../rfc/RFC-0021/) · [research.md](../../rfc/RFC-0021/research.md)
- [ADR-028](../ADR-028-inventory-reservation-model/) — the shipped reservation/balance model
- [ADR-020](../ADR-020-checkout-revalidation-policy/) — availability checked, never reserved (carries into inventory)
- [RFC-0003](../../rfc/RFC-0003/) — superseded by RFC-0021
- [`docs/api/inventory.md`](../../../api/inventory.md) · [`product.md`](../../../api/product.md)

---
_Last updated: 2026-07-24_
