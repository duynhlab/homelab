# API naming & gateway URL convention

| Attribute | Value |
|-----------|--------|
| **Version** | **v2.0.0** |
| **Status** | **Adopted** — sole URL surface (services mount these paths directly) |
| **Superseded** | `docs/api/api.md` cluster-only `/api/v1/*` shape (v0.85 and earlier) |
| **Scope** | All HTTP URLs used by browsers, services, and admin/seed callers |
| **Primary domain** | `local.duynh.me` — platform root; public API at `gateway.duynh.me` |
| **Last updated** | 2026-07-10 |

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

- `{service}` ∈ `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`, `payment`.
- `{audience}` ∈ `public`, `private`, `internal`, `protected` (`protected` is **planned — none deployed yet**).
- `{resource…}` mirrors the collection/verb owned by the service.

## Audience segments

| Value | Meaning | On gateway? | Auth enforced by |
|-------|---------|-------------|-------------------|
| `public` | Anonymous callers — no JWT required | Yes | N/A |
| `private` | Authenticated user — `Authorization: Bearer <JWT>` | Yes | Kong edge `jwt` (coarse filter) + service middleware (`pkg/authmw` verifies RS256 locally against the cached JWKS) |
| `protected` | Signed webhooks / partner HMAC / IP allowlist — **planned, none deployed yet** | Not yet (planned) | Per-route plugin or service middleware |
| `internal` | Pod → Service — cluster-only | **No — never** | Kong not exposing the route + NetworkPolicies (LIVE — kindnet enforces on K8s 1.34+) |

**Kong enforcement:** each `api-*` Ingress has one or two explicit `path:` entries — `/{service}/v1/public/` and/or `/{service}/v1/private/`. Internal audiences are never added to Ingress rules, so requests to `https://gateway.duynh.me/notification/v1/internal/notify/email` resolve to Kong's default 404.

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
| `POST` | `/auth/v1/public/login` | public | Browser |
| `POST` | `/auth/v1/public/register` | public | Browser |
| `POST` | `/auth/v1/public/refresh` | public | Browser (silent refresh) |
| `POST` | `/auth/v1/public/logout` | public | Browser — body `{refresh_token}`, revokes the token family |
| `GET` | `/auth/v1/public/jwks` | public | Every service's JWT middleware + Kong edge (verification keys) |

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
| `POST` | `/notification/v1/internal/notify/email` | internal | Any service publishing a user notification |
| `POST` | `/notification/v1/internal/notify/sms` | internal | Any service publishing a user notification |

### shipping-service (namespace `shipping`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `GET` | `/shipping/v1/public/track?tracking_number=…` | public | Browser |
| `GET` | `/shipping/v1/public/estimate?origin&destination&weight` | public | Browser |
| `GET` | `/shipping/v1/internal/orders/:orderId` | internal | order-service (order-details aggregation) |

### payment-service (namespace `payment`)

| Method | Path | Audience | Caller |
|--------|------|----------|--------|
| `POST` | `/payment/v1/public/webhooks/mockpay` | public | mockpay provider (HMAC-signed body is the credential) |
| `GET` / `POST` | `/payment/v1/private/payments` | private | Browser |
| `GET` | `/payment/v1/private/payments/:id` | private | Browser |
| `POST` | `/payment/v1/internal/payments/:id/refunds` | internal | In-cluster ops (the saga's refunds run over gRPC `PaymentService.Refund`) |
| `POST` | `/payment/v1/internal/reconciliation/runs` | internal | Reconciliation trigger (in-cluster) |
| `GET` | `/payment/v1/internal/reconciliation/runs/:id` | internal | Reconciliation status (in-cluster) |

## Service-to-service calls

The caller → callee → audience mapping for in-cluster east-west traffic:

| Caller | Target | Audience |
|--------|--------|----------|
| Every service's JWT middleware (JWKS refresh) | auth-service `/auth/v1/public/jwks` | public |
| order-service → aggregation (shipment + payment) | shipping-service, payment-service | internal (gRPC) |
| order-service → server-side pricing | cart-service | private (forwards user's JWT) |
| order-worker → saga steps (stock, shipment, money, email) | product-, shipping-, payment-, notification-service | internal (gRPC) |
| order-worker → saga cart-clear | cart-service `/cart/v1/internal/cart/:userId` | internal (tokenless) |
| product-service → aggregation | review-service | internal (gRPC) |
| auth-service → registration | user-service | **Planned** — no in-cluster caller today (auth registers into its own DB) |

Most of these hops now run over **gRPC**, not HTTP. For transport (gRPC vs REST per hop), addresses, ports, and migration status, see [`grpc-internal-comms.md`](grpc-internal-comms.md) — it is authoritative for east-west transport.

## Registering a new route

1. Choose the audience — `public`, `private`, or `internal`. This is a permanent contract decision.
2. Mount it in the owning service at `/{service}/v1/{audience}/{resource…}`. Apply JWT middleware only to the `/{service}/v1/private` router group.
3. If it's `public` or `private` **and** browser-reachable, add a `path:` entry to `kubernetes/infra/configs/kong/ingress-api.yaml` for that service. If it's `internal`, do nothing — the service DNS is enough.
4. Add a row to the route inventory above.
5. Update the frontend `src/api/*.js` module if the browser calls it.

## Google-aligned practices (apply to `{resource…}` and bodies)

- Plural nouns for collections; stable resource IDs.
- Standard HTTP methods; custom actions as POST sub-paths.
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
