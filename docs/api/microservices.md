# Microservices Catalog

The platform-wide map of feature ownership, composition boundaries, and current
cross-service gaps.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Status** | Living ownership reference for the deployed platform | — |
| **Covers** | Feature and data authority, composite-feature boundaries, and known-gap rollup | — |
| **Does not cover** | Shared protocol rules, route payloads, deployment wiring, or exact call edges | — |
| **Related** | [Shared API guide](./api.md) · [service contracts](./README.md#service-contracts) · [workflow registry](./workflows.md) | — |
| **Area hub** | [docs/api/README.md](./README.md) | — |
| **Design records** | None | — |

This catalog is authoritative for the question **“which component owns this
feature or fact?”** A serving service owns its contract even when another
service or browser composes the result. Service-repository README API tables are
implementation hints; when they disagree with `docs/api/`, this documentation
wins and the mismatch is drift to fix.

## Document boundary

| Question | Canonical owner |
|----------|-----------------|
| Shared URL, audience, auth, errors, gRPC, topology, call graph, and user journeys | [api.md](./api.md) |
| One service's routes, RPCs, payloads, runtime modes, deployment, and detailed gaps | Its [service contract](./README.md#service-contracts) |
| Feature and data authority across the platform | [Feature ownership](#feature-ownership) below |
| Temporal workflow owner, task queue, participants, and lifecycle | [workflows.md](./workflows.md) and [temporal.md](./temporal.md) |
| Deployment and CI status across services | [README.md § Service contracts](./README.md#service-contracts) |
| Current cross-service risk themes | [Known gaps and ongoing work](#known-gaps-and-ongoing-work) below |

The current runtime inventory is the hub rollup, verified by
[`local-stack/compose.yaml`](../../local-stack/compose.yaml) and the
[`kubernetes/apps/`](../../kubernetes/apps/) manifests. It includes ten Go
microservices, the Storefront and Backoffice application services, two Temporal
workers, Keycloak, and the MockPay provider stub. The former auth-service is
archived; [auth.md](./auth.md) is historical contract material, not a live
owner.

## Feature ownership

| Capability or fact | Canonical owner | Ownership boundary | Contract |
|--------------------|-----------------|--------------------|----------|
| Customer and staff credentials, realms, token issuance, and identity claims | Keycloak | Services verify tokens but do not mint or mutate identity claims | [identity.md](./identity.md) |
| Customer profile fields | user | Keycloak owns identity; user owns display/profile persistence | [user.md](./user.md) |
| Products, categories, lifecycle, and current prices | product | Inventory owns stock; review owns ratings | [product.md](./product.md) |
| Warehouse balances, availability, reservations, allocation, and movement ledger | inventory | Product may display availability but cannot define it | [inventory.md](./inventory.md) |
| Per-customer mutable basket | cart | Product owns current price; checkout owns purchase-session snapshots | [cart.md](./cart.md) |
| Purchase session, totals composition, promo attachment, and confirm idempotency | checkout | Order remains the sole durable order writer | [checkout.md](./checkout.md) |
| Orders, status history, fulfillment orchestration, and cancellation policy | order | Participant services own each external side effect | [order.md](./order.md) |
| Product reviews and ratings | review | Product only aggregates the review-owned result | [review.md](./review.md) |
| Shipping quotes, shipments, tracking numbers, and shipment state | shipping | Checkout consumes quotes; order consumes shipment state | [shipping.md](./shipping.md) |
| Notification inbox records and send-attempt state | notification | Order requests messages but does not own delivery records | [notification.md](./notification.md) |
| Payment/refund state, ledger, provider attempts, and reconciliation | payment | Order orchestrates money steps but cannot write payment state | [payments.md](./payments.md) |
| Shopper UI and browser-side presentation | Storefront application service | Owns no business data or business API | [frontend platform contract](../frontend/README.md) |
| Operator UI and protected-API consumption map | Backoffice application service | Owns no business data, authorization decision, or BFF | [admin.md](./admin.md) |

## Composite feature boundaries

Composition changes the response shape, not the underlying authority.

| Composite behavior | Response or workflow owner | Contributing authorities | Boundary rule | Deep dive |
|--------------------|----------------------------|--------------------------|---------------|-----------|
| Product details | product | review ratings; inventory availability | Missing enrichment may degrade explicitly; product never invents either fact | [product contract](./product.md) |
| Checkout session and confirm | checkout | cart quantities; product prices; inventory availability; shipping quote | Checkout snapshots and validates; successful confirm hands one idempotent command to order | [checkout contract](./checkout.md) |
| Order details | order | shipping state; payment state; inventory reservation | Order authorizes the owned record first, then soft-fails optional enrichment | [order contract](./order.md) |
| Fulfillment and cancellation | order | inventory, shipping, payment, notification, and cart | Order owns workflow state; every participant owns and idempotently applies its side effect | [workflow registry](./workflows.md) |
| Backoffice operations | Backoffice browser | six serving services | The browser calls `/protected/` contracts directly; no BFF or shared admin database exists | [admin consumer index](./admin.md) |

Exact synchronous edges and transports live only in
[api.md § Current East-West Call Graph](./api.md#current-east-west-call-graph).
Exact durable workflow steps live only in the
[workflow registry](./workflows.md).

## Known gaps and ongoing work

This is a navigation rollup, not a second copy of each service's analysis.
`Condition` describes risk or lifecycle; it is deliberately not the capability
availability vocabulary used by service At-a-glance tables.

| Theme | Owner | Condition | Detail |
|-------|-------|-----------|--------|
| East-west workload authentication and encryption | platform | Planned; NetworkPolicy is the current fence | [api.md § Security](./api.md#security) |
| Profile field reachability, timestamp maintenance, and first-write race | user | Current limitations | [user known gaps](./user.md#known-gaps) |
| First stock balance for an untracked catalog SKU | inventory | Manual operator bootstrap; detected and fail-closed | [inventory known gaps](./inventory.md#known-gaps) |
| Promo contention, asymmetric upstream errors, and parked confirm recovery | checkout | Accepted operational trade-offs | [checkout known gaps](./checkout.md#known-gaps) |
| Committed-stock cancellation and workflow-start terminal failures | order | Accepted or alerted trade-offs | [order known gaps](./order.md#known-gaps) |
| Real provider delivery, send idempotency, and unused SMS/HTTP twins | notification | Current limitations and no-caller surfaces | [notification known gaps](./notification.md#known-gaps) |
| Deprecated aliases, unpersisted destination, and demo quote math | shipping | Migration debt and accepted limitations | [shipping known gaps](./shipping.md#known-gaps) |
| Deprecated aliases, direct DB connection, reconciliation limits, and single-replica constraint | payment | Migration and scaling constraints | [payment known gaps](./payments.md#known-gaps) |
| Bounded review feed and write-once reviews | review | Accepted design limits | [review known gaps](./review.md#known-gaps) |
| Backoffice availability and static-delivery hardening | Backoffice | Current platform gaps | [Backoffice known gaps](../frontend/admin-portal/README.md#known-gaps) |

Resolved migrations and retired surfaces stay in their RFCs, ADRs, and archived
contracts; they are not ongoing-work rows here.

## References

- [API documentation index](./README.md)
- [Shared API and service communication guide](./api.md)
- [Workflow registry](./workflows.md)
- [Repository index](../README.md#repositories)

_Last updated: 2026-08-26 — removes duplicated deployment, route, RPC, and technique inventories; restores the catalog to feature ownership and current known-gap rollup._
