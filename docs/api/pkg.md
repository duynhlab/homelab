# Shared Go Library (`pkg`)

Fourteen independently tagged Go modules carrying the platform's middleware,
observability wiring, database helpers, and the versioned east-west protobuf
contracts. A service pins only the modules it imports, and each moves on its own
release line.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Repository** | [`duynhlab/pkg`](https://github.com/duynhlab/pkg) | — |
| **Modules** | **14**, one per package — `github.com/duynhlab/pkg/<module>`. There is **no root `go.mod`**, and one must never be re-created | — |
| **Newest tags** | `v0.37.1` for `obsx` (span helpers) · `v0.37.0` for `temporalx` (Temporal's own versioning env names — **breaking**) · `v0.37.0` for `authmw idempotency proto` (RFC-0024 P3 identity cutover) · `v0.36.1` for `dbx grpcx httpx migratex` · `v0.36.0` for `flagx logger/zapx logger/zerolog logger/clog` · `v0.1.0` for `httpmw`, which starts its own line | — |
| **Single-module line** | Frozen at `v0.35.0` (2026-08-06). **No plain `v0.36.x` tag exists** | — |
| **Consumers** | 11 Go services (the frontend SPA does not use it) | — |
| **Bump mechanics** | Per module: `go get github.com/duynhlab/pkg/<module>@vX.Y.Z` | — |
| **Design records** | — | [RFC-0014](../proposals/rfc/RFC-0014/) (obsx) · [RFC-0017](../proposals/rfc/RFC-0017/) (dbx, TraceContext) · [RFC-0021](../proposals/rfc/RFC-0021/) (flagx, inventory/product contracts) · [ADR-038](../proposals/adr/ADR-038-shared-http-middleware/) (layering, `httpmw`) |

## Overview

`pkg` exists so eleven services do not each carry their own copy of JWT
verification, OTel wiring, gRPC hardening, or idempotency semantics. Two rules
shape it:

1. **Contracts live here, generated stubs are committed.** A service imports
   `proto/<svc>/v1` at the version it pins — no protoc at build time, and a
   contract change is visible as an ordinary version bump.
2. **One module per package, one tag per module.** A service pins only what it
   imports, so a change to `temporalx` cannot force a release on the six services
   that never touch Temporal.

### Why the split, concretely

The security round released as `v0.36.1` bumped gRPC and `golang.org/x`. Under
the old single module, that would have moved every consumer of every package.
Per module, it touched **nine**: `flagx`, `logger/zapx` and `logger/clog` carry
no such dependency, so they legitimately stayed at `v0.36.0`. Different newest
tags across modules is the normal state, not drift.

### Layering

Modules sit in strict layers, and **a module may only import a lower layer**.
Same-layer imports are forbidden even when they would not create a cycle, because
they create hidden tag-ordering constraints.

```mermaid
flowchart TD
  L2["<b>Layer 2 — terminal</b><br/>obsx · dbx · migratex · temporalx<br/><i>no module may import these</i>"]
  L1["<b>Layer 1 — building blocks</b><br/>httpx · grpcx · httpmw · authmw · idempotency"]
  L0["<b>Layer 0 — foundation</b><br/>proto · logger/zapx · logger/zerolog · logger/clog · flagx<br/><i>zero internal dependencies</i>"]
  L2 -->|may import| L1
  L1 -->|may import| L0
  L2 -->|may import| L0

  classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
  classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
  classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
  class L2 platform;
  class L1 service;
  class L0 data;
```

Enforcement is `depguard` in the repo's `.golangci.yml`, which also confines the
OTel **SDK** to `obsx`. Today no module imports another at all — the layers state
what is *allowed*, so the constraint is cheap to keep and expensive to recover
once broken.

The rule that bites: **`obsx` is Layer 2, so no shared module can call it.** A
shared HTTP middleware that wants trace context must build the field from the
OpenTelemetry **API**, which Layer 1 may import. [ADR-038](../proposals/adr/ADR-038-shared-http-middleware/)
works that through, and both Layer 1 middleware now live the consequence:
`grpcx` inlined its trace-id helper, and `httpmw` carries its own five-line copy
of the trace-context field rather than opening the first cross-module edge —
the 2026-08-07 telemetry audit measured the failure class this prevents:
per-repo middleware copies got trace binding wrong in 9 of 10 HTTP services
(details preserved in [ADR-038](../proposals/adr/ADR-038-shared-http-middleware/) § References).

Authoritative per-package detail lives in the repo's own
[`README`](https://github.com/duynhlab/pkg#packages) and `AGENTS.md`; this page is
the platform-side summary and the release ledger.

## Packages

| Module | Layer | Purpose |
|---------|:---:|---------|
| `authmw` | 1 | Fail-closed Gin middleware verifying RS256 JWT bearer tokens locally against a cached JWKS (issuer/audience pinned). JWT-only since RFC-0009 P5. **v0.37.0 (RFC-0024 P3):** verifies the Keycloak realm via an explicit `Config` — `OIDC_ISSUER` (default `https://id.duynh.me/realms/duynhlab`), `OIDC_AUDIENCE` (default `duynhlab-platform`), optional `OIDC_JWKS_URL` (empty derives `<issuer>/protocol/openid-connect/certs`); normalizes `realm_access.roles`; `user_id` is the `sub` string. The pre-P3 `AUTH_JWKS_URL`/`JWT_ISSUER`/`JWT_AUDIENCE` env names are gone. |
| `dbx` | 2 | pgx pools pre-wired with OTel (otelpgx tracing + pool-stat metrics), transaction-pooler-safe defaults, password-file credential hot-reload. |
| `flagx` | 0 | Startup-validated env flags for migration modes (RFC-0021): enum flags + bounded percent flag; values safe as metric labels. |
| `grpcx` | 1 | East-west gRPC server/client helpers: OTel, panic recovery, health, reflection, keepalive, round-robin over headless Services, machine-readable error reasons, access-log interceptor (level follows the status class). |
| `httpmw` | 1 | The shared Gin middleware pair every HTTP service mounts, in order: `Tracing(serviceName, extraSkipRoutes...)` (otelgin server span + `http.server.*` metrics) then `Logging(logger, extraSkipRoutes...)` (access log), plus `LoggerFrom`, `TraceID`, `LoggerWithTraceID`. One `DefaultSkipRoutes` map feeds both, so the trace and log skip lists cannot drift apart; matching is exact on the Gin route pattern (`c.FullPath()`), so a probe on a path nobody registered is traced as a 404 instead of vanishing. gin and otelgin are imported here and nowhere else in `pkg` (ADR-038). |
| `httpx` | 1 | Shared HTTP envelope: additive error shape (`error` + stable `code`) and list pagination. |
| `idempotency` | 1 | Postgres-backed idempotency store, Stripe-style: claim → first response replays verbatim → mismatch is a conflict; in-flight locks with stale-lock takeover. Caller owns the table. **v0.37.0:** `UserID` is `string` (Keycloak `sub`, ADR-042 — was `int64`). |
| `logger/zapx` · `logger/zerolog` · `logger/clog` | 0 | Structured logger adapters with trace-ID injection. **Only `zapx` has consumers** — never add the other two to a service. |
| `migratex` | 2 | Embedded golang-migrate runner (`Run(fsys, dir, dsn)`) — always against the DIRECT DB host, never a transaction pooler (DDL is unsafe through PgBouncer/PgDog). |
| `obsx` | 2 | The single OTel SDK wiring point (RFC-0014 P0): traces/metrics/logs over OTLP, one `Shutdown`, zap tee, `TraceContext`, Pyroscope profiling. **v0.37.1:** also owns the span helpers services used to copy — `Tracer`, `StartSpan`, `AddSpanAttributes`, `AddSpanEvent`, `RecordError`, `SetSpanStatus`; the instrumentation `scope` they take is a package path (`github.com/duynhlab/user-service/internal/logic/v1`), never the service name, which already rides as `service.name` on the Resource. |
| `temporalx` | 2 | Temporal client/worker bootstrap mirroring grpcx/obsx: OTel tracing interceptor, SDK RED metrics, Worker Deployment Versioning. **v0.37.0:** reads Temporal's own `TEMPORAL_DEPLOYMENT_NAME` (the platform's invented `TEMPORAL_WORKER_DEPLOYMENT_NAME` is gone), so an identity injected by the Temporal Worker Controller needs no manifest help; `Versioning`/`MustVersioning`/`WithDefaultVersioningBehavior` removed — `VersioningFromEnv`/`MustVersioningFromEnv` are the only entry points, half a config still exits 1, and an unset behaviour still resolves to `Pinned`. |
| `proto/<svc>/v1` | 0 | Versioned contracts + committed stubs for `cart`, `inventory`, `notification`, `order`, `payment`, `product`, `review`, `shipping`. **v0.37.0:** `user_id` is `string` everywhere — notification (was `int32`) and payment (was `int64`) joined the already-string contracts (ADR-042). |

## Consumer matrix

Which modules each service imports — derived from imports, which is also what
each `go.mod` requires (verified: no service requires a module it does not
import, or imports one it does not require).

| Service | n | authmw | dbx | flagx | grpcx | httpx | idempotency | logger/zapx | migratex | obsx | temporalx | proto |
|---------|:-:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|-------|
| auth | 5 | — | ✓ | — | — | ✓ | — | ✓ | ✓ | ✓ | — | — |
| user | 6 | ✓ | ✓ | — | — | ✓ | — | ✓ | ✓ | ✓ | — | — |
| inventory | 6 | — | ✓ | — | ✓ | — | — | ✓ | ✓ | ✓ | — | inventory |
| product | 7 | — | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | inventory, product, review |
| shipping | 7 | — | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | shipping |
| cart | 8 | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | cart |
| review | 8 | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | review |
| notification | 8 | ✓ | ✓ | — | ✓ | ✓ | — | ✓ | ✓ | ✓ | — | notification |
| payment | 9 | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | payment |
| order | 10 | ✓ | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | inventory, notification, order, payment, shipping |
| checkout | 10 | ✓ | ✓ | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | cart, inventory, order, product, shipping |

`inventory` is the only service with **no `httpx`** — a useful counter-example to
the assumption that every service shares one floor. `httpmw` has no column yet;
its adoption is still rolling (see below).

## Adoption

All eleven services are migrated off the frozen root module. `inventory` was last
(2026-08-08), which is also why it is absent from the migration runbook in the pkg
repo.

| Modules | Pinned at |
|---------|-----------|
| `authmw idempotency proto` | `v0.37.0` |
| `dbx grpcx httpx migratex` | `v0.36.1` |
| `temporalx` | `v0.37.0` on `order` — the breaking env rename reaches only the versioned worker; `checkout` stays on `v0.36.1`, which is safe because it passes no versioning option at all |
| `flagx logger/zapx` | `v0.36.0` |
| `obsx` | `v0.36.1`, except `inventory` on `v0.37.0` — the span-helper wave is still rolling |
| `httpmw` | **Not adopted anywhere yet.** `v0.1.0` is tagged and all nine HTTP services have an open pull request pinning it; none is merged, so every service still carries its own `middleware/` copy. `inventory` is not in that count — it serves gRPC and mounts no Gin middleware |

A service's own `go.mod` is the authority for which versions it pins; this table
records the fleet-wide state, not a per-service guarantee.

## Operations

- **Bumping:** `go get github.com/duynhlab/pkg/<module>@vX.Y.Z && go mod tidy`,
  build + tests, PR touching `go.mod` + `go.sum` only. Dependabot groups all
  `github.com/duynhlab/pkg/*` into one PR per service, so a fleet round is eleven
  PRs, not eleven times fourteen.
- **A stale root require must be deleted, never version-edited.** Editing
  `require github.com/duynhlab/pkg v0.35.0` to a `v0.36.x` points at a tag that
  does not exist; mixing the root require with a per-module one fails immediately
  with `ambiguous import`.
- **Releasing:** `make release-<module> VER=x.y.z` — **no `v` prefix** in `VER`;
  it tags `<module>/vx.y.z`. Nested modules encode `/` as `:`, so `logger/zapx` is
  `make release-logger:zapx`. The target refuses a dirty tree or a HEAD that is
  not an ancestor of `origin/main`.
- **A pushed tag is immutable.** The module proxy caches it, so a mistake is
  superseded by a new patch, never corrected in place.
- **Order matters when modules depend on each other:** tag the dependency first,
  then the dependents. No module imports another today, so this is currently
  theoretical — it stops being theoretical the first time it is not.
- **Contract compatibility:** removals are staged like RFC-0021 P4 did — callers
  migrate off first (evidence, not assumption), then the RPC leaves the contract
  in a minor release.

## Release history

Two sequences, not one. The single-module line ended when the repository split;
per-module numbering continues from it, which is why the first per-module tag is
`v0.36.0` rather than `v0.1.0`.

### Per-module tags

| Tag line | Modules | Date | What it carried |
|-----|---------|------|-----------------|
| `v0.37.1` | `obsx` | 2026-08-16 | The tracer scope is the package path of the code creating the span, not the service name. |
| `v0.1.0` + `v0.37.0` | `httpmw` `obsx` | 2026-08-16 | `httpmw` itself (ADR-038): the shared Gin `Tracing` + `Logging` pair lifted out of the per-service `middleware/` copies — one skip list behind both, exact matching on the Gin route pattern. `obsx` took the span helpers in the same release. Its `v0.37.0` is this wave, not the 2026-08-11 line below that carries the same number for other modules. |
| `v0.37.0` | `authmw idempotency proto` | 2026-08-11 | RFC-0024 P3 identity cutover (ADR-041/042): authmw verifies the Keycloak realm via `Config` + `OIDC_ISSUER`/`OIDC_AUDIENCE`/`OIDC_JWKS_URL` (old `AUTH_JWKS_URL`/`JWT_*` names removed) and normalizes `realm_access.roles`; idempotency `UserID` → `string`; notification/payment protos `user_id` → `string`. |
| `v0.37.0` | `temporalx` | 2026-08-21 | **Breaking — the first per-module tag to remove exported API.** Reads Temporal's own `TEMPORAL_DEPLOYMENT_NAME`; the invented `TEMPORAL_WORKER_DEPLOYMENT_NAME` is retired, so a worker still given the old name exits 1 rather than polling unversioned. `Versioning`, `MustVersioning` and `WithDefaultVersioningBehavior` deleted — a fleet-wide grep found no caller. Landed with homelab RFC-0026 / ADR-054. |
| `v0.36.2` | `temporalx` | 2026-08-21 | Temporal SDK `v1.45.0` → `v1.48.0`. Additive across v1.46–v1.48; nothing touching `DeploymentOptions` or `VersioningBehavior`. |
| `v0.36.1` | `authmw dbx grpcx httpx idempotency migratex obsx proto temporalx` | 2026-08-08 | gRPC and `golang.org/x` security bumps; test-coverage gaps closed. The four modules without those dependencies stayed at `v0.36.0`. |
| `v0.36.0` | all 13 | 2026-08-07 | The split itself: one module per package, Go 1.26, per-module release tooling. `grpcx` inlined its trace-id helper to drop the `obsx` call the new layering forbids. |

### Single-module line (`github.com/duynhlab/pkg`, frozen at `v0.35.0`)

Every release of the original module. Note: `v0.12.1` was never published (the
sequence jumps `v0.12.0` → `v0.12.2`).

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

- [`duynhlab/pkg`](https://github.com/duynhlab/pkg) — README (packages), `AGENTS.md` (layering), `docs/MIGRATION.md` (per-service runbook)
- [ADR-038](../proposals/adr/ADR-038-shared-http-middleware/) — why a shared middleware module must build trace context from the OTel API, not `obsx`
- [tracing.md § Request filtering](./tracing.md#request-filtering-automatic) — the skip-list contract `httpmw` enforces
- [api.md § gRPC Runtime Model](./api.md#grpc-runtime-model) — how services use grpcx at runtime
- [observability.md](./observability.md) — the obsx contract every service follows
- Per-service contracts: [Service contracts](./README.md#service-contracts)

_Last updated: 2026-08-21 — `temporalx v0.36.2` (Temporal SDK v1.48.0) and `v0.37.0` (breaking: Temporal's own versioning env names, three exported helpers removed) added to the ledger; the fleet pin for `temporalx` is split while only order needs it. Previously: the shared HTTP middleware wave (ADR-038) — `httpmw v0.1.0`, `obsx v0.37.1` span helpers with package-path scopes._
