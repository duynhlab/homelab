# API naming & gateway URL convention

| Attribute | Value |
|-----------|--------|
| **Version** | **v3.0.1** |
| **Status** | **Adopted** — sole URL surface (services mount these paths directly) |
| **Superseded** | v2.0.0 free-form `{resource…}` (13 routes renamed, [ADR-017](../proposals/adr/ADR-017-api-path-collection-noun/)); `docs/api/api.md` cluster-only `/api/v1/*` shape (v0.85 and earlier) |
| **Scope** | All HTTP URLs used by browsers, services, and admin/seed callers |
| **Primary domain** | `local.duynh.me` — platform root; public API at `gateway.duynh.me` |
| **Last updated** | 2026-07-13 (RFC-0015 P2: checkout shipping/payment/confirm routes) |

## Purpose

Specify the **single** URL shape used everywhere in the platform — frontend, service handlers, service-to-service callers. There is no separate "cluster" vs "edge" path any more; services register Variant A paths directly on their Gin routers and Kong passes requests through without rewriting.

The shape is inspired by a multi-segment edge layout and refined with ideas from the Google API Design Guide (see [References](#references)).

## URL shape

```
https://gateway.duynh.me/{service}/v1/{audience}/{resource…}
```

for browser (north-south) traffic, and

```
http://{service}.{namespace}.svc.cluster.local:8080/{service}/v1/{audience}/{resource…}
```

for in-cluster (east-west) traffic. Same path, different host — Kong just forwards.

- `{service}` ∈ `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`, `payment`, `checkout` (RFC-0015 — P1 surface live in local-stack; cluster lands at P5).
- `{audience}` ∈ `public`, `private`, `internal`, `protected` (`protected` is **planned — none deployed yet**).
- `{resource…}` **must start with a collection noun owned by the service** — see the rule below.

## Collection-noun rule (v3.0.0, ADR-017)

The segment immediately after `{audience}` is a **collection noun the service
owns** — by default the plural of the service's domain noun:

```
/{service}/v1/{audience}/{collection}/{resource…}
```

- Collections per service: `auth`\*, `users`, `products`, `cart`\*, `orders`,
  `reviews`, `notifications`, `shipments`, `payments`, `checkout`\*
  ([RFC-0015](../proposals/rfc/RFC-0015/)).
- **Closed exception list (\*):** process-named services with no natural
  plural collection — `auth` and `checkout` — use the literal service-name
  segment and nest their resources beneath it
  (`/auth/v1/public/auth/login`, `/checkout/v1/private/checkout/sessions`);
  `cart` is singular (a per-user singleton resource).
- Secondary resources nest under the owned noun, they never start a new
  top-level segment: `payments/webhooks/mockpay`,
  `payments/reconciliation/runs` — **not** `webhooks/…`, `reconciliation/…`.
- Custom actions are sub-paths of the collection (`shipments/track`,
  `notifications/read-all`); never a bare verb after the audience.
- Lookup by a foreign key uses a nested segment on the owned collection:
  `shipments/orders/:orderId`.
- A new service MUST register its collection noun here before mounting routes.

## Audience segments

| Value | Meaning | On gateway? | Auth enforced by |
|-------|---------|-------------|-------------------|
| `public` | Anonymous callers — no JWT required | Yes | N/A |
| `private` | Authenticated user — `Authorization: Bearer <JWT>` | Yes | Kong edge `jwt` (coarse filter) + service middleware (`pkg/authmw` verifies RS256 locally against the cached JWKS) |
| `protected` | Signed webhooks / partner HMAC / IP allowlist — **planned, none deployed yet** | Not yet (planned) | Per-route plugin or service middleware |
| `internal` | Pod → Service — cluster-only | **No — never** | Kong not exposing the route + NetworkPolicies (LIVE — kindnet enforces on K8s 1.34+) |

**Kong enforcement:** each `api-*` Ingress has one or two explicit `path:` entries — `/{service}/v1/public/` and/or `/{service}/v1/private/`. Internal audiences are never added to Ingress rules, so requests to `https://gateway.duynh.me/notification/v1/internal/notifications/email` resolve to Kong's default 404.

## Hostnames

| Role | Host |
|------|------|
| Public API gateway (north-south) | **`gateway.duynh.me`** |
| Frontend SPA (React) | `local.duynh.me` |
| Static assets + CDN (future) | `static.duynh.me` |
| Private internal gateway (future) | `internal.gateway.duynh.me` |

## Complete route inventory

### auth-service (namespace `auth`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `POST` | `/auth/v1/public/auth/login` | public | Browser |
| `POST` | `/auth/v1/public/auth/register` | public | Browser |
| `POST` | `/auth/v1/public/auth/refresh` | public | Browser (silent refresh) |
| `POST` | `/auth/v1/public/auth/logout` | public | Browser — body `{refresh_token}`, revokes the token family |
| `GET` | `/auth/v1/public/auth/jwks` | public | Every service's JWT middleware + Kong edge (verification keys) |

### user-service (namespace `user`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` | `/user/v1/public/users/:id` | public | Browser |
| `GET` | `/user/v1/private/users/profile` | private | Browser |
| `PUT` | `/user/v1/private/users/profile` | private | Browser |
| `POST` | `/user/v1/internal/users` | internal | *No in-cluster caller today* (auth registers into its own DB; reserved for a future registration fan-out) |

### product-service (namespace `product`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` | `/product/v1/public/products` | public | Browser |
| `GET` | `/product/v1/public/products/:id` | public | Browser |
| `GET` | `/product/v1/public/products/:id/details` | public | Browser (aggregates reviews) |
| `POST` | `/product/v1/internal/products` | internal | Admin / seed |

### cart-service (namespace `cart`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` / `POST` / `DELETE` | `/cart/v1/private/cart` | private | Browser; `GET` also by order-service (server-side pricing, forwarded `Authorization`) |
| `GET` | `/cart/v1/private/cart/count` | private | Browser (badge) |
| `PATCH` / `DELETE` | `/cart/v1/private/cart/items/:itemId` | private | Browser |
| `DELETE` | `/cart/v1/internal/cart/:userId` | internal | order-worker (saga `ClearCart` — tokenless, NetworkPolicy-fenced) |

### order-service (namespace `order`)

All private.

| Method | Path | Caller |
|--------|------|--------|
| `GET` | `/order/v1/private/orders` | Browser |
| `GET` | `/order/v1/private/orders/:id` | Browser |
| `GET` | `/order/v1/private/orders/:id/details` | Browser (aggregates shipment + payment) |
| `POST` | `/order/v1/private/orders` | Browser |

### review-service (namespace `review`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` | `/review/v1/public/reviews?product_id=…` | public | Browser + product-service (aggregation) |
| `POST` | `/review/v1/private/reviews` | private | Browser |

### notification-service (namespace `notification`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` | `/notification/v1/private/notifications` | private | Browser |
| `GET` | `/notification/v1/private/notifications/count` | private | Browser (bell badge) |
| `PATCH` | `/notification/v1/private/notifications/read-all` | private | Browser (mark all as read) |
| `GET` / `PATCH` | `/notification/v1/private/notifications/:id` | private | Browser |
| `POST` | `/notification/v1/internal/notifications/email` | internal | Any service publishing a user notification |
| `POST` | `/notification/v1/internal/notifications/sms` | internal | Any service publishing a user notification |

### shipping-service (namespace `shipping`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` | `/shipping/v1/public/shipments/track?tracking_number=…` | public | Browser |
| `GET` | `/shipping/v1/public/shipments/estimate?origin&destination&weight` | public | Browser |
| `GET` | `/shipping/v1/internal/shipments/orders/:orderId` | internal | order-service (order-details aggregation) |

### payment-service (namespace `payment`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `POST` | `/payment/v1/public/payments/webhooks/mockpay` | public | mockpay provider (HMAC-signed body is the credential) |
| `GET` / `POST` | `/payment/v1/private/payments` | private | Browser |
| `GET` | `/payment/v1/private/payments/:id` | private | Browser |
| `POST` | `/payment/v1/internal/payments/:id/refunds` | internal | In-cluster ops (the saga's refunds run over gRPC `PaymentService.Refund`) |
| `POST` | `/payment/v1/internal/payments/reconciliation/runs` | internal | Reconciliation trigger (in-cluster) |
| `GET` | `/payment/v1/internal/payments/reconciliation/runs/:id` | internal | Reconciliation status (in-cluster) |

### checkout-service (namespace `checkout`) — RFC-0015 P1+P2 (local-stack; cluster at P5)

All private (Kong edge JWT + in-service authmw); sessions owner-scoped by the
JWT `user_id`. Promo lands in P4; shipping fee/tax are 0-stubs until the P3
GetQuote integration.

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `POST` | `/checkout/v1/private/checkout/sessions` | private | Browser — create (201) or return the active session (200, idempotent) |
| `GET` | `/checkout/v1/private/checkout/sessions/:id` | private | Browser |
| `PUT` | `/checkout/v1/private/checkout/sessions/:id/address` | private | Browser |
| `PUT` | `/checkout/v1/private/checkout/sessions/:id/shipping` | private | Browser — choose method (P2: fee/tax 0-stub) |
| `PUT` | `/checkout/v1/private/checkout/sessions/:id/payment` | private | Browser — attach `tok_…` reference (PAN-like → 400 pre-persist) |
| `POST` | `/checkout/v1/private/checkout/sessions/:id/confirm` | private | Browser — idempotent order handoff; `Idempotency-Key` header REQUIRED (≤120 chars) |
| `DELETE` | `/checkout/v1/private/checkout/sessions/:id` | private | Browser — cancel |

## Deprecated aliases (transitional — expand phase, ADR-017)

The v3.0.0 rename ships expand→contract. Routes that had **live callers** keep
their pre-v3 path mounted as an alias (same handler) for one release; the
contract release removes them:

| Deprecated alias | Canonical path |
|------------------|----------------|
| `/auth/v1/public/{login,register,refresh,logout,jwks}` | `/auth/v1/public/auth/{…}` |
| `/shipping/v1/public/{track,estimate}` | `/shipping/v1/public/shipments/{track,estimate}` |
| `/payment/v1/public/webhooks/mockpay` | `/payment/v1/public/payments/webhooks/mockpay` |
| `/payment/v1/internal/reconciliation/runs[/:id]` | `/payment/v1/internal/payments/reconciliation/runs[/:id]` |

The zero-HTTP-caller internal routes (`/shipping/v1/internal/orders/:orderId`,
`/notification/v1/internal/notify/{email,sms}` — both hops are gRPC) were
renamed **without** aliases. Contract checklist lives in
[ADR-017](../proposals/adr/ADR-017-api-path-collection-noun/).

## Service-to-service calls

The caller → callee → audience mapping for in-cluster east-west traffic:

| Caller | Target | Audience |
|--------|--------|----------|
| Every service's JWT middleware (JWKS refresh) | auth-service `/auth/v1/public/auth/jwks` | public |
| order-service → aggregation (shipment + payment) | shipping-service, payment-service | internal (gRPC) |
| order-service → server-side pricing | cart-service | private (forwards user's JWT) |
| order-worker → saga steps (stock, shipment, money, email) | product-, shipping-, payment-, notification-service | internal (gRPC) |
| order-worker → saga cart-clear | cart-service `/cart/v1/internal/cart/:userId` | internal (tokenless) |
| product-service → aggregation | review-service | internal (gRPC) |
| checkout-service → cart snapshot | cart-service `cart.v1/GetCart` | internal (gRPC, read-only — ADR-021) |
| checkout-service → price/stock re-validation | product-service `product.v1/GetProducts` | internal (gRPC, cache-bypassing — ADR-020) |
| auth-service → registration | user-service | **Planned** — no in-cluster caller today (auth registers into its own DB) |

Most of these hops now run over **gRPC**, not HTTP. For transport (gRPC vs REST per hop), addresses, ports, and migration status, see [`grpc-internal-comms.md`](grpc-internal-comms.md) — it is authoritative for east-west transport.

## Registering a new route

1. Choose the audience — `public`, `private`, or `internal`. This is a permanent contract decision.
2. Mount it in the owning service at `/{service}/v1/{audience}/{collection}/{resource…}` — the collection noun per the rule above (register a new service's noun in this doc first). Apply JWT middleware only to the `/{service}/v1/private` router group.
3. If it's `public` or `private` **and** browser-reachable, add a `path:` entry to `kubernetes/infra/configs/kong/ingress-api.yaml` for that service. If it's `internal`, do nothing — the service DNS is enough.
4. Add a row to the route inventory above.
5. Update the frontend `src/api/*.js` module if the browser calls it.

## Google-aligned practices (apply to `{resource…}` and bodies)

- Plural nouns for collections; stable resource IDs.
- Standard HTTP methods; custom actions as sub-paths of the owned collection (POST for mutating actions).
- Consistent error envelope: `{ "error": "<message>" }`.
- List endpoints: pagination (`page_size`, `page_token` or offset/limit — be consistent per service).
- JSON field naming: `snake_case` across services (aligns with current handlers).

## Static assets (future reference)

```
https://static.duynh.me/storage/app/v5/<release>/assets/header.css
```

Immutable file names (content hash) + explicit `Cache-Control` for chunks.

## References

- Google API Design Guide — <https://cloud.google.com/apis/design>

## History

| Version | Date | Change |
|---------|------|--------|
| v1.0.0 | 2026-04-09 | Initial Draft — Variant A vs B exploration, illustrative services. |
| v1.1.0 | 2026-04-17 | Adopted Variant A at the edge. Services still mounted on `/api/v1/*`; Kong rewrote edge → cluster via per-namespace `pre-function` plugins. |
| **v2.0.0** | **2026-04-17** | **Full migration — services mount Variant A paths directly, Kong is pure pass-through, `/api/v1/*` removed entirely. Internal audiences live only in-cluster (never on gateway).** Breaking change; frontend and all service-to-service callers updated in lockstep. |
| **v3.0.0** | **2026-07-12** | **Collection-noun rule ([ADR-017](../proposals/adr/ADR-017-api-path-collection-noun/)) — the segment after `{audience}` must be a service-owned collection noun; 13 routes renamed (auth 5, shipping 3, notification 2, payment 3).** Expand→contract: live-caller routes keep deprecated aliases for one release; zero-caller internal routes renamed outright. |
| v3.0.1 | 2026-07-12 | Checkout joins the process-named exception (with auth): owning segment is the literal `checkout`, resources nest beneath it (`checkout/sessions[…]`) — a bare `sessions` collection was ambiguous platform-wide. Applied before any consumer existed (pre-P3 SPA), so no aliases needed. |
