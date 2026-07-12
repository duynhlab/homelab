# ADR-018: Keep order the only orders-writer; checkout hands off via CreateOrder gRPC

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-13 | [RFC-0015](../../rfc/RFC-0015/) |

## Context

RFC-0015's confirm step must turn a validated checkout session into a real
order and start the fulfillment saga. Two services now care about order
creation: order-service owns the `orders` schema, the idempotent insert
(partial unique index on `(user_id, idempotency_key)`), and the
`OrderFulfillmentWorkflow` kickoff; checkout-service owns the session funnel
and has already re-validated items and prices against product-service (the
price authority, ADR-020) by the time the user confirms.

The confirm handoff is machine-to-machine, must be idempotent under retries
and crashes (a checkout retry must never double-create or double-charge), and
sits east-west where gRPC is the platform's official transport. Order had no
inbound gRPC surface before this.

## Decision

We keep **order-service as the single writer of orders and the single starter
of the fulfillment saga**, and give it its first inbound gRPC surface:
`order.v1/CreateOrder` on `:9090` (dual-port next to HTTP, the shipping
pattern). Checkout calls it with the session snapshot and a **required,
deterministic idempotency key** (`checkout:<session_id>:<Idempotency-Key>`).

The adapter reuses the exact logic seam the browser REST endpoint uses
(validate + enrich + atomic insert with idempotency-conflict replay) and
**skips the live cart re-read** — the only caller has already re-validated
against product, a strictly stronger check than cart's denormalized prices.
Saga kickoff is idempotent: attempted on fresh AND replayed orders but only
while the order is still `pending` (status gate), with
`WorkflowIDReusePolicy=RejectDuplicate` on the existing
`order-fulfillment-<id>` dedup ID; "already started" is success, any other
kickoff failure answers `Unavailable` so the machine caller retries and the
replay path heals zombie pending orders.

Trust follows the platform's east-west posture: no per-request user JWT —
`user_id` crosses as an explicit field and **NetworkPolicy is the fence**
(only the checkout namespace may reach order `:9090` in the cluster phase),
the same accepted posture as ReserveStock/CreateShipment/GetCart.

## Alternatives considered

**Checkout writes orders directly (shared table or its own copy).**
Pros: one fewer network hop. Cons: two writers of one schema, the partial
unique index and saga kickoff would have to be duplicated exactly, and drift
between the copies becomes a double-charge factory. Rejected — the invariant
"one writer, one saga starter" is the whole safety story.

**Reuse the REST endpoint (`POST /order/v1/private/orders`) service-to-service.**
Pros: no new surface. Cons: REST is the browser transport here; the endpoint
expects a user JWT and reads the live cart (weaker than checkout's product
re-validation), and its idempotency key is an optional header where the
machine flow needs it required. Rejected — wrong contract for a machine
caller, and east-west REST contradicts the gRPC-only transport decision.

**A new "place order" saga owned by checkout (checkout starts Temporal).**
Pros: checkout controls the whole funnel. Cons: two services starting
workflows against order state, kickoff dedup spread across repos, and order's
`pending`-status gate would race a foreign starter. Rejected as a boundary
violation.

## Consequences

- Order gains a second transport for one RPC; both delegate to one shared
  saga starter (`internal/fulfillment`), so kickoff semantics cannot drift.
- The composed key caps the client `Idempotency-Key` at 120 chars (order-side
  limit is 200 for the whole key) — enforced at checkout's web boundary.
- gRPC replay returns the order's **current** status, which may already be
  past `pending`; callers must not assume otherwise.
- The cluster phase (P5) must ship the NetworkPolicy admitting only checkout
  to order `:9090`, plus the `order-grpc` headless Service and
  `grpc_server: true` in `rsip-order` — until then the fence exists only in
  the local stack's flat network (accepted for local dev).
- Revisit trigger: a second internal caller of CreateOrder (it would need its
  own key namespace), or payment-before-order flows (RFC-0016 territory).

---
_Last updated: 2026-07-13_
