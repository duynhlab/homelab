# Telemetry standards audit

_Audit date: 2026-09-16. Sources: homelab `26f92780`; service SHAs recorded below. This is a static code/config audit; no live cluster or ClickHouse query was run. The normative application contract in `docs/api/` was reviewed after the initial draft and the conclusions below incorporate it._

## Executive assessment

The proposed direction is sound, but it mixes three different contracts: the OpenTelemetry data model, an application coding convention, and backend/storage policy. The fleet already emits OTLP logs, traces, and metrics through `pkg/obsx`; it is not currently a `slog` fleet. Migrating Zap solely to satisfy OTel would add risk without improving conformance. The highest-value gaps are event identity, redaction, propagation when tracing export is disabled, and a small number of metric histogram definitions.

OpenTelemetry LogRecords have top-level `Timestamp`, `ObservedTimestamp`, trace context, severity, body, resource, scope, attributes, and `EventName`; `EventName` is optional rather than mandatory for every record. The data model is independent of the Go logging API. See the [OTel Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/), [event conventions](https://opentelemetry.io/docs/specs/semconv/general/events/), and [Metrics Data Model](https://opentelemetry.io/docs/specs/otel/metrics/data-model/).

## Inventory and evidence

| Area | Observed state | Assessment |
|---|---|---|
| Logger | All active services pin `github.com/duynhlab/pkg/logger/zapx v0.36.0`; OTLP bridge is `otelzap`. | **Conformant transport; migration optional.** `otelzap v0.19.0` maps Zap fields to OTel attributes and error fields to structured errors. |
| Logs | HTTP middleware emits JSON and native OTLP trace IDs; gRPC access logs use `trace_id`, `method`, `code`, `duration`. | **Partial.** No production call sites use `EventName`/`event.name`; HTTP fields are `method`, `path`, `status`, rather than the OTel HTTP names. |
| Resource | Kubernetes templates set `OTEL_SERVICE_NAME`, namespace, pod, and environment; workers additionally set `service.version` from build ID. | **Partial.** `service.version` is not consistently supplied to API services; `cloud.region` is not established. |
| Tracing | HTTP middleware, gRPC interceptors, DB instrumentation, and Temporal workers are present. | **Partial.** W3C propagator is installed only inside the enabled tracer-provider branch. Export-disabled processes can therefore lose inbound/outbound propagation. |
| Metrics | OTLP application metrics go through Collector to VictoriaMetrics; the Collector span-metrics connector has explicit buckets. The application contract says exemplars are not available on this platform. | **Mostly conformant.** `order.inventory.commit_lag` and `payment.reconciliation.run.duration` rely on SDK default histogram boundaries; do not promise application exemplars. |
| ClickHouse | Collector exports OTel logs/traces to `otel.otel_logs` and `otel.otel_traces`; schema stores `EventName`, resource attributes, log attributes, severity, and trace fields. | **Good storage shape.** ClickHouse is supplementary OLAP, not a reason to flatten all OTel fields into stdout JSON. |

Service dependency snapshot: `zapx v0.36.0` is pinned by all ten active services. `obsx` is `v0.37.1` for user, product, cart, review, shipping, notification, and payment; `v0.37.0` for inventory; `v0.38.0` for order and checkout. SHAs: user `f4801bf`, product `e8db071`, inventory `ca09848`, cart `1647e4d`, order `ff7afe0`, review `4ac3a8b`, shipping `1a098a7`, notification `b62b938`, payment `7672982`, checkout `5ab15c6`.

## Assessment of the proposed standard

| Proposal | Decision | Required refinement |
|---|---|---|
| TRACE/DEBUG/INFO/WARN/ERROR/FATAL | **Keep as policy; map to OTel severity.** | Zap has no TRACE; represent it as a disabled diagnostic policy or add an internal level. Do not use FATAL for recoverable request failures. Preserve `SeverityText` and `SeverityNumber`. |
| `domain.object.action` event names | **Keep, with the existing contract's naming decision.** | `docs/api/logs.md` currently standardizes a lower-snake-case `event` attribute (for example `inventory.reservation_committed`), while OTel's LogRecord has the distinct optional `EventName` field. Choose one migration rule and map it deliberately to ClickHouse `EventName`; do not silently introduce both `event` and `event.name`. |
| Required fields | **Keep conceptually, adjust physical shape.** | Timestamp, severity, body, trace context, resource, and attributes are OTel fields. `service.name`, version, and environment belong in Resource. Kubernetes metadata should be platform-enriched. `trace_id`/`span_id` are conditional when valid context exists. |
| OTel semantic attributes | **Keep, with the repo's staged migration rule.** | `docs/api/logs.md` explicitly marks the canonical HTTP/gRPC access schema as a target, not yet as-built; preserve legacy fields during LOG-1 migration. Adopt current conventions and version the convention set. |
| Message vs attributes | **Keep.** | Stable event body/message plus typed attributes. Do not parse prose in ClickHouse. Add an event-name helper to the shared package. |
| Standard `slog` underneath | **Change to recommendation, not requirement.** | Keep Zap/`otelzap` while it satisfies the LogRecord contract. Consider `slog` only through a compatibility adapter after benchmarks, redaction tests, and service migration plan. |
| Structured errors and exceptions | **Keep.** | Pass the error object to the bridge where safe; use `exception.type`, `exception.message`, and stacktrace policy. Never copy credentials or raw request bodies into attributes. |
| Mandatory redaction | **Make a hard shared control.** | `zapx`/`obsx` currently show no central redactor. Add allowlist/redaction in the shared package and test the listed keys case-insensitively, including nested maps and headers. |
| W3C propagation | **Keep and fix implementation.** | The API contract requires W3C propagation and supported Temporal continuity. Install `TraceContext` and `Baggage` regardless of exporter enablement. Never generate business trace IDs; preserve remote parent context. |
| Kafka example | **Do not standardize yet.** | No Kafka path was identified in this audit. Define messaging rules only when a deployed messaging transport exists; Temporal is the current async path. |

## Findings and priority

### P0 — propagation is coupled to exporter enablement

`pkg/obsx/setup.go:316-332` calls `otel.SetTextMapPropagator` only when a tracer provider exists. A process with tracing export disabled can still receive a valid `traceparent`, but its outbound calls will not reliably continue that context. Install the composite propagator independently during setup and add a test with `TRACING_ENABLED=false` that extracts and injects a remote context.

### P1 — no shared event-name contract

The ClickHouse schema has `EventName` (`kubernetes/infra/configs/clickhouse-schema/configmap-schema.yaml:90-92`) and the exporter inserts it when present, but production Go call sites do not consistently populate it. Without it, analysts must group on message text or infer event classes from attributes. Add a typed shared helper and migrate business lifecycle/error events first; keep middleware access records explicitly classified.

### P1 — redaction is not demonstrably centralized

The shared `zapx` and `obsx` paths do not expose a central redaction policy for `authorization`, cookies, passwords, tokens, API keys, private keys, or database credentials. This is a control gap, not proof that secrets are currently leaking. Add allowlist/denylist handling at the shared boundary, nested-value tests, and a CI fixture that fails on sensitive key/value emission.

### P1 — HTTP/gRPC attribute vocabulary is inconsistent with OTel

HTTP middleware emits `method`, `path`, `status`, and `duration` (`pkg/httpmw/logging.go:171-177`); gRPC emits `method`, `code`, `duration`, and `peer` (`pkg/grpcx/logging.go:130-138`). Keep protocol-specific fields where their semantics differ, but add the canonical OTel attributes (`http.request.method`, `url.path`/`http.route`, `http.response.status_code`, `rpc.method`, `rpc.grpc.status_code`) at the instrumentation boundary and preserve old query fields during migration.

### P2 — service version coverage is uneven

Workers set `service.version` from their build ID (`kubernetes/apps/order-worker.yaml:184-189`), while the domain ResourceSets set service identity and environment but not a version (`kubernetes/apps/domains/catalog-rs.yaml:81-95`). Make release version/build metadata a single input for every service and worker; do not manually duplicate pod metadata.

### P2 — two business histograms rely on generic defaults

`order.inventory.commit_lag` (`order-service/internal/saga/metrics.go:52-54`) and `payment.reconciliation.run.duration` (`payment-service/internal/logic/v1/metrics.go:49-51`) declare seconds but no explicit boundaries. Default buckets are unlikely to represent their operational ranges. Choose domain-specific boundaries from observed distributions, add them to the instruments, and test p50/p95/p99 queries.

### P2 — ClickHouse schema compatibility is a runtime gate

The Collector `v0.159.0` exporter inserts the OTel fields and optional `EventName` (`exporter source at v0.159.0`); the committed schema states that column mismatch fails only at insert time. Pin the exporter/schema compatibility check in CI with a disposable ClickHouse instance or upstream SQL snapshot. Keep `create_schema: false` in the cluster and the bootstrap Job as the owner.

## Recommended rollout

1. Fix propagation and add shared redaction tests; these are safety/correlation controls.
2. Add event-name and semantic-attribute helpers in `pkg`, then migrate the highest-value business events and error paths. Keep legacy query fields during a deprecation window.
3. Make `service.version` uniform and choose explicit business histogram boundaries; validate metric cardinality and exemplars.
4. Add Collector/schema compatibility CI and ClickHouse queries that use `EventName`, `ResourceAttributes`, and trace IDs without parsing `Body`.
5. Reconsider `slog` only after the contract is enforced. If selected, migrate behind the shared package with dual-handler tests, benchmark overhead, and per-service adoption; do not require application teams to change logger APIs solely for backend compatibility.

## Acceptance checklist

- A disabled-export test preserves W3C parent context across HTTP, gRPC, DB, and Temporal boundaries.
- A log test proves `EventName`, severity text/number, typed attributes, trace IDs, and resource fields reach the OTLP record.
- Redaction tests cover every mandatory key in mixed case and nested structures.
- Every active service and worker has `service.name`, `service.version`, `deployment.environment.name`, namespace, and pod identity where available.
- Metrics tests verify units, explicit histogram boundaries, bounded attributes, cumulative/delta handling, and exemplars where supported.
- A ClickHouse smoke test inserts and queries logs/traces using the pinned Collector schema.

## Reconciliation with `docs/api/`

The API tree is normative for application-side observability. It adds constraints that a backend-only scan can miss:

- `docs/api/observability.md` requires one `obsx.SetupObservability` call, tracing before logging, no hand-built SDK providers, bounded metric attributes, and errors logged once at the decision boundary.
- `docs/api/logs.md` says the current custom event field is `event`, uses lower snake-case custom keys, and marks the OTel-shaped HTTP/gRPC access schema as a **target not yet as-built**. This confirms the attribute mismatch finding, but a migration must preserve existing dashboards and queries.
- `docs/api/metrics.md` records 63 shipped instruments, the 13-bucket HTTP view, the DB bucket fix since `pkg v0.24.0`, and the no-drift rule for services pinning different `obsx` versions. The two business histograms called out above are therefore a catalog/version-drift issue, not evidence that every metric lacks buckets.
- `docs/api/tracing.md` requires automatic HTTP, gRPC, and DB spans, meaningful manual spans/events, replay-safe Temporal logging, and says platform exemplars are unavailable. The Collector connector's exemplar setting must not be presented as an application-side capability until the VictoriaMetrics path is verified.

The service-specific API pages should be the next audit slice for business event and metric names: they define intended operational interpretation, while this report identifies shared implementation and pipeline gaps.

_Last updated: 2026-09-16_
