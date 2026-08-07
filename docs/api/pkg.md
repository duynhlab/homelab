# Shared Go Library (`pkg`)

One module every Go service pins: `github.com/duynhlab/pkg` carries the
platform's middleware, observability wiring, database helpers, and the
versioned east-west protobuf contracts — one version bump moves libraries and
contracts together.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Repository** | [`duynhlab/pkg`](https://github.com/duynhlab/pkg) | — |
| **Module** | `github.com/duynhlab/pkg` — a **single** Go module; `proto/` stubs are part of it, not a nested module | — |
| **Latest release** | `v0.35.0` (2026-08-06) | — |
| **Consumers** | 11 Go services (the frontend SPA does not use it) | — |
| **Bump mechanics** | Hand-authored PR `Bump pkg to vX.Y.Z` touching only `go.mod` + `go.sum` | — |
| **Design records** | — | [RFC-0014](../proposals/rfc/RFC-0014/) (obsx) · [RFC-0017](../proposals/rfc/RFC-0017/) (dbx, TraceContext) · [RFC-0021](../proposals/rfc/RFC-0021/) (flagx, inventory/product contracts) |

## Overview

`pkg` exists so ten services do not each carry their own copy of JWT
verification, OTel wiring, gRPC hardening, or idempotency semantics. Two rules
shape it:

1. **Contracts live here, generated stubs are committed.** A service imports
   `proto/<svc>/v1` at the module version it pins — no protoc at build time,
   and a contract change is visible as an ordinary version bump.
2. **One version, whole module.** Because protos and libraries share the
   module, "which contract does order speak?" has the same answer as "which
   pkg does order pin?" — see the adoption table below.

Authoritative per-package detail lives in the repo's own
[`README`](https://github.com/duynhlab/pkg#packages) and `AGENTS.md`; this
page is the platform-side summary and the bump ledger.

## Packages

| Package | Purpose |
|---------|---------|
| `authmw` | Fail-closed Gin middleware verifying RS256 JWT bearer tokens locally against a cached JWKS (issuer/audience pinned). JWT-only since RFC-0009 P5. |
| `dbx` | pgx pools pre-wired with OTel (otelpgx tracing + pool-stat metrics), transaction-pooler-safe defaults, password-file credential hot-reload. |
| `flagx` | Startup-validated env flags for migration modes (RFC-0021): enum flags + bounded percent flag; values safe as metric labels. |
| `grpcx` | East-west gRPC server/client helpers: OTel, panic recovery, health, reflection, keepalive, round-robin over headless Services, machine-readable error reasons, access-log interceptor (level follows the status class). |
| `httpx` | Shared HTTP envelope: additive error shape (`error` + stable `code`) and list pagination. |
| `idempotency` | Postgres-backed idempotency store, Stripe-style: claim → first response replays verbatim → mismatch is a conflict; in-flight locks with stale-lock takeover. Caller owns the table. |
| `logger/zapx` · `logger/zerolog` · `logger/clog` | Structured logger adapters with trace-ID injection. |
| `migratex` | Embedded golang-migrate runner (`Run(fsys, dir, dsn)`) — always against the DIRECT DB host, never a transaction pooler (DDL is unsafe through PgBouncer/PgDog). |
| `obsx` | The single OTel SDK wiring point (RFC-0014 P0): traces/metrics/logs over OTLP, one `Shutdown`, zap tee, `TraceContext`, Pyroscope profiling. |
| `temporalx` | Temporal client/worker bootstrap mirroring grpcx/obsx: OTel tracing interceptor, SDK RED metrics, Worker Deployment Versioning options. |
| `proto/<svc>/v1` | Versioned contracts + committed stubs for `cart`, `inventory`, `notification`, `order`, `payment`, `product`, `review`, `shipping`. |

## Consumer matrix

Which subpackages each service imports (as of `v0.35.0`):

| Service | authmw | dbx | flagx | grpcx | httpx | idempotency | migratex | obsx | temporalx | proto |
|---------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|-------|
| auth | — | ✓ | — | — | ✓ | — | ✓ | ✓ | — | — |
| user | ✓ | ✓ | — | — | ✓ | — | ✓ | ✓ | — | — |
| product | — | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | — | inventory, product, review |
| cart | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | — | cart |
| order | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | inventory, notification, order, payment, shipping |
| review | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | — | review |
| shipping | — | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | — | shipping |
| notification | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | — | notification |
| payment | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | payment |
| checkout | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | cart, inventory, order, product, shipping |
| inventory | — | ✓ | — | ✓ | — | — | ✓ | ✓ | — | inventory |

Every service uses a `logger/*` adapter; the column is omitted for width.

## Adoption

| Service | pkg version |
|---------|-------------|
| auth, user, product, cart, order, review, shipping, notification, payment, checkout, inventory | `v0.35.0` (2026-08-07 wave) |

The platform-wide bump wave of 2026-08-07 brought every service to the same
version; before it the fleet ranged from `v0.24.0` to `v0.35.0`.

## Operations

- **Bumping:** branch `chore/bump-pkg-vX.Y.Z`, `go get
  github.com/duynhlab/pkg@vX.Y.Z && go mod tidy`, build + tests, PR titled
  `Bump pkg to vX.Y.Z` (go.mod + go.sum only). Bumps are hand-authored —
  no bot rule covers this module.
- **Releasing pkg:** tag on `main` after merge; consumers pick the tag up on
  their next bump PR. A contract change (proto) and its first consumer land as
  separate PRs — pkg first, tagged, then the consumer bumps.
- **Contract compatibility:** removals are staged like RFC-0021 P4 did —
  callers migrate off first (evidence, not assumption), then the RPC leaves
  the contract in a minor release (`v0.33.0`/`v0.34.0`).

## Release history

Every release since the module began — the bump ledger. Note: `v0.12.1` was
never published (the sequence jumps `v0.12.0` → `v0.12.2`).

| Tag | Date | What it carried |
|-----|------|-----------------|
| `v0.35.0` | 2026-08-06 | `CheckAvailability` reports unknown SKUs (`unknown_sku_ids`) |
| `v0.34.0` | 2026-08-05 | product.v1 becomes a price-only contract |
| `v0.33.0` | 2026-08-05 | product.v1 loses its stock write RPCs |
| `v0.32.0` | 2026-08-01 | `refund_request_id` on payment.v1 `RefundRequest` |
| `v0.31.0` | 2026-07-30 | grpcx access-log level follows the status code's class |
| `v0.30.0` | 2026-07-28 | temporalx Worker Deployment Versioning options |
| `v0.29.0` | 2026-07-23 | product `BatchGetCurrentPrices` price-only RPC |
| `v0.28.0` | 2026-07-23 | inventory.v1 east-west contract |
| `v0.27.0` | 2026-07-23 | grpcx machine-readable error-reason convention |
| `v0.26.0` | 2026-07-23 | `delivery_key` on notification `SendEmailRequest` |
| `v0.25.0` | 2026-07-20 | dbx password-file credential hot-reload |
| `v0.24.0` | 2026-07-16 | DB-scale bucket View for `db.client.operation.duration` |
| `v0.23.0` | 2026-07-15 | dbx pool helper + obsx `TraceContext` (RFC-0017 W0) |
| `v0.22.0` | 2026-07-13 | promo discount carried through `CreateOrder` |
| `v0.21.0` | 2026-07-13 | shipping.v1 `GetQuote` for checkout totals |
| `v0.20.0` | 2026-07-12 | order.v1 `CreateOrder` contract (RFC-0015 P2) |
| `v0.19.0` | 2026-07-12 | cart.v1 `GetCart`, product `GetProducts`, checkout httpx codes (RFC-0015 P1) |
| `v0.18.1` | 2026-07-09 | gRPC interceptor order fixed so panics are logged |
| `v0.18.0` | 2026-07-09 | gRPC access-log interceptor in `NewServer` |
| `v0.17.0` | 2026-07-09 | Prometheus bridge removed; OTel metrics default on |
| `v0.16.1` | 2026-07-09 | obsx setup hardened from canary review findings |
| `v0.16.0` | 2026-07-08 | obsx `SetupObservability` — the OTel SDK wiring seam |
| `v0.15.1` | 2026-07-05 | `refunded_minor` on the payment snapshot |
| `v0.15.0` | 2026-07-05 | payment.v1 `GetPayment` read RPC |
| `v0.14.0` | 2026-07-04 | payment.v1 contract + shared idempotency package |
| `v0.13.0` | 2026-07-03 | httpx payment error codes (RFC-0010) |
| `v0.12.2` | 2026-07-02 | version-note docs follow-up |
| `v0.12.0` | 2026-07-02 | authmw goes JWT-only |
| `v0.11.1` | 2026-07-01 | unknown-kid/bad-alg JWTs classified 401, not 503 |
| `v0.11.0` | 2026-07-01 | authmw local RS256 JWT verification |
| `v0.10.0` | 2026-06-26 | Temporal SDK workflow/activity metrics in temporalx |
| `v0.9.0` | 2026-06-25 | `SetupProfiling` hardened; README refactor |
| `v0.8.0` | 2026-06-25 | obsx `SetupProfiling` — shared Pyroscope profiling |
| `v0.7.0` | 2026-06-15 | temporalx + product/shipping saga gRPC contracts |
| `v0.6.0` | 2026-06-14 | grpcx hardening |
| `v0.5.0` | 2026-06-13 | httpx + zapx |
| `v0.4.0` | 2026-06-09 | migratex — embedded golang-migrate runner |
| `v0.3.0` | 2026-06-02 | obsx — gRPC OTel metrics bridged to Prometheus (bridge later removed in `v0.17.0`) |
| `v0.2.0` | 2026-05-31 | module renamed to `github.com/duynhlab/pkg` |
| `v0.1.3` | 2026-05-31 | shared fail-closed authmw gRPC middleware |
| `v0.1.2` | 2026-05-31 | auth/review/notification protos + gRPC auth/deadline helpers |
| `v0.1.1` | 2026-03-16 | Go 1.25.8 vulnerability fixes |
| `v0.1.0` | 2026-02-05 | initial library (logger) |

## References

- [`duynhlab/pkg`](https://github.com/duynhlab/pkg) — README (packages) + `AGENTS.md`
- [api.md § gRPC Runtime Model](./api.md#grpc-runtime-model) — how services use grpcx at runtime
- [observability.md](./observability.md) — the obsx contract every service follows
- Per-service contracts: [Service contracts](./README.md#service-contracts)

_Last updated: 2026-08-07 — created with the v0.35.0 fleet-wide bump wave._
