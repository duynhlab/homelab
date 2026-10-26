# RFC-0030 telemetry source audit

Repository review on **2026-10-23**, on macOS. This is source and unit-test
evidence, not proof of telemetry delivered by a deployed cluster. The review
used the `otel-semantic-conventions`, `golang-observability`, Go context and
concurrency, and code-review skills. Repository ADRs override generic skill
naming/sampling defaults.

## Frozen scope

Analytics before this change: `198e1ff60b93fcbb3302539bd5d87ba905aa4677`.
Registry PR: [pkg#130](https://github.com/duynhlab/pkg/pull/130).

Registry/shared package source: `fd56ffb68c7fbce4bcff18c2d555df36cf57874b`.
Homelab baseline: `79dfba9226ee1892785a484e397cf0c291262c2d`.
The final implementation SHAs and check results are recorded in the linked PRs
and [Linux handoff #1266](https://github.com/duynhlab/homelab/issues/1266).

The ten service remote-main snapshots below all pin `obsx v0.48.0`,
`httpmw v0.4.0`, `logger/slogx v0.4.0`, and `dbx v0.40.1`.
Order/checkout also pin `temporalx v0.45.0`. Local service checkouts were older,
so they were not used as evidence for current remote-main instrumentation.
The image column is the **desired configuration in the homelab baseline**, not
a claim that a cluster runs that source SHA. Linux must resolve image digests,
release tags and runtime resource versions before claiming deployed coverage.

| Service | Audited remote-main SHA | Baseline desired image tag |
|---|---|---|
| user-service | [`473acb4f4fbf`](https://github.com/duynhlab/user-service/tree/473acb4f4fbf13c789320d3a490391c7a8299888) | `2.5.1` |
| product-service | [`4a6730bf5658`](https://github.com/duynhlab/product-service/tree/4a6730bf56587056111d66b5484d57ebb6d8559e) | `1.16.1` |
| inventory-service | [`f4b4eff68d5b`](https://github.com/duynhlab/inventory-service/tree/f4b4eff68d5bb5cd98313b5953e767f02163b59d) | `0.9.1` |
| cart-service | [`5b9b69c70242`](https://github.com/duynhlab/cart-service/tree/5b9b69c70242cf8b8ddb00c0c7296af5f2b76285) | `2.4.1` |
| order-service | [`658c7df7c11c`](https://github.com/duynhlab/order-service/tree/658c7df7c11cb7c980a81c10056df7eb976e16d0) | `2.10.2` |
| review-service | [`ed8e4d8d2f46`](https://github.com/duynhlab/review-service/tree/ed8e4d8d2f46018966e42e4b91b222b452da3bc3) | `2.5.0` |
| shipping-service | [`8f1b1066b141`](https://github.com/duynhlab/shipping-service/tree/8f1b1066b14109da093b04fd577be1be250c58d2) | `1.10.0` |
| notification-service | [`9b94ed6d656e`](https://github.com/duynhlab/notification-service/tree/9b94ed6d656e0ab9d1222a81cfacd2de84b02a6e) | `2.4.1` |
| payment-service | [`3cba46481cdd`](https://github.com/duynhlab/payment-service/tree/3cba46481cdde64cc359b3769028bb4a17fea612) | `2.8.0` |
| checkout-service | [`08bfc43b0a39`](https://github.com/duynhlab/checkout-service/tree/08bfc43b0a391056f65ee323cf3d1e254e910a80) | `0.13.2` |

## Findings and disposition

| Severity | Finding / baseline evidence | Impact | Disposition and verification |
|---|---|---|---|
| High | Analytics `internal/logic/v1/service.go:30,145`: request-only lag histogram | Idle portal cannot reveal source lag; old samples look plausible | Replace with idle sampler and gauges; fake-clock threshold/expiry/recovery tests; Linux idle alert gate remains |
| Medium | Analytics `internal/core/repository/clickhouse.go:43`: private duration instrument and no client span | Query latency is outside the standard DB schema; request trace stops before the dependency | Adapter owns standard duration and one client span; parent/child, buckets, bounded attrs, query/scan/close tests |
| Medium | `pkg/semconv/policies/registry.rego`: no analytics namespace or metric definitions | C22 would reject analytics signals | Add namespace owner, three gauges and bounded attributes; upstream DB metrics imported, not redefined; Weaver checks |
| Medium | Analytics service/adapter flatten all failures to a sentinel | Cannot distinguish freshness, data validation, limits, timeout and caller cancellation | Preserve public sentinel with bounded internal reason; sanitized span/metric tests; API response unchanged |
| Medium | Analytics `.github/workflows/check.yml`: integration disabled | SQL execution and integration coverage absent from CI | Existing reusable integration job runs a disposable digest-pinned ClickHouse; actual CI execution remains required |
| Medium | Ten remote-main `cmd/main.go` shutdown functions pass the HTTP drain context to telemetry shutdown | An exhausted drain budget leaves no export budget for final spans/logs | Separate fleet follow-up; analytics cleanup already uses independent bounded contexts |
| Medium | Checkout remote-main `cmd/main.go:101` shuts down worker telemetry with `context.Background()` and discards the error | Worker exit is not explicitly bounded by the application; export failure is hidden | Same fleet follow-up; add worker timeout/error tests outside this PR |
| Low | Draft API example does not state fractional lag; shared naming guide omits planned report exception | Consumer/auditor can infer a false integer or collection requirement | Clarify fraction support and planned ADR-069 exception; no route rename |

The fleet shutdown finding is reproducible from the frozen source: telemetry
shutdown call sites are user:314, product:446, inventory:415, cart:364,
order:887, review:298, shipping:353, notification:365, payment:659 and
checkout:535 in each `cmd/main.go`. Follow the pinned source links above, not
moving line numbers on main. [Issue #1359](https://github.com/duynhlab/homelab/issues/1359) tracks the remediation and
failure-path runtime tests; no fleet code changes are included here.

## Shared-contract review

| Axis | Evidence and conclusion | Limit |
|---|---|---|
| Resource identity | `obsx/setup.go:514–590` merges shared resources; domain ResourceSets set version and pod identity. All ten remote-main entrypoints use shared bootstrap | Desired manifests and source do not prove deployed identity; analytics replica resource wiring is a G8 gate |
| Propagation / sampling | `obsx/setup.go` installs W3C TraceContext+Baggage and ParentBased ratio sampling. Existing HTTP chains use Tracing → Logging → Recovery | No sampling policy changed; cross-process ancestry must be checked in backend |
| HTTP ownership | `httpmw v0.4.0` owns server metrics and canonical status-based access errors; analytics reuses it | No extra HTTP histogram or access log introduced; real OTLP duplication checked in C22 |
| Log correlation / redaction | `slogx` adds trace/span IDs from context and redacts the structured envelope; its existing tests cover both | A recording trace is not guaranteed by head sampling; do not promise a detailed span for every 503 |
| DB ownership | `dbx` uses otelpgx without query parameters/connection details. ClickHouse v2.49.0 `WithSpan` propagates context; adapter adds instrumentation | No new shared DB module for one consumer; server query-log correlation still needs Linux |
| Metrics / buckets | `obsx` has one View dispatcher, named DB buckets and HTTP/RPC cardinality filters; analytics uses those DB boundaries | Registry and SDK tests do not prove backend translation; [budget and queries](README.md#identity-and-cardinality-budget) require runtime measurement |
| Errors / shutdown | Raw ClickHouse exceptions are sanitized; caller cancellation is distinct from deadline/limits. Sampler is joined before pool close | Fleet shutdown context reuse is tracked separately; no blanket fleet pass |
| Sensitive data | Analytics exports fixed source names/query summaries/reasons, no SQL, parameters, user IDs or raw exceptions; tests inject secret markers | Existing service span identifiers are not metric dimensions. This review does not certify every historical log or stored backend record as PII-free |

The fleet review inspected frozen Go sources for telemetry constructors,
HTTP chains, attributes and lifecycle paths; it did not execute every service
or exhaustively prove all business instrumentation. No other shared-contract
change is justified by the reviewed evidence. Keep unrelated findings separate
rather than turn this analytics patch into a fleet migration.

## Verification boundary

Mac checks cover race-tested sampler timing/expiry, invalid batches and recovery,
metric names/types/units/attributes, DB buckets and span ancestry, sanitized
failure reasons, existing API/lifecycle regressions, build/vet/lint, and
integration compilation. Shared obsx tests and Weaver registry
check/generation/diff/lockstep are separate checks.

The alert rules are deployed (`analytics-alerts.yaml`) and were seen firing
and resolving on Kind; a live notification pipeline is still not part of this
audit. Dashboard JSON can be imported, but rendering and real labels are
still Linux gates. CI must execute the disposable ClickHouse SQL suite and
publish integration coverage; total coverage must not be confused with Sonar's
new-code coverage. No release tag, rollout, G8/G10 pass or Adoption completion
is implied. See [Linux qualification](README.md#linux-qualification).
