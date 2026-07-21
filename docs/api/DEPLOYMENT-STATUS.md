# Deployment Status

One platform rollup answering "what runs where" — local-stack vs cluster vs planned. This file is the **canonical owner** of platform-wide deployment truth; per-service detail lives in each service doc's **At a glance** table.

| Badge | Meaning |
|-------|---------|
| **Implemented** | Runs in local-stack + cluster; e2e or manifest evidence |
| **Partial** | Partly shipped (e.g. HTTP live, no gRPC caller) |
| **Technical debt** | Shipped but planned removal |
| **No caller** | Route/RPC wired, no live consumer — keep documented |
| **Planned** | Designed, not deployed |

## Platform rollup

| Component | Local | Cluster | Notes |
|-----------|:-----:|:-------:|-------|
| auth API | ✓ | ✓ | HTTP-only, public edge only ([auth.md](./auth.md)) |
| user API | ✓ | ✓ | public + private edge ([user.md](./user.md)) |
| product API + gRPC | ✓ | ✓ | saga participant ([product.md](./product.md)) |
| cart API + gRPC | ✓ | ✓ | saga participant via REST ClearCart ([cart.md](./cart.md)) |
| order API + gRPC | ✓ | ✓ | saga orchestrator ([order.md](./order.md)) |
| order-worker | ✓ | ✓ | queue `order-fulfillment` — [kubernetes/apps/order-worker.yaml](../../kubernetes/apps/order-worker.yaml) |
| review API + gRPC | ✓ | ✓ | ([review.md](./review.md)) |
| shipping API + gRPC | ✓ | ✓ | saga participant ([shipping.md](./shipping.md)) |
| notification API + gRPC | ✓ | ✓ | saga participant; SMS **No caller** ([notification.md](./notification.md)) |
| payment API + gRPC | ✓ | ✓ | saga participant ([payments.md](./payments.md)) |
| mockpay provider | ✓ | ✓ | webhook HMAC → payment public webhook route |
| checkout API | ✓ | ✓ | **P5 shipped** — [kubernetes/apps/services/checkout.yaml](../../kubernetes/apps/services/checkout.yaml) |
| checkout-worker | ✓ | ✓ | queue `checkout` — [kubernetes/apps/checkout-worker.yaml](../../kubernetes/apps/checkout-worker.yaml) |
| frontend SPA | ✓ | ✓ | local `:3001`; single Kong entrypoint `:8080` |
| Legacy `POST /order/v1/private/orders` | ✓ | ✓ | **Technical debt — P6 removal** (RFC-0015) |
| Legacy order→cart REST pricing | ✓ | ✓ | **Technical debt — P6 removal** (RFC-0015) |
| gRPC mTLS east-west | — | — | **Planned** (RFC-0020 research) |

## Edge exposure (verified)

- No `/internal/` audience is exposed at either edge — verified in [kong.yml](../../local-stack/gateway/kong.yml) and [ingress-api.yaml](../../kubernetes/infra/configs/kong/ingress-api.yaml). NetworkPolicy is the fence.
- Known local divergence: local-stack Kong routes product and order on bare prefixes (`/product/`, `/order/`) while the cluster ingress splits `/product/v1/public/` and `/order/v1/private/`. Service paths are identical (Variant A pass-through, `strip_path: false` everywhere).

## References

- [workflows.md](./workflows.md) — Temporal workflow registry
- [microservices.md](./microservices.md) — feature → API → technique matrix
- [api.md](./api.md) — shared HTTP/gRPC rules

_Last updated: 2026-07-21_
