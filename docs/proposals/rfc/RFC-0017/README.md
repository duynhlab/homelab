# RFC-0017 Platform telemetry standard: per-layer signal ownership + fleet instrumentation

| Status | Scope | Created | Last updated |
|--------|-------|---------|--------------|
| implemented | platform-wide | 2026-07-14 | 2026-07-16 |

> **Don't forget: every decision is a tradeoff.** This RFC deliberately spends
> effort instrumenting *every* service's data layer and domain — more code and
> more series than "the auto layer is enough" — in exchange for a fleet that
> can be debugged and reasoned about uniformly. The cost is itemized in
> Drawbacks; the guardrail against its main risk (cardinality) is a hard
> bounded-label rule.

## Summary

RFC-0014 moved the platform to full OTLP push and gave every service **RED**
(HTTP/gRPC, via `otelgin`/`otelgrpc`) and **USE** (Go runtime + cAdvisor) for
free. A 10-service audit shows the story stops there: the **`logic` layer owns
no business metrics** on 9 of 10 services (only checkout has any), the **`core`
layer is telemetry-dark everywhere** — no service traces its database queries —
and repository errors vanish into bare `return err`. This RFC makes the
**3-layer × 3-signal ownership model explicit and normative**, then instruments
the whole fleet to it: DB query tracing at `core` (a shared `pkg` helper),
structured repo-error logs, and a per-service **business-metrics catalog** at
`logic`. It is a production-grade rollout, not a demo — the goal is a platform
whose telemetry mirrors what a mature production estate looks like.

## Motivation

The platform's observability is uneven in a way that only shows up under
pressure:

- **The `core` layer is invisible.** No service attaches an `otelpgx`
  `QueryTracer` to its `pgxpool` (verified across all 10). A `logic`-layer span
  like `auth.login` therefore has **no child DB span** — a slow login cannot be
  attributed to SQL vs bcrypt, and a database outage produces spans with a
  recorded error but no queryable log at the source (repositories `return err`
  with no table/op/SQLSTATE context).
- **The `logic` layer has no domain metrics.** Business outcomes exist only as
  trace span-events (`authentication.failed`, `refresh.reuse_detected`,
  `insufficient_stock`, …). They cannot be rated, alerted, or dashboarded —
  there is no `login-failure-rate`, no `payment decline-rate`, no
  `saga-compensation-rate`, no cache `hit-ratio`. Only checkout-service (RFC-0015
  P4) declares business instruments, and it is the reference the rest should
  follow.
- **Small correctness/leak issues ride along.** Two services carry a redundant
  manual `http.request` span duplicating `otelgin`'s server span; two set
  `username`/`email` as span attributes (PII + unbounded-cardinality risk).
- **The dashboards drifted.** The local-stack board still queries pre-cutover
  metrics that are no longer emitted (`go_memstats_*`, `go_threads`,
  `process_cpu_seconds_total`, `requests_in_flight`, `up{}`).

RFC-0014 was the pipeline; this RFC is the **coverage** — closing it to a
production bar across every service and every layer.

### Goals

- A **normative 3-layer × 3-signal ownership model** every service and PR follows.
- **`core` DB tracing fleet-wide** via a shared `pkg` helper (one place, all 10
  adopt) so every `logic` span shows its DB children, plus structured
  repo-error logs (table/op/SQLSTATE).
- A **per-service business-metrics catalog** at the `logic` layer — the domain
  KPIs each service should own, with **bounded labels and no PII**.
- **Consume it:** alerts and SLOs on the new domain KPIs, and a **separate**
  business-metrics dashboard (never mixed into the RED/runtime board).
- Small hygiene fixes: drop redundant manual HTTP spans; remove PII span attrs.

### Non-Goals

- No change to the OTLP pipeline, backends, or vmagent config (RFC-0014 stands).
- **No exemplars** (accepted-lost in RFC-0014; correlation stays via `trace_id`).
- No new tracing/metrics backend.
- No cache layer added where none exists — only instrument the one that does
  (product's Valkey). A user-service cache is a *finding*, not a deliverable here.
- SPA/business-facing dashboards beyond the operator board are out of scope.

## Proposal

### The standard — per-layer signal ownership

Each of the three architectural layers **owns** a distinct slice of telemetry.
This is the normative table; a PR that instruments the wrong layer (e.g. a
business metric in `web`, or a DB span hand-rolled in `logic`) is rejected.

| Layer | Owns | Metrics | Traces | Logs |
|-------|------|---------|--------|------|
| **`web/v1`** | transport | HTTP + gRPC **RED — AUTO** (`otelgin`/`otelgrpc`); never hand-written | server span **AUTO**; **no** redundant manual `http.request` span | one request log carrying `trace_id`; middleware chain = tracing → logging |
| **`logic/v1`** | domain | **business metrics live here** — OTel Meter counters/histograms, bounded labels | business spans (per use-case) — **never** PII in attributes | domain-event logs (outcome + `trace_id`) |
| **`core`** | dependencies | DB + cache metrics (hit/miss, op duration where no tracer) | **DB query spans via `otelpgx`**; cache spans via `redisotel` | **repo errors logged with context** (table, op, SQLSTATE) |

```mermaid
flowchart TB
    subgraph WEB["web/v1 — transport (AUTO)"]
        RED["HTTP/gRPC RED<br/>otelgin · otelgrpc"]
    end
    subgraph LOGIC["logic/v1 — domain (HAND-DECLARED)"]
        BIZ["business metrics<br/>+ business spans + domain logs"]
    end
    subgraph CORE["core — dependencies"]
        DBSPAN["DB spans (otelpgx)<br/>cache hit/miss · repo-error logs"]
    end
    WEB --> LOGIC --> CORE --> DB[(PostgreSQL)]
    CORE -.cache-aside.-> VK[(Valkey · product only)]

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    class RED,BIZ,DBSPAN service;
    class DB,VK data;
```

### Conventions (normative)

1. **Business metrics are declared in `logic`** via `otel.Meter("<service>")`,
   OTel dotted names (`<service>.<noun>.<verb>`), `WithUnit("s")` for durations,
   monotonic counters for counts. vmagent's `usePrometheusNaming` renders the
   PromQL form (counter → `_total`, seconds histogram → `_seconds`).
2. **Every label value is enumerable and bounded.** A `reason`/`result`/`outcome`
   with a small fixed set is fine; `user_id`, `order_id`, `session_id`,
   `payment_id`, `promo_code`, IPs, or raw errors are **forbidden** as labels or
   span attributes (they belong in logs/traces). See
   [Application metrics § cardinality control](../../../api/metrics.md#app-side-cardinality-control).
3. **DB tracing is uniform**, added once as a shared `pkg` helper that attaches
   an `otelpgx` `QueryTracer` to the pool at build time — services opt in with
   one line, not a per-repo copy. `otelpgx` is tracer-only; it does not change
   the pooler's simple-protocol query mode.
4. **RED/USE are never hand-written.** If a service author is declaring an HTTP
   or runtime counter, they are doing it wrong — those come from the auto layer.

### Alternatives

| | (1) Auto layer only (status quo) | (2) Per-repo DB tracing + ad-hoc metrics | **(3) Standard + shared helper + catalog — chosen** |
|---|---|---|---|
| `core` visibility | none | uniform but 10 copies | uniform, one helper |
| Business metrics | none (except checkout) | inconsistent naming/labels | one convention, reviewed catalog |
| Cardinality safety | n/a | per-author judgement | hard bounded-label rule |
| Effort | zero | high + drift | moderate, front-loaded in `pkg` |

**(1) rejected** — it is the current gap. **(2) rejected** — it reintroduces the
per-service drift RFC-0014 spent effort deleting.

## Key decisions (research-hardened)

Verified against current library docs (context7) at the pinned versions before
committing. These are the traps that would otherwise bite; each is baked into
the shared `pkg` layer so services cannot diverge.

**At a glance** (details below):

| # | Area | The trap (what goes wrong) | The rule |
|---|------|----------------------------|----------|
| D-1 | DB span | full SQL becomes the span name → cardinality + PII | `WithTrimSQLInSpanName()` (span = `SELECT`) |
| D-2 | DB PII | bind values / conn details leak into spans | forbid `WithIncludeQueryParameters`; disable conn details |
| D-3 | DB pool | no pool-saturation gauges | `RecordStats(pool)` mandatory, fail-boot on error |
| D-4 | DB spans | extra "acquire" span per query (2–3× volume) | `WithDisableAcquireTracer()` |
| D-5 | DB pooler | extended protocol breaks PgDog + adds prepare spans | keep `SimpleProtocol` on pooled pools |
| D-6 | wiring | pool built before providers → **0 spans, no error** | providers set/passed before any pool |
| D-7 | temporality | forcing delta would fight VictoriaMetrics | keep **cumulative** (SDK default); collector processor is defensive |
| D-8 | instrument | Counter used for a rises-and-falls value | Counter / UpDownCounter / gauge decision table |
| D-9 | cardinality | unbounded labels → 2000-cap overflow, silent | bounded enum labels only; no ids/free-text/`err.Error()` |
| D-10 | cache | `redisotel` logs raw command (`GET product:12345`) | `WithDBStatement(false)` + `WithPoolName` |
| D-11 | money hop | trace header not propagated / signed | `otelhttp.NewTransport`; drain body every path |
| D-12 | logs↔trace | bridge misses native `TraceId` without ctx | `Log(ctx)` helper; already level-gated + de-duped |

**DB tracing (`otelpgx`, W0 shared pool helper):**
- **D-1 — Trim SQL from span names.** `otelpgx` defaults to the *full SQL* as
  the span name (`query SELECT … WHERE id=3`) → cardinality blow-up + PII in
  Tempo. The helper MUST set `WithTrimSQLInSpanName()` (span = `SELECT`).
- **D-2 — Never capture query parameters or connection details.** Forbid
  `WithIncludeQueryParameters()` (writes bind values `%+v` → emails/tokens in
  spans) in every environment; add `WithDisableConnectionDetailsInAttributes()`.
- **D-3 — `RecordStats(pool)` is mandatory** and a *separate* call — without it
  there are no pool-saturation gauges (the signal you want when PgDog is the
  bottleneck). The helper calls it and fails bootstrap on error.
- **D-4 — Disable the acquire tracer** (`WithDisableAcquireTracer()`): the
  default emits an extra "acquire" span per connection checkout (2–3× span
  volume fleet-wide); pool health is watched via D-3 metrics instead.
- **D-5 — Simple protocol stays.** Keep `DefaultQueryExecMode =
  QueryExecModeSimpleProtocol` on every PgDog-fronted pool — required for the
  transaction-mode pooler *and* it removes per-SQL `prepare` spans. (Confirms
  the existing jsonb-as-string gotcha; documented, not rediscovered.)
- **D-6 — Providers before pools.** A pool built before `obsx` installs the
  global providers binds to the no-op provider → **zero DB spans, no error**.
  The helper takes the providers explicitly (or asserts they are set).
  `otelpgx` uses `pgx.*`/`db.system` attributes, not semconv v1.41 `db.query.*`
  — dashboards query the `pgx.*` namespace.

**Metrics (`logic` business instruments):**
- **D-7 — Temporality stays cumulative.** The SDK default is cumulative, which
  is exactly what VictoriaMetrics wants; the collector's `deltatocumulative` is
  a *defensive passthrough* for any delta source, not a reason to switch. Do
  **not** force delta at the SDK. (Documented so it is never "fixed" wrongly.)
- **D-8 — Instrument choice is explicit.** Monotonic domain count → `Counter`
  (`_total`); a level that rises *and* falls known at mutation points →
  `UpDownCounter`; a level sampled on read → observable gauge. `payment_outbox_pending`
  is an `UpDownCounter`/gauge, never a counter.
- **D-9 — Bounded labels, enforced.** The SDK caps cardinality at 2000
  attribute-sets/metric then silently overflows; every label value is an
  enumerable set (`result`/`outcome`/`op`/`error.type`), never an id, free text,
  or `err.Error()`. Duration histograms use base unit `s` with the platform
  bucket View (RFC-0014 D-7); money uses a minor-unit histogram with its own View.

**Logs / cache / propagation:**
- **D-10 — `redisotel` must not leak the command.** `WithDBStatement` is ON by
  default → raw `GET product:12345` as `db.statement` (cardinality + PII); the
  product cache client sets `WithDBStatement(false)` and `WithPoolName(<name>)`
  per client so pool metrics stay separable.
- **D-11 — Outbound trace propagation via `otelhttp.NewTransport`.** For the
  payment→mockpay hop: it injects `traceparent` at RoundTrip (after the app
  signs), so the HMAC scope stays body + whitelisted headers and the money hop
  joins the trace. Client spans only end on body close/EOF → `defer Body.Close()`
  + drain on **every** path, including non-2xx.
- **D-12 — `otelzap` gets the context.** The bridge sets the native
  `LogRecord.TraceId` only when `ctx` is passed as a zap field; today the
  middleware injects `trace_id` as a *string* (queryable in VictoriaLogs — works
  today), but a `logic`-layer `Log(ctx)` helper is added (W1) so OTLP-native
  logs↔trace correlation works too. Its OTLP core is already level-gated
  (`NewIncreaseLevelCore`) and the double-ingest guard (`otlp-logs` label) is in
  place from RFC-0014 P4.

## Design Details

### `core` layer — DB tracing + error logs (uniform, all 10)

A `pkg` helper wraps pool construction so `poolCfg.ConnConfig.Tracer` is an
`otelpgx` tracer feeding the global TracerProvider `obsx` installs. Result:
every `logic` span gains child `db.query` spans (statement, table, rows,
duration) and DB latency/errors become attributable. Repositories additionally
log failures with structured context (table, op, SQLSTATE) instead of bare
`return err`. Cache (product only): `redisotel` on the go-redis client for
cache-op spans + a hit/miss counter.

### `logic` layer — per-service business-metrics catalog

> **Historical design — superseded by the shipped catalog.** The implemented
> reference (all 34 shipped instruments, exact names, label values, and
> recording semantics) is
> [**docs/observability/metrics/metrics-catalog.md**](../../../observability/metrics/metrics-catalog.md).
> The table below is the pre-implementation design; it diverged during W1/W2:
> saga metrics gained the `order.` prefix (`order_saga_outcome_total`, …),
> `product_cache_operations_total` shipped as `product_cache_gets_total`
> (redisotel covers per-command detail), and several rows were **not
> implemented** (backlog, not committed): `auth_login_attempts`,
> `user_profile_created`, `product_stock_releases`,
> `product_cache_stampede_lock`, `product_reviews_aggregation`,
> `cart_operations`, `orders_created`, `reviews_created`,
> `shipping_quote_requests`, `notification_send_total`,
> `payment_captured_amount_minor`, `payment_outbox_pending`, and the four
> checkout funnel rows (`sessions_created`, `confirm_rejected`,
> `promo_applied`, `session_stage_reached`).

Curated from the audit; each is a `logic`-layer instrument with bounded labels.

**Reference pattern (from `checkout` + `payment`, the two most-instrumented
services).** A service's *basic* set is small and follows the same shape those
two already prove:
1. **One primary outcome counter** with a bounded `result`/`outcome` label —
   the domain KPI (checkout `sessions.confirmed`, payment `authorization{result}`).
2. **The single most critical domain signal** — the thing that means money or
   security is at risk (payment `reconciliation_discrepancies`, auth
   `refresh{reuse_detected}`, order `saga_compensation`).
3. *(only where it's a real objective)* one duration histogram
   (checkout `confirm.duration`, payment `provider_request.duration`).

**Basic tier = the `Priority: High` rows below** — that is what W1 implements
now, per service. `Med`/`Low` rows are the richer later pass (W2). `checkout`
is already done (RFC-0015 P4); its four funnel additions are the High rows in
its block.

| Service | Metric (PromQL) | Type | Bounded labels | Purpose | Priority |
|---------|-----------------|------|----------------|---------|----------|
| **auth** | `auth_login_attempts_total` | Counter | `result`=success\|invalid_credentials\|user_not_found | Core auth KPI; brute-force/credential-stuffing alert | High |
| auth | `auth_registrations_total` | Counter | `result`=success\|conflict\|error | Signup volume + failure ratio | High |
| auth | `auth_refresh_operations_total` | Counter | `result`=rotated\|invalid\|expired\|reuse_detected | Token-rotation health + stolen-token replay signal | High |
| auth | `auth_family_revocations_total` | Counter | `reason`=logout\|reuse | Revocations, separating logout from theft | Med |
| auth | `auth_password_hash_duration_seconds` | Histogram | `op`=hash\|compare | Isolate bcrypt cost from SQL time | Med |
| **user** | `user_profile_created_total` | Counter | `result`=success\|already_exists\|invalid_email\|invalid_user_id | Registration-completion tail (auth→user handshake) | Med |
| user | `user_profile_updated_total` | Counter | `result`=success\|unauthorized | Write volume + authz-failure signal | Med |
| user | `user_profile_lookup_total` | Counter | `audience`=public\|private, `found`=true\|false | Read split + 404 rate (justifies a future cache) | Med |
| **product** | `product_cache_operations_total` | Counter | `op`=get_product\|get_list, `result`=hit\|miss\|error | **Cache hit-ratio** (RED for cache-aside) | High |
| product | `product_stock_reservations_total` | Counter | `result`=reserved\|insufficient_stock\|error | Saga inventory-rejection rate (business vs infra) | High |
| product | `product_stock_releases_total` | Counter | `result`=released\|error | Saga compensation volume/failures | Med |
| product | `product_cache_stampede_lock_total` | Counter | `outcome`=acquired\|populated_by_peer\|timeout_fallback | Lock contention / DB-fallback stampedes | Med |
| product | `product_reviews_aggregation_total` | Counter | `result`=ok\|soft_failed\|no_client | Review gRPC soft-fail rate | Med |
| **cart** | `cart_operations_total` | Counter | `operation`=add\|update\|remove\|clear, `outcome`=ok\|invalid_qty\|not_found\|error | Cart write funnel + error rate per op | High |
| cart | `cart_items_added_total` | Counter | `result`=added\|rejected_invalid_qty | Top of purchase-conversion funnel | Med |
| cart | `cart_cleared_total` | Counter | `source`=user_rest\|internal_saga | Checkout-completion vs abandonment clears | Med |
| cart | `cart_snapshot_requests_total` | Counter | `result`=ok\|empty\|invalid_arg\|error | gRPC GetCart (RFC-0015 checkout read) | Med |
| **order** | `orders_created_total` | Counter | `result`=created\|replayed\|invalid, `source`=rest\|grpc_checkout | Throughput + idempotent-replay + validation-reject | High |
| order | `order_value_minor` | Histogram (minor USD) | `totals_source`=demo\|checkout_quoted | AOV/revenue + mispriced-quote detection | Med |
| order | `saga_outcome_total` | Counter | `outcome`=confirmed\|failed\|compensated | Fulfillment success rate (top SLO) | High |
| order | `saga_compensation_total` | Counter | `step`=void_payment\|refund_payment\|release_stock\|cancel_shipment\|fail_order, `result`=ok\|failed | Stuck-money detection (failed refund/void) | High |
| order | `payment_activity_total` | Counter | `op`=authorize\|capture\|void\|refund, `result`=ok\|declined\|rejected\|error | Authorize decline + capture failure | High |
| order | `stock_reservation_total` | Counter | `result`=reserved\|insufficient\|error | Insufficient-stock rate (common saga failure) | Med |
| **review** | `reviews_created_total` | Counter | `result`=created\|duplicate\|invalid_rating | Creation happy-path vs rejects | Med |
| review | `reviews_rating` | Histogram (rating 1–5) | — | Rating distribution (signature domain signal) | Med |
| review | `reviews_duplicate_rejected_total` | Counter | — | Business + integrity signal (pre-check + DB race) | Low |
| review | `grpc_reviews_truncated_total` | Counter | — | Silent truncation at the 10k gRPC cap | Low |
| **shipping** | `shipping_quote_requests_total` | Counter | `method`=standard\|express, `region_bucket`=domestic\|intl, `outcome`=ok\|unknown_input | GetQuote demand mix + 400 rate | High |
| shipping | `shipment_created_total` | Counter | `outcome`=ok\|invalid_order_id\|error | Saga step-2 volume + idempotent repeats | Med |
| shipping | `shipment_cancelled_total` | Counter | `outcome`=ok\|error | Saga compensation frequency | Med |
| shipping | `shipment_lookup_total` | Counter | `kind`=track\|by_order, `found`=true\|false | Customer tracking + fulfillment polling hit/miss | Med |
| **notification** | `notification_send_total` | Counter | `channel`=email\|sms, `outcome`=sent\|invalid_recipient\|error | Core domain event; send-volume + failure SLO | High |
| notification | `notification_read_total` | Counter | `mode`=single\|all | Engagement with delivered notifications | Low |
| notification | `notification_send_duration_seconds` | Histogram | `channel`=email\|sms | Send latency seam (future real provider) | Low |
| **payment** | `payment_authorization_total` | Counter | `result`=authorized\|declined\|error, `currency` | Decline rate — primary payment KPI | High |
| payment | `payment_operation_total` | Counter | `op`=capture\|void\|refund, `result`=ok\|rejected\|error | Money-lifecycle transitions | High |
| payment | `payment_captured_amount_minor_total` | Counter | `currency` | Settled money volume | Med |
| payment | `payment_provider_request_duration_seconds` | Histogram | `op`=charge\|capture\|refund\|void, `outcome`=ok\|declined\|transient | mockpay dependency SLI (the money hop) | High |
| payment | `payment_reconciliation_discrepancies_total` | Counter | `kind` (bounded) | Ledger-vs-provider drift per recon run | High |
| payment | `payment_outbox_pending` | UpDownCounter/gauge | — | Unpublished outbox backlog (stuck relay) | Med |
| **checkout** *(has 6; +4 for the funnel)* | `checkout_sessions_created_total` | Counter | — | Funnel entry — the missing conversion denominator | High |
| checkout | `checkout_confirm_rejected_total` | Counter | `reason`=in_flight\|key_conflict\|order_rejected\|upstream | Confirm failure taxonomy | High |
| checkout | `checkout_promo_applied_total` | Counter | — | Promo apply attempts (funnel vs redeemed) | Med |
| checkout | `checkout_session_stage_reached_total` | Counter | `stage`=address_set\|shipping_set\|ready | Per-stage funnel drop-off | Med |

### `web` hygiene (all services)

Delete the redundant manual `http.request` span where present (otelgin already
emits the server span); confirm the chain is exactly tracing → logging.

## Security considerations

### Cardinality & PII guardrail — the one rule to internalize

Every metric label and span attribute is either **bounded & safe** or it does
not belong there. This is the single most important review gate in the whole
RFC, so it gets a picture and a table.

*Why it matters:* each distinct label-value combination is a **separate time
series**. A bounded value (`result=success|error`) adds a handful of series; an
unbounded one (`user_id`, `order_id`, an error message) adds *one per value* —
millions — which overflows the SDK's 2000-cap (D-9), blows up storage, and, if
it's an id or email, **leaks PII** into metrics and traces that are searchable
by anyone with a dashboard.

```mermaid
flowchart TD
    V["a value you want to attach<br/>(to a metric label or span attribute)"] --> Q1{"Is the set of possible<br/>values small & fixed?<br/>(e.g. success|error, GET|POST)"}
    Q1 -->|no| LOG["put it in a LOG or a span EVENT<br/>(free-form, not indexed as a series)"]
    Q1 -->|yes| Q2{"Could it ever contain<br/>PII or a secret?<br/>(email, token, name)"}
    Q2 -->|yes| LOG
    Q2 -->|no| OK["OK as a metric label / span attribute"]

    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    class V,Q1,Q2 service;
    class OK data;
    class LOG external;
```

| Value | Label / span-attribute? | Where it goes instead |
|-------|-------------------------|------------------------|
| `result` / `outcome` / `op` / `reason` (fixed enum) | ✅ yes | — |
| `http_route` (matched template, ~20) | ✅ yes | — |
| `channel` = email\|sms, `method` = standard\|express | ✅ yes | — |
| `user_id`, `order_id`, `session_id`, `payment_id` | ❌ never | log / span event (or as the trace's own id) |
| `promo_code`, email, username, token | ❌ never (PII) | redacted log only |
| raw error string / `err.Error()` | ❌ never | log message; use a bounded `error.type` label |
| full SQL text, redis key with an id | ❌ never | trimmed span name (D-1); statement off (D-10) |

**This table is the PR review checklist for every W1–W3 change.** A new label or
attribute that isn't in the left "✅" shape is a blocker.

### Other security notes

- Remove existing `username`/`email` span attributes (auth/user) in W1 (D-2).
- Security-relevant domain events (`auth_login_attempts_total{result=invalid_credentials}`,
  `auth_refresh_operations_total{result=reuse_detected}`) become **alertable** —
  a direct security win over span-event-only visibility.

## Observability & SLO impact

- New series budget: bounded per the label sets above; estimated additive load
  is small relative to the RED baseline (each counter is `services × label
  combinations`, all enumerable). No unbounded label is introduced.
- New alerts: login-failure-rate, refresh-reuse, payment decline-rate,
  saga-compensation-rate (stuck money), cache hit-ratio floor, outbox backlog.
- New SLIs where a domain KPI is a genuine objective (e.g. fulfillment success
  = `saga_outcome_total{outcome=confirmed}` ratio) — via Sloth, following the
  existing pattern.

## Rollout & rollback

**Vertical, one service per PR.** Each service PR fully instruments that service
end to end — core DB tracing + repo-error logs + `web` hygiene + its *basic*
(`Priority: High`) business metrics — so every PR ships a complete, deployable,
reviewable unit (and is the cleanest learning increment). PRs are TDD-first (a
test asserts each instrument records the expected series), source-driven against
the pinned OTel API, gauntlet-reviewed; the shared `pkg` helper gets a
doubt-cycle before the first service adopts it.

- **W0 — `pkg` foundation:** the shared `otelpgx` pool helper with the mandated
  safe defaults (**D-1…D-6**), the `Log(ctx)` helper (**D-12**), and the
  business-metric convention (**D-8, D-9**). **Written fresh/clean — no
  migration shims, no back-compat layer;** the current per-service
  `database.go` pool build is replaced by the shared constructor. Tag `pkg`.
- **W1 — per-service instrumentation** (one PR each, order by criticality:
  **payment → order → auth → product → cart → shipping → review →
  notification → user**; checkout's basics fold in with its funnel additions).
  Each PR: adopt the DB-tracer helper + repo-error logs; drop the redundant
  `http.request` span; remove PII span attrs (**D-2**); add the service's
  **basic** business metrics (the `High` rows).
- **W2 — richer + special surfaces:** the `Med`/`Low` catalog rows; payment
  mockpay-hop tracing (**D-11**); order saga custom metrics; product
  `redisotel` cache hit/miss (**D-10**).
- **W3 — consume it:** fix the stale RED/runtime dashboard (drop dead
  scrape-era panels) and add a **separate** `$app`-templated business-metrics
  dashboard, in both the local-stack json and the cluster `grafana-dashboards`
  repo; alerts + SLOs; finalize docs.

Each PR is independently revertable; W0 lands before any service adopts it.

## Testing / verification

- Per service: `go build` + `go test -race` (instrument-records-series test) +
  golangci-lint + gauntlet; local-stack shows the new metrics in VictoriaMetrics
  and DB child spans in Tempo under the `logic` span.
- Fleet: on `make up`, `count({__name__=~"<svc>_.*"})` shows the new business
  series per service; a Tempo trace of a checkout→order→saga path shows a DB
  span at every hop; the business dashboard renders per `$app`.

## Implementation History

- 2026-07-14 — RFC drafted from a 10-service telemetry audit (3 layers × 3
  signals) + the doc-accuracy pass that exposed the checkout-only business-metric
  gap. `provisional` pending review.
- 2026-07-15 — **W0** landed: `pkg` v0.23.0 — `dbx.NewPool` (otelpgx tracer with
  the D-1…D-6 safe defaults + `RecordStats` pool metrics) and
  `obsx.TraceContext` (native trace_id/span_id on OTLP log records) (pkg#47).
- 2026-07-16 — **W1** landed: all 9 remaining services instrumented vertically
  (dbx adoption, `http.request` span removed, PII span attrs dropped, High-tier
  business metrics); payment#34 was the template.
- 2026-07-16 — **W2** landed: Med/Low business metrics fleet-wide (7 PRs) +
  special surfaces — payment mockpay-hop D-11 (payment#35), product redisotel
  D-10 (product#123); checkout gap closed in one W0+W1+W2 PR (checkout#21).
  Bucket lesson: every non-HTTP seconds histogram needs explicit boundaries.
- 2026-07-16 — **W3** landed: local RED board repaired + Business KPIs board
  (homelab#522/#523/#526); cluster channel switched to the
  `duynhlab/helm-charts` `grafana-dashboards` chart via `configMapRef`
  (helm-charts#15, homelab#527) — the W3 text above predates this and still
  names the retired `grafana-dashboards` repo; legacy board URLs repaired
  (homelab#528).
- 2026-07-16 — **W4** landed (extension beyond the original waves): DB-client
  observability — `obsx.DBDurationBuckets` View fixing
  `db_client_operation_duration_seconds` quantiles (pkg v0.24.0, pkg#48),
  fleet bump ×10, Database dashboard row + 4 `DBClient*`/`PgxPool*` alerts +
  runbook §12 (homelab#524). Fleet released as v1.4.0/v1.3.0/v0.3.0.
- 2026-07-16 (evening) — **Fleet verified on Kind — RFC closed.** Two-round
  `make up` gate: Round 1 clean bring-up in ~24 min (19/19 Kustomizations,
  43/43 HelmReleases), full purchase saga over the Kong HTTPS edge, audit 5/6
  (business series ×10, DB-scale grid + sane p95, chart-fed dashboards + 21
  GrafanaDashboards synced, db-client alert group loaded) — and caught
  **BUGS-1**: both worker manifests hardcoded pre-RFC image tags, so every
  worker-side metric was absent (fixed in homelab#532, workers → 1.4.0/0.3.0).
  Round 2 verified the fix: `order_saga_outcome_total{confirmed}`,
  payment-activity/stock-reservation counters, and `db_client_*`/`pgxpool_*`
  for both workers all live. Business-metric alerts + Sloth SLOs are
  **de-scoped to a follow-up** (the W3 bullet above predates this split);
  the ~16 unimplemented catalog rows remain backlog.
- 2026-07-16 — Status → **implemented**. Shipped catalog documented in
  [metrics-catalog.md](../../../observability/metrics/metrics-catalog.md)
  (34 instruments); design-catalog divergences noted inline above. Remaining
  (not part of this RFC's exit): business-metric alerts + SLOs, unimplemented
  catalog rows (backlog).

## Related

- [RFC-0013](../RFC-0013/) — cardinality audit & streaming-aggregation playbook
  (the bounded-label discipline this RFC enforces).
- [RFC-0014](../RFC-0014/) — full OpenTelemetry adoption (the OTLP-push pipeline
  this RFC builds coverage on top of); [ADR-016](../../adr/ADR-016-otel-metrics-cutover/).
- [RFC-0015](../RFC-0015/) — checkout service, whose P4 business metrics are the
  reference pattern for the `logic`-layer catalog.
- [Application Metrics (RED)](../../../observability/metrics/metrics-apps.md) —
  the metrics-pillar doc this RFC extends with the Business family.

---
_Last updated: 2026-07-14_
