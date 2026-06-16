# Platform Code Review — Open Items

> **Original review:** 2026-05-30 (per-repo source review across the 7 Go services, `pkg`, `frontend`).
> **Updated:** 2026-06-16 — pruned to remaining items only.
>
> **Resolved & removed from this file** (all live on `main`): every **Critical / High / clear-bug**
> finding (the 8 `fix/security-correctness-review` PRs merged 2026-05-30), plus the top deferred
> recommendations — shared fail-closed **`pkg/authmw`** (kills the copy-paste auth-bypass class),
> **`pkg` tests**, the **`pkg/httpx`** pagination + machine-readable error-`code` envelope,
> **`pkg/logger/zapx`**, the internal-route **NetworkPolicies** (`configs/network-policies/*`), and
> the **gateway-host doc reconciliation** (`duynhne.me` → `duynh.me`). Also resolved since the
> review: product review-client `MaxIdleConnsPerHost` throttle and user `allowUnauthenticatedFallback`.
>
> This file now tracks only the **remaining MEDIUM/LOW** items. **Verified** = re-checked against
> current `main` (2026-06-16); **carried** = from the 2026-05-30 review, re-verify before acting.

---

## Cross-cutting / new

| Finding | Where | Sev | Verified |
|---------|-------|-----|----------|
| `ReserveStock`/`ReleaseStock` don't bust the product Valkey cache → stock can read stale until TTL (~10 min); DB is authoritative. (Introduced by the Temporal saga; adjacent to the product cache items.) | product-service cache + order saga | MEDIUM | ✅ open |

## frontend

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| Checkout sends client-supplied `price` (tampering vector) → derive server-side | `CheckoutPage.jsx` | MEDIUM | ✅ still sends `product_price` |
| JWT in `localStorage` (XSS-exfiltratable) — architectural; accepted for demo | `LoginPage.jsx`, `client.js` | HIGH | carried |
| OrdersPage detail fetch has a stale-response race | `OrdersPage.jsx` | MEDIUM | carried |
| CartPage reads `localStorage` non-reactively; dead effect; uneven loading UX | various | LOW | carried |

## auth-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| `User.Password` still serialises (`json:"password,omitempty"`, not `json:"-"`) | `internal/core/domain/user.go` | MEDIUM | ✅ still serializable |
| No logout / session revocation; expired rows accumulate | sessions repo | MEDIUM | carried |
| Session-create failure swallowed → login "succeeds" with a dead token | `internal/logic/v1/service.go` | LOW | carried |

## review-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| `user_id` exposed in public review responses | `internal/core/domain/review.go` | LOW | ✅ still exposed |
| No request / DB timeouts | `cmd/main.go`, repo | MEDIUM | carried |

## product-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| `/details` aggregate not cached; re-fetches reviews every call | `internal/web/v1/handler.go` | MEDIUM | carried |
| CORS allows only localhost; dead `Update`/`Delete`; related-products error discarded | various | LOW | carried |

## shipping-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| Public `track` may leak internal `id`/`order_id` (enumeration) → trim public DTO | `internal/web/v1/handler.go` | MEDIUM | re-verify |
| Undocumented `trackingId` alias; dead `EstimateRequest` struct | various | LOW | carried |

## user-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| `UpsertUserProfile` non-atomic check-then-insert race → `ON CONFLICT` upsert | `…/psql/user_repository.go` | MEDIUM | carried |
| `GetUser` mock ignores DB; fake data + wrong 404 path → implement real query | `…/psql/user_repository.go` | MEDIUM | carried |
| Update response omits username/email, echoes input | `internal/logic/v1/service.go` | MEDIUM | carried |

## cart-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| Shipping/total computed in repo (layering) → move to logic | repo | MEDIUM | carried |
| Concurrent add+update race on a cart row | repo | MEDIUM | accepted at this scale |
| No pool lifetime/idle/health tuning | `internal/core/database.go` | MEDIUM | carried |
| Dead `globalPool`/`GetPool`/`GetDB` | `internal/core/database.go` | LOW | carried |

## order-service

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| No pool tuning; `created_at` set app-side not DB | `internal/core/database.go` | MEDIUM | carried |
| Global singletons + silent no-op wrappers; unused non-tx `Create` | handler/aggregation | LOW | carried |

## pkg

| Finding | Location | Sev | Verified |
|---------|----------|-----|----------|
| Two divergent loggers (`clog` RFC3339 vs `zerolog` Unix) coexist with the `zapx` standard | `logger/` | MEDIUM | ✅ all three present |
| Invalid `LOG_LEVEL` silently falls back to `info` with no warning | logger | MEDIUM | carried |
| `zerolog.TimeFieldFormat` is a process-global side effect; whole-second resolution | logger | MEDIUM | carried |
| Doc comment claims it reads `LOG_LEVEL` env; it takes a param | logger | LOW | carried |

---

## Suggested next order

1. **Checkout `price` server-side derivation** (frontend) — the only remaining clear **tampering** vector.
2. **Product cache-bust on reserve** — close the stock-staleness gap the saga introduced.
3. **Public DTO trimming** (shipping `track`, review `user_id`) + **auth `Password` `json:"-"`** — small, removes data-exposure.
4. The rest (pool tuning, dead code, `ON CONFLICT` upsert, single-logger standard) — opportunistic cleanup.
