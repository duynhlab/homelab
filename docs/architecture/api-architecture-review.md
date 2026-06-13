# API & 3-Layer Architecture Review

> **Axis:** Architecture (with API/interface design).
> **Date:** 2026-06-13.
> **Method:** Applied the `api-and-interface-design` and `code-review-and-quality`
> (architecture axis) skills against (a) the design docs in `docs/api`, `docs/caching`,
> `docs/databases`, `docs/observability`, and (b) the **actual Go source** of two
> representative services (`product-service`, `order-service`) plus the shared `pkg`
> library.
> **Outcome:** Review only — **no code was changed**. Findings are severity-labelled
> with a recommended direction each.

> **Resolution status (2026-06-13, follow-up implementation):**
> - ✅ **#2 Pagination** — standard `{items,page,page_size,total_items,total_pages}` envelope (`pkg/httpx`) on products/reviews/orders/notifications.
> - ✅ **#3 Error code** — additive `{"error","code"}` via `httpx.RespondError` across all 8 services.
> - ✅ **#9 Logger** — shared `pkg/logger/zapx` adopted by the 6 zap services.
> - ✅ **#8 Caching doc** — `caching.md` layer wording corrected.
> - ✅ **3-layer fix** — notification-service repo moved to `internal/core/repository` with an injected pool.
> - ✅ **#7** — already documented (`grpc-internal-comms.md` hop table); opening claim made precise.
> - ⏸️ **#1 Shared-DB HA** and **#4 gRPC mTLS** — deferred to separate infra work (out of this code round).
> - ↔️ **#5 / #6** — cache-invalidation ownership & soft-fail convention: documentation follow-ups, not yet written.

---

## 1. Scope & method

- **In scope:** the public/internal HTTP contract (Variant A URL shape, audiences,
  error envelope, versioning, pagination), the gRPC east-west contracts, and how the
  `web → logic → core` layering absorbs cross-cutting concerns (caching, databases,
  observability).
- **Verified against code, not just docs:** `product-service` (cache-aside +
  product→review gRPC) and `order-service` (order→shipping/notification/cart
  orchestration). The other six services were assumed to follow the same template based
  on the shared `pkg` boundary and the documented model.
- **Out of scope:** correctness, security, and performance axes are only touched where
  they intersect architecture (e.g. gRPC mTLS is raised as a trust-boundary coupling
  concern, not a full security audit). No CHANGELOG entry — this is a review artifact,
  not a platform change.

Severity legend (from `code-review-and-quality`):
`Critical` blocks merge · *Required* must address · **Consider** worth doing · *Nit* optional · **FYI** context only.

---

## 2. Verdict

**The code-level architecture is strong and does not need restructuring.** The 3-layer
model is implemented faithfully and consistently across the two services inspected. The
findings below are almost entirely at the **design/infra/contract** level — the shape of
the platform around the services — not the structure of the Go code itself.

### What's working well (don't change these)

- **Dependency direction holds.** Imports flow `web/v1 → logic/v1 → core` only; no
  `web → core` shortcuts, no `core → logic` back-edges, no cycles. Verified in both
  services.
- **Dependency inversion is real.** Repository interfaces live in `internal/core/domain`
  (e.g. `ProductRepository`, `OrderRepository`) and are implemented in
  `internal/core/repository` (`PostgresProductRepository`), with compile-time conformance
  checks: `var _ domain.ProductRepository = (*PostgresProductRepository)(nil)`.
- **Transport stays in the web layer.** gRPC/HTTP clients live in `web/v1`
  (`review_client.go`, `shipping_grpc_client.go`, `cart_client.go`); the logic layer
  depends on small local interfaces (`ReviewFetcher`, `shipmentFetcher`), so business
  logic never imports a transport type. Proto types are adapted to domain types at the
  edge — no proto/DB types leak into logic or HTTP responses.
- **Contracts are centralized.** Protos and generated stubs live once in
  `pkg/proto/{svc}/v1`; no service hand-copies another's contract. `buf breaking` guards
  compatibility in CI.
- **Clean cross-cutting separation.** Observability is middleware/decorator-driven
  (`tracing → logging → metrics`), with `layer=web|logic` span attributes and a *single*
  RED histogram (`request_duration_seconds`) — no redundant counters. Caching is injected,
  not hard-wired, and is nil-safe (degrades gracefully). `order-service` carries
  idempotency keys end-to-end.
- **The edge contract is coherent.** Variant A (`/{service}/v1/{audience}/{resource}`) is
  applied uniformly; audiences (`public|private|internal|protected`) are enforced by Kong
  Ingress (north-south) + NetworkPolicy (east-west); the error envelope shape is uniform.

---

## 3. Findings

| # | Severity | Finding | Axis |
|---|----------|---------|------|
| 1 | *Required* (High) | `supporting-shared-db` couples 4 services on one non-HA Postgres | Architecture |
| 2 | *Required* | List endpoints have no pagination contract | Interface |
| 3 | *Required* | Error envelope has no machine-readable `code` | Interface |
| 4 | **Consider** (Med) | gRPC east-west has no mTLS; NetworkPolicy is the only fence | Architecture |
| 5 | **Consider** (Med) | No cross-service cache-invalidation ownership rule | Architecture |
| 6 | **Consider** | Soft-fail vs hard-fail convention is implicit | Architecture |
| 7 | **FYI** | `order → cart` is REST while docs claim "gRPC-only east-west" | Architecture |
| 8 | *Nit* | `caching.md` layer ownership wording contradicts the code | Docs |
| 9 | *Nit* | Logging stack is fragmented (3 loggers, 2 formats) | Architecture |

---

### Finding 1 — Shared database couples four services *(Required, High)*

**Evidence:** `docs/databases/002-database-integration.md`. `supporting-shared-db` is a
**single, non-HA** PostgreSQL instance hosting the `user`, `notification`, `shipping`, and
`review` databases. By contrast `cnpg-db` (product/cart/order) also co-locates databases
on one cluster but runs **3-node HA + PgDog**.

**Why it matters (architecture):** this is the database-per-service principle bent the
furthest it goes. Even with separate logical databases, one instance means:

- **Single point of failure** — one node loss takes down 4 services at once, and there is
  no failover for this tier.
- **Resource contention / blast radius** — a runaway query or autovacuum storm in
  `notification` starves `user`, `shipping`, `review`.
- **Migration coupling** — `golang-migrate` runs embedded per service, but a long
  `ALTER`/lock from one service's migration can block the others on the same instance.
  No coordination mechanism is documented.

**Recommendation:** This is a defensible cost trade-off for a learning/homelab cluster —
but make it an *explicit, documented* trade-off rather than an implicit one:
1. Near-term: give `supporting-shared-db` the same HA treatment as `cnpg-db` (≥3 nodes),
   and document the shared-tier SLO + per-service schema ownership.
2. Note the migration-lock risk in the DB docs and keep migrations small/online.
3. Long-term (if these services ever matter for real availability): split to dedicated
   databases. For now, documenting the risk is enough.

---

### Finding 2 — No pagination contract on list endpoints *(Required)*

**Evidence:** `docs/api/api-naming-convention.md` suggests "pagination (`page_size`,
`page_token` or offset/limit — be consistent per service)", but `docs/api/api.md` list
endpoints (`GET /product/v1/public/products`, `GET /review/v1/public/reviews`) return
**bare arrays** with no `page`/`limit`/`total` envelope.

**Why it matters (`api-and-interface-design` red flag):** "List endpoints without
pagination — you will need it the moment someone has 100+ items." Retrofitting pagination
later is a **breaking change** to the response shape (array → wrapped object), which under
Hyrum's Law will break every consumer that iterates the top-level array.

**Recommendation:** Decide the shape *now*, while there is one consumer (the SPA). Pick one
(cursor `page_token` scales better than offset for growing tables) and wrap list responses
from day one:
```json
{ "items": [ ... ], "page": 1, "page_size": 20, "total_items": 142 }
```
Then document it in `api.md` with one example. The product list is already cached with a
key that *includes* `:page:limit` (`product:list:…:{page}:{limit}`), so the cache layer
already assumes pagination exists — the HTTP contract just hasn't caught up.

---

### Finding 3 — Error envelope lacks a machine-readable code *(Required)*

**Evidence:** every error is `{"error": "<human message>"}` (e.g. `{"error": "Review
already exists"}` → 409, `{"error": "Product not found"}` → 404), per `docs/api/api.md`.

**Why it matters:** the only machine-usable signal is the HTTP status, which is too coarse
(several distinct 400s share one status). Clients that need to branch on a *specific* error
will end up **string-matching the message text** — and per Hyrum's Law, once they do, the
message becomes a frozen contract you can no longer reword or localize.

**Recommendation:** Adopt the skill's standard envelope before more consumers appear:
```json
{ "error": { "code": "REVIEW_ALREADY_EXISTS", "message": "Review already exists", "details": {} } }
```
`code` is the stable contract (UPPER_SNAKE, safe to match on); `message` stays free to
change. If a full reshape is too invasive right now, the cheaper first step is adding a
stable `code` field alongside the existing `error` string and migrating the SPA to it.

---

### Finding 4 — gRPC east-west has no mTLS *(Consider, Medium)*

**Evidence:** `docs/api/grpc-internal-comms.md` — services dial each other on `:9090` with
`insecure` credentials; mTLS is explicitly deferred. The fence is NetworkPolicy, which
`docs/api/microservices.md` notes is "enforced only with an enforcing CNI".

**Why it matters (architecture/trust boundary):** identity between services is currently
*positional* (you are trusted because you reached the port), not *authenticated*. If the
CNI doesn't enforce NetworkPolicy, there is effectively no east-west trust boundary. JWTs
are forwarded in gRPC metadata for user-scoped calls, but the *channel* itself is
unauthenticated.

**Recommendation:** The building blocks already exist — `pkg/grpcx` centralizes dialing,
and cert-manager already distributes a `homelab-ca-bundle` via trust-manager. Wiring
`grpcx` TLS creds to that CA closes the gap in one shared place without touching service
business code. Reasonable to keep deferred for a learning cluster, but track it as the top
security-adjacent architecture debt.

---

### Finding 5 — No cross-service cache-invalidation rule *(Consider, Medium)*

**Evidence:** `docs/caching/caching.md` + code — `product-service` owns the Valkey cache;
invalidation (`InvalidateProductList`, `DeleteByPattern("product:list:*")`) is internal to
that service. Nothing defines what happens if *another* service ever mutates product data.

**Why it matters:** today only `product` touches Valkey, so live risk is low — but the
*design* has no stated ownership boundary. The implicit rule ("the owning service is the
only writer, and staleness is bounded by TTL") is correct and worth making explicit before
a second writer appears and silently serves stale reads.

**Recommendation:** Document the invariant in `caching.md`: **one service owns each cache
namespace; cross-service reads accept TTL-bounded staleness; no out-of-band writers.**
That single sentence prevents a whole class of future bugs.

---

### Finding 6 — Soft-fail vs hard-fail is implicit *(Consider)*

**Evidence:** product→review soft-fails to `[]`; order→shipping soft-fails to `null`
shipment; order→notification is best-effort fire-and-forget (detached context, no retry).
All sensible — but the *rule* is nowhere stated.

**Recommendation:** Add a short "Aggregation failure modes" section to `api.md`: optional
enrichment (reviews, shipment) **soft-fails** and returns partial data; user-visible side
effects (notifications) are **best-effort**; anything on the critical path **hard-fails**.
Making the rule explicit keeps the 8 services consistent as they grow.

---

### Finding 7 — `order → cart` is REST while docs claim gRPC-only *(FYI)*

**Evidence:** `AGENTS.md` and `grpc-internal-comms.md` state east-west is "gRPC-only, no
REST fallback" and the migration is "complete" — but `order-service/internal/web/v1/cart_client.go`
calls cart over HTTP/JSON.

**Why it matters:** mixed transport is *fine* architecturally; the problem is the docs
claim a completeness that isn't true. A reader trusting the docs would be surprised.

**Recommendation:** Either migrate the cart hop to gRPC, or (simpler) document it as the one
known exception in `grpc-internal-comms.md` so the "complete / no fallback" claim is
accurate.

---

### Finding 8 — `caching.md` layer wording contradicts the code *(Nit)*

**Evidence:** `docs/caching/caching.md` says caching is "implemented in the **Core Layer**"
in one place and "**Logic Layer** implements Cache-Aside" in another. The **code** is
unambiguous and correct: the cache *abstraction* (`CacheClient`, `ProductCache`,
`ValkeyCacheClient`) lives in `internal/core/cache`, and the cache-aside *orchestration*
(check → miss → load → set, with SETNX stampede lock) lives in `internal/logic/v1`.

**Recommendation:** Tighten the doc to match: "abstraction in core, cache-aside decision in
logic." The code needs no change.

---

### Finding 9 — Fragmented logging stack *(Nit)*

**Evidence:** `docs/api/logs.md` — `cart`/`auth` use clog+zerolog; the other six use Zap;
time format (ISO8601 vs Unix) and the message field name (`msg` vs `message`) differ.

**Why it matters:** not an API contract issue, but it works against the otherwise-excellent
single-trace-id correlation story — cross-service log queries and dashboards must handle two
schemas.

**Recommendation:** Standardize on one logger and one field schema (ISO8601 + `message`).
A shared `pkg/logger` adapter already exists; routing all services through it would
converge the format without per-service rewrites.

---

## 4. API / interface contract scorecard

Running the `api-and-interface-design` verification checklist against the documented + coded contract:

| Check | Status | Note |
|-------|--------|------|
| Typed input and output per endpoint | ✅ | Gin binding + domain structs; proto for gRPC |
| Single consistent error format | ⚠️ | One shape, but no machine-readable `code` (Finding 3) |
| Validation at boundaries only | ✅ | Web layer validates; logic trusts types |
| List endpoints paginated | ❌ | Not implemented (Finding 2) |
| New fields additive / backward-compatible | ✅ | Documented v1→v2-alongside strategy; additive stays on v1 |
| Consistent naming | ✅ | `snake_case` fields, plural resources, explicit `/v1/` |
| Contracts committed with code | ✅ | `pkg/proto/*` + `buf` in CI |
| Resource-oriented URLs (no verbs) | ✅ | Variant A; custom actions as POST sub-paths |

**Net:** strong contract with two real gaps — pagination and a machine-readable error code.

---

## 5. Priority order (if you act on any of this)

1. **Pagination + error `code`** (Findings 2, 3) — cheapest to fix *now*, most expensive to
   retrofit later (both are breaking changes once consumers depend on the current shape).
2. **Document the shared-DB trade-off + HA it** (Finding 1) — highest operational risk.
3. **gRPC mTLS** (Finding 4) — the real security-adjacent debt; infra already in place.
4. Everything else is documentation hygiene (Findings 5–9) — low effort, do opportunistically.

---

## 6. Verification of this review

- Every claim cites a real doc or source file; the layering/dependency claims were taken
  from the actual `product-service` / `order-service` imports, not inferred from docs.
- No code, manifests, or service repos were modified — this review adds only this file.
- Severity labels follow `code-review-and-quality`; the §4 scorecard follows the
  `api-and-interface-design` verification checklist.
