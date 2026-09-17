# RFC-0031 delivery plan — proposed after acceptance

This is a dependency-ordered implementation plan, not evidence of a shipped
cutover. Each task becomes eligible only after RFC-0031 and its resulting ADRs
are accepted.

## Phase 0 — contract approval

### Task 0.0: Decide the logging facade

The RFC proposes `pkg/logger/slogx`; the audit recommends keeping `logger/zapx`. The
decision belongs to architecture review, and this plan has to be executable either
way, so it branches here.

| Outcome | Phase 1 tasks that run | Tasks that are dropped |
|---|---|---|
| **slogx** (RFC proposal) | 1.1 build `slogx`, 1.1b retire unused adapters, 1.1c `obsx` drops its zap-typed API | — |
| **Keep Zap** (audit recommendation) | 1.1c′ add the central redaction boundary and the stable event helper to `logger/zapx`; 1.1c still runs for the SDK-type leak only | 1.1, 1.1b |

Either outcome leaves Tasks 1.2 through 1.5 and every later phase unchanged. The
shared-package rule, the tracing, metrics and profiling contracts, and the fleet
enforcement do not depend on which logger sits behind the facade.

**Verification:** the decision is recorded in ADR-070 with the evidence the audit
asked for — a benchmark of both facades under fleet log volume and a redaction test
suite both pass — or with an explicit statement that acceptance proceeds without it.

### Task 0.1: Approve the resulting decisions

**Acceptance criteria:**

- ADR-070 names the facade chosen in Task 0.0 and records the pre-1.0 OTel Logs API
  containment and the cutover cost.
- ADR-071 through ADR-076 are created at `Proposed` and reviewed together.
- The target contract is approved with SemConv v1.41.0 as its baseline.

**Verification:** architecture review approves the seven resulting ADRs, ADR-070 through ADR-076.

### Task 0.2: Freeze the catalog and privacy boundary

**Acceptance criteria:**

- Initial event catalog covers access, lifecycle, business decision, retry and compensation classes.
- Each sensitive field has an allow, deny or review classification.
- HTTP, gRPC, Temporal and ClickHouse query schemas have one owner.

**Verification:** owner sign-off against the [normative target contract](./README.md#normative-target-contract).

## Phase 1 — shared foundations

### Task 1.1: Build pkg/logger/slogx

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

**Acceptance criteria:**

- Shared HTTP, gRPC, runtime, DB and cache instruments remain the only automatic sources.
- Every business metric has bounded attributes, unit, ownership and replay semantics.
- The two known seconds histograms receive reviewed boundaries based on SLOs or measured ranges.

**Dependencies:** Task 1.2.

**Verification:** metric-reader tests, cardinality allowlist tests and VictoriaMetrics p50/p95/p99 queries.

### Task 1.4: Enforce the profiling contract

**Acceptance criteria:**

- All services and both worker modes use one shared profiler lifecycle.
- Profiles expose only the approved service, namespace, environment and version labels.
- The profiler derives those labels from the same resource the tracer and meter use.
  Today it re-parses `OTEL_RESOURCE_ATTRIBUTES` for the deprecated key
  `deployment.environment`, which no manifest sets, so `deployment_environment` is
  empty fleet-wide; after this task both `deployment_environment` and
  `service_version` are populated on every process, verified by a Pyroscope
  label-values query.
- Profiling failure/disable paths preserve readiness, and runtime sampling changes have benchmark evidence.

**Dependencies:** Task 1.2.

**Verification:** Pyroscope ingestion test, profile-label query, disable/failure test and trace-to-profile manual-pivot check.

### Task 1.5: Enforce the tracing contract

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

**Acceptance criteria:**

- Dashboards, SQL examples, panel variables and trace-log pivots use canonical attributes.
- Removed access fields are absent from current queries and runbooks.
- The duplicate `dashboards/ClickHouse/` tree is deleted, so no unfixed byte-identical copy survives the migration.
- Event and trace queries work across the 90-day ClickHouse retention tier.

**Dependencies:** Phase 3.

**Verification:** query regression suite, rendered dashboard review and a seeded ClickHouse fixture.

### Task 4.2: Verify VictoriaMetrics and Pyroscope consumers

**Acceptance criteria:**

- Application and span-derived metrics have documented, non-duplicated operational uses.
- Business histogram panels use meaningful buckets and expose p50/p95/p99.
- Pyroscope CPU, heap, allocation, goroutine, mutex and block investigations are documented and the manual trace pivot is accurate.

**Dependencies:** Phase 3.

**Verification:** PromQL regression checks, profile queries, alert-rule validation and rendered runbook review.

### Task 4.3: Publish as-built contracts

**Acceptance criteria:**

- docs/api logging, observability, tracing, metrics, temporal and service references describe only verified deployed behavior.
- The event catalog and migration evidence are linked from the proper owners.
- Platform runbooks and dashboards document investigation paths.

**Dependencies:** Tasks 4.1 and 4.2.

**Verification:** docs ownership review, Mermaid rendering and link checks.

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
_Last updated: 2026-09-17 — facade renamed to `pkg/logger/slogx`; module placement and depguard criteria added to Task 1.1; Task 1.1b retires the unused `logger/zerolog` and `logger/clog` adapters; the log-record representation question is out of scope, so named records keep the deployed `event` attribute._
