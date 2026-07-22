# Application Metrics Catalog

Every metric series the 10 Go services emit, in lookup-table form — the
**"what exists"** companion to [Application metrics](../../api/metrics.md) (authoring)
and [metrics-apps.md](metrics-apps.md) (platform alert map / ops). All names below are the **Prometheus-rendered** forms as they appear
in VictoriaMetrics (verified live 2026-07-16); the OTel instrument names are
listed beside them.

| | |
|---|---|
| **Auto-instrumented** | 3 HTTP + 2 gRPC + 4 runtime + 15 DB-client families — identical across the fleet, zero per-service code |
| **Hand-declared (business)** | **34 instruments** across the 10 services (25 counters, 6 second-histograms, 2 value-histograms + label-less counters) |
| **Source of truth** | Each service's `internal/logic/v1/metrics.go` (+ `internal/saga/`, `internal/core/{provider,cache}/` where noted) |
| **Conventions** | RFC-0017 D-8 (instrument choice) / D-9 (bounded labels, no PII/ids) |
| **Naming render** | vmagent `usePrometheusNaming`: dots→`_`, Counter gains `_total`, `WithUnit("s")` histogram gains `_seconds` |
| **Consumed by** | [Business KPIs dashboard](../grafana/README.md#dashboards), RED board Database row, [alert catalog §1](../alerting/alert-catalog.md#1-microservices-red-metrics) |

---

## Auto-instrumented families (no per-service code)

These come from libraries wired once in `pkg` — never hand-write them
([Application metrics](../../api/metrics.md) has the full mechanics per family):

| Family (PromQL) | Type | Labels | Answers | Deep dive |
|---|---|---|---|---|
| `http_server_request_duration_seconds` | Histogram (13 SLO buckets) | `http_request_method`, `http_route`, `http_response_status_code` | RED core: rate, errors, p50/p95/p99, Apdex | [HTTP server metrics](../../api/metrics.md#http-server-metrics-auto-instrumented) |
| `http_server_{request,response}_body_size_bytes` | Histogram (byte buckets) | same | RX/TX bandwidth per route | same |
| `rpc_server_call_duration_seconds` | Histogram | `rpc_method`, `rpc_response_status_code`, `rpc_system_name` | East-west RED, callee side | [gRPC instrumentation](../../api/metrics.md#grpc-instrumentation-east-west) |
| `rpc_client_call_duration_seconds` | Histogram | `rpc_method`, `rpc_response_status_code` (server addr/port dropped by View) | East-west RED, caller side | same |
| `go_goroutine_count` · `go_memory_used_bytes` · `go_memory_gc_goal_bytes` · `go_memory_limit_bytes` | Gauge | resource attrs only (+ `go_memory_type`) | Runtime health + the D-4 liveness heartbeat | [Go runtime metrics](../../api/metrics.md#go-runtime-metrics) |
| `db_client_operation_duration_seconds` | Histogram (`DBDurationBuckets`, pkg ≥ v0.24.0) | `pgx_operation_type` = `query`\|`batch`\|`copy`\|`connect`\|`prepare`\|`acquire`, `db_system_name` | App-side DB latency p95/p99 | [DB client metrics](../../api/metrics.md#db-client-metrics-otelpgx) |
| `db_client_operation_errors_total` | Counter | same | Non-`ErrNoRows` DB failures | same |
| `pgxpool_*` (13 series: `acquired/idle/total/max_connections`, `acquires_total`, `empty_acquire_total`, `empty_acquire_wait_time_nanoseconds_total`, …) | Gauges + Counters | pool name, `db_system` | Pool in-flight, saturation, contention | same |
| `db_client_connections_*` (usage, `use_time_milliseconds`, hits/misses/timeouts/waits) | mixed | `state` | **Valkey cache pool** (redisotel, product only) — *not Postgres* | [naming trap](../../api/metrics.md#db-client-metrics-otelpgx) |

> gRPC note: the two `rpc_*_call_duration_seconds` families are the **only**
> `rpc_*` series on the platform (verified against the live series list) —
> health-check and reflection RPCs are excluded at the source by
> `pkg/grpcx`'s telemetry filter.

---

## Business metrics — per-service catalog

Hand-declared in each service's own code (RFC-0017). Every label is a bounded
enum — no ids, no PII; amounts ride in histogram **values**, never labels.

### payment (4)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `payment_authorization_total` | `payment.authorization.total` · Counter | `result` = `authorized`\|`declined`\|`error` · `currency` = 10-code allowlist (`USD`, `EUR`, …) or `other` | **Decline-rate KPI.** Once per real charge drive; idempotent replays return before the provider call — never double-counted |
| `payment_operation_total` | `payment.operation.total` · Counter | `op` = `capture`\|`void`\|`refund` · `result` = `ok`\|`rejected`\|`error` | Money-lifecycle transitions. Only real transitions counted (idempotent no-ops skipped); `error` = provider failure only |
| `payment_reconciliation_discrepancies_total` | `payment.reconciliation.discrepancies.total` · Counter | `kind` | Ledger-vs-provider drift. Per-run **detection** count — a standing discrepancy re-counts every run; read as a rate, not distinct drifts |
| `payment_provider_request_duration_seconds` | `payment.provider.request.duration` · Histogram, `s`, SLO buckets | `op` = `charge`\|`capture`\|`void`\|`refund` · `outcome` = `ok`\|`declined`\|`transient` | **The money-hop SLI** (mockpay). Recorded via defer — every return path timed, incl. transport errors. Reconciliation reads deliberately not timed |

### order (5)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `order_saga_outcome_total` | `order.saga.outcome.total` · Counter | `outcome` = `confirmed`\|`failed` (pre-capture, money voided)\|`compensated` (post-capture, money refunded) | **Fulfillment success rate.** One terminal branch per execution, `!workflow.IsReplaying` guard; best-effort (crash between emit and task completion loses, never doubles). Records the *path taken*, not that compensation succeeded |
| `order_saga_compensation_total` | `order.saga.compensation.total` · Counter | `step` = `void_payment`\|`refund_payment`\|`release_stock`\|`cancel_shipment`\|`fail_order` · `result` = `ok`\|`failed` | `result="failed"` is the **stuck-money signal** — alert on it. IsReplaying-guarded, one per real compensation run |
| `order_payment_activity_total` | `order.payment.activity.total` · Counter | `op` = `authorize`\|`capture`\|`void`\|`refund` · `result` = `ok`\|`declined`\|`rejected`\|`error` | Saga's view of payment calls. Terminal outcomes fire once; transient `error` re-drives via Temporal retry and counts **per attempt** (health signal) |
| `order_stock_reservation_total` | `order.stock_reservation.total` · Counter | `result` = `reserved`\|`insufficient`\|`error` | Saga-side ReserveStock view (distinct from product's own counter). Activities don't replay — no guard needed; `error` counts per retry attempt |
| `order_value_minor` | `order.value.minor` · Histogram, unit `1`, money buckets `500…1000000` (cents: $5…$10k) | `totals_source` = `demo`\|`checkout_quoted` | **AOV / revenue distribution.** Amount is the histogram value. Exactly once per genuine creation — never on idempotent replay |

### auth (4)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `auth_registrations_total` | `auth.registrations.total` · Counter | `result` = `success`\|`conflict` (name/email taken)\|`error` (infra) | Signup volume + failure ratio. Exactly once per Register call, every terminal path |
| `auth_refresh_operations_total` | `auth.refresh.operations.total` · Counter | `result` = `rotated`\|`invalid`\|`expired`\|`reuse_detected` | `reuse_detected` = **stolen-token replay** (critical security signal; counted even if the follow-on revoke fails). Infra failures return before recording |
| `auth_family_revocations_total` | `auth.family_revocations.total` · Counter | `reason` = `logout`\|`reuse` | Only *successful* revocations count. Measures revoke operations, not distinct families (idempotent replays re-count) — read spikes as "revoke activity" |
| `auth_password_hash_duration_seconds` | `auth.password_hash.duration` · Histogram, `s`, SLO buckets | `op` = `hash` (register)\|`compare` (login) | Isolates bcrypt cost from SQL/token work (stop-closure fires right after the bcrypt call) |

### product (2)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `product_stock_reservations_total` | `product.stock.reservations.total` · Counter | `result` = `reserved`\|`insufficient_stock`\|`error` | Product-side inventory view of the saga. Exactly once per ReserveStock invocation |
| `product_cache_gets_total` | `product.cache.gets` · Counter | `result` = `hit`\|`miss`\|`error` | **Cache-Aside hit-ratio** — the semantic split redisotel can't see (it sees GETs, not their hit/miss meaning) |

### cart (3)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `cart_items_added_total` | `cart.items_added.total` · Counter | `result` = `added`\|`rejected_invalid_qty` | Top of the purchase funnel. Recorded at the web layer (qty rule enforced by request binding); persistence failures deliberately not counted (DB span covers them) |
| `cart_cleared_total` | `cart.cleared.total` · Counter | `source` = `user_rest`\|`internal_saga` | Checkout-completion clears vs user clears. Only successful clears count |
| `cart_snapshot_requests_total` | `cart.snapshot_requests.total` · Counter | `result` = `ok`\|`empty`\|`invalid_arg`\|`error` | gRPC GetCart (checkout's east-west read). Exactly once per request |

### shipping (3)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `shipment_created_total` | `shipment.created.total` · Counter | `outcome` = `ok`\|`invalid_order_id`\|`error` | Saga step 2. Idempotent replay also returns `ok` (`ON CONFLICT … RETURNING` hides first-insert-vs-existing) — terminal outcome, not distinct creations |
| `shipment_cancelled_total` | `shipment.cancelled.total` · Counter | `outcome` = `ok` (incl. idempotent no-op)\|`error` | Saga compensation frequency |
| `shipment_lookup_total` | `shipment.lookup.total` · Counter | `kind` = `track`\|`by_order` · `found` = `true`\|`false` | Tracking + fulfillment-poll hit/miss. Infra failures not counted so `found` stays a clean existence boolean |

### user (2)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `user_profile_updated_total` | `user.profile_updated.total` · Counter | `result` = `success`\|`unauthorized` | Write volume + authz-rejection signal. Once per UpdateProfile terminal branch; persistence failures via DB span |
| `user_profile_lookup_total` | `user.profile_lookup.total` · Counter | `audience` = `public`\|`private` · `found` = `true`\|`false` | Read split + miss rate. `public` miss = 404; `private` miss returns the auth-derived fallback (still 200) |

### review (3 — all label-less)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `reviews_rating` | `reviews.rating` · Histogram, unit `1`, buckets `1,2,3,4,5` | — | **Star-rating distribution** — one bucket per star; rating validated 1–5 (logic + DB CHECK). One sample per successful review |
| `reviews_duplicate_rejected_total` | `reviews.duplicate_rejected.total` · Counter | — | Counted from both duplicate paths: pre-check hit AND the unique-violation race a concurrent insert trips |
| `grpc_reviews_truncated_total` | `grpc.reviews_truncated.total` · Counter | — | GetProductReviews filled the page cap (possible silent data loss). Edge case: an exactly-cap-sized result also counts |

### notification (2)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `notification_read_total` | `notification.read.total` · Counter | `mode` = `single`\|`all` | Added by `n` = rows actually flipped (mark-all of 5 adds 5); idempotent no-ops not counted |
| `notification_send_duration_seconds` | `notification.send.duration` · Histogram, `s`, SLO buckets | `channel` = `email`\|`sms` | Send-path latency, validated-input → persisted. The seam where a real provider call would live |

### checkout (6)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `checkout_sessions_confirmed_total` | `checkout.sessions.confirmed` · Counter | — | Sessions confirmed into an order — the funnel exit |
| `checkout_sessions_expired_total` | `checkout.sessions.expired` · Counter | `reason` = `timer` (abandonment workflow)\|`lazy` (read-path backstop) | A lazy majority ⇒ the worker is down. Recorded from the worker's MarkSessionExpired activity |
| `checkout_price_changed_total` | `checkout.price.changed` · Counter | — | Confirms bounced with `PRICE_CHANGED`/`STOCK_UNAVAILABLE` (session requoted) |
| `checkout_promo_redeemed_total` | `checkout.promo.redeemed` · Counter | — | Redemptions counted at confirm (the authoritative gate, P4) |
| `checkout_promo_rejected_total` | `checkout.promo.rejected` · Counter | `reason` = `expired`\|`exhausted` | Rejections at the confirm gate, error-mapped to a bounded reason |
| `checkout_confirm_duration_seconds` | `checkout.confirm.duration` · Histogram, `s`, SLO buckets | — | End-to-end confirm hop (product re-validate + order gRPC) |

---

## Conventions (why the tables look like this)

- **Bounded labels only (D-9)** — every label above is an enumerable const
  block in the service's `metrics.go`; ids, emails, and amounts are forbidden
  as label values (they ride in spans/logs or histogram values).
- **Naming render** — OTel dotted names → PromQL by vmagent's
  `usePrometheusNaming`: `payment.authorization.total` →
  `payment_authorization_total`; `product.cache.gets` (no `.total`) still
  gains `_total`; `WithUnit("s")` adds `_seconds`; histograms explode into
  `_bucket`/`_sum`/`_count`.
- **Buckets are histogram-only** and any non-HTTP histogram must set them
  explicitly — see the
  [instrument-types explainer](../../api/metrics.md#otel-instrument-types) for the
  full rule and the ms-default trap.
- **Exactly-once discipline** — counters are gated on the transition that
  actually applied (not on stale re-drives); Temporal workflow code adds a
  `!workflow.IsReplaying` guard, activities don't need one.

## References

- [metrics-apps.md](metrics-apps.md) — mechanics per family (pipeline, labels, buckets, correlation)
- [Alert catalog §1](../alerting/alert-catalog.md#1-microservices-red-metrics) — the alerts consuming these series
- [RFC-0017](../../proposals/rfc/RFC-0017/README.md) — the design decisions (D-8/D-9) and original catalog (historical)
- [Grafana dashboards](../grafana/README.md#dashboards) — Business KPIs + RED boards built from this catalog

---

_Last updated: 2026-07-16 — initial catalog, compiled from every service's `metrics.go` (34 shipped instruments) and the live VictoriaMetrics series list; supersedes the RFC-0017 design catalog as the shipped reference._
