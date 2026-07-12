# ADR-021: Cart gains a read-only gRPC surface; writes stay on REST

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-12 | [RFC-0015](../../rfc/RFC-0015/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

Checkout (RFC-0015) needs the user's cart lines at session creation. The
platform convention says every synchronous east-west call is gRPC, but cart
had no gRPC server — its consumers were the browser (REST, JWT) and the
saga's tokenless internal `ClearCart` REST route. Order-service also still
reads cart over REST with a forwarded JWT (server-side pricing) — a known
convention exception scheduled for cleanup in RFC-0015 P6.

## Decision

We will add a **read-only** `cart.v1.CartService` gRPC server to cart
(`GetCart(user_id) → items[]`, `:9090`, `pkg/grpcx`), serving exactly the
snapshot read checkout needs. Prices convert to int64 minor units once at
this boundary. The write path deliberately does **not** move: browser writes
stay on the JWT-protected REST API, and the saga's `ClearCart` stays on the
tokenless internal REST route.

**Criteria for migrating cart writes to gRPC later** (revisit when any holds):
1. A second in-cluster *writer* appears (today order-worker's `ClearCart` is
   the only one).
2. The saga's cart-clear step needs richer semantics than idempotent
   fire-and-forget (e.g., partial clears, returns).
3. RFC-0002 lands mTLS and the platform tightens tokenless REST internals in
   general.

## Alternatives considered

### Checkout reads cart over REST with a forwarded JWT
- Pros: no new server; mirrors what order-service does today.
- Cons: extends the exact east-west REST exception the convention (and
  RFC-0015's P6 cleanup) is closing; couples checkout to browser auth
  semantics for an internal read.
- Rejected: new edges must follow the convention — that's how the exception
  list shrinks instead of growing.

### Move the whole cart API (reads + writes) to gRPC now
- Pros: one transport story.
- Cons: touches the shipped saga (`ClearCart`) and the browser path for zero
  P1 value; scope creep in a phase whose deliverable is checkout sessions.
- Rejected: additive read surface now, criteria-gated write migration later.

## Consequences

- Positive: checkout's snapshot read follows the east-west convention from
  day one; cart's browser API and the saga are untouched (zero regression
  surface); the server is a thin adapter over the existing logic layer.
- Negative / accepted: cart now runs two transports (HTTP + gRPC) with the
  operational surface that implies (port, NetworkPolicy allows, health);
  the read/write transport split must be explained (this ADR is that
  explanation); minor-unit conversion now happens in two gRPC boundaries
  (cart + product) until the float columns are themselves migrated.

## References

- [RFC-0015](../../rfc/RFC-0015/) §New gRPC surfaces
- [ADR-020](../ADR-020-checkout-revalidation-policy/) — why prices in this
  read are advisory (cart is not the price authority)
- `cart-service/internal/grpc/v1` — the server

_Last updated: 2026-07-12_
