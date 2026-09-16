# RFC-0031 delivery plan — proposed after acceptance

This is a dependency-ordered implementation plan, not evidence of a shipped
cutover. Each task becomes eligible only after RFC-0031 and its resulting ADRs
are accepted.

## Phase 0 — contract approval

### Task 0.1: Approve the logging facade decision

**Acceptance criteria:**

- The ADR names pkg/obslog as the sole service-facing facade.
- The ADR records the pre-1.0 OTel Logs API containment and the clean-cutover cost.
- The target contract is approved with SemConv v1.41.0 as its baseline.

**Verification:** architecture review approves the five resulting ADRs.

### Task 0.2: Freeze the catalog and privacy boundary

**Acceptance criteria:**

- Initial event catalog covers access, lifecycle, business decision, retry and compensation classes.
- Each sensitive field has an allow, deny or review classification.
- HTTP, gRPC, Temporal and ClickHouse query schemas have one owner.

**Verification:** owner sign-off against the [normative target contract](./README.md#normative-target-contract).

## Phase 1 — shared foundations

### Task 1.1: Build pkg/obslog

**Acceptance criteria:**

- Native EventName, severity mapping, safe stdout JSON and OTLP record are emitted from one facade.
- Redaction runs before both sinks and is tested for nested values and errors.
- Direct Zap and otelzap application usage has a documented removal path.

**Verification:** package unit tests and disposable Collector-to-ClickHouse integration test.

### Task 1.2: Repair correlation and resource identity

**Acceptance criteria:**

- W3C extraction/injection works with all exporters disabled.
- API services and workers emit service name, version and environment consistently.
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
- Profiling failure/disable paths preserve readiness, and runtime sampling changes have benchmark evidence.

**Dependencies:** Task 1.2.

**Verification:** Pyroscope ingestion test, profile-label query, disable/failure test and trace-to-profile manual-pivot check.

## Checkpoint — shared package

- Shared package tests pass.
- No resource or propagation regression is accepted.
- Contract tests can assert native EventName in ClickHouse.
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
- Mockpay follows the same safe provider logging contract.

**Dependencies:** Task 3.2.

**Verification:** browser checkout, duplicate confirm, price/stock rejection and abandonment tests.

## Checkpoint — full fleet

- No service, worker or mockpay production import uses Zap or otelzap.
- No legacy event or access key remains in emitted fixtures.
- Full service-repository test suites pass at their pinned package version.

## Phase 4 — analytics and operations

### Task 4.1: Migrate ClickHouse and Grafana consumers

**Acceptance criteria:**

- Dashboards, SQL examples, panel variables and trace-log pivots use EventName and canonical attributes.
- Removed access fields are absent from current queries and runbooks.
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
- VictoriaMetrics receives bounded application series and Pyroscope receives profiles from all service and worker identities.
- The release has no dual-write or legacy dashboard compatibility path.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| OTel Go Logs API changes before v1 | Shared package churn | Contain direct API use in obslog and version-pin integration tests |
| Partial fleet migration | Two incompatible query contracts | Promote only after all service, worker, dashboard and runbook gates pass |
| Temporal replay duplicates telemetry | Misleading events and metric overcount | Use workflow-aware logger; test replay; emit side-effect telemetry only from activities |
| Redaction bypass | Sensitive data reaches retained stores | One recursive boundary, deny-list tests and fixtures through both sinks |
| SemConv drift | Broken dashboards and cardinality growth | Keep v1.41 baseline; upgrade through an explicit obsx release and query migration |
| Metric label growth | VictoriaMetrics series and query cost increase | Enforce label allowlists, reject identifiers and measure active series before promotion |
| Profiling overhead | CPU, allocation or lock sampling changes service behavior | Keep one centrally owned configuration and require representative benchmarks for sampling changes |

---
_Last updated: 2026-09-16_
