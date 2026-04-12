# API naming & gateway URL convention

| Attribute | Value |
|-----------|--------|
| **Version** | **v1.0.0** (draft) |
| **Status** | Draft — design exploration, not production policy |
| **Canonical API** | [`api.md`](api.md) — live **`/api/v1/*`** surface; **this document does not replace** that reference |
| **Scope** | Gateway-facing URL naming (edge), Chợ Tốt–style segments + Google API Design Guide notes |
| **Primary domain** | **`duynhne.me`** — production domain for the hosts below (not a placeholder) |
| **Last updated** | 2026-04-09 |

## Purpose

Capture a **gateway-facing** URL model inspired by a **multi-segment** edge layout (service → audience → resource path), refined with ideas from the [Google API Design Guide](https://cloud.google.com/apis/design). Use it when designing **north-south routing**, **Kong/Envoy routes**, or **public docs** for a future gateway—not when implementing handlers inside services that still expose `/api/v1/...` behind the mesh.

## Relationship to [`api.md`](api.md)

| Concern | [`api.md`](api.md) (current) | This document (draft) |
|--------|------------------------------|-------------------------|
| Path shape | `/api/v1/{resource}` per service | `https://{gateway}/{service}/v1/{audience}/...` (edge convention) |
| Version | `v1` in path | Major version explicit; position fixed by ADR (see below) |
| Audience | Tables (frontend vs internal) | Segment `public` / `private` / `protected` / `internal` |

**Bridge pattern:** gateway can **strip/rewrite** edge URLs to cluster paths such as `/api/v1/...` so service code stays aligned with [`api.md`](api.md) until a deliberate migration.

## Hostnames on `duynhne.me`

**Root domain:** `duynhne.me` is the platform’s primary domain. The subdomains below are **intended hostnames** (same DNS zone / TLS), not fake examples.

| Role | Host |
|------|------|
| Public API gateway (north-south) | `gateway.duynhne.me` |
| Optional private hostname for internal L7 (VPC/private LB only; **not** public internet) | `internal.gateway.duynhne.me` |
| Static assets + CDN | `static.duynhne.me` |

**Illustrative only** in this document: the **`{service}`** segment (e.g. `catalog`, `auth`, `payment`), **resource paths**, and **IDs** (`prod_01HZZZZ`, `ord_9Zbc82`, …)—they show the convention; wire them to real services when you deploy the gateway and publish OpenAPI.

## Audience segments (`type`)

Segment **must** be one of:

| Value | Meaning | Typical edge policy |
|-------|---------|---------------------|
| `public` | No end-user JWT required | Rate limit, WAF, optional cache for safe GETs |
| `private` | Authenticated user (e.g. JWT) | JWT validation, user context |
| `protected` | Special verification (signed webhooks, partner keys, HMAC, IP allowlists) | Dedicated plugins + audit |
| `internal` | **GKE-only** service-to-service: one workload calling another inside the cluster (Pod → Service) | **Not** for browsers or public clients. Use **Kubernetes Service DNS** (`*.svc.cluster.local`) and **NetworkPolicy** by default; optional **private** gateway/mesh + mTLS. Never expose `internal` routes on a public load balancer. |

**`internal` in practice:** Callers and callees are **workloads in GKE** (or peered internal endpoints you treat as cluster-adjacent). Typical path: `http://{service}.{namespace}.svc.cluster.local:{port}/...` per your service chart, aligned with [`api.md`](api.md) where applicable. The `.../v1/internal/...` URL shape and `internal.gateway.duynhne.me` apply when you deliberately route that same convention through an **internal-only** hostname (private Google Cloud load balancer / internal Gateway) — still **only** reachable from inside the VPC / GKE, not from the internet.

## Version placement (pick one in ADR)

- **Variant A — version after service (Chợ Tốt–friendly):**  
  `https://gateway.duynhne.me/{service}/v1/{audience}/{resource...}`
- **Variant B — version after host (common in many Google HTTP APIs):**  
  `https://gateway.duynhne.me/v1/{service}/{audience}/{resource...}`

The following samples use **Variant A**.

## Sample URLs (host: `gateway.duynhne.me`; paths illustrative)

### `public`

```http
GET https://gateway.duynhne.me/catalog/v1/public/products
GET https://gateway.duynhne.me/catalog/v1/public/products/prod_01HZZZZ
GET https://gateway.duynhne.me/search/v1/public/query?q=headphones&page_size=20
GET https://gateway.duynhne.me/geo/v1/public/regions/VN/districts
```

### `private`

```http
GET  https://gateway.duynhne.me/auth/v1/private/users/me
GET  https://gateway.duynhne.me/order/v1/private/orders
GET  https://gateway.duynhne.me/order/v1/private/orders/ord_9Zbc82/details
POST https://gateway.duynhne.me/cart/v1/private/carts/me/items
```

### `protected`

```http
POST https://gateway.duynhne.me/payment/v1/protected/webhooks/stripe
POST https://gateway.duynhne.me/partners/v1/protected/ingest/events
```

### `internal` (GKE workloads only)

**In-cluster (typical):** Pod → Service DNS — no public hostname. Paths follow [`api.md`](api.md) or your service contract (example namespaces match common `{service}.{namespace}` pattern).

```http
POST http://notification.notification.svc.cluster.local:8080/api/v1/notify/email
GET  http://product.product.svc.cluster.local:8080/api/v1/products
```

**DNS internals (GCP / GKE):** how `*.svc.cluster.local` works, optional **Cloud DNS private zones** (`*.gke.internal`, per-env names), `gcloud`/Terraform — see **[GKE internal & private DNS](gke-internal-dns.md)**.

**Private gateway hostname (optional):** same semantics — callers are still **only** GKE/VPC-internal; TLS or L7 routing on a **private** LB.

```http
POST https://internal.gateway.duynhne.me/search/v1/internal/reindex/jobs
POST https://internal.gateway.duynhne.me/notify/v1/internal/dispatch/email
```

### Same resource, different policy (illustrative)

```text
GET https://gateway.duynhne.me/catalog/v1/public/products/123
GET https://gateway.duynhne.me/catalog/v1/private/products/123
```

Prefer **one resource tail** after `audience`; document both in OpenAPI with shared path template if needed.

## Google-aligned practices (summary)

Apply to the **resource path after `audience`** and to **response bodies**:

- Plural nouns for collections; stable resource IDs.
- Standard HTTP methods where possible; custom actions as documented sub-paths or POST bodies per team standard.
- Consistent **error** envelope (e.g. `code`, `message`, optional `details`).
- List endpoints: **pagination** (`page_size`, `page_token` or equivalent).
- One **JSON field naming** style (e.g. `camelCase` vs `snake_case`) across public APIs.

## Static assets (reference)

Pattern aligned with object storage + CDN:

```text
https://static.duynhne.me/storage/app/v5/5.21.1/assets/header.css
```

Use immutable file names (content hash) and explicit `Cache-Control` for chunks.

## Next steps

1. Record **Variant A vs B** and hostname map in an ADR.
2. For each `{service}`, publish **OpenAPI** with tags per `audience`.
3. Keep [`api.md`](api.md) as the **source of truth** for implemented routes until gateway rollout is decided.
