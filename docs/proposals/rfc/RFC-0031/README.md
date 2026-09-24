# RFC-0031 Cross-signal telemetry standard and ClickHouse operations

| Status | Scope | Research | Created | Last updated |
|--------|-------|----------|---------|--------------|
| Accepted | platform-wide | [./research.md](./research.md) — gate passed 2026-09-16, Context7 rerun 2026-09-17 | 2026-09-16 | 2026-09-17 |

## Prerequisites

- [x] [./research.md](./research.md) merged; [research review gate](./research.md#research-review-gate) ticked
- [x] Context7 audit complete — rerun 2026-09-17 after the first pass recorded it unavailable; the log is in the [research footer](./research.md#context7-audit-log) and it changed four normative statements
- [x] Owner approved **ready for RFC**
- [x] Live verification recorded — local-stack and a fresh, seeded Kind cluster, 2026-09-17, in [research § Live verification](./research.md#live-verification); every claim it contradicted was changed to match
- [x] Mechanism detail stays in `./research.md`; this document summarises and links it
- [x] ADR-070 through ADR-076 created at `Accepted` / Adoption `Not started` with this RFC under [`docs/proposals/adr/`](../../adr/) — owner decision 2026-09-17, following the RFC-0028/RFC-0030 precedent of accepting the records with the RFC. `docs/api/` files to touch: `observability.md`, `logs.md`, `tracing.md`, `metrics.md`, `profiling.md`, `pkg.md`, `temporal.md` — the same seven the delivery plan names — synced only when Adoption is Complete, never at acceptance

## Summary

Adopt one application telemetry contract across logs, metrics, traces and
continuous profiles. Logging moves to pkg/logger/slogx behind one context-first
API with one tested redaction boundary — decided at architecture review on
2026-09-17; tracing keeps its sampling, span and
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
| Is the logging migration settled? | Yes — `pkg/logger/slogx`, owner decision 2026-09-17; the audit's opposing view stays recorded under [Open disagreement: keep Zap](#open-disagreement-keep-zap) |
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

pkg/logger/slogx becomes the only application logging facade (owner decision,
2026-09-17). Its diagnostic methods emit structured slog records. Its context-first event method emits a record whose
stable `event` attribute is a lower-case dot-separated identifier. The message is
short display text; values belong in typed attributes.

The package owns severity mapping, common resource attributes, native trace and
span correlation, recursive redaction, output formatting, sampling and test
helpers. It writes safe structured JSON to stdout and directly creates the OTel
record used for export.

**Why slog rather than the current Zap path.** The two official bridges are
equivalent in what they produce: `otelzap` and `otelslog` both map time, message,
level and attributes, with the message as the record body. Neither is a
conformance argument for the other. The reasons that do hold are: `log/slog` is the standard
library, so the facade adds no logging dependency to every service; its
context-first `Handler` interface matches the correlation and redaction seam this
contract needs; a single implementation gives one tested redaction boundary
instead of one per adapter; and the shared package already carries a slog bridge —
`temporalx.WithLogger` routes SDK logs through `zapslog` into slog — although no
service has wired it yet, so it is a capability, not a deployed fact. The cost is a fleet
migration of every production logging call site, and the OTel Go Logs API is still pre-1.0 —
the facade exists to contain that instability in one module.

The release removes the legacy application contract: Zap imports, otelzap, and
access fields named path, status, code, duration, client_ip, user_agent and
peer. The `event` attribute is kept. Access records use pinned OTel HTTP and RPC semantic
conventions, with an explicit duration unit where needed. W3C traceparent and
baggage propagation are installed independently of exporters.

Metrics keep their current OTel-to-VictoriaMetrics path. RFC-0031 standardizes
instrument ownership, units, bounded attributes, explicit histogram boundaries,
temporality and Temporal replay semantics; it does not add a second metrics
pipeline. Profiles keep the direct pyroscope-go path and receive a closed label
allowlist, centrally owned runtime sampling, non-critical failure policy,
bounded shutdown and an honest manual trace-to-profile workflow.

### User Stories

- As an on-call engineer, I can find payment.authorization.failed by its stable
  event attribute, follow its trace, and see safe error metadata without parsing
  a message.
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
| pkg/logger/slogx facade over slog plus direct OTel Logs API | Standard-library logging with no added dependency; one policy boundary; context-first handler seam; slog already reached through `zapslog` in `temporalx` | Fleet migration of every production logging call site; OTel Logs API remains pre-1.0 | Proposed |
| Zap facade over the existing `logger/zapx` | Much smaller diff; keeps the adapter every service already pins | Keeps a third-party logging dependency in every service and leaves the redaction boundary split across adapters | Rejected — owner decision 2026-09-17; the audit's recommendation is kept on record under § Open disagreement: keep Zap |
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
and `otelzap` produce equivalent records, so no conformance argument separates
them. What remains is a dependency and consistency argument.

**Resolved 2026-09-17.** The owner chose the slog facade at architecture review,
for the reasons in § Proposal, and accepted the audit's cost without the benchmark
it asked for: the work the two options share — closing the shared package's SDK and
Zap type leaks (Task 1.1c) — is the larger part of either path, and the platform is
greenfield, so the moment to pay the migration is now rather than after a second
generation of call sites has accumulated. The audit's recommendation stays on record
here so that the trade-off is visible to whoever reads this after the cutover, and
the redaction test suite the audit asked for is still required — as an acceptance
criterion of Task 1.1, not as a precondition of the decision.

## Decision outcome

**Chosen option:** **pkg/logger/slogx facade over slog plus direct OTel Logs API**,
exactly as § Alternatives names it, together with **preserve VictoriaMetrics and
Pyroscope with stricter shared contracts**. The remaining § Alternatives rows are
rejected.

**Rationale:** the facade is chosen on standard-library, dependency and
single-redaction-boundary grounds — one implementation of redaction, no logging
dependency added to any service, and a fleet that is greenfield so the migration is
paid once. It is explicitly **not** chosen on conformance grounds: the two official
bridges produce equivalent records, and the audit's recommendation to keep Zap stays
recorded under [§ Open disagreement: keep Zap](#open-disagreement-keep-zap). The two
backend rows are accepted without a competing option; they fix the scope. Against
§ Goals: one context-first API with one tested redaction boundary (the first goal) is
satisfied only by a single facade, and the fleet-wide cutover with no legacy contract
(the last goal) is what makes the greenfield moment the cheap one.

**Namespace prefix (ADR-076):** the owner chose to **keep the bare platform
namespaces** (`order.*`, `payment.*`, `checkout.*`, `inventory.*`, …) and register
each as an explicit exception in the semantic-convention registry, rather than adopt
a `duynhlab.` prefix. The accepted cost is that an upstream convention claiming one of
those namespaces forces a rename later; the Rego policy admits exactly the registered
set and denies any new bare namespace, so the exception list cannot grow silently.

**Decided:** 2026-09-17, owner (`duynhne`), at architecture review; recorded in
ADR-070 (facade) and ADR-076 (namespace rule). All resulting ADRs are `Accepted` at
Adoption `Not started` — acceptance installs nothing and changes no application
contract.

## Architecture & Diagrams

The target-state diagram answers where each application signal is created and
stored.

Legend: cyan is an application process, blue is the Collector, green is shared
data, purple is the platform UI, and the pale signal colors distinguish logs,
metrics, traces and profiles.

~~~mermaid
flowchart LR
    A["Service or worker"] --> L["pkg/logger/slogx (proposed)<br/>logs"]
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

## Design Details

The template asks five questions of any design; the contract below is long enough
that they deserve direct answers here.

**How is it enabled or disabled?** Per signal, through the environment the shared
package already reads: `OTEL_LOGS_ENABLED` and `OTEL_METRICS_ENABLED` are inputs on
every service's input provider, `TRACING_ENABLED` gates the tracer provider, and
`PROFILING_ENABLED` gates the profiler. There is no switch below the facade: a service
cannot enable "some" of the logging contract, because the contract is the facade.
`PROFILING_ENABLED` is today a literal in each domain ResourceSet rather than an input,
so its scope is a domain, not a service — the profiling contract says so and the
delivery plan decides whether to promote it.

**Does enabling it change default behaviour?** Yes, in three visible ways and in no
hidden one. The access record changes shape (pinned semantic-convention attribute
names replace `path`/`status`/`code`/`duration`, and `client_ip`/`user_agent`/`peer`
disappear). Two business histograms gain explicit boundaries, so their quantiles
become meaningful and stop being comparable with the numbers they produced before.
Every service's `cmd/main.go` stops importing SDK and Zap types once the shared
package closes its type leaks. Sampling rates, backends, retention and the Collector
topology are unchanged by this RFC.

**Can it be disabled again once enabled?** Per signal, yes, through the same flags,
and disabling one signal must not disturb another — a rule the propagation section
exists to enforce, since today turning tracing export off also removes W3C
propagation. The contract as a whole cannot be "disabled back" to the previous
shape: there is no compatibility mode, by decision, and rollback is a version pin of
the shared package and the services together.

**How does an operator determine the feature is in use?** From the telemetry itself,
not from a config flag. A process on the new contract shows the four approved labels
with non-empty values in Pyroscope, `spanmetrics_calls_total` series with its
`service_name`, records in the 90-day store whose `ScopeName` is the shared facade's
package path and whose attribute keys are the canonical ones, and — once the registry
exists — a passing `weaver registry live-check`. A service on the old contract is
visible by the same means: a `path` key in its log attributes is proof it has not
adopted the release.

**Drawbacks of enabling it.** They are real and this section is where they live.
Every production logging call site in every service changes in one release train
with no dual-emission window, so a half-finished rollout is a failed one and must be
rolled back whole. The OpenTelemetry Go Logs API the facade wraps is pre-1.0; the
facade exists to contain that, but a breaking upstream change lands on the shared
package first and on the fleet second. The fleet lint policy adds a gate every repo
must pass, and the shared package must first close type leaks in its own public API —
a breaking release of the most-depended-on module. The closed profile-label set is
stricter than the as-built policy and removes a latitude services currently have.
The Collector stays a single, stateful replica until a separate decision splits it,
so this RFC standardises production without yet standardising transport capacity.
None of these is an argument against the change; each is a cost the owner accepts by
accepting the RFC.

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

### Shared-package rule

This is the rule the rest of the contract exists to serve, so it comes first.

A service does not choose its own telemetry libraries. It imports the shared
package and the OpenTelemetry **API**; the SDK, every exporter, every bridge and
every backend client are linked in exactly one place, `pkg/obsx`, and a change to
how the fleet emits telemetry is a change to the shared package followed by a
version bump, never an edit in a service. At ten services this is a convention. At
a thousand it is the only thing that keeps four signals correlatable, because it
turns "did every team do it right" into "did the one package do it right".

The rule follows OpenTelemetry's own library guideline — instrumented code depends
on the API alone, the SDK is configured once per process by its owner — so it is
not stricter than upstream, it is upstream applied to a fleet. The as-built
contract already states the boundary for the OTel packages
([`docs/api/observability.md` § API vs SDK vs contrib](../../../api/observability.md));
this RFC extends the same table to logging and profiling and, more importantly,
gives it an enforcement mechanism, which today it does not have.

| Signal | A service may import | A service must not import | Owned by |
|---|---|---|---|
| Logs | `pkg/logger/slogx` | `go.uber.org/zap`, `zapcore`, `log/slog` directly, `github.com/rs/zerolog`, `go.opentelemetry.io/contrib/bridges/*`, `go.opentelemetry.io/otel/log` | `slogx` (API), `obsx` (export) |
| Metrics | `go.opentelemetry.io/otel/metric`, `otel/attribute`; instruments via `obsx` helpers | `go.opentelemetry.io/otel/sdk/metric`, `otel/exporters/*`, `github.com/prometheus/client_golang` | `obsx` |
| Traces | `go.opentelemetry.io/otel/trace`, `otel/attribute`, `otel/codes`; spans via `obsx.StartSpan` | `go.opentelemetry.io/otel/sdk/trace`, `otel/exporters/*`, `otel/propagation` setup | `obsx`, `httpmw`, `grpcx` |
| Profiles | nothing — `obsx.SetupProfiling` only | `github.com/grafana/pyroscope-go`, `runtime.SetMutexProfileFraction`, `runtime.SetBlockProfileRate` | `obsx` |
| Transport | `pkg/httpmw`, `pkg/grpcx` | `contrib/instrumentation/*` directly | `httpmw`, `grpcx` |

Tests are exempt, exactly as the shared package already exempts its own tests: an
in-memory reader or exporter is the correct way to assert on telemetry.

**Why the API is allowed and not merely tolerated.** A span kind, an attribute or a
status code is an API type; the shared helpers take them as parameters
(`obsx.StartSpan(ctx, scope, name, ...trace.SpanStartOption)`,
`obsx.AddSpanAttributes(ctx, ...attribute.KeyValue)`). A rule that forbade the API
would forbid using the helpers. The line is drawn where OpenTelemetry draws it: API
in, SDK out. Profiling shows the model at its cleanest — the helper exposes no
Pyroscope type, and today no service imports `pyroscope-go` at all.

**Enforcement.** Today nothing enforces any row of this table. Every service lints
with an identical `.golangci.yml` whose enabled set does not include `depguard`, and
`go.uber.org/zap`, `log/slog`, `zerolog` and `client_golang` are unguarded fleet-wide,
the shared package included. The shared CI workflow every service already calls at a
pinned commit accepts only a config *path*, so a fleet policy has nowhere to live.
The mechanism this RFC adopts:

1. One policy file, `golangci-policy.yml`, in the shared-workflows repository,
   containing `depguard` rules shaped like the shared package's existing
   `otel-sdk-only-in-obsx` rule (with the same `!$test` exemption). The file
   originally also carried a `forbidigo` rule against a seconds-unit histogram
   declared without explicit boundaries; that rule is **withdrawn** — the silent
   failure it guarded is closed at its source instead, by the shared View that
   gives the fleet boundaries to every histogram whose unit is `s`
   ([§ Metrics contract](#metrics-contract), ADR-073 amended 2026-09-23).
2. The shared lint job gains a second, additive pass that checks out that file and
   runs `golangci-lint run --config=<policy>`; a service keeps its own quality config
   untouched. The linter has no config inheritance or remote include, so a checked-out
   file passed by path is the mechanism, not a workaround.
3. The policy starts **non-blocking** for one release, then blocks. The shared
   package's own wording travels with it: *if the rule rejects your import, the
   import is wrong — not the rule; escalate to a human before touching it.*
4. The policy exempts `cmd/**` **until Task 1.1c lands**, because today the shared
   package itself forces `main()` to import SDK and Zap types through its public
   signatures — `obsx.WithTracerProviderFactory(func(...sdktrace.TracerProviderOption))`,
   `obsx.ZapCore(...) zapcore.Core`, `obsx.TraceContext(ctx) zap.Field`. Those are
   leaks in the contract, not misbehaviour in services, and the rule cannot be honest
   about the fleet until they are closed. When they are, the exemption is removed and
   the rule says what the table says.

The linter versions must converge as part of this: the shared package lints at one
golangci-lint version and the services at another, so a policy validated in one
place is not proven in the other.

### Semantic-convention registry

The shared-package rule fixes *where* telemetry is produced. It does not fix *what
the names are*, and at fleet scale names are the contract: a query written against
`order.id` on one service must mean the same thing on the next one. Today the
platform's own attributes and metrics — `order.*`, `payment.*`, `checkout.*`,
`inventory.*` — are defined in prose across `docs/api/` and enforced by review. Two
things are wrong with that at scale, and both are already visible at ten services.

First, the names live in bare namespaces. OpenTelemetry's naming guidance asks
application authors to prefix their own attributes with a unique application or
reverse-domain name, and warns specifically against bare OpenTelemetry-style
namespaces because a future semantic-convention release can claim them. No file in
`docs/api/` states a namespace rule at all. Second, prose drifts from code: the audit
found the shared-package contract describing a library as unadopted while every
service used it, and three files disagreeing on how many trace sinks exist. Nothing
generated those pages from a source of truth, so nothing could catch the drift.

The mechanism the wider industry converged on, and that OpenTelemetry now ships as
its own tool, is a **semantic-convention registry as code**: attributes, metrics and
events declared in YAML, reviewed through pull requests like any other contract,
with documentation and language constants **generated** from it and conformance
**checked** in CI. OpenTelemetry Weaver provides exactly this:

| Weaver capability | What it gives this platform |
|---|---|
| A registry manifest that **depends on** the upstream semantic conventions at a pinned version and **imports** the standard attributes it reuses | The platform defines only its own names; `http.*`, `rpc.*`, `db.*` come from upstream at the same version `pkg/obsx` pins |
| `registry check` with **Rego policies** | Naming rules become executable — a prefix rule, a stability field, a unit on every metric — and a violation fails the pull request |
| `registry generate` with a **Go target** | The attribute keys and metric names in the shared package are generated, so a name changes in one YAML file and every service picks it up through a version bump |
| `registry generate` with a **markdown target** | The catalog sections of `docs/api/` are generated, which is the only durable cure for prose drift |
| `registry diff` | A breaking rename is detected as a schema change, not discovered by a broken dashboard |
| `registry live-check` against OTLP | Real telemetry from local-stack or Kind is compared to the registry, with a non-zero exit on violation — the conformance test a new service runs on day one |

This RFC adopts the registry as a **resulting decision, ADR-076**, and states the
one question it does not settle: **the namespace prefix.** Two honest options:

| Option | Cost | Benefit |
|---|---|---|
| Prefix every platform attribute and metric with `duynhlab.` (`duynhlab.order.id`) | Every existing dashboard, alert and runbook that names a platform attribute changes once; names get longer | Zero future collision risk; the rule is mechanical and a Rego policy enforces it |
| Keep bare `order.*`-style namespaces and register each one in the registry as a deliberate exception | Nothing changes today | A future upstream `order.*` or `payment.*` convention forces the rename anyway, at a worse time, and the exception list has to be maintained |

The registry is required either way. The prefix question was decided on 2026-09-17:
the owner **keeps the bare namespaces and registers each one as an explicit
exception**; ADR-076 records the decision and its Rego policy admits exactly that
registered set, so a new bare namespace fails review rather than accumulating. What
this section does not do is call the registry
a quick win. It touches the shared package, every service, the shared CI and
`docs/api/`, and it is where the catalog rows the previous telemetry standard left as
backlog finally get a home — it is program-sized work and is scheduled as such in the
delivery plan.

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
| Logs | stdout plus OTLP through the Collector | VictoriaLogs for 7-day operations; ClickHouse for 90-day SQL. Edge gateway access logs are filtered out of the VictoriaLogs pipeline and kept only in ClickHouse | What happened in this case and why? |
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
record additionally carries a stable `event` attribute. The stdout JSON and OTLP
record are two renderings of the same safe record.

Three forces shape the split below — the wide-record pattern large fleets converged
on, the cost of enforcing a schema too widely, and OpenTelemetry's own guidance on
what an event is. The reasoning and its sources are in
[research.md § How the wider industry splits events from logs](./research.md#how-the-wider-industry-splits-events-from-logs);
this section states only the resulting rule.

| Record kind | Use | Schema | Named |
|---|---|---|---|
| Canonical access record | One wide record per served HTTP or gRPC call, emitted once at the boundary | Fixed, owned by shared middleware | No — the call is already a span |
| Named business event | Durable outcome, state transition, retry exhaustion or compensation, at the commit point | Strict, registered in the event catalog | Yes |
| Diagnostic log | Investigation detail without a stable schema | Free | No |
| Span event | A milestone within a sampled span | Stable name, bounded count | Span-scoped |

The access record deliberately carries no event name. A served request already has a
span that owns its duration and outcome, so naming it as an event would duplicate
the span and contradict the rule above. It stays one wide, stably-named log record
that the on-call path reads directly and that joins to its span by trace ID.

A name is therefore a property of a **small, reviewed catalog**, not a fleet-wide
labelling exercise. The pressure to name everything is the failure mode: a catalog
that grows with every log line stops being queryable and becomes a second, weaker
copy of the message text.

Named records keep the deployed `event` attribute as their identifier, so no query
consumer has to learn a second name for the same thing during this cutover.

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
| Event | Accepts severity, stable name, display body and typed attributes; sets the `event` attribute |
| Diagnostic | Accepts severity, body and typed attributes; sets no event name |
| Attributes | Uses typed values, limits count/depth/value size and recursively redacts before every sink |
| Error | Maps typed errors to safe error.type; optional exception data and stack traces are bounded and redacted |
| Resource | Attaches service.name, service.version, deployment.environment.name and available Kubernetes identity |
| Output | Writes one safe JSON record to stdout and one equivalent OTLP LogRecord when logs export is enabled |
| Lifecycle | Flushes once with the process shutdown context after servers/workers finish draining |

The facade replaces direct Zap, slog, otelzap and OTel Logs API use in
application repositories; the import boundary and its enforcement are stated once in
[§ Shared-package rule](#shared-package-rule).

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
  `pkg/obsx` is denied by `depguard`. The facade needs only the API, so it stays
  inside that boundary. This is also why the facade is
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
| HTTP server summary | http.request.method, http.route, http.response.status_code; error.type — the status code — only for a 5xx | No raw URL path/query, client.address, network.peer.address or user_agent.original |
| gRPC server summary | rpc.system.name=grpc, rpc.method as the fully-qualified name, rpc.response.status_code in the spec spelling (`NOT_FOUND`); error.type only for the codes the server span marks Error | No peer address, no rpc.service, arbitrary metadata or raw protobuf |
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

The gRPC status key is `rpc.response.status_code`, not the `rpc.status_code` this
table first named: the pinned instrumentation (otelgrpc v0.71 on semantic conventions
v1.43) writes `rpc.response.status_code` on the server span, and an access record
that names the same fact with a different key cannot be joined to its span.
Corrected at the Task 0.2 freeze, measured against the module rather than the
research note.

### Event catalog and ownership

Every named event has an owner, schema and operational purpose. The catalog is
maintained beside the owning service contract after implementation; the initial
cutover catalog is reviewed in the shared package change.

The catalog is meant to stay small enough to read in one sitting. A class is
admitted when an operator would query it by name across services; anything an
operator would only read while following one request belongs in the access record
or a diagnostic log instead. Adding a class is a reviewed change to this table, not
a decision made at a call site.

The served HTTP or gRPC call is absent from this table by design; see
[§ Record model](#record-model). Its severity mapping, and the frozen list of names
each class admits, are in
[`docs/api/logs.md` § Event catalog](../../../api/logs.md#event-catalog).

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

| Environment | Edge rate actually applied | Service `OTEL_SAMPLE_RATE` |
|---|---|---|
| Base manifest (inherited by a future production cluster) | 50 — **applied nowhere today** | `0.1`, applying only to traces a service starts itself |
| Kind cluster | 100 — the local overlay patches the base value | `0.1` |
| Local-stack | 100 | `1.0` |

The base manifest says so itself: the 50 is "the number a future prod cluster
inherits", and it also records that nobody has done the storage arithmetic for it.
This RFC therefore states the applied rate per environment and does not describe 50
as a running configuration.

A sampled remote parent is always honoured. There is no environment-to-rate
auto-mapping: the rate is set explicitly per environment, and a change to it is a
volume and cost change that must be reviewed as one.

#### Span naming, kind and scope

Span names are stable operation classes — `checkout.confirm`, `inventory.reserve`,
`payment.capture`. Business identifiers never enter a span name; they are
attributes, added only when operationally justified. Note that span names and
event names are **different namespaces**: a span name is a two-part operation class,
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
| Span-derived RED | Collector span-metrics connector | Operational service-graph view; it is not a second application metric API. Its dimensions must use the attribute names of the pinned semantic conventions: the connector today declares `http.method`, a name the conventions have replaced with `http.request.method`, so that dimension is expected to be empty for service spans and is verified live in research; correcting it is an amendment to the span-metrics decision record, not a service change |

Every business metric records the operational question, owner, canonical name,
instrument type, unit, bounded attribute allowlist, retry/replay semantics,
dashboard/alert consumer and removal plan. It is emitted after the authoritative
outcome is known.

#### Instrument and aggregation rules

There are seven instrument types, not four — the synchronous family and its
asynchronous counterparts are separate choices, and the contract names both:

| Instrument | Sync / async | Measures |
|---|---|---|
| Counter | sync | a count of events that only grows |
| Observable Counter | async | a monotonic total cheap to read on demand |
| UpDownCounter | sync | a running total that rises and falls |
| Observable UpDownCounter | async | current additive state sampled per collection |
| Histogram | sync | the distribution of a measured value |
| Gauge | sync | a last-value written at the event, non-additive |
| Observable Gauge | async | a point-in-time sample read each collection |

- Selection is two questions, in order: is the value **additive**, and is it
  **monotonic**; then whether it is known at a decision point (sync) or sampled
  (async).
- Synchronous instruments record at the decision. Observable instruments sample
  cheap current state and must not perform blocking I/O in callbacks.
- **An Observable Counter callback must report the cumulative total, not the
  increment.** The SDK computes deltas between observations, so reporting
  increments silently corrupts every `rate()` built on that series. This failure
  is invisible in the instrument declaration and only shows up as a wrong rate,
  so it is a required review item for any async counter.
- Units use UCUM values and are instrument metadata, not suffixes in the OTel name.
- Temporality remains cumulative at the application SDK; the Collector
  delta-to-cumulative processor is a defensive boundary.

**The canonical fleet bucket set is fixed.** HTTP and gRPC duration histograms use
`0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 5, 10`, pinned by an SDK
View in the shared package. Every service uses exactly these values: divergent
boundaries break cross-service `histogram_quantile()` comparison and blunt SLO
precision. A service that overrides the View is a defect even when its own
dashboards look right.

**Why a new seconds histogram must declare boundaries.** The shared View matches
only the named HTTP and gRPC instruments. A brand-new business histogram matches no
View and falls back to the SDK default boundaries, which are **millisecond-shaped**
(`0, 5, 10, … 10000`). A sub-second operation then lands entirely in the first
bucket and every quantile collapses to approximately zero — a silent failure that
produces a plausible-looking dashboard. The instrument must pass the platform
bucket set explicitly at declaration, or an approved View must cover it.

This is exactly the state of the two known gaps: `order.inventory.commit_lag` and
`payment.reconciliation.run.duration` declare seconds and match no View. Non-time
histograms pick their own scale the same way — money at cent scale, ratings at
`1,2,3,4,5`. Boundaries come from the operational SLO or a measured distribution and
are then tested with p50, p95 and p99 queries.

**Names on the wire.** Application code declares the dotted OTel name only. On
ingest, a Counter gains `_total`, a Histogram explodes into
`_bucket`/`_sum`/`_count`, and a seconds-unit histogram gains a `_seconds` infix.
Dashboards and alerts query the rendered name; the contract is the dotted one.

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
directly to Pyroscope. `mockpay` does not — its manifest carries no telemetry
environment at all, for any signal — and this RFC brings it under the same contract
rather than leaving one Go process outside a fleet-wide standard. Profiling remains
non-critical to the business path: startup failure emits a sanitized warning and does
not make readiness false.

#### Profile types and cost

The shared helper owns ten profile types: CPU, allocation objects/bytes, in-use
objects/bytes, goroutine, mutex count/duration and block count/duration. Service
code does not start a second profiler or change process-global runtime sampling.

The Go SDK currently declares an eleventh type, `goroutine_leak`. It is **excluded
by decision, not by omission**: goroutine growth is already visible through the
goroutine profile and the runtime goroutine-count metric, and the platform has no
alert or runbook that would consume a separate leak profile. Admitting it later is a
change to this contract, reviewed with an overhead measurement like any other
profile type.

Mutex and block profiles have measurable runtime cost because they change
process-global runtime sampling — the shared helper sets the mutex profile fraction
and the block profile rate itself, and applies them only after the profiler has
started successfully, so a misconfigured endpoint costs nothing. Those rates stay
centrally configured; a change requires a workload benchmark and a documented
overhead budget.

`PROFILING_ENABLED` is the kill switch, and this contract states its real scope:
today it is a literal in each domain ResourceSet, not a per-service input, so
turning profiling off is a GitOps commit that disables **every service in that
domain**. Either the delivery plan promotes it to a per-service input or the
operational documentation says plainly that no per-service switch exists. Whichever
is chosen, disabling profiling must not change logs, metrics, traces or readiness.

#### Profile identity and labels

Profiles share service identity with OTel signals. The allowed label set is
closed:

- service_name;
- service_namespace;
- deployment_environment;
- service_version.

No other OTel resource attribute automatically becomes a profile label. User,
workflow, run, request, trace, order, session, payment, SKU and pod identifiers,
raw paths, addresses, secrets and arbitrary input are forbidden.

The closed set is a **target, not the as-built state**. Measured per service on the
Kind cluster, an application profile carries the contract's `service_name` and
`service_namespace` (workers also `service_version`) plus two labels the contract does
not name: `pyroscope_spy`, which the SDK stamps on every profile, and `span_name`,
which the span-scoped CPU profile adds. On local-stack the SDK additionally surfaces
`hostname`, `target`, `service_git_ref` and `service_repository`. Each undeclared label
is either admitted here explicitly — `span_name` is what makes a CPU profile
span-scoped and stays; `pyroscope_spy` is a constant and is harmless — or stripped in
the shared helper; the delivery plan decides per label, and the verification gate
counts the label set exactly.

The cluster also runs a **second profile producer** the application contract does not
cover: the profiling agent scrapes itself and the Pyroscope server, and those series
carry Kubernetes discovery labels (`pod`, `container`, `namespace`,
`app_kubernetes_io_*`). They are platform self-observation, they never appear on a
service's profiles, and they stay out of this contract — but a reader of the global
label list must know they are there, or the closed set looks violated when it is not.

**This narrows the deployed contract, and the change is deliberate.** The current
as-built policy also permits "low-cardinality deployment identity from resource
attributes", which is open-ended: it has no list, so two services can disagree about
what qualifies and both be compliant. Closing the set to four labels makes profile
identity comparable across services and makes a violation testable. Widening it
again is a reviewed change to this table, not a judgement made per service.

**Two of the four labels are empty today, not one.** The profiler builds its labels
by parsing `OTEL_RESOURCE_ATTRIBUTES` and looking up `service.namespace`,
`deployment.environment` and `service.version`. No manifest puts
`deployment.environment` in that variable — environment arrives through a separate
`DEPLOYMENT_ENVIRONMENT` variable that the tracer and meter path maps to the current
key `deployment.environment.name`, which the profiler does not look for. So
`deployment_environment` is empty on every profile, workers included, and would stay
empty even if this contract were implemented exactly as written above. The fix is
that the profiler derives its labels from the **same resource** the other signals
use, not from a second parse of the environment; the delivery plan carries it.

`service_version` is empty for a different reason: API services have no version
source at all. A concrete one already exists and is not wired — every **domain
service** input provider carries an `image_tag` under Flux image automation, and it
feeds only the container image tag. The delivery plan uses that input rather than
inventing a second version source. `mockpay` is the exception: its image is pinned by
hand by design, so it needs its own version input. Downstream consumers are already
waiting — the metrics agent promotes `service.version`, and cluster dashboards
render deployment annotations from it, so those panels are blank for every API
service today.

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
deployment.environment.name. Kubernetes identity is **application-side platform
enrichment**: the manifests inject `K8S_NAMESPACE_NAME`, `K8S_POD_NAME` and
`DEPLOYMENT_ENVIRONMENT` from the Downward API, and the shared package maps them to
`k8s.namespace.name`, `k8s.pod.name` (plus `service.namespace`) and
`deployment.environment.name`. No collector-side enrichment exists — the collector
runs no `k8sattributes`, `resource` or `transform` processor — so **only those three
Kubernetes attributes are present**. Nothing sets container, node, deployment,
cluster, pod UID or region.

That gap is visible in storage: the ClickHouse logs schema materialises eight
`k8s.*` columns and five of them (`cluster.name`, `container.name`, `deployment.name`,
`node.name`, `pod.uid`) are empty for every record, because no producer writes them.

> **Amended 2026-09-24 (Task 4.4).** The gateway Collector now runs `k8sattributes`
> and a `resource/cluster` insert on its two logs pipelines, and all seven `k8s.*`
> columns are filled for application records. The Downward API attributes stay the
> SDK's contract; the Collector adds only what the API server knows. One addition
> reaches every signal: service pods declare `k8s.container.name` in
> `OTEL_RESOURCE_ATTRIBUTES`, because the `migrate` init container leaves the
> processor two containers to choose from.
No dashboard reads them today, so it is schema debt rather than a broken consumer.
The contract states the honest set and leaves two choices to the delivery plan:
populate the missing keys with a collector `k8sattributes` processor — the
OpenTelemetry-recommended path and the only one that can supply
`k8s.deployment.name` — or drop the dead columns.

The implementation must eliminate the current difference where worker build
metadata is present but API release version is absent; the source for the latter is
named under [§ Profile identity and labels](#profile-identity-and-labels).

W3C Trace Context plus Baggage is configured once, independently of tracer,
logger and exporter enablement. A disabled exporter must not cause a service to
stop extracting or injecting valid context. No application business logic
generates trace_id, span_id or parent_span_id.

### Collector contract

The premise that "once the application contract is standard, shipping through the
Collector is easy" is true only while the Collector is not itself a bottleneck. This
section states what the Collector is today and the conditions under which its shape
must change, so that the fleet does not discover them from an outage.

**Today.** One Collector `Deployment` with a single replica, `memory_limiter` at
800 MiB, `batch`, `delta_to_cumulative` (five-minute staleness) on the metrics
pipeline, a `span_metrics` connector fed from the traces pipeline, and a
`filter/drop_edge_logs` processor that removes the edge gateway's access logs from
the VictoriaLogs pipeline while the ClickHouse pipeline keeps them. Exporters: OTLP
HTTP to VictoriaTraces, VictoriaLogs and the metrics agent, Prometheus remote write for
the span-derived metrics, and the ClickHouse exporter for logs and traces. No
Kubernetes enrichment, no tail sampling, no load-balancing tier.

**Why it cannot simply be scaled horizontally.** Two of those components are
stateful per stream. `delta_to_cumulative` accumulates per series, and the
span-metrics connector aggregates per trace; a second replica behind a plain Service
splits a series or a trace across replicas and produces wrong numbers rather than
half the load. OpenTelemetry's own deployment guidance is explicit that
data-aware routing — a `loadbalancing` exporter keyed on trace ID or metric name —
is **required** for tail-based sampling and for cumulative-to-delta conversion. So
the Collector today is correct at one replica and incorrect at two, and that is a
property of its configuration, not a capacity number.

**Contract.**

- The Collector is a **platform component with one owner**; a service never runs its
  own Collector, sidecar or exporter, and never targets a backend directly.
- The current single-replica shape is acceptable while all three hold: fewer than the
  fleet-scale trigger of services, active series under the budget stated in
  [§ Fleet scale](#fleet-scale), and no tail sampling. When any one fails, the shape
  becomes **agent → gateway**: a stateless agent tier that receives OTLP, applies
  `memory_limiter` and resource enrichment, and forwards through a `loadbalancing`
  exporter to a gateway tier that owns the stateful processors and the exporters.
  That change is an ADR, not a replica count.
- **Degradation policy per signal when the Collector is unavailable.** The SDKs
  queue and then drop; a service must never block a request on export, and readiness
  must not depend on the Collector. Metrics are cumulative at the SDK so a gap heals
  on reconnect; traces and logs in the gap are lost and the loss is visible in the
  Collector's own health metrics, which VictoriaMetrics scrapes. Profiling already
  behaves this way and is the model.
- **Kubernetes enrichment moves to the Collector** when the agent tier exists, with
  the `k8sattributes` processor and pod association by IP or UID; until then the
  Downward API mechanism stated under
  [§ Resource and propagation contract](#resource-and-propagation-contract) is the
  contract, and the empty materialised columns are debt the delivery plan clears.
  *Amended 2026-09-24:* Task 4.4 did not wait for the agent tier. The gateway
  Collector enriches its logs pipelines, associating by the SDK's pod name and
  namespace first and then by connection IP. Traces and metrics are left
  unenriched there, because span-metrics turns every resource attribute into a
  label.
- The edge-log exception is part of the routing table, not folklore: edge access
  logs go to the 90-day store only, by decision, and the two log pipelines are the
  mechanism.
- **The edge and the fleet speak two semantic-convention generations, and the
  Collector is where that is reconciled.** Measured on local-stack: spans from the
  services carry the pinned names (`http.request.method`, `http.response.status_code`,
  `http.route`, `url.path`, `user_agent.original`, `client.address`), while spans from
  the edge gateway carry the pre-stability names (`http.method`, `http.status_code`,
  `http.url`, `user_agent`, `peer.address`) plus Envoy's own (`upstream_cluster`,
  `component`, `response_flags`, `guid:x-request-id`). Any consumer that joins edge
  and service spans on an HTTP attribute, including the span-metrics dimensions,
  sees two vocabularies. A service must not paper over this; the Collector owns the
  normalisation — a `transform` processor that maps the edge's legacy keys onto the
  pinned names at ingest, or an edge configuration change if the gateway gains
  stable-convention output — and the span-metrics amendment in the delivery plan is
  decided together with it.

### Fleet scale

Everything above is written for the current ten services and two workers and must
still be true at a hundred or a thousand. These are the rules that only bite at that
size, stated now because they are cheapest to adopt before they are needed.

**Shared-package version policy.** Today the module that owns the SDK is pinned at
three different versions across ten services, the transport module at two, and the
mechanism that moves a version is a per-repository dependency bot that already groups
all shared-package modules into one pull request. That mechanism scales; the absence
of a rule does not. The rule: a service may run at most **one minor version behind**
the shared package's current release; the release notes state the floor; a service
below the floor fails the fleet lint policy. Converging the three current `obsx`
versions is a prerequisite of the lint rollout, because a policy that depends on the
shared API's shape cannot be checked against three shapes.

**Contract changes are greenfield, not migrations.** This standard is defined once,
fresh. A change to it is a shared-package release that every service adopts through
the same version bump; there is **no compatibility shim, no dual-emission window and
no contract-version attribute on records**. The rollout train is: shared package →
services in domain waves → consumers (dashboards, alerts, runbooks) in the same
release. A service that has not adopted the release is a service below the floor,
and the lint policy names it.

**Cardinality has a budget, and the budget has arithmetic.** The per-attribute
denylist under [§ Cardinality and replay](#cardinality-and-replay) is necessary and
not sufficient: the binding constraint at fleet scale is total active series.
Today ten services emit roughly 2,800 active series between them, dominated by the
13-bucket HTTP and gRPC histograms multiplied by route and method. The budget is a
**per-service ceiling** set from that measurement, a **fleet ceiling** equal to the
metrics store's tested ingest capacity, and the SDK's own attribute-set limit as the
last backstop. A new service is admitted with a number, and a dashboard shows the
budget against the fleet total.

**Onboarding is a path, not a conversation.** A new service gets: the shared package
at the current floor, the canonical `cmd/main.go` bootstrap from the as-built
contract, the domain ResourceSet defaults for every telemetry variable, and a
**conformance check** it can run on day one — `weaver registry live-check` against
its own OTLP output in local-stack. Passing that check is the definition of
"instrumented"; nothing else is.

**Cost is written down before the rate is raised.** The edge manifest records that
the storage arithmetic for fifty-percent sampling has never been done for either
the 90-day or the 7-day trace store. This RFC does not change the rate and does not
pretend the sum exists; raising the applied rate anywhere requires the sum first.

## Security considerations

The security content of this RFC is gathered here so a reviewer can find it in one
place; the normative text stays in the subsections it belongs to.

- **Data leaving the process.** Redaction runs before *both* sinks, stdout and OTLP,
  recursing through groups, maps, arrays, errors and exception data, with a named
  minimum key list and case-insensitive matching. Client IPs, full User-Agent strings,
  peer addresses, request and response bodies, DSNs, payment secrets, PAN-shaped
  values and arbitrary headers are removed by policy. The current access logger
  emits two of those fields today, which the audit records as a privacy-policy
  violation this RFC closes.
- **Spans carry more than the log policy allows, and the RFC says so rather than
  hiding it.** Measured on local-stack: the shared HTTP instrumentation puts
  `client.address`, `user_agent.original` and `url.path` on every server span, and the
  shared database and cache instrumentation put `db.statement` and
  `db.connection_string` on every client span. The connection string is safe — the
  instrumentation reduces it to scheme, host and port, and none of 4,268 sampled
  values carried a credential. The statement is not: cache statements embed the lock
  key, and the lock key embeds the business identifier, so an identifier the log
  policy would redact reaches the trace store through a span. All of these are
  semantic-convention attributes emitted by upstream instrumentation, not by service
  code, so a service cannot remove them and the shared-package rule is the only place
  they can be governed. The tracing task in the delivery plan decides, per attribute,
  whether it is permitted on spans (bounded, operationally useful) or dropped by a
  shared span processor; until then the asymmetry between the log policy and the span
  payload is a known, recorded gap.
- **Baggage.** Baggage rides every outbound call, including calls to third-party
  providers. The platform default is no application baggage; an approved key must
  never carry PII, tokens or secrets and must be stripped before an external call.
- **Idempotency keys** are retained across retries and are never logged raw.
- **Trust boundary.** The shared-package rule is also a network rule: a service talks
  to the Collector and to nothing else in the telemetry plane. Backend credentials
  — ClickHouse, Pyroscope, the metrics agent — exist only in the Collector's and the
  shared package's configuration, never in a service. That is what the shared-package
  rule buys the security reviewer.
- **Admission and policy.** No new privileged workload, host access or namespace is
  introduced; the Collector's `Deployment` is unchanged by this RFC. The lint policy
  runs in CI, not in the cluster. When the agent tier is introduced later, the
  `k8sattributes` processor needs a read-only cluster role for pods and namespaces,
  which is recorded in that ADR. *Amended 2026-09-24:* Task 4.4 added the processor
  to the gateway Collector with a read-only ClusterRole on **pods only**. With
  this extraction set the processor never lists namespaces, ReplicaSets or nodes.

## Observability & SLO impact

An observability standard changes the instruments the platform's own SLOs are built
on, so this section states what moves and what an operator watches.

- **Histogram boundaries change meaning.** The two business histograms that gain
  explicit boundaries produce quantiles that are correct going forward and
  incomparable with their history; any recording rule or Sloth SLO reading them is
  re-baselined at the cutover, and the discontinuity is annotated on the dashboards
  that show them. The HTTP and gRPC duration histograms keep the canonical 13-bucket
  set and are unaffected.
- **Dashboards and alerts move in the same release.** Every ClickHouse query and
  Grafana panel that reads a legacy access key is replaced in the release that stops
  emitting the key; an alert on a removed key would otherwise go silent rather than
  fire, which is the failure mode to guard against. Error-budget panels may show a
  step at the cutover and that step is expected.
- **New signals to watch during rollout.** `spanmetrics_calls_total` per service, as
  the RED continuity check that a service is still emitting after adoption; the
  Collector's own health metrics for queue depth and dropped items, since a schema
  mismatch on the ClickHouse exporter fails at insert time and shows up there first;
  Pyroscope label coverage, as the proof that the four labels are populated; and the
  count of records with a `path` attribute in the 90-day store, which must fall to
  zero as the fleet adopts the release.
- **What does not change.** Sampling rates, retention, the backends and the
  Collector topology are unchanged, so no SLO that depends on volume or storage moves
  because of this RFC.

## Rollout & rollback

After acceptance and ADR approval, implementation lands in this order:

1. Build and contract-test slogx, resource versioning and independent W3C propagation.
2. Cut every listed service, worker, consumer and mockpay over to the shared package using the remediation matrix in [research.md](./research.md).
3. Verify metric contracts in VictoriaMetrics and profile coverage in Pyroscope.
4. Replace ClickHouse dashboards, query examples and runbooks in the same release.
5. Run Compose and Kind end-to-end audits across all four signals.

The full dependency order, acceptance criteria, checkpoints and risks are in
[delivery-plan.md](./delivery-plan.md).

This is a **greenfield** standard. The contract is defined once, fresh, and adopted
as one release train; there is **no migration mechanism** — no dual-write
compatibility mode, no legacy-field window, no contract-version attribute to let two
shapes coexist. The remediation matrix is an inventory of what each service replaces,
not a bridge between two contracts.

Rollback pins the shared package and all application releases back to their
prior versions and restores the matching dashboard configuration together. A
partial rollout is a failed rollout and must not be promoted.

## Verification gates

| Gate | Evidence |
|---|---|
| Named event | A Collector-to-ClickHouse test reads a stable event name for each named record |
| Redaction | Nested attributes, errors and exception data cannot leak forbidden values to either output |
| Transport | HTTP/gRPC contract tests assert one summary, semantic attributes, low-cardinality route/method and probe filtering |
| Temporal | Replay test proves no duplicate export/metric side effect; activity tests prove terminal and compensation records correlate |
| Tracing | The effective sampling rate per environment is asserted against the edge configuration actually applied, not the base manifest; every manual span carries exactly one kind matching its layer and a package-path scope; an expected business rejection leaves span status unset while an unexpected failure sets Error with `error.type`; no application baggage key exists without a registered review; the probe skip-list is pinned by a unit test shared between the trace and metric paths |
| Metrics | No IDs reach labels; each new histogram has approved seconds or domain buckets; retry semantics are tested |
| Profiles | All processes expose the approved profile types and four-label allowlist; disable/failure paths preserve readiness; trace correlation is verified as manual or supported by the deployed datasource |
| Resource and propagation | API and worker records contain required resource data; W3C extraction/injection works with exporters disabled |
| ClickHouse | Dashboards, saved SQL and runbooks query canonical attributes and native trace IDs, and contain no removed access keys |
| Release | Compose and Kind audit passes browser checkout, HTTP, gRPC, Temporal, expected business rejection, dependency failure and both correlation directions |

## Resulting decisions

| Decision | ADR | Status |
|----------|-----|--------|
| Logging facade and event catalog | [ADR-070](../../adr/ADR-070-logging-facade-and-event-catalog/) | Accepted / Not started |
| Canonical event, access and privacy data contract | [ADR-071](../../adr/ADR-071-telemetry-event-data-contract/) | Accepted / Not started |
| Fleet cutover with no migration mechanism | [ADR-072](../../adr/ADR-072-telemetry-clean-cutover/) | Accepted / Not started |
| Metric instrument, cardinality and replay contract | [ADR-073](../../adr/ADR-073-application-metrics-contract/) | Accepted / Not started |
| Continuous profiling identity and overhead contract | [ADR-074](../../adr/ADR-074-continuous-profiling-contract/) | Accepted / Not started |
| Tracing sampling, span and baggage contract | [ADR-075](../../adr/ADR-075-application-tracing-contract/) | Accepted / Not started |
| Platform semantic-convention registry and bare-namespace rule | [ADR-076](../../adr/ADR-076-semantic-convention-registry/) | Accepted / Not started |

All seven were created at `Accepted` with this RFC on 2026-09-17, following the
RFC-0028 and RFC-0030 precedent; Adoption moves off `Not started` only as the
delivery plan lands, and `docs/api/` is synced when Adoption is Complete.

## Implementation History

| Date | Event |
|---|---|
| 2026-09-16 | Research gate passed on an official-source fallback; RFC opened at `provisional` with the telemetry audit (#1062) |
| 2026-09-17 | Second and third revisions: facade renamed to `pkg/logger/slogx`, log-record representation taken out of scope, shared-package rule for all four signals, tracing / Collector / fleet-scale / registry contracts, template sections, live verification on local-stack and a fresh Kind cluster (#1063) |
| 2026-09-17 | Bring-up exposed that the RustFS bucket Job's MinIO client image had left Docker Hub; fixed separately (#1064) |
| 2026-09-17 | **Accepted** at architecture review: facade `pkg/logger/slogx`, bare namespaces with registered exceptions; ADR-070 through ADR-076 created at `Accepted` / `Not started` |

No implementation has started. Phase 0 of the delivery plan is now eligible; no code,
manifest, dashboard or `docs/api/` contract changes until it runs.

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
- [Shared package contract](../../../api/pkg.md) — module layout, layering and the per-service pin ledger

`docs/api` defects found while writing this RFC, tracked separately from it (they
describe the as-built contract and are fixed there, not here): the metrics contract's
footer counts five trace sinks where the tracing and observability contracts count
two; the logging contract's first example shows the target access-log schema as
live output while a later section says it is not yet as-built; the shared-package
contract still lists the archived `auth` service as a live consumer; the tracing
contract's production-recommendations table still shows a ten-percent sampling row
after the base rate moved to fifty; and the docs index still advertises exemplars
in the metrics guide while the platform does not promise them.
- [OTel Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [OTel HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/)
- [OTel RPC semantic conventions](https://opentelemetry.io/docs/specs/semconv/rpc/rpc-spans/)

---
_Last updated: 2026-09-17 — **Accepted** at architecture review (owner, 2026-09-17): facade `pkg/logger/slogx`, bare namespaces with registered exceptions; ADR-070…076 created at `Accepted / Not started`. third revision. Added the shared-package rule for all four signals with its enforcement mechanism, a tracing contract with gate, task and ADR-075, Collector and fleet-scale contracts, a semantic-convention registry as ADR-076, and the Design Details, Security considerations and Observability & SLO impact sections. Corrected the sampling table, Kubernetes enrichment, profile labels and mockpay scope to deployed reality, and verified the contract live on local-stack and a fresh Kind cluster (research § Live verification). The standard is greenfield: no migration mechanism. Earlier the same day: Context7 rerun, facade renamed to `pkg/logger/slogx`, log-record representation taken out of scope._
