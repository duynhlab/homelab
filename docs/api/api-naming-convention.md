# API naming & gateway URL convention

| Attribute | Value |
|-----------|--------|
| **Version** | **v1.1.0** |
| **Status** | **Adopted** — production edge convention |
| **Canonical API** | [`api.md`](api.md) — cluster-internal **`/api/v1/*`** surface (service-to-service callers) |
| **Scope** | Gateway-facing URL naming (edge) for browser/public callers |
| **Primary domain** | `duynhne.me` — platform root; APIs live on `gateway.duynhne.me` |
| **Last updated** | 2026-04-17 |

## Purpose

Specify the single URL shape used at the public edge — `gateway.duynhne.me` — for browser-originated traffic. Service handlers do **not** move; Kong rewrites edge paths down to cluster paths. Inspired by Chợ Tốt's multi-segment edge layout and refined with [Google API Design Guide](https://cloud.google.com/apis/design) ideas.

## Relationship to [`api.md`](api.md)

| Concern | [`api.md`](api.md) | This doc |
|---------|--------------------|----------|
| Scope | Cluster-internal `/api/v1/{resource}` surface (service-to-service) | Browser edge `https://gateway.duynhne.me/{service}/v1/{audience}/{resource}` |
| Handler mounts | Accurate — reflects what services expose | N/A — gateway-only |
| Audience | Per-row tables | Encoded in the URL segment (`public`/`private`/`internal`/`protected`) |

**Bridge pattern (adopted):** Kong's per-namespace `pre-function` plugin rewrites edge → cluster at the request access phase. See [`kubernetes/infra/configs/kong/rewrite-plugins.yaml`](../../kubernetes/infra/configs/kong/rewrite-plugins.yaml).

## Hostnames

| Role | Host |
|------|------|
| Public API gateway (north-south) | **`gateway.duynhne.me`** |
| Frontend SPA (React) | `duynhne.me` |
| Static assets + CDN (future) | `static.duynhne.me` |
| Private internal gateway (future, optional) | `internal.gateway.duynhne.me` — only if we later expose an internal L7 edge |

## URL shape (Variant A — adopted)

```
https://gateway.duynhne.me/{service}/v1/{audience}/{resource…}
```

- `{service}` — one of: `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`.
- `{audience}` — exactly one of the values below.
- `{resource…}` — the remainder of the path; chosen to mirror cluster paths where practical so operators can cross-reference quickly.

**Variant B rejected.** We considered `/v1/{service}/{audience}/…` and chose Variant A because service ownership reads more naturally at the first segment — easier for Kong routing tables and per-team autonomy.

## Audience segments

| Value | Meaning | Edge policy (today) |
|-------|---------|---------------------|
| `public` | Anonymous — no JWT required | CORS allow-list + rate-limit + request-size-limit |
| `private` | Authenticated user (JWT) | Same as public; service validates JWT in middleware (defense-in-depth) |
| `protected` | Signed webhooks / partner HMAC / IP allowlist | Reserved; no routes today |
| `internal` | Pod → Service (cluster-only) | **Never exposed on `gateway.duynhne.me`** — reachable only via `*.svc.cluster.local` |

## Edge → cluster mapping (complete)

### auth-service (namespace `auth`)

| Edge | Cluster |
|------|---------|
| `POST /auth/v1/public/login` | `/api/v1/auth/login` |
| `POST /auth/v1/public/register` | `/api/v1/auth/register` |
| `GET /auth/v1/private/me` | `/api/v1/auth/me` |

### user-service (namespace `user`)

| Edge | Cluster |
|------|---------|
| `GET /user/v1/public/users/:id` | `/api/v1/users/:id` |
| `GET /user/v1/private/users/profile` | `/api/v1/users/profile` |
| `PUT /user/v1/private/users/profile` | `/api/v1/users/profile` |
| `POST /api/v1/users` *(internal only)* | not on gateway |

### product-service (namespace `product`)

| Edge | Cluster |
|------|---------|
| `GET /product/v1/public/products` | `/api/v1/products` |
| `GET /product/v1/public/products/:id` | `/api/v1/products/:id` |
| `GET /product/v1/public/products/:id/details` | `/api/v1/products/:id/details` |
| `POST /api/v1/products` *(internal only)* | not on gateway |

### cart-service (namespace `cart`)

| Edge | Cluster |
|------|---------|
| `GET \| POST \| DELETE /cart/v1/private/cart` | `/api/v1/cart` |
| `GET /cart/v1/private/cart/count` | `/api/v1/cart/count` |
| `PATCH \| DELETE /cart/v1/private/cart/items/:itemId` | `/api/v1/cart/items/:itemId` |

### order-service (namespace `order`)

| Edge | Cluster |
|------|---------|
| `GET /order/v1/private/orders` | `/api/v1/orders` |
| `GET /order/v1/private/orders/:id` | `/api/v1/orders/:id` |
| `GET /order/v1/private/orders/:id/details` | `/api/v1/orders/:id/details` |
| `POST /order/v1/private/orders` | `/api/v1/orders` |

### review-service (namespace `review`)

| Edge | Cluster |
|------|---------|
| `GET /review/v1/public/reviews?product_id=…` | `/api/v1/reviews` |
| `POST /review/v1/private/reviews` | `/api/v1/reviews` |

### notification-service (namespace `notification`)

| Edge | Cluster |
|------|---------|
| `GET /notification/v1/private/notifications` | `/api/v1/notifications` |
| `GET /notification/v1/private/notifications/count` | `/api/v1/notifications/count` |
| `GET \| PATCH /notification/v1/private/notifications/:id` | `/api/v1/notifications/:id` |
| `POST /api/v1/notify/{email,sms}` *(internal only)* | not on gateway |

### shipping-service (namespace `shipping`)

| Edge | Cluster |
|------|---------|
| `GET /shipping/v1/public/track?tracking_number=…` | `/api/v1/shipping/track` |
| `GET /shipping/v1/public/estimate?…` | `/api/v1/shipping/estimate` |
| `GET /api/v1/shipping/orders/:orderId` *(internal only)* | not on gateway |

## Rewrite rule (per namespace)

Each service namespace gets one `KongPlugin` (pre-function) attached to its ingress via annotation `konghq.com/plugins: rewrite-edge-to-cluster,rate-limiting-api,request-size-limiting-api`. Two rewrite patterns:

```lua
-- Pattern A: service name == cluster collection (auth, shipping)
local p = kong.request.get_path()
local new, n = p:gsub("^/auth/v1/[%w]+", "/api/v1/auth")
if n > 0 then kong.service.request.set_path(new) end
```

```lua
-- Pattern B: edge resource already carries the collection (everyone else)
local p = kong.request.get_path()
local new, n = p:gsub("^/product/v1/[%w]+", "/api/v1")
if n > 0 then kong.service.request.set_path(new) end
```

Source of truth: [`kubernetes/infra/configs/kong/rewrite-plugins.yaml`](../../kubernetes/infra/configs/kong/rewrite-plugins.yaml).

## Google-aligned practices (apply to `{resource…}` and bodies)

- Plural nouns for collections; stable resource IDs.
- Standard HTTP methods; custom actions as sub-paths or POST with typed bodies.
- Consistent error envelope: `{ "error": "<message>" }` — see [`api.md`](api.md) *Common Response Patterns*.
- List endpoints: pagination (`page_size`, `page_token` or offset/limit — be consistent per service).
- JSON field naming: `snake_case` across services (aligns with current handlers).

## Internal endpoints (reminder)

Never add to `ingress-api.yaml`. Internal paths are reachable from other pods only, via:

```
http://{service}.{namespace}.svc.cluster.local:8080/api/v1/...
```

NetworkPolicy is the right tool to keep them inaccessible from outside the cluster. Do not rely on "it's unlisted in Kong" — the ingress surface is the contract, but NetworkPolicy is the fence.

## Static assets (future reference)

Pattern aligned with object storage + CDN:

```
https://static.duynhne.me/storage/app/v5/<release>/assets/header.css
```

Immutable file names (content hash) + explicit `Cache-Control` for chunks.

## Change control

- Any new public browser route requires:
  1. A cluster handler in the relevant service.
  2. An edge path in `ingress-api.yaml` and (if shape differs from the service's existing Lua pattern) an update to `rewrite-plugins.yaml`.
  3. A row added to the mapping tables above.
  4. OpenAPI spec update in the owning service repo (tag per audience).

- Internal endpoints need only (1). Keep them off the gateway.

## History

| Version | Date | Change |
|---------|------|--------|
| v1.0.0 | 2026-04-09 | Initial draft exploring Variant A vs B (illustrative services). |
| v1.1.0 | 2026-04-17 | **Adopted** Variant A; replaced illustrative services with the real 8; added rewrite rule reference and internal-endpoint rules. |
