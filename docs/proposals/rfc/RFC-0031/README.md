# RFC-0031 Cross-signal telemetry standard and ClickHouse operations

| Status | Scope | Research | Created | Last updated |
|--------|-------|----------|---------|--------------|
| provisional | platform-wide | [./research.md](./research.md) — gate passed 2026-09-16 | 2026-09-16 | 2026-09-16 |

## Summary

Adopt one application telemetry contract across logs, metrics, traces and
continuous profiles. Logging moves to pkg/logger/slogx behind one context-first
API with one tested redaction boundary; tracing keeps its sampling, span and
baggage rules and gains an explicit contract instead of an inherited pointer;
metrics retain the OTel Meter API and VictoriaMetrics with stricter instrument,
bucket, cardinality and replay rules; profiling retains the shared Pyroscope
SDK path with an explicit label, overhead, lifecycle and correlation contract.

The normative target contract is part of this RFC. The dependency-ordered
implementation work is in [delivery-plan.md](./delivery-plan.md). Neither the
contract nor the plan changes the current application contract until this RFC
and its resulting ADRs are accepted.

## Review map

| Review question | Where to look |
|-----------------|---------------|
| What problem and outcome does this RFC cover? | [Motivation](#motivation) and [Proposal](#proposal) |
| Which option is being reviewed? | [Decision outcome](#decision-outcome) and [Alternatives](#alternatives) |
| What exact application contract is proposed? | [Normative target contract](#normative-target-contract) |
| What does each signal have to do? | [Record model](#record-model) · [Tracing](#tracing-contract) · [Metrics](#metrics-contract) · [Profiling](#continuous-profiling-contract) |
| Is the logging migration settled? | No — [Open disagreement: keep Zap](#open-disagreement-keep-zap) |
| How will the fleet migrate and roll back? | [Rollout and rollback](#rollout--rollback) and the [delivery plan](./delivery-plan.md) |
| What evidence must pass before promotion? | [Verification gates](#verification-gates) |
| Where is the current-state evidence? | [Research](./research.md) and the [audit report](../../../observability/audits/2026-09-16-telemetry-standards.md) |

## Motivation

The platform transports logs and traces into ClickHouse, metrics into
VictoriaMetrics and profiles into Pyroscope, but the signals do not yet share
one enforceable application contract.
Operators infer event identity from messages and must know which legacy HTTP or
gRPC attributes each dashboard expects. The research audit also found
privacy-policy violations and propagation coupled to export configuration.
Two business histograms use generic defaults instead of reviewed
operation-specific boundaries, API service versions are missing from
cross-signal identity, and profiling has no reviewed overhead budget or
explicit verification gate despite being enabled fleet-wide.

### Goals

- Give all Go services and workers one context-first logging API with one tested redaction boundary.
- Make each request answerable from one wide access record rather than a join across scattered lines.
- Give the small set of durable business outcomes a stable, owned schema that survives message-text edits.
- Preserve W3C trace correlation whether telemetry export is enabled or not.
- Make the tracing contract explicit — sampling, span naming, span kind, error status and baggage safety.
- Provide stable ClickHouse queries for events, access records and trace-to-log investigation.
- Keep application metrics bounded and meaningful in VictoriaMetrics, including Temporal replay semantics and explicit histogram boundaries.
- Make Pyroscope coverage, profile labels, overhead, failure behavior and trace correlation verifiable.
- Complete the migration as one release, leaving no legacy query contract.

### Non-Goals

- Change product APIs, business workflows, retention periods or ClickHouse topology.
- Turn every diagnostic line into a named event.
- Add unbounded request, identity or payload data to logs or metrics.
- Move metrics or profiles into ClickHouse.
- Replace VictoriaMetrics or Pyroscope.

## Proposal

pkg/logger/slogx becomes the only application logging facade. Its diagnostic methods
emit structured slog records. Its context-first event method emits an OTel log
record whose native EventName is a lower-case dot-separated, stable identifier.
The message is short display text; values belong in typed attributes.

The package owns severity mapping, common resource attributes, native trace and
span correlation, recursive redaction, output formatting, sampling and test
helpers. It writes safe structured JSON to stdout and directly creates the OTel
record used for export.

**Why slog rather than the current Zap path.** Not because of EventName. The
official Zap bridge maps the message to the record body and never sets EventName,
but the official slog bridge `otelslog` behaves identically — it maps time,
message, level and attributes, and also leaves EventName untouched. Native
EventName comes from calling the OTel Logs API directly, which a Zap-based facade
could do just as well. The reasons that do hold are: `log/slog` is the standard
library, so the facade adds no logging dependency to every service; its
context-first `Handler` interface matches the correlation and redaction seam this
contract needs; a single implementation gives one tested redaction boundary
instead of one per adapter; and slog is already in the platform's path, since
`temporalx` routes SDK logs through `zapslog` into slog today. The cost is a fleet
migration of roughly 950 call sites, and the OTel Go Logs API is still pre-1.0 —
the facade exists to contain that instability in one module.

The release removes the legacy application contract: Zap imports, otelzap,
custom event, and access fields named path, status, code, duration, client_ip,
user_agent and peer. Access records use pinned OTel HTTP and RPC semantic
conventions, with an explicit duration unit where needed. W3C traceparent and
baggage propagation are installed independently of exporters.

Metrics keep their current OTel-to-VictoriaMetrics path. RFC-0031 standardizes
instrument ownership, units, bounded attributes, explicit histogram boundaries,
temporality and Temporal replay semantics; it does not add a second metrics
pipeline. Profiles keep the direct pyroscope-go path and receive a closed label
allowlist, centrally owned runtime sampling, non-critical failure policy,
bounded shutdown and an honest manual trace-to-profile workflow.

### User Stories

- As an on-call engineer, I can find payment.authorization.failed by EventName,
  follow its trace, and see safe error metadata without parsing a message.
- As a service owner, I use the same API in an HTTP handler, gRPC method,
  Temporal activity and consumer, with correlation inherited from context.
- As a security reviewer, I can prove that secrets, client IPs and full
  User-Agent values cannot leave through either stdout or OTLP.
- As an on-call engineer, I can trust a VictoriaMetrics percentile because its
  histogram buckets match the operation and its labels are bounded.
- As a performance investigator, I can find CPU, heap, goroutine and
  synchronization profiles for the same service/version and time window as a
  slow trace.

### Alternatives

| Option | Benefit | Cost | Status |
|--------|---------|------|--------|
| pkg/logger/slogx facade over slog plus direct OTel Logs API | Standard-library logging with no added dependency; one policy boundary; context-first handler seam; slog already reached through `zapslog` in `temporalx` | Fleet migration of roughly 950 call sites; OTel Logs API remains pre-1.0 | Proposed |
| Zap facade over the existing `logger/zapx` plus the same direct OTel Logs API | Much smaller diff; keeps the adapter every service already pins; reaches native EventName by the identical direct-API path | Keeps a third-party logging dependency in every service and leaves the redaction boundary split across adapters | Rejected — but note the audit recommends it; see § Other solutions considered |
| Raw OTel Logs API in every service | Full record control | Duplicates redaction, correlation and tests | Rejected |
| Preserve VictoriaMetrics and Pyroscope with stricter shared contracts | No backend migration; fixes measured contract gaps | Requires metric/profile tests and service-version convergence | Proposed |
| Replace metrics or profiles during this RFC | One large observability redesign | Expands blast radius without solving the audited application gaps | Rejected |

For the detailed source comparison and migration inventory, see
[research.md](./research.md).

## Other solutions considered

| Option | Shape | Why not chosen |
|--------|-------|----------------|
| Keep legacy fields and dual-write | Let dashboards consume old and new attributes | Hides incomplete migration and preserves two contracts indefinitely |
| Parse event identity from message text | Use log search or regular expressions | Loses typed aggregation and makes alert/query behavior message-dependent |
| Add a separate event database | Emit business events outside the telemetry pipeline | Creates another reliability, security and operational surface without solving access and trace correlation |

### Open disagreement: keep Zap

The audit that supplies this RFC's evidence does **not** agree with the migration.
It records that "migrating Zap solely to satisfy OpenTelemetry would add risk
without improving conformance", and scores the slog proposal as a recommendation
rather than a requirement — keep `zapx` and `otelzap` while they satisfy the
LogRecord contract, and consider slog only through a compatibility adapter after
benchmarks, redaction tests and a migration plan.

That position got stronger, not weaker, once the bridges were checked: `otelslog`
leaves EventName unset exactly as `otelzap` does, so the original justification for
the migration does not survive. What remains is a dependency and consistency
argument, not a conformance one.

This RFC still proposes the slog facade, for the reasons in § Proposal. The
disagreement is recorded here rather than resolved, because § Decision outcome is
owner-decided at architecture review. The evidence that would settle it is the
evidence the audit already asked for: a benchmark of the two facades under fleet
log volume, a redaction test suite that both must pass, and a measured estimate of
the migration cost across roughly 950 call sites.

## Decision outcome

**Chosen option:** undecided — architecture review pending.

**Rationale:** The research recommendation is the pkg/logger/slogx facade over slog
plus the direct OTel Logs API, on standard-library, dependency and
single-redaction-boundary grounds. It is explicitly **not** recommended on
EventName grounds: the direct OTel Logs API reaches native EventName from a
Zap-based facade equally well, and neither official bridge sets it. The audit
recommends keeping Zap; that disagreement is stated in
[§ Other solutions considered](#open-disagreement-keep-zap) and is the main thing
architecture review has to settle.

**Decided:** pending architecture review.

## Architecture & Diagrams

The target-state diagram answers where each application signal is created and
stored.

Legend: cyan is an application process, blue is the Collector, green is shared
data, purple is the platform UI, and the pale signal colors distinguish logs,
metrics, traces and profiles.

~~~mermaid
flowchart LR
    A["Service or worker"] --> L["pkg/logger/slogx<br/>logs"]
    A --> M["OTel Meter API<br/>metrics"]
    A --> T["OTel Tracer API<br/>traces"]
    A --> P["pyroscope-go<br/>profiles"]
    L --> O["OTLP Collector"]
    M --> O
    T --> O
    O --> VL["VictoriaLogs<br/>7d logs"]
    O --> VM["VictoriaMetrics<br/>metrics"]
    O --> VT["VictoriaTraces<br/>7d traces"]
    O --> CH["ClickHouse<br/>90d logs + traces"]
    P --> PY["Pyroscope<br/>7d profiles"]
    VL --> G["Grafana"]
    VM --> G
    VT --> G
    CH --> G
    PY --> G
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef log fill:#d3f9d8,color:#111,stroke:#2f9e44;
    classDef trace fill:#c5f6fa,color:#111,stroke:#0c8599;
    classDef profile fill:#f3d9fa,color:#111,stroke:#9c36b5;
    class A service;
    class O collector;
    class G platform;
    class CH data;
    class L,VL log;
    class M,VM metric;
    class T,VT trace;
    class P,PY profile;
~~~

## Normative target contract

| Attribute | Value |
|-----------|-------|
| **Status** | Proposed target; not an as-built application contract |
| **Owner** | Platform engineering with each service owner |
| **Applies after** | RFC acceptance and the resulting ADRs |
| **Signals** | Logs, metrics, traces and continuous profiles |
| **Source baseline** | docs/api observability, logs, metrics, tracing, profiling, Temporal, workflows, graceful shutdown and service contracts |
| **SemConv baseline** | OpenTelemetry semantic conventions v1.41.0, pinned by pkg/obsx |

This section makes the target reviewable without replacing the deployed
contracts in docs/api. The as-built rules remain authoritative until the clean
cutover has passed every verification gate.

### Design constraints inherited from docs/api

| Existing contract | RFC-0031 target must preserve |
|---|---|
| Application observability | One bootstrap point, no per-service SDK/exporter construction, shared Views and a deliberate SemConv upgrade process |
| Application logging | One access summary per HTTP or gRPC call, probe filtering, final-decision error ownership and two delivery paths: stdout plus OTLP |
| Application tracing | W3C Trace Context plus Baggage, ParentBased sampling, automatic transport instrumentation and no wrapper spans around instrumented work |
| Application metrics | No duplicate RED/USE instruments, no IDs as labels, explicit boundaries for business latency histograms and stated retry semantics |
| Temporal and workflow registry | Deterministic workflow code, replay-safe workflow logging, activity-context instrumentation, pinned-worker lifecycle and no IDs in metric/profile labels |
| API idempotency and deadlines | Retry-safe operations retain the same idempotency key; logging must never expose its raw value |
| Graceful shutdown | Readiness drains before stopping work; telemetry flush is bounded and happens after work-serving resources stop |

### Signal routing and ownership

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

### Record model

Each logical application record has a timestamp, severity text and normalized
severity number, a short body, resource identity, instrumentation scope,
attributes, and native trace and span identifiers when context exists. A named
record additionally has native OTel EventName. The stdout JSON and OTLP record
are two renderings of the same safe record.

Three forces shape the split below, and they pull in different directions.

The first is the wide-record pattern that large-scale services converged on: emit
**one** structured record per unit of work, with every field the investigation
needs already attached, rather than five narrow lines that must be joined on a
request ID afterwards. Field names in that record become muscle memory for
on-call, so their stability matters more than their elegance.

The second is the cost of enforcing a schema too widely. Operators of very large
Go fleets report that forcing a rigid schema onto ordinary service logs slows
developers down and produces field-name and type collisions, because log shape
evolves organically across many authors. The workable line is to reserve a strict,
reviewed schema for durable business outcomes and leave diagnostic logging loose.

The third is the OpenTelemetry guidance on what an event actually is: work that has
a duration and meaningful boundaries belongs in a **span**; properties describing an
operation as a whole belong in **span attributes**; unstructured diagnostic text
belongs in a **plain log record**. An event earns its name when something happens at
a point in time — a state change, a checkpoint, a lifecycle moment — and
particularly when it can happen several times inside one span or needs its own
timestamp, severity and attributes.

| Record kind | Use | Schema | EventName |
|---|---|---|---|
| Canonical access record | One wide record per served HTTP or gRPC call, emitted once at the boundary | Fixed, owned by shared middleware | Empty — the call is already a span |
| Named business event | Durable outcome, state transition, retry exhaustion or compensation, at the commit point | Strict, registered in the event catalog | Required |
| Diagnostic log | Investigation detail without a stable schema | Free | Empty |
| Span event | A milestone within a sampled span | Stable name, bounded count | Not applicable |
| Metric observation | A bounded aggregate at an authoritative decision point | Instrument catalog | Not applicable |

The access record deliberately carries no EventName. A served request already has a
span that owns its duration and outcome, so naming it as an event would duplicate
the span and contradict the rule above. It stays one wide, stably-named log record
that the on-call path reads directly and that joins to its span by trace ID.

EventName is therefore a property of a **small, reviewed catalog**, not a fleet-wide
labelling exercise. The pressure to name everything is the failure mode: a catalog
that grows with every log line stops being queryable and becomes a second, weaker
copy of the message text.

Where a name is required, the facade must never encode EventName as an ordinary
attribute. A backend must receive it in the OTel LogRecord EventName field — the
`event.name` attribute that older material shows is deprecated for this purpose.

#### Event names and body

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

#### Severity

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

### Service-facing facade

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

#### Placement in the shared package

The facade ships as `pkg/logger/slogx`, a sibling of the existing `logger/zapx`,
`logger/zerolog` and `logger/clog` modules. Three constraints from `duynhlab/pkg`
govern the placement and are binding on the resulting ADR:

- **`logger/` is a namespace, not a module.** Each backend adapter carries its own
  `go.mod` and its own `<module-path>/v<semver>` tag. The repository has no
  top-level `go.mod` and none may be created, so the facade cannot be named
  `pkg/logger`; it must be a named sibling.
- **A logger module may link the OTel API but never the SDK.** `logger/*` may
  import `go.opentelemetry.io/otel` and its API packages, including
  `go.opentelemetry.io/otel/log`; importing `go.opentelemetry.io/otel/sdk` or
  `pkg/obsx` is denied by `depguard`. Setting a native EventName needs only the
  API, so the facade stays inside that boundary. This is also why the facade is
  not named `obslog`: the `obs*` prefix belongs to `obsx`, the one module that is
  allowed to link the SDK.
- **The cutover retires adapters, it does not accumulate them.** `logger/zapx` is
  the only adapter any service imports today; `logger/zerolog` and `logger/clog`
  have no consumers. Adding a fourth adapter while two stay unused is not an
  acceptable end state, so the same release that lands `slogx` removes `zerolog`
  and `clog`.

### Canonical attributes

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

### Event catalog and ownership

Every named event has an owner, schema and operational purpose. The catalog is
maintained beside the owning service contract after implementation; the initial
cutover catalog is reviewed in the shared package change.

The catalog is meant to stay small enough to read in one sitting. A class is
admitted when an operator would query it by name across services; anything an
operator would only read while following one request belongs in the access record
or a diagnostic log instead. Adding a class is a reviewed change to this table, not
a decision made at a call site.

The served HTTP or gRPC call is deliberately absent from this table — it is the
canonical access record, owned by shared transport middleware, and its outcome is
already carried by its span and by automatic RED metrics.

| Event class | Owner boundary | Required outcome attributes | Metric relationship |
|---|---|---|---|
| Business state transition | Owning logic use case after durable decision | bounded outcome/reason and approved business ID | Authoritative business metric may accompany it |
| Retry exhausted | Boundary deciding abandon, compensate or escalate | error.type, dependency or operation, attempt count if bounded | Counter semantics state attempts versus unique outcome |
| Compensation | Temporal activity or logic boundary | compensation step, outcome, safe error.type | Explicit operational metric only if catalogued |
| Workflow lifecycle | Temporal-aware workflow logger | workflow type, task queue, safe run correlation | No metric IDs; replay behaviour must be stated |
| Startup/shutdown | Process entry point | component and bounded outcome | Runtime metrics remain the heartbeat |

Expected business outcomes such as validation failure, not found, price change,
stock shortage, payment decline and invalid transition are not automatically
ERROR records. Their owning service contract decides whether they are INFO or
WARN and documents their bounded outcome attribute.

### Temporal safety and correlation

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

### Privacy, redaction and sampling

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

### Tracing contract

Traces are the primary signal for "where did time or failure go", and every other
signal in this contract correlates through the trace ID. The rules below are
restated here rather than left as an inherited pointer, because a cross-signal
standard that omits them cannot be implemented from this document alone.

Tracing keeps its current shape: the OTel Tracer API through the shared provider,
automatic transport and database instrumentation, export to VictoriaTraces for
operations and ClickHouse for SQL. Nothing in this RFC changes the backends or the
sampling rates.

#### Sampling

The sampler is `ParentBased(TraceIDRatioBased(rate))` and the **edge is the root**:
Envoy starts a span for every request it accepts and sends `traceparent` upstream,
so a browser request carrying no trace header still arrives already joined to the
edge trace. The edge's rate therefore governs the whole trace it proxies.

| Environment | Rate that decides | Service `OTEL_SAMPLE_RATE` |
|---|---|---|
| Cluster | 50% at the edge | `0.1`, applying only to traces a service starts itself |
| Local-stack | 100% | `1.0` |

A sampled remote parent is always honoured. There is no environment-to-rate
auto-mapping: the rate is set explicitly per environment, and a change to it is a
volume and cost change that must be reviewed as one.

#### Span naming, kind and scope

Span names are stable operation classes — `checkout.confirm`, `inventory.reserve`,
`payment.capture`. Business identifiers never enter a span name; they are
attributes, added only when operationally justified. Note that span names and
EventNames are **different namespaces**: a span name is a two-part operation class,
while an event name is the dot-separated class of a point-in-time occurrence. A
service must not mint one from the other.

Every span carries exactly one kind, and the kind follows the layer:

| SpanKind | Layer | Created by |
|---|---|---|
| `SERVER` | HTTP/gRPC transport in | automatic transport instrumentation |
| `INTERNAL` | `logic/v1` manual spans — the default | shared helper |
| `CLIENT` | core adapters calling out: DB, cache, gRPC client, provider | automatic instrumentation |
| `PRODUCER` / `CONSUMER` | queue and worker boundaries | supported Temporal integration |

The instrumentation scope is the **package path** of the code creating the span,
never the service name — deployment identity already rides as `service.name`.

No wrapper spans around work that is already instrumented. The granularity ladder
is: add attributes to the existing span first, then a span event, and only then a
child span. A span per function call is the anti-pattern this rule exists to stop.

#### Status, errors and exceptions

Set Error status for a failed operation, not automatically for an expected business
rejection. Outcomes such as not found, price changed, stock unavailable, payment
declined and invalid transition are normal domain results unless the owning service
contract says otherwise; they carry a bounded outcome attribute and leave the span
status unset.

An unexpected failure records the error on the span where it becomes meaningful,
sets Error status, and carries `error.type`. An exception recorded on a span uses
the standard exception span event with its `exception.type`, `exception.message`
and bounded `exception.stacktrace` attributes. No secrets, raw payloads or
sensitive provider responses reach any of them.

#### Span events

Span events use stable names — `payment.authorized`, `inventory.reserved`,
`compensation.started`. Identifiers and error detail are attributes, subject to the
same privacy rules as every other signal here.

Span events are not emitted in a loop. A span is not built to hold hundreds of
events; per-item detail belongs in correlated logs, and cross-trace fan-out belongs
in span links.

#### Baggage

`pkg/obsx` installs the composite propagator, so baggage set on a context
propagates automatically on every instrumented call. The platform default is **no
application baggage**: a new key requires review, because it crosses every
downstream hop and adds per-request header cost.

When a key is approved:

- Baggage is **immutable** — each set returns a new context, and only that context
  carries the value downstream.
- Backends **do not store baggage**. To analyse it later, copy the value onto a
  span attribute or a log attribute at the service that consumes it.
- Its legitimate use is steering behaviour at runtime — a feature flag or variant —
  not retrospective analysis, which is what span attributes are for.
- **Security:** baggage is attached to outbound calls indiscriminately, including
  third-party calls. Never put PII, tokens or secrets in it, and strip keys before
  calling an external provider. This rule is part of the privacy boundary in
  [§ Privacy, redaction and sampling](#privacy-redaction-and-sampling), not a
  tracing detail.

#### Probe and health filtering

Probe, health and reflection routes are filtered before the span starts, so a
skipped route emits neither a span nor a metric. The skip list is shared between
the trace and metric paths so the two cannot drift, and it is pinned by unit test.

### Metrics contract

Metrics continue to use the OTel Meter API and OTLP export through the shared
obsx provider. VictoriaMetrics is the only application metrics store. The
PromQL name is an ingest rendering of the canonical dotted OTel instrument
name; application code declares only the OTel name.

#### Instrument ownership

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

#### Instrument and aggregation rules

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

#### Cardinality and replay

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

### Continuous profiling contract

All ten Go services and both worker modes use obsx.SetupProfiling and push
directly to Pyroscope. Profiling remains non-critical to the business path:
startup failure emits a sanitized warning and does not make readiness false.

#### Profile types and cost

The shared helper owns CPU, allocation objects/bytes, in-use objects/bytes,
goroutine, mutex count/duration and block count/duration profiles. Service code
does not start a second profiler or change process-global runtime sampling.

Mutex and block profiles have measurable runtime cost. Their shared sampling
rates remain centrally configured; a change requires workload benchmarks and a
documented overhead budget. PROFILING_ENABLED is the emergency kill switch.
Disabling profiling must not change logs, metrics, traces or application
readiness.

#### Profile identity and labels

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

#### Trace-to-profile correlation

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

#### Profiling lifecycle

The profiler starts only after endpoint and identity validation succeeds.
Upload errors are surfaced without logging credentials or the full endpoint.
Shutdown is attempted within the process shutdown budget after work drains.
Because the current SDK stop call does not honor its context internally, tests
must prove the process budget remains bounded or the implementation must wrap
that limitation explicitly.

### Resource and propagation contract

All API and worker processes set service.name, service.version and
deployment.environment.name. Kubernetes namespace, pod, container and region
are platform enrichment where available. The implementation must eliminate the
current difference where worker build metadata is present but API release
version is absent.

W3C Trace Context plus Baggage is configured once, independently of tracer,
logger and exporter enablement. A disabled exporter must not cause a service to
stop extracting or injecting valid context. No application business logic
generates trace_id, span_id or parent_span_id.

## Rollout & rollback

After acceptance and ADR approval, implementation lands in this order:

1. Build and contract-test slogx, resource versioning and independent W3C propagation.
2. Migrate all listed services, workers, consumers and mockpay using the remediation matrix in [research.md](./research.md).
3. Verify metric contracts in VictoriaMetrics and profile coverage in Pyroscope.
4. Replace ClickHouse dashboards, query examples and runbooks in the same release.
5. Run Compose and Kind end-to-end audits across all four signals.

The full dependency order, acceptance criteria, checkpoints and risks are in
[delivery-plan.md](./delivery-plan.md).

Rollback pins the shared package and all application releases back to their
prior versions and restores the matching dashboard configuration together.
There is no dual-write compatibility mode. A partial rollout is a failed
rollout and must not be promoted.

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

## Resulting decisions

| Decision | ADR | Status |
|----------|-----|--------|
| Logging facade and native event representation | ../../adr/ADR-070-otel-native-logging-facade/ | Planned |
| Canonical event, access and privacy data contract | ../../adr/ADR-071-telemetry-event-data-contract/ | Planned |
| Fleet cutover and ClickHouse query migration | ../../adr/ADR-072-telemetry-clean-cutover/ | Planned |
| Metric instrument, cardinality and replay contract | ../../adr/ADR-073-application-metrics-contract/ | Planned |
| Continuous profiling identity and overhead contract | ../../adr/ADR-074-continuous-profiling-contract/ | Planned |
| Tracing sampling, span and baggage contract | ../../adr/ADR-075-application-tracing-contract/ | Planned |

ADR-070 through ADR-075 are **reserved numbers**, not existing records — the highest
record in the repository today is ADR-069. The paths are written as plain text
because the directories do not exist yet; they become links when each record is
created at `Proposed` during architecture review.

## Implementation History

No implementation has started. This RFC is provisional and must complete
architecture review and resulting ADR review before code, manifests, dashboards
or docs/api are changed as target state.

## Related

- [Research and remediation matrix](./research.md) — source research, audit evidence and full-fleet scope
- [Normative target contract](#normative-target-contract) — proposed cross-signal rules in this RFC
- [delivery-plan.md](./delivery-plan.md) — implementation plan after acceptance
- [Telemetry standards audit](../../../observability/audits/2026-09-16-telemetry-standards.md) — current-state evidence
- [API logging contract](../../../api/logs.md) — current deployed contract
- [API observability contract](../../../api/observability.md) — current deployed contract
- [API metrics contract](../../../api/metrics.md) — current deployed contract
- [API profiling contract](../../../api/profiling.md) — current deployed contract
- [API tracing contract](../../../api/tracing.md) — current deployed contract
- [Temporal contract](../../../api/temporal.md) — current deployed workflow rules
- [Workflow registry](../../../api/workflows.md) — current worker topology and ownership
- [Graceful shutdown](../../../api/graceful-shutdown.md) — current lifecycle contract
- [OTel Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [OTel HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/)
- [OTel RPC semantic conventions](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/)
- [SigNoz events versus logs comparison](https://signoz.io/comparisons/opentelemetry-events-vs-logs/) — secondary operational guidance; OTel remains normative

---
_Last updated: 2026-09-16_
