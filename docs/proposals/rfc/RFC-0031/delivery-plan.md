# RFC-0031 delivery plan — proposed after acceptance

This is a dependency-ordered implementation plan, not evidence of a shipped
cutover. Each task becomes eligible only after RFC-0031 and its resulting ADRs
are accepted.

## Phase 0 — contract approval

### Task 0.0: Decide the logging facade — **done 2026-09-17**

The RFC proposed `pkg/logger/slogx`; the audit recommended keeping `logger/zapx`. The
owner chose **slogx** at architecture review, so the slogx branch runs — Tasks 1.1,
1.1b and 1.1c — and the keep-Zap branch (1.1c′) is dropped. The decision is recorded
in ADR-070 with an explicit statement that acceptance proceeded without the
comparative benchmark the audit asked for; the redaction test suite the audit asked
for remains an acceptance criterion of Task 1.1.

The shared-package rule, the tracing, metrics and profiling contracts, and the fleet
enforcement never depended on this choice; Tasks 1.2 through 1.5 and every later
phase are unchanged.

**Verification:** ADR-070 is `Accepted` and names the facade; this plan carries no
Zap branch.

### Task 0.1: Approve the resulting decisions — **done 2026-09-17**

**Acceptance criteria (met):**

- ADR-070 names `pkg/logger/slogx` and records the pre-1.0 OTel Logs API containment
  and the cutover cost.
- ADR-071 through ADR-076 exist at `Accepted` / Adoption `Not started`, created with
  the RFC per the RFC-0028/RFC-0030 precedent; ADR-076 records the bare-namespace
  decision.
- The target contract is approved with SemConv v1.41.0 as its baseline.

**Verification:** the RFC index row reads `Accepted 2026-09-17` and the ADR index
lists ADR-070 through ADR-076.

### Task 0.2: Freeze the catalog and privacy boundary

**Status — frozen 2026-09-23, owner sign-off by merge.** The catalog, the
access-record severity mapping, the per-field allow / correlation-only / review / deny
classification and the schema owners are in
[`docs/api/logs.md` § Event catalog](../../../api/logs.md#event-catalog). Nineteen names
across the five classes, chosen by the RFC's own admission test — an operator would
query it by name across services — which is why single-service transitions already
counted by a metric are out. The freeze also corrects the gRPC status key to
`rpc.response.status_code`, the one the pinned instrumentation writes.

**Acceptance criteria:**

- Initial event catalog covers access, lifecycle, business decision, retry and compensation classes.
- Each sensitive field has an allow, deny or review classification.
- HTTP, gRPC, Temporal and ClickHouse query schemas have one owner.

**Verification:** owner sign-off against the [normative target contract](./README.md#normative-target-contract).

## Phase 1 — shared foundations

**Execution order (owner OK 2026-09-18): 1.2 → 1.3 → 1.5 → 1.4 → 1.1**, not the
dependency order written into the tasks below. Tasks 1.2 through 1.5 touch `obsx`,
`httpmw` and `grpcx` only and need nothing from the facade, so running them first put
two live defects — the propagator installed only when tracing was enabled, and two
empty profile labels — right weeks earlier, and kept the largest piece (the facade)
from blocking the rest. Each task's own `Dependencies` line is left as it was written;
this paragraph is the deviation, recorded rather than silently taken.

**Prerequisite (ADR-072) — pin convergence done 2026-09-18.** Every `duynhlab/pkg`
module is at its current tag in all ten services (`obsx v0.38.0` fleet-wide, was three
versions), shipped as ten patch releases after a full local-stack E2E audit; the
Dependabot `duynhlab-pkg` group PRs it superseded are closed. The linter converged the same day: `pkg` lints at golangci-lint v2.12.2 (pkg #88), the version the services' shared `go-check.yml` already defaults to — 0 issues across all fourteen modules. ADR-072's first obligation is closed; its Adoption is `Partial`.

### Task 1.1: Build pkg/logger/slogx

**Status — DONE 2026-09-23: `logger/slogx/v0.1.0` tagged** (pkg #97, #98, #99, #100,
four PRs: core + stdout envelope, the redaction boundary, the OTLP sink and `Event`,
then `Err` with the API-surface guard and `docs/MIGRATION-slogx.md`). Every acceptance
criterion below is met and tested; no service has adopted it, which is Phase 3. Two
things the plan did not foresee, both recorded in the ADRs: the instrumentation scope
is the facade's package path, not the service name, and the six envelope keys are
reserved so a caller attribute cannot make stdout and OTLP disagree about one record.
One gap carried forward: `obsx` exposes no log force-flush, so the `Config.Flush` seam
that lets a FATAL record leave the process has nothing to wire to yet. *Both closed since:
`obsx v0.45.0` added `ForceFlush` (Task 1.1c-B) and Phase 3 adopted the facade fleet-wide;
`logger/slogx v0.2.0` added `ProcessStarted`/`ProcessStopped`.*

**Acceptance criteria:**

- The module lands at `logger/slogx` with its own `go.mod` and its own
  `logger/slogx/v<semver>` tag, as a sibling of `logger/zapx`. No top-level or
  `logger/` parent module is created.
- The module imports the OTel **API** only; a `depguard` run proves it links neither
  `go.opentelemetry.io/otel/sdk` nor `pkg/obsx`.
- Stable event naming, severity mapping, safe stdout JSON and OTLP record are emitted from one facade.
- Redaction runs before both sinks and is tested for nested values and errors.
- Direct Zap and otelzap application usage has a documented removal path.

**Verification:** package unit tests, `make test-logger:slogx`, and a disposable
Collector-to-ClickHouse integration test.

### Task 1.1b: Retire the unused logger adapters

**Status — DONE 2026-09-24: pkg #108.** `logger/zapx`, `logger/zerolog` and
`logger/clog` left the tree once no service `go.mod` required `zapx`; pkg lists 12
modules. Their last tags (`zapx v0.36.1`, `zerolog v0.36.2`, `clog v0.36.2`) still
resolve, and `docs/api/pkg.md` records them.

`logger/zapx` is the only adapter any service imports; `logger/zerolog` and
`logger/clog` have no consumers. Shipping `slogx` beside two dead adapters leaves
four logger modules where one is used.

**Acceptance criteria:**

- `logger/zerolog` and `logger/clog` are removed in the same release that retires
  `logger/zapx` from the fleet.
- The shared-package contract records which adapter each historical tag belongs to,
  so an old service pin still resolves.

**Dependencies:** Task 1.1, and the fleet migration in Phase 3 before `zapx` itself
is retired.

**Verification:** no service `go.mod` references a removed module; `make modules`
lists the expected set.

### Task 1.1c: Close the type leaks in the shared package's public API

**Status — DONE 2026-09-23: 1.1c-B shipped as `obsx/v0.45.0`** (pkg #103): `ZapCore`,
`TraceContext` and the otelzap dependency are gone and `ForceFlush` backs the facade's
FATAL path. The fleet moved onto it with Phase 3.

**Earlier — split 2026-09-18 (owner OK): 1.1c-A done; 1.1c-B is now unblocked — Task 1.1 shipped `logger/slogx` v0.1.0 on 2026-09-23, so `ZapCore`, `TraceContext` and the otelzap dependency can go once the fleet has cut over in Phase 3.**
Removing `ZapCore` before the slogx facade exists would take OTLP logs away from every
service, so the non-logging leaks went first. **1.1c-A** shipped as `obsx/v0.39.2`
(`Enabled() Signals`, API-typed `TracerProvider()/MeterProvider()/LoggerProvider()`,
`WithTracerProviderFactory(func(TracerProviderConfig) ShutdownTracerProvider)` with
`SDKOptions()` as the one allowlisted SDK type, `obsx/api_surface_test.go` guarding the
surface) and a ten-service wave after a full local-stack audit — no `cmd/main.go`
imports `otel/sdk/*` any more. The fleet lint policy channel (shared-workflows
`golangci-policy.yml` + `policy-lint` inputs on `go-check.yml`, checked out at the
workflow's pinned SHA) is merged with **no `cmd/**` exemption**; service opt-in is
rolling out non-blocking. **1.1c-B** — `ZapCore`, `TraceContext`, `otelzap` and `zap`
leave `obsx` in the same release train as Task 1.1.

The fleet rule "a service imports only the shared package and the OTel API" cannot
be enforced while the shared package itself forces `main()` to import SDK and Zap
types. Today `obsx.WithTracerProviderFactory` takes
`func(...sdktrace.TracerProviderOption)`, `obsx.ZapCore` returns `zapcore.Core`, and
`obsx.TraceContext` returns `zap.Field`; every service `cmd/main.go` imports
`go.opentelemetry.io/otel/sdk/trace`, `go.uber.org/zap` and `go.uber.org/zap/zapcore`
solely to call them. `obsx` is also the fleet's `otelzap` consumer
(`obsx.ZapCore` wraps `otelzap.NewCore`).

**Acceptance criteria:**

- `obsx` exposes no `go.opentelemetry.io/otel/sdk/*`, `go.uber.org/zap` or
  `go.uber.org/zap/zapcore` type in any exported signature. The tracer-provider seam
  takes an opaque option or returns the API `trace.TracerProvider`; the log bridge is
  constructed inside the facade the Task 0.0 decision selects.
- `obsx` drops its `otelzap` dependency when the slogx outcome is chosen; under the
  keep-Zap outcome it keeps the bridge but still removes the zap-typed public API.
- This is a **breaking** `obsx` release with a migration note; every service `cmd/main.go`
  is updated in Phase 3.
- The fleet lint policy's `!cmd/**` exemption is removed in the same release train.

**Dependencies:** Task 0.0; Task 1.1 when slogx is chosen.

**Verification:** a `depguard` run over `obsx` and over each migrated service's
`cmd/` passes with no `cmd/**` exemption; `go doc` of the exported `obsx` API shows
no SDK or Zap type.

### Task 1.2: Repair correlation and resource identity

**Status — DONE 2026-09-21: `obsx v0.41.0` + homelab #1072.** The W3C propagator is
installed unconditionally, so extraction and injection work with every exporter
disabled; one `resourceAttributes` function is now the single source the tracer,
meter, logger and (from v0.44.0) the profiler read; `service.version` reaches the five
domain ResourceSets from `image_tag` and `mockpay` gained the telemetry environment it
lacked.

**Acceptance criteria:**

- W3C extraction/injection works with all exporters disabled.
- API services and workers emit service name, version and environment consistently.
  The version source for domain services is the existing `image_tag` input, wired
  into `OTEL_RESOURCE_ATTRIBUTES` as `service.version` in the domain ResourceSets;
  `mockpay` gets an explicit version input because its image is hand-pinned.
- Kubernetes identity keeps its current mechanism — Downward API into
  `K8S_NAMESPACE_NAME` / `K8S_POD_NAME` / `DEPLOYMENT_ENVIRONMENT`, mapped by the
  shared package — and the contract lists exactly the three attributes that mechanism
  produces. Adding collector-side `k8sattributes` enrichment is decided in Phase 4.
- Shutdown flush is bounded and follows readiness/work draining.

**Dependencies:** Task 1.1.

**Verification:** provider-disabled test, resource assertions and graceful-shutdown test.

### Task 1.3: Enforce the metrics contract

**Status — DONE 2026-09-21: `obsx v0.42.0`.** One dispatching View applies the fleet
boundaries to every histogram whose unit is `s`, which covers the Temporal SDK and
gRPC latencies a per-name View never reached. The planned `forbidigo` rule is
withdrawn (ADR-073 amended). The two known gaps already declared the unit, so no
service changed. Cardinality allowlist tests and the budget dashboard remain open.

**Acceptance criteria:**

- Shared HTTP, gRPC, runtime, DB and cache instruments remain the only automatic sources.
- Every business metric has bounded attributes, unit, ownership and replay semantics.
- The two known seconds histograms receive reviewed boundaries based on SLOs or measured ranges.

**Dependencies:** Task 1.2.

**Verification:** metric-reader tests, cardinality allowlist tests and VictoriaMetrics p50/p95/p99 queries.

### Task 1.4: Enforce the profiling contract

**Status — DONE 2026-09-21: `obsx v0.44.0` + homelab #1073.** The four profile labels
come from the same resource attributes every other signal reads, so
`deployment_environment` and `service_version` — measured empty when the ADR was
written — carry values; `PROFILING_ENABLED` is a per-service ResourceSet input.
Verifying the label set on Kind is part of the Phase 1 checkpoint.

**Acceptance criteria:**

- All services and both worker modes use one shared profiler lifecycle.
- Profiles expose only the approved service, namespace, environment and version labels.
- The profiler derives those labels from the same resource the tracer and meter use.
  Today it re-parses `OTEL_RESOURCE_ATTRIBUTES` for the deprecated key
  `deployment.environment`, which no manifest sets, so `deployment_environment` is
  empty fleet-wide; after this task both `deployment_environment` and
  `service_version` are populated on every process, verified by a Pyroscope
  label-values query.
- The labels the SDK adds outside the contract — `pyroscope_spy` and `span_name` on
  every application profile, plus `hostname`, `target`, `service_git_ref` and
  `service_repository` where the SDK's environment supplies them — are each admitted
  to the contract or stripped in the shared helper; a Pyroscope label-names query
  scoped to each service after this task returns exactly the admitted set. The
  profiling agent's self-scrape series are excluded from that check by service name.
- Profiling failure/disable paths preserve readiness, and runtime sampling changes have benchmark evidence.

**Dependencies:** Task 1.2.

**Verification:** Pyroscope ingestion test, profile-label query, disable/failure test and trace-to-profile manual-pivot check.

### Task 1.5: Enforce the tracing contract

**Status — DONE 2026-09-21: `obsx v0.43.0`.** `RecordError` sets Error with
`error.type` taken from the cause's concrete type and records one exception event with
a rune-safe bounded message and **no stacktrace**; `RecordOutcome` records a business
rejection under `outcome` with the status left unset. Skip lists are pinned by golden
tests and a middleware test proves no baggage is set. Edge sampling assertions remain
open.

**Acceptance criteria:**

- The sampling table in the RFC matches the edge configuration each environment
  actually applies; a change to any rate is reviewed as a volume and cost change.
- Every manual span created through the shared helper carries exactly one kind that
  matches its layer and a package-path instrumentation scope; a wrapper span around
  already-instrumented work fails review.
- Span status follows the recording-errors rule: unset for an expected business
  rejection, Error plus `error.type` for an unexpected failure; exceptions use the
  standard exception span event with bounded attributes.
- No application baggage key is set without a registered review, and no key carries
  PII, tokens or secrets.
- The probe and health skip-list is one shared list pinned by a unit test that the
  trace and metric paths both read.

**Dependencies:** Task 1.2.

**Verification:** sampling assertion against the applied edge config, span-kind and
scope tests in the shared helper, an error-status contract test with one expected
rejection and one unexpected failure, a baggage-denylist test, and the shared
skip-list test.

## Checkpoint — shared package

- Shared package tests pass.
- No resource or propagation regression is accepted.
- Contract tests can assert a stable event name in ClickHouse.
- Metrics are queryable in VictoriaMetrics with bounded series.
- CPU and heap profiles are queryable in Pyroscope with the expected labels.

## Phase 2 — transport and worker adapters

**Status — DONE 2026-09-23: pkg #102** — `httpmw/v0.2.0` (access record with the
canonical keys, `Recovery`), `grpcx/v0.37.0` (the gRPC access record), `temporalx/v0.40.0`
(SDK logs on the service slog logger); `temporalx` then grew the start-event interceptor,
`WorkflowFailed` and `WorkflowEvent` (v0.41.0–v0.42.0) and the SDK error shape
(v0.43.0).

### Task 2.1: Replace HTTP and gRPC access logging

**Acceptance criteria:**

- Exactly one completed summary per non-probe call.
- HTTP/gRPC use the canonical semantic attributes and no raw path, IP, full User-Agent or peer address.
- Access outcome severity follows the approved mapping.

**Dependencies:** Task 1.2.

**Verification:** route, gRPC status, failed-probe and trace-correlation contract tests.

### Task 2.2: Add Temporal-safe adapter

**Acceptance criteria:**

- Workflow logging is replay safe and performs no exporter side effect.
- Activities emit contextual terminal retry and compensation records.
- Workflow/run identifiers cannot become metric or profile labels.

**Dependencies:** Task 1.2.

**Verification:** workflow replay test, activity retry/compensation test and worker shutdown test.

## Checkpoint — shared boundaries

- HTTP, gRPC and Temporal contracts are proven before any service-specific migration.
- Existing idempotency, deadline and compensation behavior remains unchanged.

## Phase 3 — service migration slices

**Status — DONE 2026-09-24: one release train, not three.** All ten services, both
workers and mockpay were cut over on branches reviewed in the three batches below, then
gated together by one full compose audit (Phase A 90/90, browser checkout, Phase C, six k6
suites, privacy on stdout and in ClickHouse, 15 event names observed) and released as
`user v2.3.0` · `product v1.14.0` · `inventory v0.7.0` · `cart v2.2.0` · `order v2.8.0` ·
`review v2.2.0` · `shipping v1.7.0` · `notification v2.2.0` · `payment v2.4.0` ·
`checkout v0.11.0` (homelab #1088). The Kind checkpoint passed the same day
(`docs/platform/kind-e2e-audit.md`): no binary links zap, the catalog events land in
ClickHouse with trace ids, and propagation holds through a service with tracing off.
mockpay started its profiler only in `payment v2.4.1` (Task 4.2).

### Task 3.1: Migrate user, product, inventory and cart

**Acceptance criteria:**

- All production logging call sites use the new facade.
- Named domain events have approved schemas.
- Existing automatic RED/RPC metrics are not duplicated.

**Dependencies:** Tasks 2.1 and 2.2 where applicable.

**Verification:** focused service tests and contract-record fixtures.

### Task 3.2: Migrate order, payment, shipping and notification

**Acceptance criteria:**

- Saga decision, retry exhaustion and compensation ownership follow the target contract.
- Payment/provider errors retain safe error.type and never reveal tokens or provider payloads.
- Temporal worker activity records correlate with their trace.

**Dependencies:** Task 3.1 and Task 2.2.

**Verification:** saga replay, provider failure and compensation drills.

### Task 3.3: Migrate review, checkout and mockpay

**Acceptance criteria:**

- Checkout's idempotency, required token redaction and abandonment workflow remain intact.
- Expected business rejections remain distinguishable from infrastructure failure.
- Mockpay is onboarded to the shared package from zero: its manifest gains the same
  telemetry environment as a domain service (`OTEL_SERVICE_NAME`, collector endpoint,
  per-signal enable flags, `DEPLOYMENT_ENVIRONMENT`, `K8S_*`, `PROFILING_ENABLED`) and
  an explicit version input, and it then follows the same safe provider logging
  contract.

**Dependencies:** Task 3.2.

**Verification:** browser checkout, duplicate confirm, price/stock rejection and abandonment tests.

## Checkpoint — full fleet

- No service, worker or mockpay production import uses Zap or otelzap.
- No legacy access key remains in emitted fixtures; the `event` attribute is present on every named record.
- Full service-repository test suites pass at their pinned package version.

## Phase 4 — analytics and operations

### Task 4.1: Migrate ClickHouse and Grafana consumers

**Status — DONE 2026-09-24 (homelab #1088).** The three local-stack ClickHouse boards
read the canonical keys (`http.route`, `http.response.status_code`, `rpc.method`,
`event`), the duplicate `dashboards/ClickHouse/` tree is gone, and the board SQL returns
data on the train gate.

**Acceptance criteria:**

- Dashboards, SQL examples, panel variables and trace-log pivots use canonical attributes.
- Removed access fields are absent from current queries and runbooks.
- The duplicate `dashboards/ClickHouse/` tree is deleted, so no unfixed byte-identical copy survives the migration.
- Event and trace queries work across the 90-day ClickHouse retention tier.

**Dependencies:** Phase 3.

**Verification:** query regression suite, rendered dashboard review and a seeded ClickHouse fixture.

### Task 4.2: Verify VictoriaMetrics and Pyroscope consumers

**Status — DONE 2026-09-24 (verified on Kind).** The four business histograms
(checkout confirm, notification send, mockpay hop, order value) are on fleet-View
or minor-unit buckets, and their panels show p50/p95/p99 on the v2 and local-stack
boards; the classic chart board follows with `duynhlab/helm-charts` #25 (the cluster
picks it up on release, `semver >=0.2.0`). Every expression returns ordered quantiles on Kind. The two RED sources
have one job each (`docs/api/metrics.md`). Pyroscope has all 13 identities:
mockpay was missing until payment v2.4.1 started its profiler, and now carries
the four labels. The manual trace→profile pivot and a per-type investigation
table are documented. One limit is recorded rather than fixed: the four Temporal
identities carry no `span_name`, by obsx's replay-safe design.

**Acceptance criteria:**

- Application and span-derived metrics have documented, non-duplicated operational uses.
- Business histogram panels use meaningful buckets and expose p50/p95/p99.
- Pyroscope CPU, heap, allocation, goroutine, mutex and block investigations are documented and the manual trace pivot is accurate.

**Dependencies:** Phase 3.

**Verification:** PromQL regression checks, profile queries, alert-rule validation and rendered runbook review.

### Task 4.3: Publish as-built contracts

**Status — DONE 2026-09-24.** The seven files — `observability.md`, `logs.md`,
`tracing.md`, `metrics.md`, `profiling.md`, `pkg.md`, `temporal.md` — plus
`graceful-shutdown.md` describe the deployed facade, access records, event catalog,
collector enrichment and profile identity, each claim checked against the pkg and
service code or measured on Kind. What is not built stays **planned**: the Weaver
registry (Task 4.5), the fleet lint policy's enforcement (no service opts into
`policy-lint`), and the metrics denylist and series-budget tests. `pkg.md` records which
logger each historical tag belongs to (Task 1.1b). Per-service contracts needed no change:
their only snake_case keys are API payload fields, not log keys. Two code facts found
on the way are recorded rather than fixed: inventory mounts `httpmw.Logging`/`Recovery`
but not `Tracing`, and payment's `[GIN-debug]` route lines reach stdout because
`GIN_MODE` is unset.

**Acceptance criteria:**

- The seven `docs/api/` files this RFC names — `observability.md`, `logs.md`,
  `tracing.md`, `metrics.md`, `profiling.md`, `pkg.md`, `temporal.md` — and the
  per-service contracts describe only verified deployed behavior.
- The event catalog and migration evidence are linked from the proper owners.
- Platform runbooks and dashboards document investigation paths.

**Dependencies:** Tasks 4.1 and 4.2.

**Verification:** docs ownership review, Mermaid rendering and link checks.

### Task 4.4: Collector enrichment, schema debt and the span-metrics dimension

**Status — DONE 2026-09-24 (verified on Kind).** ADR-057 amended: the connector
declares both `http.method` and `http.request.method`; service spans now carry the
method and no series carries both. A `k8sattributes` processor (pod association by
the SDK's pod name + namespace, then connection IP) plus `resource/cluster` on both
logs pipelines fill all seven materialised `k8s.*` columns on every application
record (the edge lacks only the container name) — kept off `traces`/`metrics`
because span-metrics labels every resource attribute. The one SDK-side addition,
`k8s.container.name` on service pods, does reach spans and RED series as a constant
label; the RFC's resource-contract and admission sections carry dated amendments. The edge-log exception was already explicit in
`docs/observability/logging/README.md` (ADR-061).

**Acceptance criteria:**

- A decision is recorded, as an amendment to the span-metrics decision record, on
  the connector's `http.method` dimension: rename it to the pinned convention's
  `http.request.method`, or declare both for as long as the edge emits the older name,
  with the live measurement from research as the evidence.
- The five materialised `k8s.*` columns that no producer writes are either populated
  by a collector `k8sattributes` processor with pod association, or removed from the
  schema; the choice is recorded with the collector topology it implies.
- The routing documentation states the edge-log exception explicitly.

**Dependencies:** Task 4.1.

**Verification:** a span-metrics series carries a non-empty method dimension for a
service span; a ClickHouse query shows no materialised column that is empty for every
record.

### Task 4.5: Platform semantic-convention registry

**Acceptance criteria:**

- A Weaver registry in the shared-package repository declares every platform-owned
  attribute, metric and event, with a manifest that depends on the upstream semantic
  conventions at the version `obsx` pins and imports the standard attributes it reuses.
- The namespace decision from ADR-076 is enforced by a Rego policy in
  `weaver registry check`, and that check runs in the shared package's CI.
- The shared package's attribute keys and metric names are **generated** from the
  registry; the catalog sections of `docs/api/` are generated from the same source.
- `weaver registry live-check` runs against local-stack OTLP output in the end-to-end
  gate and exits non-zero on a violation; a new service is "instrumented" when it
  passes.

**Dependencies:** Phase 3 (the fleet is on one shared-package version), Task 0.1
(ADR-076 accepted).

**Verification:** `registry check` green in CI; a deliberately mis-named attribute in
a branch fails it; `live-check` green against the compose gate; `registry diff`
between two tags reports a planted rename.

## Final release gate

- Compose E2E audit passes HTTP, gRPC, browser checkout, Temporal workflow and provider failure cases.
- Kind E2E audit passes the equivalent deployed paths.
- One trace-to-log and one log-to-trace investigation succeeds in both operational and ClickHouse retention windows.
- The privacy regression suite shows no forbidden field at stdout, Collector or ClickHouse.
- VictoriaMetrics receives bounded application series and Pyroscope receives profiles from all service and worker identities, mockpay included, each carrying all four approved labels with non-empty values.
- The release has no dual-write or legacy dashboard compatibility path.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| OTel Go Logs API changes before v1 | Shared package churn | Contain direct API use in slogx and version-pin integration tests |
| Partial fleet migration | Two incompatible query contracts | Promote only after all service, worker, dashboard and runbook gates pass |
| Temporal replay duplicates telemetry | Misleading events and metric overcount | Use workflow-aware logger; test replay; emit side-effect telemetry only from activities |
| Redaction bypass | Sensitive data reaches retained stores | One recursive boundary, deny-list tests and fixtures through both sinks |
| SemConv drift | Broken dashboards and cardinality growth | Keep v1.41 baseline; upgrade through an explicit obsx release and query migration |
| Metric label growth | VictoriaMetrics series and query cost increase | Enforce label allowlists, reject identifiers and measure active series before promotion |
| Profiling overhead | CPU, allocation or lock sampling changes service behavior | Keep one centrally owned configuration and require representative benchmarks for sampling changes |

---
_Last updated: 2026-09-24 — Phases 2–3 and Tasks 1.1b, 1.1c-B, 4.1–4.4 recorded as built; only Task 4.5 (Weaver registry) and the Final release gate remain. Previously 2026-09-23 — Phase 1 recorded as built: Tasks 1.2, 1.3, 1.5 and 1.4 shipped in obsx v0.41.0 through v0.44.0, Task 1.1 shipped as `logger/slogx` v0.1.0, and the execution order actually taken (1.2→1.3→1.5→1.4→1.1) is stated at the head of the phase. Previously 2026-09-18 — Task 1.1c split into A (done — obsx v0.39.2, fleet wave, lint policy channel) and B (with slogx). Previously 2026-09-18 — Phase 1 prerequisite (ADR-072 pin convergence) recorded as done 2026-09-18 with the ten service releases. Previously 2026-09-17 — Tasks 0.0 and 0.1 closed by acceptance on 2026-09-17; Phase 1 eligible. third revision. Task 0.0 branches the plan on the facade decision; Task 1.1c closes the shared package's SDK and Zap type leaks; Task 1.5 enforces the tracing contract; Tasks 4.4 and 4.5 add Collector enrichment, the span-metrics dimension amendment and the Weaver registry; mockpay onboarding and the `image_tag` version source are explicit; the plan is greenfield with no migration mechanism. Earlier the same day: facade renamed to `pkg/logger/slogx`, Task 1.1b retires the unused adapters._
