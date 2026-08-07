# Application Metrics Catalog

Every metric series the 10 Go services emit, in lookup-table form — the
**"what exists"** companion to [Application metrics](../../api/metrics.md) (authoring)
and [metrics-apps.md](metrics-apps.md) (platform alert map / ops). All names below are the **Prometheus-rendered** forms as they appear
in VictoriaMetrics (verified live 2026-07-16); the OTel instrument names are
listed beside them.

| | |
|---|---|
| **Auto-instrumented** | 3 HTTP + 2 gRPC + 4 runtime + 15 DB-client families — identical across the fleet, zero per-service code |
| **Hand-declared (business)** | **63 instruments** across the 11 services (56 counters, 5 second-histograms, 2 value-histograms), 2 tombstoned |
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

### payment (12)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `payment_authorization_total` | `payment.authorization.total` · Counter | `result` = `authorized`\|`declined`\|`error` · `currency` = 10-code allowlist (`USD`, `EUR`, …) or `other` | **Decline-rate KPI.** Once per real charge drive; idempotent replays return before the provider call — never double-counted |
| `payment_operation_total` | `payment.operation.total` · Counter | `op` = `capture`\|`void`\|`refund` · `result` = `ok`\|`rejected`\|`error` | Money-lifecycle transitions. Only real transitions counted (idempotent no-ops skipped); `error` = provider failure only |
| `payment_reconciliation_discrepancies_total` | `payment.reconciliation.discrepancies.total` · Counter | `class` (was `kind` before payment 1.5.2) | Ledger-vs-provider drift. Per-run **detection** count — a standing discrepancy re-counts every run; read as a rate, not distinct drifts |
| `payment_provider_request_duration_seconds` | `payment.provider.request.duration` · Histogram, `s`, SLO buckets | `op` = `charge`\|`capture`\|`void`\|`refund` · `outcome` = `ok`\|`declined`\|`transient`\|`unknown` | **The money-hop SLI** (mockpay). Recorded via defer — every return path timed, incl. transport errors. `transient` = 429 (refused, nothing happened); `unknown` = 5xx/timeout (the work may have happened) — the phase-6 split. Reconciliation reads deliberately not timed |
| `payment_provider_unknown_total` | `payment.provider.unknown.total` · Counter | `operation` = `authorize`\|`capture`\|`void`\|`refund` · `stage` = `park`\|`resolve` (1.5.2) | Doubt by stage: `park` is NEW doubt (an intent enters processing), `resolve` is a re-ask that ALSO answered nothing. The first GameDay read 2 against one parked row because both round-trips counted indistinguishably |
| `payment_reconciliation_window_violations_total` | `payment.reconciliation.window_violations.total` · Counter | — | Provider rows outside the requested `[from, through)` window — excluded from classification, watermark held (1.5.2; the G5/F1 phantom class) |
| `payment_attempt_resolution_total` | `payment.attempt.resolution.total` · Counter | `operation` · `outcome_class` = `SUCCESS`\|`BUSINESS_DECLINE`\|`RETRYABLE_FAILURE`\|`UNKNOWN` | Doubt **settled**: a re-drive of an open question. `UNKNOWN` here is counted deliberately — a resolution that learned nothing is the interesting case, not missing data |
| `payment_attempt_write_failures_total` | `payment.attempt.write_failures.total` · Counter | `operation` | Evidence that would not persist. The park is then **refused**, so a state nobody confirmed stands — critical-alertable. A duplicate refused by the one-SUCCESS-capture index is NOT counted here |
| `payment_doubt_open` | `payment.doubt.open` · Gauge (observable) | — | Unresolved provider round-trips right now. Unwindowed on purpose: doubt about money must not age out of view |
| `payment_doubt_oldest_age_seconds` | `payment.doubt.oldest_age_seconds` · Gauge (observable), `s` | — | Age of the oldest unresolved outcome — **the escalation signal**. One fresh unknown is routine; an old one means money is sitting somewhere nobody has looked. Both gauges observe nothing on a read error rather than returning one (a returned error drops the whole export cycle) |
| `payment_doubt_sweep_failures_total` | `payment.doubt.sweep_failures.total` · Counter | `operation` | Worklist entries the sweep could not even attempt (row would not load, no key to replay under) — distinct from a resolution that ran and learned nothing |
| `payment_idempotency_release_failures_total` | `payment.idempotency.release_failures.total` · Counter | — | Keys left locked after a failed attempt; the caller is told to retry immediately and would bounce off the lock until the takeover window |

### order (24)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `order_saga_outcome_total` | `order.saga.outcome.total` · Counter | `outcome` = `confirmed`\|`failed` (pre-capture, money voided)\|`compensated` (post-capture, money refunded) | **Fulfillment success rate.** One terminal branch per execution, `!workflow.IsReplaying` guard; best-effort (crash between emit and task completion loses, never doubles). Records the *path taken*, not that compensation succeeded |
| `order_saga_compensation_total` | `order.saga.compensation.total` · Counter | `step` = `void_payment`\|`refund_payment`\|`release_stock`\|`cancel_shipment`\|`fail_order` · `result` = `ok`\|`failed` | `result="failed"` is the **stuck-money signal** — alert on it. IsReplaying-guarded, one per real compensation run |
| `order_payment_activity_total` | `order.payment.activity.total` · Counter | `op` = `authorize`\|`capture`\|`void`\|`refund` · `result` = `ok`\|`declined`\|`rejected`\|`error` | Saga's view of payment calls. Terminal outcomes fire once; transient `error` re-drives via Temporal retry and counts **per attempt** (health signal) |
| `order_stock_reservation_total` | `order.stock_reservation.total` · Counter | `participant` = `product`\|`inventory` · `result` = `reserved`\|`insufficient`\|`error` | Saga-side reserve view (distinct from product's own counter). Activities don't replay — no guard needed; `error` counts per retry attempt. `participant` was the write-cutover progress signal; since phase 4 it has one servable value, so **a `product` series reappearing is a FINDING, not progress** — it would mean a pre-P4 history started on a build that still has the branch |
| `order_inventory_commit_lag_seconds` | `order.inventory.commit_lag` · Histogram, unit `s` | — | Seconds from the ConfirmOrder **pivot** to CommitInventory settling (RFC-0021 P3). `workflow.Now` delta, IsReplaying-guarded. **Right-censored:** an order whose commit never settles contributes NO observation and surfaces as `order_reconciler_backlog` instead — read the two together. Since RFC-0021 P4 every saga takes the inventory branch, so a SILENT series means no orders are confirming (or the worker is not scraped) — not an idle branch |
| `order_fulfillment_start_outbox_pending` | `order.fulfillment.start_outbox.pending` · Observable gauge | — | PENDING rows in the start outbox (ADR-031). Normal value is 0: the inline start marks a row DISPATCHED milliseconds after insert. Reported by **both** the API and the worker — the same table read twice, so the signal survives the worker being down |
| `order_fulfillment_start_outbox_oldest_age_seconds` | `order.fulfillment.start_outbox.oldest_age` · Observable gauge, unit `s` | — | Age of the oldest PENDING row. **This, not the count, is the alertable signal** — a burst that clears in seconds is the system working; a row waiting minutes means the inline start failed and the dispatcher has not recovered it |
| `order_fulfillment_start_outbox_failed` | `order.fulfillment.start_outbox.failed` · Observable gauge | — | Rows the dispatcher will not start: either the attempt cap was exhausted, or the row was refused on its first claim (`TOKEN_CLEARED`, `TOO_OLD`, `ABANDONED_RUN`, `PARTICIPANT_UNSERVABLE`). **Terminal — nothing retries them**, so any non-zero value is a human worklist, not a transient. `last_error_code` decides the remedy, and whether money may have moved |
| `order_fulfillment_start_dispatch_total` | `order.fulfillment.start_dispatch.total` · Counter | `result` = `dispatched`\|`skipped`\|`failed`\|`abandoned` | Dispatcher outcomes per claimed row. `skipped` = the order was no longer `pending` (already recovered), which is a success, not a loss |
| `order_reconciler_backlog` | `order.reconciler.backlog` · Observable gauge | — | Terminal orders whose stock has not been confirmed to agree with their outcome (RFC-0021 P3). A **query** against the table, never a counter in memory, and **unwindowed** so an unresolved breach cannot age out. On a failed read it publishes **nothing** rather than 0 — so its failure mode is *absence*, which is why `absent()` is alerted on. Reported by both order processes |
| `order_reconciler_repairs_total` | `order.reconciler.repairs.total` · Counter | `action` = `committed`\|`released`\|`breach`\|`failed`\|`deferred`\|`unreadable` | Reconciler actions. Reported **once per order**, not once per pass — which is what makes `breach` alertable instead of 1,440 increments/day for one stuck order. A steady `committed`/`released` stream means something upstream is failing regularly |
| `order_reconciler_passes_truncated_total` | `order.reconciler.passes.truncated.total` · Counter | — | Passes that hit the 200-row batch cap. While non-zero, treat `order_reconciler_backlog` as a **floor** rather than a count |
| `order_reconciler_participant_disagreements_total` | `order.reconciler.participant_disagreements.total` · Counter | `row_participant` = `product`\|`absent`\|`other` (**normalised** — the raw column value is never a label, precisely because this fires when something is wrong with it) | Orders repaired that hold an inventory reservation while their outbox row does not say inventory-path (RFC-0021 P3). One cause only: a saga start that resolved its branch from a process flag instead of from the order. Reported **once per order**, so any increase is a distinct order and no threshold above zero is honest. Should read flat zero |
| ~~`product_stock_surface_calls_total`~~ | — | — | **REMOVED in product 1.7.0** with the RPCs it watched (RFC-0021 phase 4). It was the removal gate: two weeks of zero, measured from deployment. That gate was **waived** on 2026-08-05 in favour of code evidence, and the instrument went with the surface — so the gate query now returns *empty*, which is indistinguishable from zero. See [cutover-rollback.md § Contract removal](../../proposals/rfc/RFC-0021/cutover-rollback.md) before reading anything into a flat panel |
| `order_fulfillment_start_participant_total` | `order.fulfillment.start_participant.total` · Counter | `participant` = `product`\|`inventory`\|`""` · `source` = `recorded`\|`absent`\|`unrecognised` · `result` = `started`\|`refused` | Which branch each start RESOLVED, from what, and whether it was served. Recorded inside the resolver so no start path can omit it. Since RFC-0021 P4 only `inventory` can be served, so read `result="started"` for "which branch are sagas starting on" and `result="refused"` for the population needing a decision (its rows go terminal with `PARTICIPANT_UNSERVABLE`). `participant` is EMPTY when `source="unrecognised"` — nothing may be guessed for a token no build knows |
| `order_value_minor` | `order.value.minor` · Histogram, unit `1`, money buckets `500…1000000` (cents: $5…$10k) | — (the `totals_source` label was removed with the legacy REST create, v1.11.0 — every total is checkout-quoted) | **AOV / revenue distribution.** Amount is the histogram value. Exactly once per genuine creation — never on idempotent replay |
| `order_cancellations_total` | `order.cancellations.total` · Counter | `result` = `accepted`\|`replayed`\|`rejected`\|`error` | Cancel API outcomes (RFC-0021 P5). `replayed` = idempotent re-cancel (200); `rejected` = 409 policy/FSM refusals |
| `order_cancellation_start_dispatch_total` | `order.cancellation.start_dispatch.total` · Counter | `result` | Cancellation-outbox dispatcher outcomes — the lean sibling of the fulfillment dispatcher (no payment-token hazard) |
| `order_cancellation_outcomes_total` | `order.cancellation.outcomes.total` · Counter | `outcome` = `cancelled`\|`manual_review` | CancellationWorkflow terminal writes. The workflow always completes; the order state carries the outcome |
| `order_cancelling_backlog` | Observable gauge | — | Orders in `cancelling` older than 15 min — table query, reported by both order processes; feeds `OrderStuckCancelling` |
| `order_manual_review_backlog` | Observable gauge | — | Orders parked in `manual_review` — un-aged and unwindowed (a human decision must never quietly age out); feeds `OrderManualReviewBacklog` |
| `order_cancellation_outbox_pending` / `_failed` | Observable gauges | — | Cancellation-outbox rows by state; FAILED rows are a worklist (nothing retries them — re-cancelling re-arms the row) |
| `order_cancellation_outbox_oldest_pending_age_seconds` | Observable gauge | — | Age of the oldest PENDING row; feeds `OrderCancellationOutboxStalled` |
| `order_saga_complete_failures_total` | `order.saga.complete_failures.total` · Counter | — | The fulfillment tail could not record `confirmed → completed` after retries. A legal mid-tail cancellation is deliberately NOT counted |
| `order_projection_write_failures_total` | `order.projection.write_failures.total` · Counter | — | Processing-projection stage writes that exhausted their (~7 s) budget. UX-only — a steady rate means `/details` progress is dark, `orders.status` unaffected |

### auth (4)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `auth_registrations_total` | `auth.registrations.total` · Counter | `result` = `success`\|`conflict` (name/email taken)\|`error` (infra) | Signup volume + failure ratio. Exactly once per Register call, every terminal path |
| `auth_refresh_operations_total` | `auth.refresh.operations.total` · Counter | `result` = `rotated`\|`invalid`\|`expired`\|`reuse_detected` | `reuse_detected` = **stolen-token replay** (critical security signal; counted even if the follow-on revoke fails). Infra failures return before recording |
| `auth_family_revocations_total` | `auth.family_revocations.total` · Counter | `reason` = `logout`\|`reuse` | Only *successful* revocations count. Measures revoke operations, not distinct families (idempotent replays re-count) — read spikes as "revoke activity" |
| `auth_password_hash_duration_seconds` | `auth.password_hash.duration` · Histogram, `s`, SLO buckets | `op` = `hash` (register)\|`compare` (login) | Isolates bcrypt cost from SQL/token work (stop-closure fires right after the bcrypt call) |

### inventory (2)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `inventory_check_total` | `inventory.check.total` · Counter | `outcome` = `fulfillable`\|`shortage`\|`unknown_sku`\|`error` | Whole-basket availability reads (checkout's fail-closed gate at session create and confirm). `unknown_sku` is split from `shortage` on purpose: one needs a balance row, the other needs a requote, and lumping them made a missing row look like a real stockout. Pairs with `checkout_availability_check_total` — the same question asked from the caller's side |
| `inventory_reservation_total` | `inventory.reservation.total` · Counter | `operation` = `reserve`\|`release`\|`commit` · `outcome` = `ok`\|`replayed`\|`insufficient`\|`conflict`\|`concurrency`\|`invalid_transition`\|`not_found`\|`unknown_sku`\|`error` | The saga-side stock authority since the RFC-0021 P4 contraction. Every known rejection has its own value, so **`error` is the residual bucket and always actionable** ([`InventoryReservationInfraErrors`](../runbooks/microservices/InventoryReservationInfraErrors.md)). `unknown_sku` (0.4.1+) means no balance row in ANY warehouse — checkout already fails closed on that class, so reaching a reservation with it is a data gap that moved mid-flight, and it pages ([`InventoryReserveUnknownSKU`](../runbooks/microservices/InventoryReserveUnknownSKU.md)). `conflict` (divergent payload under a used key) is distinct from `replayed` (identical retry) |

### product (1)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| ~~`product_stock_reservations_total`~~ | — | — | **REMOVED in product 1.7.0** — it counted `ReserveStock`, which no longer exists. The recording rule and the baseline dashboard panel that read it are retired/labelled rather than left to show an empty series that looks like a signal. Live stock outcomes are inventory-service's |
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

### checkout (7)

| Metric (PromQL) | Instrument | Labels | How to read / recorded when |
|---|---|---|---|
| `checkout_sessions_confirmed_total` | `checkout.sessions.confirmed` · Counter | — | Sessions confirmed into an order — the funnel exit |
| `checkout_sessions_expired_total` | `checkout.sessions.expired` · Counter | `reason` = `timer` (abandonment workflow)\|`lazy` (read-path backstop) | A lazy majority ⇒ the worker is down. Recorded from the worker's MarkSessionExpired activity |
| `checkout_price_changed_total` | `checkout.price.changed` · Counter | — | Confirms bounced with `PRICE_CHANGED`/`STOCK_UNAVAILABLE` (session requoted) |
| `checkout_availability_check_total` | `checkout.availability.check` · Counter | `result` = `ok`\|`shortage`\|`unknown_sku`\|`error` | Inventory availability answers. `unknown_sku` (checkout 0.6.0+) is a SKU inventory does not TRACK — a data problem checkout fails closed on, kept apart from `shortage` because the fix is a balance row rather than a requote, and excluded from the error-ratio denominator so it cannot dilute the critical page. The ONLY signal that separates "inventory is down" from "inventory is refusing baskets": `checkout_price_changed_total` lumps `PRICE_CHANGED` with `STOCK_UNAVAILABLE`, and an availability failure is otherwise laundered into a generic `ErrUpstream` 503. Replaces `checkout_availability_path_total` (one authority ⇒ one possible value) and `inventory_shadow_compare_total` (nothing left to compare) |
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

_Last updated: 2026-08-01 — added the nine RFC-0021 phase-5 order series; `order_value_minor` lost its `totals_source` label (v1.11.0)._
