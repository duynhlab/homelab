# Microservices Catalog

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Status** | Living reference — the **understanding-the-system** catalog | — |
| **Covers** | Per-service feature matrix (feature → API → technique → status) and data ownership | — |
| **Related** | [api.md](api.md) (shared conventions, topology, call graph) · [workflows.md](workflows.md) · [service contracts](README.md#service-contracts) | — |
| **Area hub** | [docs/api/README.md](README.md) | — |
| **Design record** | — | None |

This document is the **understanding-the-system** reference. It does **not**
restate every endpoint (see the [service contract index](api.md#service-contract-index));
it answers, per service: *what features exist, which API surface (if any) each
feature has, and which technique implements it* — plus data ownership.

---

## 1. Platform shape

11 Go backend services (Go 1.26; ten HTTP APIs plus the gRPC-only inventory
service) and a React/Vite SPA,
fronted by **Envoy Gateway pass-through** in both environments; each service follows the
3-layer `web → logic → core` model and the Variant A URL shape
`/{service}/v1/{audience}/{resource…}`. The topology diagram and shared
HTTP/gRPC rules are owned by
[api.md § Platform API Topology](api.md#platform-api-topology).

---

## 2. Deployment snapshot (local stack)

The local end-to-end stack ([`local-stack/compose.yaml`](../../local-stack/compose.yaml))
mirrors the **app plane** (ten HTTP services + inventory gRPC), **workflow plane** (Temporal +
`order-worker` + `checkout-worker`), **provider stub** (`mockpay`), and edge
(frontend + gateway). Shared infra (Postgres, Valkey) and the observability pipeline
(OTel collector, Victoria*, ClickHouse, Grafana, Pyroscope) are internal-only —
see [`local-stack/README.md`](../../local-stack/README.md) for host ports and
audit gates.

Postgres, Valkey, Temporal, app services, workers, mockpay, gateway, and
frontend are health-gated. Temporal's consumers gate one step later, on
`temporal-bootstrap` completing rather than on the server being healthy, because
the `mop` namespace does not exist until that run-once container registers it.
Most observability containers start on `service_started`; **ClickHouse** is
health-gated and blocks the collector and Grafana until ready.

```mermaid
flowchart LR
    SPA["frontend :3001"] --> Edge["gateway :8080"]
    Edge --> SVC["10 HTTP services"]
    MP["mockpay"] -->|"provider HTTP"| PAY["payment"]
    MP -->|"webhook"| Edge
    SVC --> PG[("Postgres<br/>13 DBs")]
    SVC -->|"gRPC inventory calls"| INV["inventory<br/>gRPC only"]
    INV --> PG
    SVC --> VALKEY[("Valkey")]
    CK["checkout"] -->|"gRPC + Temporal"| SVC
    ORD["order"] --> TMP["Temporal :8233 UI"]
    CK --> TMP
    TMP --> OW["order-worker"]
    TMP --> CW["checkout-worker"]
    OW -->|"gRPC + cart REST"| SVC

    classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef worker fill:#f59e0b,color:#451a03,stroke:#b45309;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    class SPA,Edge edge;
    class SVC,INV,PAY,CK,ORD service;
    class OW,CW worker;
    class TMP platform;
    class PG,VALKEY data;
    class MP external;
```

| Component | HTTP | gRPC | Database (local) | Cache | Runtime deps / callers |
|-----------|------|------|------------------|-------|------------------------|
| keycloak | `:8080` (host `:8081`) | — | `keycloak` | — | the platform IdP (RFC-0024 P3): SPA login (PKCE), realm JWKS verified by every authmw consumer |
| auth | `:8080` | — | `auth` | — | none outbound; **nothing verifies its tokens since P3** (retires in P5) |
| user | `:8080` | — | `user` | — | Keycloak (JWKS); caller: the edge |
| product | `:8080` | `:9090` server | `product` | Valkey | review + inventory (gRPC); callers: the edge, checkout |
| inventory | health only | `:9090` server | `inventory` | — | callers: product details, checkout, order API, order-worker |
| cart | `:8080` | `:9090` server | `cart` | — | Keycloak (JWKS); callers: the edge, checkout (`GetCart`), order/order-worker (REST) |
| order | `:8080` | `:9090` server | `order` | — | Keycloak (JWKS), Temporal, shipping/payment/inventory (gRPC), cart (REST); callers: the edge, checkout (`CreateOrder`) |
| review | `:8080` | `:9090` server | `review` | — | Keycloak (JWKS); callers: the edge, product (gRPC) |
| shipping | `:8080` | `:9090` server | `shipping` | — | none outbound; callers: the edge, checkout, order, order-worker |
| notification | `:8080` | `:9090` server | `notification` | — | Keycloak (JWKS); callers: the edge, order-worker (`SendEmail`) |
| payment | `:8080` | `:9090` server | `payment` | — | Keycloak (JWKS), mockpay (HTTP); callers: the edge, order (GetPayment), order-worker (saga money) |
| checkout | `:8080` internal-only | client only | `checkout` | — | Keycloak (JWKS), cart/product/inventory/shipping/order (gRPC), Temporal; caller: the edge only |
| order-worker | `:8080` health | client only | `order` | — | Temporal; inventory/shipping/notification/payment (gRPC), cart (REST clear) |
| checkout-worker | `:8080` health | — | `checkout` | — | Temporal (`AbandonedCheckoutWorkflow`; DB-only activities) |
| mockpay | `:8080` | — | — | — | called by payment; webhooks → gateway → payment public route |
| temporal | — (`7233` gRPC, `8233` UI) | — | `temporal`, `temporal_visibility` | — | callers: order, checkout, both workers; CLI via `temporal-admintools` |
| gateway (Envoy Gateway v1.8.3, standalone provider) | `8000` → host `8080` | — | — | — (in-process local rate limit, no shared store) | ten HTTP services + cache; inventory remains east-west only; callers: frontend, browser, mockpay webhooks |
| frontend | `80` → host `3001` | — | — | — | gateway only |

> **In-cluster differences (production):** `platform-db` (CloudNativePG behind **`platform-db-pooler-rw.platform.svc.cluster.local:5432`** — auth/user/notification/shipping/review; Temporal connects **direct** to `platform-db-rw.platform:5432`);
> `product-db` (CloudNativePG behind the **pgdog-product** pooler — `product`/`cart`/`order`/`checkout`/`payment`
> databases; payment connects **direct over TLS, bypassing PgDog**).
> Locally these collapse into one Postgres holding the 11 service databases
> plus Temporal's `temporal` and `temporal_visibility`. See [`../databases/`](../databases/).
> **Logging is unified** — all 11 services log via the shared `pkg/logger` zap wrapper
> (`zapx`), teed into the OTLP pipeline (RFC-0014 P4).

---

## 3. Service feature matrix

**How to read:** one row per *behavior* (not per endpoint). The **API** column
names the surface — the full canonical path `/{service}/v1/{audience}/{resource…}`
or the gRPC RPC — and `—` for background features; full route and payload contracts live in the [owning service file](README.md#service-contracts); shared rules live in [api.md](api.md). **Technique** uses the canonical names from
the [technique index](#4-technique-index-platform-wide) (§4) — the two must stay
in sync. **Status** ∈ `Implemented` / `Partial` / `Technical debt` / `No caller` / `Planned` / `None` (shared vocabulary — see [README.md § Service contracts](README.md#service-contracts)).

### auth — identity

> Owns `users` (credentials) and refresh-token families; DB `auth` on `platform-db`
> (CloudNativePG, via the PgBouncer `Pooler` `platform-db-pooler-rw` — ADR-026 pilot;
> only `product-db` still uses PgDog). Public-only HTTP — no JWT middleware, no gRPC
> server (HTTP-only since RFC-0009 Phase 5; services verify JWTs locally).

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Token mint** (login/register) | `POST /auth/v1/public/auth/login`, `POST /auth/v1/public/auth/register` | RS256 JWT (1 h TTL, `kid` header); bcrypt verification | — | Implemented | RFC-0009 |
| **JWKS publish** | `GET /auth/v1/public/auth/jwks` | single-key JWKS, `Cache-Control: max-age=300` | — | Implemented | RFC-0009 |
| **Refresh rotation** | `POST /auth/v1/public/auth/refresh`, `POST /auth/v1/public/auth/logout` | rotating refresh tokens: opaque 32-byte token, sha256 hash at rest, family-tracked, reuse detection revokes the family (30 d TTL) | — | Implemented | — |
| **Login hardening** | (part of `/auth/v1/public/auth/login`) | constant-time dummy-hash on user-not-found (no username enumeration); generic 401 for both bad-user and bad-password | — | Implemented | — |

### user — profiles

> Owns user profiles; DB `user` on `platform-db` (CloudNativePG, via `platform-db-pooler-rw`). Verifies JWTs
> locally via `pkg/authmw`.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Public profile view** | `GET /user/v1/public/users/:id` | minimal projection (`id` + `name`, no PII) from real persistence | — | Implemented | — |
| **Own profile read/update** | `GET/PUT /user/v1/private/users/profile` | JWT-subject scoping (ownership-scoped queries); partial update preserves unset fields (COALESCE) | Keycloak JWKS | Implemented | — |
| **JIT profile provisioning** | (behavior of the private profile routes) | claim-fallback read + first-`PUT` upsert creates the row for the token's `sub` — the internal create route (`POST /user/v1/internal/users`) was removed in RFC-0024 P3 | Keycloak JWKS | Implemented (P3) | [user.md](user.md) |

### product — catalog (+ cache)

> Owns products, categories, prices (13 demo rows seeded locally). Stock left for
> inventory-service in RFC-0021 phase 4 — RPCs, read fields and schema all removed; DB `product` on
> `product-db` (CloudNativePG, via PgDog). Valkey cache. Serves gRPC on `:9090`.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Catalog list/read** | `GET /product/v1/public/products`, `GET /product/v1/public/products/:id` | cache-aside (Valkey): SETNX stampede lock (5 s TTL, token compare-and-delete release), TTL jitter 0–10 %, SCAN-based list invalidation; whitelisted sort/filter (injection-safe) | Valkey | Implemented | [caching](./caching.md) |
| **Product-details aggregation** | `GET /product/v1/public/products/:id/details` | server-side aggregation: reviews via gRPC `ReviewService.GetProductReviews` (3 s deadline, soft-fail → `[]`) + **availability from `inventory.v1/BatchGetAvailability`** (soft-fail → `status: unknown`, never a guess) + related | review | Implemented | [API call graph](api.md#current-east-west-call-graph) |
| ~~**Stock reservation**~~ (saga step) | ~~internal gRPC `ProductService.ReserveStock` / `ReleaseStock`~~ | **Removed**, not merely uncalled: the RPCs left the contract in pkg v0.33.0 / product 1.7.0 and the schema went with migration `000006` (1.10.0). The two-week-zero gate on `product_stock_surface_calls_total` was **waived** in favour of code evidence, and the instrument was deleted with the surface — so an empty panel is expected, not a measurement | ~~caller: order-worker~~ | Removed | [inventory](./inventory.md) |
| **Checkout batch read** | internal gRPC `ProductService.BatchGetCurrentPrices` | cache-bypassing **price-only** batch (product = checkout price authority; availability comes from inventory); int64 minor units; unknown ids omitted | caller: checkout | Implemented (RFC-0021 P4) | [ADR-020](../proposals/adr/ADR-020-checkout-revalidation-policy/) |
| **Product create** | `POST /product/v1/internal/products` | admin/seed path | — | Implemented | — |

### checkout — session orchestrator (RFC-0015 P1-P5)

> Owns `checkout_sessions`, item snapshots, totals, promo attachment, and
> confirm idempotency. DB `checkout` on `product-db` (CloudNativePG, via PgDog).
> The service is client-only: the edge calls its HTTP API and it calls cart, product,
> shipping, and order over gRPC. **One binary, two deployments:** `checkout`
> (API) and `checkout-worker` (Temporal worker — `AbandonedCheckoutWorkflow`,
> task queue `checkout`). P1-P5 ship in local-stack and the cluster.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Session lifecycle** | `POST /checkout/v1/private/checkout/sessions`, `GET/DELETE /checkout/v1/private/checkout/sessions/:id`, `PUT /checkout/v1/private/checkout/sessions/:id/address` (process-named `checkout` segment — see checkout.md) | explicit FSM, one active session per user, ownership-scoped queries (anti-IDOR), DB-authoritative TTL | Keycloak JWKS, cart, product | Implemented (P1) | [checkout](checkout.md) |
| **Price re-validation** | session create and confirm | cart owns quantities; product `BatchGetCurrentPrices` owns current price, inventory `CheckAvailability` owns availability (fail-closed); changed lines are explicit | cart, product | Implemented (P1-P2) | ADR-020/021 |
| **Shipping and totals** | `PUT /checkout/v1/private/checkout/sessions/:id/shipping` | shipping `GetQuote`; SQL recomputes subtotal + fee + tax - discount in minor units | shipping | Implemented (P3) | [checkout](checkout.md#totals-p3-implemented--one-composition-rule-owned-by-sql) |
| **Payment selection** | `PUT /checkout/v1/private/checkout/sessions/:id/payment` | opaque `tok_` reference only; PAN-like input rejected before persistence | — | Implemented (P2) | [checkout](checkout.md) |
| **Promo preview and redemption** | `POST/DELETE /checkout/v1/private/checkout/sessions/:id/promo` | preview on apply; serialized, idempotent redemption inside confirm | Postgres | Implemented (P4) | ADR-022 |
| **Confirm and order handoff** | `POST /checkout/v1/private/checkout/sessions/:id/confirm` | required `Idempotency-Key`; confirm-time revalidation; gRPC `order.v1/CreateOrder` | product, order | Implemented (P2) | ADR-018 |
| **Abandonment** | background Temporal workflow | durable wake-up plus DB-authoritative `expires_at`; lazy expiry remains the correctness backstop | Temporal | Implemented (P2) | ADR-019 |
| **Cluster delivery** | — | ResourceSet input, CNPG triplet, gRPC caller NetworkPolicies | platform GitOps | **Implemented (P5)** | RFC-0015 |

### cart — shopping cart

> Owns `cart_items`; DB `cart` on `product-db` (CloudNativePG, via PgDog). Verifies JWTs
> locally via `pkg/authmw`.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Cart CRUD** | `GET/POST/DELETE /cart/v1/private/cart`, `GET /cart/v1/private/cart/count`, `PATCH/DELETE /cart/v1/private/cart/items/:itemId` | fail-closed JWT (`user_id` from token, never body — ownership-scoped queries); UPSERT `ON CONFLICT (user_id, product_id)`; server-side subtotal math (empty cart = 0 shipping) | Keycloak JWKS | Implemented | — |
| **Saga cart-clear** | `DELETE /cart/v1/internal/cart/:userId` | tokenless in-cluster endpoint, NetworkPolicy-fenced; called best-effort by the saga's `ClearCart` step | caller: order-worker | Implemented | [temporal saga](temporal.md) |
| **gRPC read surface** | `cart.v1/GetCart` (`:9090`) | read-only snapshot for checkout (RFC-0015); prices → int64 minor units at this boundary; writes deliberately stay REST (ADR-021) | caller: checkout | Implemented (local-stack + cluster) | [ADR-021](../proposals/adr/ADR-021-cart-grpc-read-surface/) |

### order — orders & checkout fulfillment

> Owns `orders`, `order_items`; DB `order` on `product-db` (CloudNativePG, via PgDog).
> Verifies JWTs locally via `pkg/authmw`. **One binary, two deployments:**
> `order` (API) and `order-worker` (Temporal worker — the `worker` subcommand of
> the same binary). Serves idempotent `order.v1/CreateOrder` on gRPC `:9090` and also acts as a gRPC client.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Order reads** | `GET /order/v1/private/orders`, `GET /order/v1/private/orders/:id` | ownership-scoped queries (`WHERE id AND user_id` — anti-IDOR) | Keycloak JWKS | Implemented | — |
| **Checkout → durable fulfillment** | internal gRPC `order.v1/CreateOrder` (the only create path — the legacy REST create was removed in RFC-0021 P5) | **Temporal saga** `OrderFulfillmentWorkflow` (workflow id `order-fulfillment-<orderID>`): authorize payment → reserve inventory → create shipment → capture → **confirm (pivot)** → notify + receipt → clear cart → commit inventory → complete; compensations run in reverse (void pre-capture / refund post-pivot); exhaustion parks in `manual_review`; server-side order-math validation; atomic order+items insert; saga start via transactional outbox (ADR-031) | Temporal; inventory, shipping, payment, notification (gRPC); cart (REST) | Implemented | [Temporal Saga and 2PC](temporal.md) |
| **Customer cancellation** | `POST /order/v1/private/orders/:id/cancel` (202/200 replay/409) | `CancellationWorkflow` (`order-cancellation-<id>-v<epoch>`): policy gate (shipment not dispatched) → cancel shipment → void/refund remainder by current payment state → release RESERVED stock (COMMITTED = accepted shrinkage) → `cancelled`; exhaustion parks in `manual_review` | Temporal; shipping, payment, inventory (gRPC) | Implemented (RFC-0021 P5) | [ADR-033](../proposals/adr/ADR-033-order-status-cancellation/) |
| **Order-details aggregation** | `GET /order/v1/private/orders/:id/details` | gRPC fan-out with soft-fail enrichment: `GetShipmentByOrder` and `GetPayment` — the `shipment`/`payment` blocks are omitted (`omitempty`) when absent or unavailable | shipping, payment | Implemented | [API call graph](api.md#current-east-west-call-graph) |
| **Saga worker** | — (Temporal task queue `order-fulfillment`) | `worker` subcommand of the same image; registers workflow + activities; fail-fast if Temporal is unreachable | Temporal | Implemented | [temporal saga](temporal.md) |

### review — product reviews

> Owns `reviews` (rating 1–5, comment); DB `review` on `platform-db`
> (CloudNativePG, via `platform-db-pooler-rw`). Verifies JWTs locally via `pkg/authmw`. Serves gRPC on `:9090`.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Review list** | `GET /review/v1/public/reviews?product_id=…` | required `product_id` (missing → 400); paginated | — | Implemented | — |
| **Review create** | `POST /review/v1/private/reviews` | JWT (`user_id` from token — no impersonation); `UNIQUE (product_id, user_id)` + SQLSTATE `23505` → `409` (race-safe duplicate handling) | Keycloak JWKS | Implemented | — |
| **Review feed for product details** | internal gRPC `ReviewService.GetProductReviews` | thin adapter over the same logic layer as the HTTP list | caller: product | Implemented | [API call graph](api.md#current-east-west-call-graph) |

### shipping — tracking, estimates & shipment lifecycle

> Owns `shipments`; DB `shipping` on `platform-db` (CloudNativePG, via `platform-db-pooler-rw`). No JWT
> middleware (public + internal surfaces only). Serves gRPC on `:9090`.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Tracking** | `GET /shipping/v1/public/shipments/track` | lookup by `tracking_number` (legacy `trackingId` fallback); NULL-safe carrier scan | — | Implemented | — |
| **Estimate** | `GET /shipping/v1/public/shipments/estimate` | weight validation rejects `≤0`/`NaN`/`±Inf` → 400 | — | Implemented | — |
| **Shipment lifecycle** (saga steps) | internal gRPC `ShippingService.CreateShipment` / `CancelShipment` | idempotent by `order_id` | caller: order-worker | Implemented | [temporal saga](temporal.md) |
| **Shipment read for order details** | internal gRPC `GetShipmentByOrder` (HTTP twin: `GET /shipping/v1/internal/shipments/orders/:orderId`) | missing shipment → empty response (caller soft-fails to `null`) | caller: order | Implemented (HTTP twin: **No caller**) | [API call graph](api.md#current-east-west-call-graph) |

### notification — user notifications

> Owns `notifications`; DB `notification` on `platform-db` (CloudNativePG, via `platform-db-pooler-rw`).
> Verifies JWTs locally via `pkg/authmw` on private routes. Serves gRPC on
> `:9090`. Deployed in-cluster (comms domain) **and** in the local stack — the
> frontend's notification badge resolves against it.

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Notification inbox** | `GET /notification/v1/private/notifications`, `GET /notification/v1/private/notifications/count`, `GET/PATCH /notification/v1/private/notifications/:id`, `PATCH /notification/v1/private/notifications/read-all` | JWT; owner-scoped reads/mutations (`(id, user_id)` — anti-IDOR); paginated list | Keycloak JWKS | Implemented | — |
| **Order emails** (saga side-effects) | internal gRPC `NotificationService.SendEmail` | called best-effort by the saga (order-created, receipt, refund notice) on a detached context | caller: order-worker | Implemented | [temporal saga](temporal.md) |
| **Internal notify twins + SMS** | `POST /notification/v1/internal/notifications/email`, `POST /notification/v1/internal/notifications/sms`; gRPC `SendSMS` | HTTP twins of the gRPC path; SMS path fully unused | — | **No caller** | [notification.md](notification.md) |

### payment — payments, outbox & reconciliation

> Owns `payments`, refunds, the transactional outbox, and reconciliation runs;
> DB `payment` on `product-db` — connects **direct over TLS, bypassing PgDog**.
> Serves gRPC on `:9090` (reflection off). **Single replica by design**
> (single-writer outbox + per-instance ticker). **mockpay** is a subcommand of
> the same binary, run as a second deployment (provider selected via
> `MOCKPAY_URL`; unset → in-process stub, reconciliation disabled).

| Feature | API | Technique | Depends on | Status | Ref |
|---|---|---|---|---|---|
| **Saga money steps** | internal gRPC `PaymentService.Authorize` / `Capture` / `Void` / `Refund` | recovery-point idempotency (keys `order:<id>`, `refund:order:<id>:<refund_request_id>`; checkpointed provider calls survive crash takeover); a decline is a business response, not a gRPC error; the **caller names each refund** so an order can owe more than one | mockpay; caller: order-worker | Implemented | [RFC-0010](../proposals/rfc/RFC-0010/), ADR-009/010, [ADR-037](../proposals/adr/ADR-037-per-request-refund-identity/) |
| **Payment reads (browser)** | `GET /payment/v1/private/payments`, `GET /payment/v1/private/payments/:id` | JWT; owner-scoped | Keycloak JWKS | Implemented | [payments.md](payments.md) |
| **Payment create (browser)** | `POST /payment/v1/private/payments` | requires `Idempotency-Key`; token-only `payment_method` (`tok_…`, PAN-like digit runs rejected); shared validators across HTTP and gRPC | Keycloak JWKS | Implemented | [payments.md](payments.md) |
| **Payment enrichment for order details** | internal gRPC `GetPayment` (by order id) | read snapshot; caller soft-fails | caller: order | Implemented | [payments.md](payments.md) |
| **Provider webhook** | `POST /payment/v1/public/payments/webhooks/mockpay` | **webhook HMAC**: `Mockpay-Signature: t=…,v1=…` — HMAC-SHA256 over the raw body, constant-time compare, ±5 min replay window, fail-closed on empty secret, 1 MiB body cap | mockpay | Implemented | RFC-0010 |
| **Outbox relay** | — (background loop) | **transactional outbox** — events enqueued in the same tx as the money movement, drained by a 10 s single-writer relay (at-least-once) | Postgres | Implemented | ADR-007 |
| **Reconciliation** | `POST /payment/v1/internal/payments/reconciliation/runs` (optional `from`/`through` backfill), `GET …/runs/:id` + 5-min ticker | detect-only ledger comparison **bounded to a time window** asked of both sides, with a completion-gated high-watermark; single-writer via an advisory lease (409 when held); auto-heal flag-gated (`RECON_HEAL_ENABLED`, lost-capture-response class only); hourly retention reaper (30 d) | mockpay ledger | Implemented | ADR-011/012, [ADR-035](../proposals/adr/ADR-035-windowed-reconciliation/), [ADR-036](../proposals/adr/ADR-036-single-writer-lease/) |
| **Unknown provider outcomes** | — (internal to the money paths) | an UNKNOWN answer parks the intent in `processing` and records the round-trip in `payment_attempts`; it **never triggers the semantic opposite** operation. Resolution re-asks under the ORIGINAL key, on the request path and on a 1-min sweep; callers see `Unavailable`/503 for doubt and `FailedPrecondition` for a decided rejection | mockpay; caller: order-worker | Implemented (RFC-0021 P6) | [ADR-034](../proposals/adr/ADR-034-provider-outcome-ambiguity/) |

### frontend — React SPA

Calls only the gateway at `/{service}/v1/{public,private}/…`; JWT stored in
`localStorage.authToken` and sent as `Authorization: Bearer`. Uses the
server-side aggregation endpoints (`/product/v1/public/products/:id/details`,
`/order/v1/private/orders/:id/details`) — no client-side orchestration. **gRPC
is never browser-facing.**

---

## 4. Technique index (platform-wide)

| Technique | What it solves | Where used | Deep-dive |
|---|---|---|---|
| **RS256 JWT + JWKS** | Stateless identity — no per-request auth hop | Mint: Keycloak realm `duynhlab` (RFC-0024 P3, ADR-041; `user_id` = `sub` string UUID). Verify locally via `pkg/authmw` v0.37.0: user, cart, order, review, notification, payment, checkout | RFC-0009, [API auth model](api.md#authentication) |
| **Rotating refresh tokens** | Long-lived sessions without long-lived access tokens; reuse detection | Keycloak realm (`revokeRefreshToken` + `maxReuse 0`); auth's own implementation is unused since P3 | — |
| **Temporal saga** | All-or-nothing multi-service checkout with compensations | order (+ `order-worker`); participants: inventory, shipping, payment, notification, cart | [Temporal Saga and 2PC](temporal.md) |
| **Temporal abandonment timer** | Durable session expiry without polling the DB | checkout (+ `checkout-worker`); DB-authoritative `expires_at` (ADR-019) | [workflows.md](workflows.md#abandoned-checkout) |
| **Cache-aside (Valkey)** | Read-heavy hot paths | product (SETNX stampede lock, TTL jitter, SCAN invalidation) | [caching](./caching.md) |
| **Transactional outbox** | Reliable side-effects with the DB write (no dual-write gap) | payment (single-writer relay) | ADR-007 |
| **Reconciliation** | Detect provider/ledger drift | payment (ticker + internal trigger API, flag-gated auto-heal) | ADR-011/012 |
| **Webhook HMAC** | Authenticating an unauthenticated public caller | payment ← mockpay | RFC-0010 |
| **gRPC east-west (`:9090`)** | Typed internal transport | Servers: product, inventory, cart, order, review, shipping, notification, payment. Clients: product→review/inventory; order API→inventory/shipping/payment; order-worker→inventory/shipping/notification/payment; checkout→cart/product/inventory/shipping/order | [API call graph](api.md#current-east-west-call-graph) |
| **Idempotency** | Exactly-once effects under retries | HTTP `Idempotency-Key`: checkout confirm, payment create/refund. gRPC order create key required. Saga natural keys: `reservation_id`, shipment `order_id`, payment recovery points; order status commands replay by `(order_id, command_id)` | ADR-010 |
| **Server-side aggregation** | No client-side orchestration | product `/details`, order `/details` (soft-fail enrichment) | — |
| **Ownership-scoped queries** | Anti-IDOR — rows fetched with `(id, user_id)` | checkout, order, notification, payment, cart, user (token-derived `user_id`) | — |
| **Embedded migrations** | Schema self-management per binary (golang-migrate) | all 11 services | [../databases/](../databases/) |

Rule: every value in a service table's **Technique** column appears here, and
every row here is used by at least one service table — that is this doc's
internal consistency check.

---

## 5. Inter-service communication map

The east-west call graph — every gRPC hop, the two documented cart REST
exceptions, transports, and failure modes — is owned by
[api.md § Current East-West Call Graph](api.md#current-east-west-call-graph);
transport details (addresses, dual-port, HTTP/2 load balancing) live in
[api.md § gRPC Runtime Model](api.md#grpc-runtime-model). The durable-workflow
hops behind `order-worker` and `checkout-worker` are indexed in
[workflows.md](workflows.md). Service-to-service target addresses are injected
as env vars — gRPC hops via `*_GRPC_ADDR`, the REST hops via
`CART_SERVICE_URL` — see `local-stack/compose.yaml` and the cluster ResourceSet
templates.

---

## 6. Known gaps & ongoing work

| Item | Service(s) | Status |
|------|------------|--------|
| Committed-stock restock on cancellation (`RESTOCK_SKIPPED`) | order / inventory | **Accepted shrinkage** — inventory.v1 has no `Return` RPC; revisit trigger in [ADR-033](../proposals/adr/ADR-033-order-status-cancellation/) |
| ~~Legacy order→cart REST pricing on direct create~~ | order | **Gone** — it died with the legacy REST create (RFC-0021 P5); checkout/product own price authority |
| gRPC mTLS east-west | platform | **Planned** (RFC-0020); NetworkPolicy remains the fence until then |
| Internal `POST /users` has no in-cluster caller | user | Wired to real persistence; auth registers into its own DB |
| Internal HTTP notify twins + gRPC `SendSMS` unused | notification | No caller (saga emails go via gRPC `SendEmail`) |
| Internal HTTP `GET /shipping/v1/internal/shipments/orders/:orderId` redundant | shipping | No caller — order reads shipment over gRPC |
| Internal routes rely on NetworkPolicy, no in-app caller auth | product, user, cart, shipping, notification | NetworkPolicies authored (see [`../security/`](../security/)); enforced (kindnet on Kind 1.34+; policy CNI in prod) |
| Saga email recipient hardcoded (`noreply@orders.local`) | order, notification | Real customer-email lookup is a noted TODO |

---

*Run the whole platform locally for verification: `cd local-stack && docker compose up -d --build` → SPA at http://localhost:3001, edge gateway at http://localhost:8080 (demo login `alice` / `password123`).*

_Last updated: 2026-08-12 — RFC-0024 P3 identity cutover: Keycloak mints and every authmw consumer verifies realm tokens (string `sub` as `user_id`); user's internal create is replaced by JIT provisioning; auth's tokens are unconsumed pending P5._
