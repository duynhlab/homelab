# Telemetry standards audit

_Audit date: 2026-09-16. Sources: homelab `26f92780`; service SHAs recorded below. This is a static code/config audit; no live cluster or ClickHouse query was run. The normative application contract in `docs/api/` was reviewed after the initial draft and the conclusions below incorporate it._

## Executive assessment

The proposed direction is sound, but it mixes three different contracts: the OpenTelemetry data model, an application coding convention, and backend/storage policy. The fleet already emits OTLP logs, traces, and metrics through `pkg/obsx`; it is not currently a `slog` fleet. Migrating Zap solely to satisfy OTel would add risk without improving conformance. The highest-value gaps are event identity, redaction, propagation when tracing export is disabled, and a small number of metric histogram definitions.

OpenTelemetry LogRecords have top-level `Timestamp`, `ObservedTimestamp`, trace context, severity, body, resource, scope, attributes, and `EventName`; `EventName` is optional rather than mandatory for every record. The data model is independent of the Go logging API. See the [OTel Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/), [event conventions](https://opentelemetry.io/docs/specs/semconv/general/events/), and [Metrics Data Model](https://opentelemetry.io/docs/specs/otel/metrics/data-model/).

## Inventory and evidence

| Area | Observed state | Assessment |
|---|---|---|
| Profiling | All ten services call `obsx.SetupProfiling`; both worker modes use the same binaries and enable profiling. The SDK is configured to push ten Go profile types directly to Pyroscope. | **Implemented with contract gaps.** The four-label allowlist exists, but API services lack `service.version`, runtime sampling has no reviewed overhead budget, and Grafana's VictoriaTraces datasource supports only a manual trace-to-profile pivot. |
| Logger | All active services pin `github.com/duynhlab/pkg/logger/zapx v0.36.0`; OTLP bridge is `otelzap`. | **Conformant transport, insufficient target interface.** OTel conformance alone does not require migration, but RFC-0031 selects `slogx` to enforce native EventName, redaction and one fleet API if accepted. |
| Logs | HTTP middleware emits JSON and native OTLP trace IDs; gRPC access logs use `trace_id`, `method`, `code`, `duration`. | **Partial.** No production call sites use `EventName`/`event.name`; HTTP fields are `method`, `path`, `status`, rather than the OTel HTTP names. |
| Resource | Kubernetes templates set `OTEL_SERVICE_NAME`, namespace, pod, and environment; workers additionally set `service.version` from build ID. | **Partial.** `service.version` is not consistently supplied to API services; `cloud.region` is not established. |
| Tracing | HTTP middleware, gRPC interceptors, DB instrumentation, and Temporal workers are present. | **Partial.** W3C propagator is installed only inside the enabled tracer-provider branch. Export-disabled processes can therefore lose inbound/outbound propagation. |
| Metrics | The pipeline routes OTLP application metrics through the Collector to VictoriaMetrics; the Collector span-metrics connector has explicit buckets. The application contract says exemplars are not available on this platform. | **Mostly conformant.** `order.inventory.commit_lag` and `payment.reconciliation.run.duration` rely on SDK default histogram boundaries; do not promise application exemplars. |
| ClickHouse | Collector exports OTel logs/traces to `otel.otel_logs` and `otel.otel_traces`; schema stores `EventName`, resource attributes, log attributes, severity, and trace fields. | **Good storage shape.** ClickHouse is supplementary OLAP, not a reason to flatten all OTel fields into stdout JSON. |

Service dependency snapshot: `zapx v0.36.0` is pinned by all ten active services. `obsx` is `v0.37.1` for user, product, cart, review, shipping, notification, and payment; `v0.37.0` for inventory; `v0.38.0` for order and checkout. SHAs: user `f4801bf`, product `e8db071`, inventory `ca09848`, cart `1647e4d`, order `ff7afe0`, review `4ac3a8b`, shipping `1a098a7`, notification `b62b938`, payment `7672982`, checkout `5ab15c6`.

## Assessment of the proposed standard

| Proposal | Decision | Required refinement |
|---|---|---|
| TRACE/DEBUG/INFO/WARN/ERROR/FATAL | **Keep as policy; map to OTel severity.** | Zap has no TRACE; represent it as a disabled diagnostic policy or add an internal level. Do not use FATAL for recoverable request failures. Preserve `SeverityText` and `SeverityNumber`. |
| `domain.object.action` event names | **Keep, with the existing contract's naming decision.** | `docs/api/logs.md` currently standardizes a lower-snake-case `event` attribute (for example `inventory.reservation_committed`), while OTel's LogRecord has the distinct optional `EventName` field. Choose one migration rule and map it deliberately to ClickHouse `EventName`; do not silently introduce both `event` and `event.name`. |
| Required fields | **Keep conceptually, adjust physical shape.** | Timestamp, severity, body, trace context, resource, and attributes are OTel fields. `service.name`, version, and environment belong in Resource. Kubernetes metadata should be platform-enriched. `trace_id`/`span_id` are conditional when valid context exists. |
| OTel semantic attributes | **Keep through the selected clean cutover.** | `docs/api/logs.md` explicitly marks the canonical HTTP/gRPC access schema as a target, not yet as-built. Adopt the pinned conventions, version the convention set, and migrate producers and consumers in one promotion unit. |
| Message vs attributes | **Keep.** | Stable event body/message plus typed attributes. Do not parse prose in ClickHouse. Add an event-name helper to the shared package. |
| Standard `slog` underneath | **Change to recommendation, not requirement.** | Keep Zap/`otelzap` while it satisfies the LogRecord contract. Consider `slog` only through a compatibility adapter after benchmarks, redaction tests, and service migration plan. |
| Structured errors and exceptions | **Keep.** | Pass the error object to the bridge where safe; use `exception.type`, `exception.message`, and stacktrace policy. Never copy credentials or raw request bodies into attributes. |
| Mandatory redaction | **Make a hard shared control.** | `zapx`/`obsx` currently show no central redactor. Add allowlist/redaction in the shared package and test the listed keys case-insensitively, including nested maps and headers. |
| W3C propagation | **Keep and fix implementation.** | The API contract requires W3C propagation and supported Temporal continuity. Install `TraceContext` and `Baggage` regardless of exporter enablement. Never generate business trace IDs; preserve remote parent context. |
| Kafka example | **Do not standardize yet.** | No Kafka path was identified in this audit. Define messaging rules only when a deployed messaging transport exists; Temporal is the current async path. |

## Full-fleet re-audit

The initial audit was incomplete because it inferred fleet state from shared packages. This re-audit treats `docs/api` as the intended application contract, then checks each active process and every shipped query consumer.

| Process | Entry transport | Stable EventName | Current logging path | Result |
|---|---|---:|---|---|
| user | HTTP | no | `httpmw` + Zap | migrate |
| product | HTTP + gRPC client | no | `httpmw` + Zap | migrate |
| inventory | gRPC | no | `grpcx` + Zap | migrate |
| cart | HTTP + gRPC | no | `httpmw`/`grpcx` + Zap | migrate |
| order | HTTP + gRPC + Temporal | no | `httpmw`/`grpcx` + Temporal logger | migrate |
| review | HTTP + gRPC | no | `httpmw`/`grpcx` + Zap | migrate |
| shipping | HTTP + gRPC | no | `httpmw`/`grpcx` + Zap | migrate |
| notification | HTTP + gRPC | no | `httpmw`/`grpcx` + Zap | migrate |
| payment + mockpay | HTTP + gRPC | no | `httpmw`/`grpcx` + Zap | migrate |
| checkout | HTTP + gRPC client + Temporal | no | `httpmw` + Zap + worker logger | migrate |
| order worker | Temporal | no | Temporal replay-safe logger | migrate |
| checkout worker | Temporal | no | Zap/Temporal logger | migrate |

## Findings and priority

### F1 — no application EventName exists (P0)

Search across the ten active service repositories found zero production Go callsites carrying `zap.String("event", ...)`, and the current `otelzap` bridge maps Zap fields only to LogRecord attributes. The database column `otel_logs.EventName` therefore exists but is empty for application records. ClickHouse cannot safely aggregate business outcomes without parsing `Body`.

### F2 — privacy policy and access logger disagree (P0)

`docs/api/observability.md` forbids IP and full User-Agent in logs by default. `pkg/httpmw/logging.go` emits both `client_ip` and `user_agent`; the value cap in its test limits size but does not make the data safe. `pkg/grpcx/logging.go` also records peer address. Remove these fields in the cutover and test redaction before both stdout and OTLP emission.

### F3 — shared-package documentation is stale (P1)

`docs/api/pkg.md` says `httpmw` is not adopted anywhere. The current mains for user, product, cart, order, review, shipping, notification, payment and checkout all mount `httpmw.Tracing` and `httpmw.Logging`. Correct this as an as-built defect, independently of the target standard.

### F4 — all ClickHouse access-log consumers use legacy keys (P1)

The local logs explorer, traces explorer and service deep-dive dashboard read `LogAttributes['path']`, `['status']`, `['code']` and `['duration']`; platform logging guides do the same. Dashboard JSON, SQL examples, trace-log links, alerts and runbooks must migrate in the same release gate.

### F5 — event terminology is internally inconsistent (P1)

`docs/api/logs.md` requires a legacy `event` attribute in lower snake case. OTel now deprecates the `event.name` attribute in favour of native `LogRecord.EventName`, which uses lowercase dot-namespaced names. RFC-0031 replaces the old contract rather than maps two names indefinitely.

### F6 — W3C propagation has an exporter kill-switch failure mode (P1)

`pkg/obsx/setup.go` installs the composite W3C propagator only in the branch that builds a tracer provider. Turning trace export off changes propagation behavior. The standard requires propagation to remain installed when recording or export is disabled.

### F7 — resource and metric contracts drift across the fleet (P2)

Only versioned workers reliably receive `service.version`; API ResourceSets do not provide a release/build value. `obsx` versions differ across active services. The order saga's inventory-commit and payment reconciliation histograms omit explicit business boundaries. These are separate defects: resource identity migration, package-version convergence, and two metric-instrument fixes.

### F8 — profiling is deployed but not release-gated (P2)

The fleet has broad profiling coverage, but the release gate checks neither profile arrival nor label shape. `obsx.SetupProfiling` centrally enables CPU, allocation, in-use, goroutine, mutex and block profiles; mutex/block sampling changes process-global runtime settings. Define the allowed profile labels, benchmark any sampling-rate change, verify all ten services and both worker identities in Pyroscope, and document that the current VictoriaTraces datasource requires a manual service/time pivot.

## Evidence details

### P0 — propagation is coupled to exporter enablement

`pkg/obsx/setup.go:316-332` calls `otel.SetTextMapPropagator` only when a tracer provider exists. A process with tracing export disabled can still receive a valid `traceparent`, but its outbound calls will not reliably continue that context. Install the composite propagator independently during setup and add a test with `TRACING_ENABLED=false` that extracts and injects a remote context.

### P1 — no shared event-name contract

The ClickHouse schema has `EventName` (`kubernetes/infra/configs/clickhouse-schema/configmap-schema.yaml:90-92`) and the exporter inserts it when present, but production Go call sites do not consistently populate it. Without it, analysts must group on message text or infer event classes from attributes. Add a typed shared helper and migrate business lifecycle/error events first; keep middleware access records explicitly classified.

### P1 — redaction is not demonstrably centralized

The shared `zapx` and `obsx` paths do not expose a central redaction policy for `authorization`, cookies, passwords, tokens, API keys, private keys, or database credentials. This is a control gap, not proof that secrets are currently leaking. Add allowlist/denylist handling at the shared boundary, nested-value tests, and a CI fixture that fails on sensitive key/value emission.

### P1 — HTTP/gRPC attribute vocabulary is inconsistent with OTel

HTTP middleware emits `method`, `path`, `status`, and `duration` (`pkg/httpmw/logging.go:171-177`); gRPC emits `method`, `code`, `duration`, and `peer` (`pkg/grpcx/logging.go:130-138`). Keep protocol-specific fields where their semantics differ, but emit the canonical OTel attributes (`http.request.method`, `url.path`/`http.route`, `http.response.status_code`, `rpc.method`, `rpc.grpc.status_code`) at the instrumentation boundary and move all query consumers in the same clean-cutover release.

### P2 — service version coverage is uneven

Workers set `service.version` from their build ID (`kubernetes/apps/order-worker.yaml:184-189`), while the domain ResourceSets set service identity and environment but not a version (`kubernetes/apps/domains/catalog-rs.yaml:81-95`). Make release version/build metadata a single input for every service and worker; do not manually duplicate pod metadata.

### P2 — two business histograms rely on generic defaults

`order.inventory.commit_lag` (`order-service/internal/saga/metrics.go:52-54`) and `payment.reconciliation.run.duration` (`payment-service/internal/logic/v1/metrics.go:49-51`) declare seconds but no explicit boundaries. Default buckets are unlikely to represent their operational ranges. Choose domain-specific boundaries from observed distributions, add them to the instruments, and test p50/p95/p99 queries.

### P2 — ClickHouse schema compatibility is a runtime gate

The Collector `v0.159.0` exporter inserts the OTel fields and optional `EventName` (`exporter source at v0.159.0`); the committed schema states that column mismatch fails only at insert time. Pin the exporter/schema compatibility check in CI with a disposable ClickHouse instance or upstream SQL snapshot. Keep `create_schema: false` in the cluster and the bootstrap Job as the owner.

## Recommended rollout

1. Fix propagation and add shared redaction tests; these are safety/correlation controls.
2. Build the selected `slogx` facade and native EventName path, then complete the owner-selected clean cutover across every service, worker and access logger without a legacy dual-write window.
3. Make `service.version` uniform, converge `obsx`, approve the two missing histogram boundary sets, and verify bounded series in VictoriaMetrics.
4. Gate Pyroscope coverage for all services and workers, enforce the four-label allowlist, benchmark sampling changes, and verify the documented manual trace pivot.
5. Add Collector/schema compatibility CI and migrate ClickHouse queries, dashboards and runbooks in the same promotion unit as the application cutover.

## Acceptance checklist

- A disabled-export test preserves W3C parent context across HTTP, gRPC, DB, and Temporal boundaries.
- A log test proves `EventName`, severity text/number, typed attributes, trace IDs, and resource fields reach the OTLP record.
- Redaction tests cover every mandatory key in mixed case and nested structures.
- Every active service and worker has `service.name`, `service.version`, `deployment.environment.name`, namespace, and pod identity where available.
- Metrics tests verify units, explicit histogram boundaries, bounded attributes, cumulative/delta handling and Temporal replay semantics. Application exemplars are not a supported platform workflow.
- Profiling tests verify all expected profile types, four allowed labels, non-critical failure behavior, service/version coverage and the manual trace-to-profile pivot.
- A ClickHouse smoke test inserts and queries logs/traces using the pinned Collector schema.

## Reconciliation with `docs/api/`

The API tree is normative for application-side observability. It adds constraints that a backend-only scan can miss:

- `docs/api/observability.md` requires one `obsx.SetupObservability` call, tracing before logging, no hand-built SDK providers, bounded metric attributes, and errors logged once at the decision boundary.
- `docs/api/logs.md` says the current custom event field is `event`, uses lower snake-case custom keys, and marks the OTel-shaped HTTP/gRPC access schema as a **target not yet as-built**. This confirms the attribute mismatch finding; the selected clean cutover migrates dashboards and queries in the same release rather than preserving legacy fields.
- `docs/api/metrics.md` records 63 shipped instruments, the 13-bucket HTTP view, the DB bucket fix since `pkg v0.24.0`, and the no-drift rule for services pinning different `obsx` versions. The two business histograms called out above are therefore a catalog/version-drift issue, not evidence that every metric lacks buckets.
- `docs/api/tracing.md` requires automatic HTTP, gRPC, and DB spans, meaningful manual spans/events, replay-safe Temporal logging, and says platform exemplars are unavailable. The Collector connector's exemplar setting must not be presented as an application-side capability until the VictoriaMetrics path is verified.
- `docs/api/profiling.md` defines shared Pyroscope setup, ten Go profile types, low-cardinality labels and non-critical failure behavior. The platform profiling guide confirms the one-click trace pivot was lost with Tempo and the deployed VictoriaTraces Jaeger datasource requires a manual service/time pivot.

The service-specific API pages should be the next audit slice for business event and metric names: they define intended operational interpretation, while this report identifies shared implementation and pipeline gaps.

_Last updated: 2026-09-16_
