# OpenTelemetry (OTel)

OpenTelemetry is the common language every service, worker, and the edge use to describe
"what just happened" during a request. This doc explains it from zero, shows
how this platform uses it today (Collector topology, sampling, operations).
**Service instrumentation policy** (normative rules for PRs) lives in
[**Application observability**](../../api/observability.md).

## Quick facts

| Item | Value |
|------|-------|
| SDK | OpenTelemetry Go (version owned by the consumed `pkg/obsx/go.mod`), wired by **`pkg/obsx` `SetupObservability`** (one call in `main()`) |
| Semconv | **v1.41.0**, pinned in `pkg/obsx` — bumps only via a deliberate `obsx` release |
| Collector | `otel-collector` (contrib distribution, `monitoring` namespace) |
| Signals | Traces ✅ (10 services, 2 workers, and the edge) · Metrics ✅ (OTLP push, fleet-wide since RFC-0014 P3; `/metrics` scrape retired) · Logs ✅ (slogx/otelslog → OTLP, fleet-wide since RFC-0014 P4) |
| Protocol | Services and workers use OTLP/HTTP protobuf on `:4318`; the cluster Collector also accepts OTLP/gRPC on `:4317`, which the edge's tracing provider uses |
| Propagation | W3C Trace Context (`traceparent`); the edge propagates it natively (Envoy Gateway `telemetry.tracing`, no plugin config) |
| Sampling | `ParentBased(TraceIDRatioBased)` head sampling. Kind and Compose use 100%. The base 50% edge setting is planned and overridden in deployed local configuration. ParentBased respects incoming decisions; service ratios apply to new roots (see [Sampling](#sampling)) |
| Trace backends | **Two sinks** — VictoriaTraces (7d, fast path) + ClickHouse `otel_traces` (90d SQL). Tempo and Jaeger retired under [RFC-0027](../../proposals/rfc/RFC-0027/README.md) |
| Service identity | `OTEL_SERVICE_NAME` + Downward API envs, injected by the app ResourceSets |

## How to use this area

The documents in this area serve different learning needs. None replaces the
original RFC, which remains the historical decision and rollout record.

| Goal | Start here |
|------|------------|
| Build the mental model from zero (API vs SDK, signals, OTLP, propagation, the old-vs-new migration story) | [OTel fundamentals](fundamentals.md) |
| Understand the Collector (components, patterns, deployed pipelines) | [Collector](collector.md) |
| Implement a Go service step by step | [Implementation guide](../../api/telemetry-implementation.md) |
| Review rules for service code and PRs | [Application observability](../../api/observability.md) |
| Understand the deployed signal paths | [How it works in this platform](#how-it-works-in-this-platform) |
| Operate or troubleshoot export | [Operations](#operations) |
| Read the decision and rollout history | [RFC-0014](../../proposals/rfc/RFC-0014/) |

## OTel in plain words

When a user clicks "checkout", the request travels through the edge, the order
service, the shipping service, a database, a cache. If something is slow or
broken, you need the story of that trip. **Telemetry** is that story, and it
comes in three forms — the three OTel **signals**:

- **Trace** — the *map of the trip*: which services the request visited, in
  what order, and how long each stop took.
- **Metrics** — the *dashboard gauges*: counters and timers aggregated over
  many requests (requests/sec, error rate, p99 latency). Great for alerting,
  useless for explaining one specific slow request.
- **Logs** — the *notes scribbled along the way*: individual events with
  detail ("payment declined for order 42").

Before OpenTelemetry, every vendor had its own agent, wire format, and API —
switching backends meant re-instrumenting the code. OTel is the CNCF-standard
answer: **one API, one SDK, one wire protocol (OTLP)**, and any backend that
speaks it. This platform leans on that portability: the same span stream fans
out to its trace sinks without touching a line of Go, and RFC-0014
extends the same idea to metrics and logs.

## The building blocks — and who imports what

The OTel spec's core rule: *libraries depend only on the API; if no SDK is
installed, API calls are no-ops.* That split is why instrumentation can live
in shared code without forcing a telemetry runtime on anyone:

| Layer | Go modules | Who imports it here |
|---|---|---|
| **API** | `go.opentelemetry.io/otel`, `otel/trace`, `otel/metric`, `otel/log` (bridge API) | Library/shared code: `pkg/obsx`, `pkg/grpcx`, middleware |
| **SDK** | `otel/sdk`, `otel/sdk/metric`, `otel/sdk/log`, `otel/sdk/resource` | **Only `pkg/obsx.SetupObservability`** — services never wire the SDK directly |
| **Exporters** (SDK plugins) | `otlptracehttp`, `otlpmetrichttp`, `otlploghttp` | `pkg/obsx` only |
| **Contrib** | `otelgin`, `otelgrpc` (+`filters`), `instrumentation/runtime`, `bridges/otelslog` | `pkg/httpmw` owns HTTP, `pkg/grpcx` gRPC, `pkg/logger/slogx` the bridge, `pkg/obsx` runtime setup |

Other concepts, in one line each:

- **Span / trace** — a span is one leg of the trip (one handler, one DB
  query); a trace is every span sharing one `trace_id`, forming a tree.
- **Context propagation** — the `trace_id` travels in the W3C `traceparent`
  header (or gRPC metadata); the edge stamps it natively, `pkg/grpcx`/HTTP
  middleware pass it on.
- **Resource attributes** — the name tag on everything a process emits
  (`service.name`, `k8s.namespace.name`, …). Built by `obsx` from env.
- **OTLP** — the common wire protocol for all three signals. Services and
  workers standardize on **HTTP/protobuf `:4318`** (D-6). The cluster Collector
  also exposes OTLP/gRPC on `:4317`, which the edge's tracing provider uses
  (Envoy's tracing speaks gRPC only) — the Go application path itself stays on
  HTTP. The Collector then translates and routes each signal to the
  backend-specific ingest endpoint.
- **Collector** — the mail room between producers and backends: receivers →
  processors → exporters, one pipeline per signal. Producers know one
  address; the collector owns the fan-out.
- **Views** — SDK-side reshaping of metrics at aggregation time (bucket
  boundaries, dropped attributes). This platform's Views are **mandatory
  policy**, not tuning (see below).

### What OpenTelemetry does not replace

OpenTelemetry standardizes how telemetry is created, described, transported,
and processed. It is not the database, query language, dashboard, or alert
evaluator. Keeping those boundaries clear makes the stack easier to reason
about and keeps backend changes out of service code.

| Responsibility | This platform uses | OTel role |
|----------------|--------------------|-----------|
| Instrumentation API and SDK | `pkg/obsx`, `otelgin`, `otelgrpc`, `otelslog` | Defines and emits signals |
| Wire protocol | OTLP/HTTP protobuf | Standard transport |
| Processing and routing | OpenTelemetry Collector | Receives, batches, normalizes, and fans out |
| Storage and query | VictoriaMetrics, VictoriaLogs, ClickHouse, VictoriaTraces | Not an OTel responsibility |
| Visualization and alerting | Grafana, VMAlert, VMAlertmanager, Sloth | Consumes backend data; not an OTel responsibility |

## Platform instrumentation policy (RFC-0014 — normative)

> **Canonical location:** [Application observability](../../api/observability.md)
> — rules 1–10, middleware order, env table, three-layer spans, and correlation
> fields. This section is not duplicated here.

Rationale and rollout history: [RFC-0014](../../proposals/rfc/RFC-0014/README.md).

## How it works in this platform

Use the [Collector routing diagram](collector.md#component-model) for the exact
input-to-store topology and the [pipeline table](collector.md#the-deployed-pipelines)
for processor order. This lookup answers which path to inspect for a missing signal:

| Producer / signal | Current configured route | Important boundary |
|---|---|---|
| Services/workers: traces | OTLP/HTTP :4318 → Collector → VictoriaTraces + ClickHouse | Sampled; manual span semantics remain the service's responsibility |
| Services/workers: metrics | OTLP/HTTP :4318 → Collector → vmagent → VictoriaMetrics | SDK RED feeds SLOs independently of trace sampling |
| Services/workers: logs | OTLP/HTTP :4318 → Collector → VictoriaLogs + ClickHouse | slogx redacts before stdout and OTLP |
| Edge spans | OTLP/gRPC :4317 → Collector → trace stores | ParentBased honors incoming sampling decisions |
| Edge access logs | OTLP/gRPC :4317 → Collector → ClickHouse | Filtered from VictoriaLogs; stdout remains available |
| Non-SDK pod logs | Vector → VictoriaLogs; Vector :4319 → Collector → ClickHouse | Dedicated receiver prevents duplicate VictoriaLogs ingest |
| Derived span metrics | traces → span_metrics → remote write → VictoriaMetrics | Exploration of sampled spans, not the SLO numerator |
| Profiles | Go SDK → Pyroscope | Bypasses Collector; manual trace/profile pivot |

Vector skips application and edge pods labelled for OTLP logs. Check the
[logging pipeline](../logging/README.md) before changing that selection: adding
another path can duplicate records instead of fixing missing data.

> Historical note: at the RFC-0014 P3 cutover, checkout-service had not yet
> been deployed to the cluster, so the planned `legacy-checkout` scrape fence
> was dropped at landing (ADR-016). RFC-0015 P5 later deployed checkout and
> checkout-worker directly on the unified OTel path. No app service is scraped
> for metrics today.

- **Traces** — unchanged: every service and worker exports spans via `obsx`;
  the edge opens the root span; the collector fans out to two sinks.
- **Metrics** — OTLP push, fleet-wide: services and workers emit semconv
  metrics through the OTel Meter API to the collector, which forwards them to vmagent's OTLP
  ingest and on to VMSingle. The `/metrics` scrape and client_golang RED were
  removed at the P3 cutover. Exemplars are not available on this path
  (VictoriaMetrics won't-fix, D-14). Details, mapping tables and the consumer
  checklist: [RFC-0014](../../proposals/rfc/RFC-0014/README.md).
- **Logs** — service and worker slogx records pass through the level-gated
  otelslog bridge to VictoriaLogs, where `TraceId` becomes a **queryable `trace_id` field** (this
  is what repairs the traces↔logs correlation). Vector handles the configured non-SDK pod log path.

### Cluster and local-stack differences

The same application instrumentation runs in both environments, but the
Collector and backend topology are intentionally different. This distinction
matters when a local query returns a series that does not exist in the cluster.

| Concern | Kubernetes | Local-stack |
|---------|------------|-------------|
| Producer sampling | Kind: 100%; the base 50% edge value is **planned**, overridden by the local overlay. Inspect rendered service env for root sampling | 100% at the edge (`samplingRate: 100`) and `1.0` at services |
| Collector receivers | OTLP/HTTP `:4318`, OTLP/gRPC `:4317`, and Vector-only OTLP/HTTP `:4319` | OTLP/HTTP `:4318` and OTLP/gRPC `:4317` (same reason) |
| Trace fan-out | VictoriaTraces **and ClickHouse** | VictoriaTraces **and ClickHouse** — the two now match |
| RED metrics | Application SDK metrics **plus** the `span_metrics` connector ([ADR-057](../../proposals/adr/ADR-057-span-metrics-in-collector/)) | Application SDK metrics plus a spanmetrics compatibility connector |
| Infrastructure logs | Vector DaemonSet | Container logging path used by the local stack |

The local spanmetrics connector is a compatibility aid, not the source of the
cluster RED metrics. Cluster dashboards and alerts use the semconv metrics
emitted directly by `otelgin` and `otelgrpc`.

## Sampling

Keeping every production trace is expensive, so the platform samples — but this
is a platform built to be studied, and a trace that was never sampled is a
question nobody can answer later. The planned cluster baseline therefore selects **half**
of new edge-rooted traffic (`samplingRate: 50`), raised from an inherited 10 that
RFC-0024 had copied from Kong without reasoning about it. Local-stack and Kind
set the rate to full so a learner can inspect every demo request.

**Head sampling** means the decision is made once, when the trace starts, per
`trace_id`, via `TraceIDRatioBased` — not per span, and never revisited.

One consequence that looks like an incident and is not: **`spanmetrics_calls_total`
is derived from spans**, so it scales with the edge rate. The day a cluster moves
its baseline 10 → 50, the RED dashboard's rates jump 5× with no change in traffic,
while the SLO board beside it does not move at all — Sloth and the Apdex recording
rules read the SDK's own `http_server_request_duration_seconds` /
`rpc_server_call_duration_seconds`, and no alert reads spanmetrics. The two boards
disagreeing by a factor that just changed is arithmetic, not a regression.

Two knobs, and they are not the same knob. The edge's `samplingRate` (a percent,
0–100) selects new roots; ParentBased respects an incoming parent decision.
Untrusted sampled parents can therefore bypass an assumed ratio cap. Choose
the ingress trust policy before using sampling as a cost bound. A service's `OTEL_SAMPLE_RATE` (a
ratio, 0.0–1.0, set by the environment) is wrapped in `ParentBased`, so it applies
**only** where that service is itself the root — background work, scheduled
workflows, anything not entering through the gateway. Earlier observation
of edge-parented worker spans does not prove all future background work has a
parent; verify both parented and root work in the candidate environment.

The subtlety is *who decides*. The design: the edge (root) decides once,
everyone downstream honours it — that is what the `ParentBased` wrapper does
(the official default, `parentbased_traceidratio`: sample the root by ratio,
then follow the parent's decision). All services and workers configure
`ParentBased(TraceIDRatioBased(rate))` (now inside `obsx.SetupObservability`),
and the edge's own sampler is `ParentBased` too, so a service's own ratio only
applies when it is the *root* of a trace; when it has a parent (the
edge→service hop, or a service→service gRPC hop) it always honours the
parent's `sampled` flag. Concretely, per the OTel Go SDK: a sampled remote
parent → `AlwaysOn`, an unsampled one → `AlwaysOff`. This makes sampling
*complete* — a trace the edge keeps is kept whole downstream. Details in
[tracing/architecture.md](../tracing/architecture.md).

## Operations

Environment variables read by `obsx.ConfigFromEnv`: see
[Application observability § Environment variables](../../api/observability.md#environment-variables).

Quick verification:

- **Traces arriving** — Grafana → Explore → **VictoriaTraces** → pick
  `service.name = order` from the service dropdown; or straight at the API:
  `curl -s localhost:10428/select/jaeger/api/services`.
- **OTLP metrics arriving** — VMSingle/vmui:
  `http_server_request_duration_seconds_bucket{app="<svc>"}` with 13 buckets.
- **OTLP logs arriving** — Explore → **VictoriaLogs** →
  `trace_id:"<id>"` returns the request's lines.
- **Collector health** — `kubectl -n monitoring logs deploy/otel-collector-opentelemetry-collector`;
  zpages on `:55679`.

## References

- Official: [opentelemetry.io/docs/concepts](https://opentelemetry.io/docs/concepts/) · [Go SDK](https://opentelemetry.io/docs/languages/go/) · [versioning & stability](https://opentelemetry.io/docs/specs/otel/versioning-and-stability/) · [Collector](https://opentelemetry.io/docs/collector/) · [sampling](https://opentelemetry.io/docs/concepts/sampling/) · [VictoriaMetrics OTel](https://docs.victoriametrics.com/victoriametrics/integrations/opentelemetry/) · [VictoriaLogs OTel](https://docs.victoriametrics.com/victorialogs/data-ingestion/opentelemetry/)
- In-house: [OTel fundamentals](fundamentals.md) (concepts + old-vs-new migration story) · [Collector](collector.md) · [Application observability](../../api/observability.md) · [RFC-0014](../../proposals/rfc/RFC-0014/README.md) (design record + tracking) · [tracing/README.md](../tracing/README.md) · [tracing/architecture.md](../tracing/architecture.md) · [logging/README.md](../logging/README.md) · [metrics/histograms.md](../metrics/histograms.md) · [metrics/streaming-aggregation.md](../metrics/streaming-aggregation.md) · [../platform/envoy-gateway.md](../../platform/envoy-gateway.md)
