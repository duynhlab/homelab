# RFC-0031 telemetry contract — proposed target

| Attribute | Value |
|-----------|-------|
| **Status** | Proposed target; not an as-built application contract |
| **Owner** | Platform engineering with each service owner |
| **Applies after** | RFC acceptance and the resulting ADRs |
| **Signals** | Logs, metrics, traces and continuous profiles |
| **Source baseline** | docs/api observability, logs, metrics, tracing, profiling, temporal, workflows, graceful shutdown and service contracts |
| **SemConv baseline** | OpenTelemetry semantic conventions v1.41.0, pinned by pkg/obsx |

This document makes RFC-0031 reviewable without replacing the deployed
contracts in docs/api. The as-built rules remain authoritative until the clean
cutover has passed its verification gates.

## Design constraints inherited from docs/api

| Existing contract | RFC-0031 target must preserve |
|---|---|
| Application observability | One bootstrap point, no per-service SDK/exporter construction, shared Views and a deliberate SemConv upgrade process |
| Application logging | One access summary per HTTP or gRPC call, probe filtering, final-decision error ownership and two delivery paths: stdout plus OTLP |
| Application tracing | W3C Trace Context plus Baggage, ParentBased sampling, automatic transport instrumentation and no wrapper spans around instrumented work |
| Application metrics | No duplicate RED/USE instruments, no IDs as labels, explicit boundaries for business latency histograms and stated retry semantics |
| Temporal and workflow registry | Deterministic workflow code, replay-safe workflow logging, activity-context instrumentation, pinned-worker lifecycle and no IDs in metric/profile labels |
| API idempotency and deadlines | Retry-safe operations retain the same idempotency key; logging must never expose its raw value |
| Graceful shutdown | Readiness drains before stopping work; telemetry flush is bounded and happens after work-serving resources stop |

## Signal routing and ownership

The four signals share resource identity and data classification, but they keep
their existing storage and operational roles.

| Signal | Application path | Backend | Primary question |
|---|---|---|---|
| Logs | stdout plus OTLP through the Collector | VictoriaLogs for 7-day operations; ClickHouse for 90-day SQL | What happened in this case and why? |
| Metrics | OTel Meter API through the Collector | VictoriaMetrics | How often, how slow and how saturated? |
| Traces | OTel Tracer API through the Collector | VictoriaTraces for 7-day operations; ClickHouse for 90-day SQL | Where did time or failure propagate? |
| Profiles | pyroscope-go SDK direct push | Pyroscope with 7-day profile retention | Which code consumed CPU, memory or synchronization time? |

ClickHouse is not a metrics or profile backend. VictoriaMetrics also scrapes
Pyroscope's service health metrics so the platform can alert when profiling is
unavailable; those self-metrics are not application profiles.

## Record model

Each logical application record has a timestamp, severity text and normalized
severity number, a short body, resource identity, instrumentation scope,
attributes, and native trace and span identifiers when context exists. A named
record additionally has native OTel EventName. The stdout JSON and OTLP record
are two renderings of the same safe record.

| Record kind | Use | EventName |
|---|---|---|
| Diagnostic log | Investigation detail without a stable schema | Empty |
| Named event | Lifecycle, state transition, decision, retry exhaustion, compensation or access summary | Required |
| Span event | A milestone within a sampled span | Stable name, bounded count |
| Metric observation | A bounded aggregate at an authoritative decision point | Not applicable |

The facade must never encode EventName as an ordinary event attribute. A backend
must receive it in the OTel LogRecord EventName field.

### Event names and body

Event names are lowercase dot-separated operation classes. They have at least
three parts where the domain supports it and contain no identifier, status code,
provider response, route parameter or free text.

| Correct | Incorrect |
|---|---|
| order.created | OrderCreatedSuccessfully |
| payment.authorization.failed | payment.authorization.failed.4821 |
| checkout.session.requoted | checkout session 123 was requoted |
| temporal.activity.retry.exhausted | retry failed again |
| http.server.request.completed | POST order success |

The body is a concise display phrase. Attributes carry values. The name and
attribute schema are an API: changing either requires a documented migration,
not a message-text edit.

### Severity

| Facade level | OTel severity number | Use |
|---|---:|---|
| TRACE | 1 | Fine-grained diagnostic evidence, disabled by default |
| DEBUG | 5 | Troubleshooting evidence |
| INFO | 9 | Expected lifecycle, decision and business events |
| WARN | 13 | Handled degradation or unexpected condition |
| ERROR | 17 | Final failed operation or exhausted retry |
| FATAL | 21 | Process cannot continue and will terminate |

Fatal is reserved for bootstrap failure after safe shutdown/flush has been
attempted. A workflow, handler, activity or normal business decision must not
terminate the process to signal failure.

## Service-facing facade

The shared package owns the unstable OTel Logs API. Application code receives a
context-first facade with diagnostic methods, an Event method and test helpers.
The precise Go signatures are an ADR implementation detail, but these
behaviours are required:

| Capability | Required behaviour |
|---|---|
| Context | Every emission accepts context; it reads native trace and span context without business code constructing IDs |
| Event | Accepts severity, stable name, display body and typed attributes; creates a native EventName |
| Diagnostic | Accepts severity, body and typed attributes; leaves EventName empty |
| Attributes | Uses typed values, limits count/depth/value size and recursively redacts before every sink |
| Error | Maps typed errors to safe error.type; optional exception data and stack traces are bounded and redacted |
| Resource | Attaches service.name, service.version, deployment.environment.name and available Kubernetes identity |
| Output | Writes one safe JSON record to stdout and one equivalent OTLP LogRecord when logs export is enabled |
| Lifecycle | Flushes once with the process shutdown context after servers/workers finish draining |

The facade replaces direct Zap, slog, otelzap and OTel Logs API use in
application repositories. Instrumentation packages may remain the sole
implementation boundary for the OTel API.

## Canonical attributes

Use a pinned OTel semantic convention whenever it defines an attribute. A
domain-specific key is lowercase dot-separated and must be registered in the
event catalog before use.

| Situation | Required attributes | Forbidden or constrained attributes |
|---|---|---|
| HTTP server summary | http.request.method, http.route, http.response.status_code; error.type only for an error outcome | No raw URL path/query, client.address, network.peer.address or user_agent.original |
| gRPC server summary | rpc.system.name=grpc, rpc.method, rpc.response.status_code; error.type only for an error outcome | No peer address, arbitrary metadata or raw protobuf |
| Database decision | db.system.name, db.operation.name where provided by the pinned instrumentation; error.type on failure | No SQL parameters, DSN or credentials |
| Messaging consumer or producer | messaging.system and messaging.destination.name where a real broker exists | No message body or unrestricted headers |
| Error | error.type and a safe, documented domain or dependency outcome | No raw error string if it may include credentials, payloads or customer data |
| Domain decision | Registered domain attributes such as order.id or payment.provider when operationally justified | No raw payment token, idempotency key, address, email or arbitrary user input |
| Temporal activity | temporal.workflow.type, temporal.activity.type, temporal.task_queue and approved correlation IDs | No direct telemetry exporter call from workflow code; IDs never become metric/profile labels |

Duration is measured by the corresponding span and metric. An access event does
not invent a second unqualified duration attribute. If an event requires a
duration that is not represented by its span or metric, its attribute name,
unit, cardinality and query use must be approved in the event catalog.

HTTP route is the matched low-cardinality route template. It is never replaced
by raw URL path. Query strings, request/response bodies, authorization material,
cookies, peer addresses and full User-Agent values are forbidden.

## Event catalog and ownership

Every named event has an owner, schema and operational purpose. The catalog is
maintained beside the owning service contract after implementation; the initial
cutover catalog is reviewed in the shared package change.

| Event class | Owner boundary | Required outcome attributes | Metric relationship |
|---|---|---|---|
| HTTP/gRPC completed | Shared transport middleware/interceptor | method or RPC method, route or service, status | Automatic RED only; no duplicate metric |
| Business state transition | Owning logic use case after durable decision | bounded outcome/reason and approved business ID | Authoritative business metric may accompany it |
| Retry exhausted | Boundary deciding abandon, compensate or escalate | error.type, dependency or operation, attempt count if bounded | Counter semantics state attempts versus unique outcome |
| Compensation | Temporal activity or logic boundary | compensation step, outcome, safe error.type | Explicit operational metric only if catalogued |
| Workflow lifecycle | Temporal-aware workflow logger | workflow type, task queue, safe run correlation | No metric IDs; replay behaviour must be stated |
| Startup/shutdown | Process entry point | component and bounded outcome | Runtime metrics remain the heartbeat |

Expected business outcomes such as validation failure, not found, price change,
stock shortage, payment decline and invalid transition are not automatically
ERROR records. Their owning service contract decides whether they are INFO or
WARN and documents their bounded outcome attribute.

## Temporal safety and correlation

Temporal workflow code is replayed. It may use only the SDK's replay-safe
workflow logger and deterministic workflow APIs. It must not call the facade's
OTLP export path, make arbitrary network calls, generate a trace ID, emit a
non-deterministic timestamp, or increment a metric directly.

Activities and worker entry points may use the facade with their supplied
context. They emit named records for terminal retry exhaustion, compensation
failure, workflow lifecycle and worker readiness/shutdown as applicable.
Supported Temporal instrumentation provides trace continuity; application code
does not store ad hoc trace headers in workflow input.

Workflow, run, order, reservation and session identifiers may be trace/log
attributes only when operationally justified. They are forbidden from metric
labels, resource attributes, event names and profile labels. Raw idempotency
keys and payment tokens are always forbidden; a keyed, access-controlled
correlation representation needs a separate security decision.

## Privacy, redaction and sampling

Redaction happens before stdout and OTLP. It must recurse through groups, maps,
arrays, errors and exception payloads and match case-insensitively after key
normalization. At minimum it removes authorization, cookie, set-cookie,
password, passwd, token, access_token, refresh_token, client_secret, api_key,
private_key and secret.

The policy also removes raw request/response bodies, client IPs, peer addresses,
full User-Agent strings, database connection strings, payment secrets,
PAN-shaped values and arbitrary headers. Sensitive business data needs a named
owner, purpose, retention rule and review before it can be emitted.

Sampling may reduce volume but is never a privacy control. The existing
ParentBased trace sampler continues to decide tracing independently of logging
and metrics. Log sampling must retain ERROR, FATAL, terminal retry and
compensation-failure records.

## Metrics contract

Metrics continue to use the OTel Meter API and OTLP export through the shared
obsx provider. VictoriaMetrics is the only application metrics store. The
PromQL name is an ingest rendering of the canonical dotted OTel instrument
name; application code declares only the OTel name.

### Instrument ownership

| Metric family | Owner | Rule |
|---|---|---|
| HTTP RED | otelgin through shared HTTP instrumentation | One server duration histogram; handlers do not add request counters or latency histograms |
| gRPC RED | otelgrpc through pkg/grpcx | One client/server duration histogram; high-cardinality server address and port stay removed by the shared View |
| Runtime | OTel Go runtime instrumentation | Process heartbeat and Go runtime state; no service-local duplicate |
| Database/cache | Shared instrumented adapters | Use the adapter's instruments and Views; repositories do not wrap the same operation in another metric |
| Business | Owning logic at the durable decision point | Only signals unavailable from automatic instrumentation |
| Span-derived RED | Collector span-metrics connector | Operational service-graph view; it is not a second application metric API |

Every business metric records the operational question, owner, canonical name,
instrument type, unit, bounded attribute allowlist, retry/replay semantics,
dashboard/alert consumer and removal plan. It is emitted after the authoritative
outcome is known.

### Instrument and aggregation rules

- Counter measures a monotonic event count. It never carries a current-state value.
- UpDownCounter measures additive state that rises and falls.
- Gauge measures a sampled non-additive value.
- Histogram measures a distribution used for percentiles or threshold buckets.
- Synchronous instruments record at the decision. Observable instruments sample
  cheap current state and must not perform blocking I/O in callbacks.
- Units use UCUM values and are instrument metadata, not suffixes in the OTel name.
- Temporality remains cumulative at the application SDK; the Collector
  delta-to-cumulative processor is a defensive boundary.

Business histograms require domain-appropriate explicit boundaries or an
approved shared View. The current order.inventory.commit_lag and
payment.reconciliation.run.duration histograms are known gaps because they use
seconds but rely on generic SDK defaults. Boundaries must be chosen from the
operational SLO or measured distribution, then tested with p50, p95 and p99
queries.

### Cardinality and replay

Metric attributes are low-cardinality enums or normalized operation classes.
User, request, trace, span, workflow, run, order, cart, session, payment, SKU,
promo, IP, raw URL, image SHA, pod UID, email and arbitrary error text are
forbidden as metric attributes.

Temporal metrics state whether they count attempts or unique durable outcomes.
Workflow replay must not increment an application metric. Activities may record
attempt metrics only when the name and catalog explicitly say attempt; durable
business counters emit at the idempotent commit boundary.

The platform does not promise application exemplars. The Collector span-metrics
connector may attach exemplars internally, but docs/api records that the
VictoriaMetrics path has no supported exemplar investigation workflow.
Correlation remains metric and time window to logs, then trace_id to trace.

## Continuous profiling contract

All ten Go services and both worker modes use obsx.SetupProfiling and push
directly to Pyroscope. Profiling remains non-critical to the business path:
startup failure emits a sanitized warning and does not make readiness false.

### Profile types and cost

The shared helper owns CPU, allocation objects/bytes, in-use objects/bytes,
goroutine, mutex count/duration and block count/duration profiles. Service code
does not start a second profiler or change process-global runtime sampling.

Mutex and block profiles have measurable runtime cost. Their shared sampling
rates remain centrally configured; a change requires workload benchmarks and a
documented overhead budget. PROFILING_ENABLED is the emergency kill switch.
Disabling profiling must not change logs, metrics, traces or application
readiness.

### Profile identity and labels

Profiles share service identity with OTel signals. The allowed label set is
closed:

- service_name;
- service_namespace;
- deployment_environment;
- service_version.

No other OTel resource attribute automatically becomes a profile label. User,
workflow, run, request, trace, order, session, payment, SKU and pod identifiers,
raw paths, addresses, secrets and arbitrary input are forbidden. The uneven
service.version coverage found in API ResourceSets is therefore also a
profiling correlation defect.

### Trace-to-profile correlation

When tracing and profiling are enabled, the shared tracer-provider wrapper adds
pyroscope.profile.id to spans. CPU profiles are span-scoped; heap, allocation,
goroutine, mutex and block profiles remain service-and-time scoped.

Grafana currently queries VictoriaTraces through a Jaeger-type datasource,
which does not expose the Tempo-only tracesToProfiles link. The supported
workflow is a manual Pyroscope query using service.name and the span time
window. The pyroscope.profile.id span attribute remains correlation evidence,
but the deployed datasource cannot consume it for direct navigation.
RFC-0031 must not claim a one-click trace-to-profile link unless a separate
datasource capability is deployed and verified.

### Profiling lifecycle

The profiler starts only after endpoint and identity validation succeeds.
Upload errors are surfaced without logging credentials or the full endpoint.
Shutdown is attempted within the process shutdown budget after work drains.
Because the current SDK stop call does not honor its context internally, tests
must prove the process budget remains bounded or the implementation must wrap
that limitation explicitly.

## Resource and propagation contract

All API and worker processes set service.name, service.version and
deployment.environment.name. Kubernetes namespace, pod, container and region
are platform enrichment where available. The implementation must eliminate the
current difference where worker build metadata is present but API release
version is absent.

W3C Trace Context plus Baggage is configured once, independently of tracer,
logger and exporter enablement. A disabled exporter must not cause a service to
stop extracting or injecting valid context. No application business logic
generates trace_id, span_id or parent_span_id.

## Verification gates

| Gate | Evidence |
|---|---|
| Native event | A Collector-to-ClickHouse test reads a non-empty EventName for each named record |
| Redaction | Nested attributes, errors and exception data cannot leak forbidden values to either output |
| Transport | HTTP/gRPC contract tests assert one summary, semantic attributes, low-cardinality route/method and probe filtering |
| Temporal | Replay test proves no duplicate export/metric side effect; activity tests prove terminal and compensation records correlate |
| Metrics | No IDs reach labels; each new histogram has approved seconds or domain buckets; retry semantics are tested |
| Profiles | All processes expose the approved profile types and four-label allowlist; disable/failure paths preserve readiness; trace correlation is verified as manual or supported by the deployed datasource |
| Resource and propagation | API and worker records contain required resource data; W3C extraction/injection works with exporters disabled |
| ClickHouse | Dashboards, saved SQL and runbooks query EventName/native trace IDs and contain no removed access keys |
| Release | Compose and Kind audit passes browser checkout, HTTP, gRPC, Temporal, expected business rejection, dependency failure and both correlation directions |

## References

- [RFC research](./research.md)
- [RFC proposal](./README.md)
- [Application observability](../../../api/observability.md)
- [Application logging](../../../api/logs.md)
- [Application metrics](../../../api/metrics.md)
- [Application tracing](../../../api/tracing.md)
- [Application profiling](../../../api/profiling.md)
- [Temporal workflows](../../../api/temporal.md)
- [Workflow registry](../../../api/workflows.md)
- [Graceful shutdown](../../../api/graceful-shutdown.md)
- [OTel Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [OTel HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/)
- [OTel RPC semantic conventions](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/)

---
_Last updated: 2026-09-16_
