# RFC-0014 explained: from client_golang to OpenTelemetry

A from-zero walkthrough of **why and how** the platform moved its observability
from the old hand-rolled Prometheus setup to **OpenTelemetry (OTLP push)** —
told with old-vs-new diagrams and plain-language analogies. Start here if the
stack is new to you; the deep-dives ([metrics](metrics/metrics-apps.md),
[traces](tracing/README.md), [logs](logging/README.md),
[policy](opentelemetry.md)) assume you already know this story.

| | |
|---|---|
| **What changed** | Metrics + logs moved from pull/Vector to **OTLP push**; traces were already OTel. One SDK wires all three. |
| **When** | RFC-0014 P0–P5 (2026-07); metrics cutover P3, logs wave P4 |
| **In-process** | `obsx.SetupObservability()` (`duynhlab/pkg`) — one call, all signals |
| **Transport** | OTLP/HTTP → OpenTelemetry Collector → backends |
| **Backends** | VictoriaMetrics (metrics), VictoriaLogs (logs), Tempo/Jaeger/VictoriaTraces (traces), Pyroscope (profiles) |
| **The one rule** | Instrument once, in `pkg/obsx`; services never touch the SDK directly |

---

## Why this doc exists

Observability has a lot of moving parts and a lot of jargon (SDK, exporter,
collector, OTLP, semconv, pull vs push…). If you have never set it up before,
the manifests and the policy page are hard to read cold. This doc builds the
mental model **once**, comparing the old world we came from with the new one, so
the rest of the docs make sense.

One sentence to anchor everything: **every service now hands all of its
telemetry to one local SDK, which pushes it to a central Collector, which sorts
it and forwards each signal to the right database.** The rest is detail.

---

## 1. The big picture — old vs new

**Before RFC-0014.** Each Go service hand-wrote Prometheus metrics with
`client_golang`, exposed them on an HTTP `/metrics` endpoint, and waited to be
**scraped**. Logs were written to stdout in three different shapes (zap,
zerolog, clog) and a Vector agent tailed every container. Traces already used
OpenTelemetry. Three different instrumentation styles, and metric→trace
correlation depended on **exemplars** (which our metrics database never
supported).

```mermaid
flowchart TB
    subgraph OLD["BEFORE RFC-0014 (hybrid, pull-based)"]
        direction TB
        svcO["Go service<br/>client_golang /metrics :8080<br/>+ zap/zerolog/clog → stdout<br/>+ OTel traces"]
        sm["ServiceMonitor<br/>job=microservices"]
        vecO["Vector<br/>(tails every pod)"]
        vmO[(VictoriaMetrics)]
        vlO[(VictoriaLogs)]
        tO[(Tempo/Jaeger)]
        svcO -.->|"Prometheus SCRAPES /metrics (pull, 15s)"| sm --> vmO
        svcO -.->|"stdout JSON"| vecO --> vlO
        svcO -.->|"OTLP traces"| tO
    end
    classDef metric fill:#ffe8cc,stroke:#e8590c,color:#111;
    classDef log fill:#d3f9d8,stroke:#2f9e44,color:#111;
    classDef trace fill:#c5f6fa,stroke:#0c8599,color:#111;
    class vmO metric;
    class vlO log;
    class tO trace;
    style OLD fill:#ffe3e3,color:#111;
```

**After RFC-0014.** Every service calls one function, `obsx.SetupObservability()`.
That wires the OpenTelemetry SDK for **all three signals** and **pushes** them
over OTLP to the Collector. No `/metrics` endpoint, no scraping of app services,
no hand-written metrics. Logs ride the same SDK (a zap→OTLP bridge). Correlation
is now a real `trace_id` field on every log line.

```mermaid
flowchart TB
    subgraph NEW["AFTER RFC-0014 (unified, OTLP push)"]
        direction TB
        svcN["Go service<br/>obsx.SetupObservability()<br/>otelgin · otelgrpc · zap→OTLP tee"]
        col[/"OpenTelemetry Collector"/]
        vmN[(VictoriaMetrics)]
        vlN[(VictoriaLogs)]
        tN[(Tempo · Jaeger · VictoriaTraces)]
        svcN -.->|"OTLP push (metrics·logs·traces) :4318"| col
        col -->|"metrics"| vmN
        col -->|"logs (trace_id field)"| vlN
        col -->|"traces"| tN
    end
    classDef otc fill:#a5d8ff,stroke:#1971c2,color:#111;
    classDef metric fill:#ffe8cc,stroke:#e8590c,color:#111;
    classDef log fill:#d3f9d8,stroke:#2f9e44,color:#111;
    classDef trace fill:#c5f6fa,stroke:#0c8599,color:#111;
    class col otc;
    class vmN metric;
    class vlN log;
    class tN trace;
    style NEW fill:#e7f5ff,color:#111;
```

What actually moved: **metrics** (pull → push, P3) and **logs** (Vector-only →
OTLP push, P4). **Traces** were already OTel; RFC-0014 just folded their wiring
into the same one-call setup. `checkout-service` is the lone exception — it was
never migrated and still runs the old client_golang code, so it's a handy live
reference of "before."

---

## 2. Who's who — components and their jobs

Think of the whole pipeline as a **central post office**:

- Your service writes a "letter" (a metric point, a log line, a span). The
  **SDK** (`obsx`) is the mailbox on your desk — it sticks the return address on
  (`service.name`, `trace_id`, k8s pod) and hands the letter to a courier.
- The **exporter** is the courier — it drives the letter over OTLP to the post
  office.
- The **Collector** is the central post office: letters arrive at the
  **receiver** (drop-off counter), pass through **processors** (sorting,
  batching, franking), and leave via **exporters** (delivery routes) to the
  right warehouse.
- The **backends** (VictoriaMetrics/Logs/Traces, Tempo, Pyroscope) are the
  warehouses that store and index the mail so Grafana can look it up.

| Component | Where | Job |
|---|---|---|
| `pkg/obsx` (SDK wiring) | in every Go service | One call builds the Tracer/Meter/Logger providers, the resource labels, and the exporters. The only place instrumentation is configured. |
| `otelgin` / `otelgrpc` | in the HTTP/gRPC middleware | Auto-record spans **and** the semconv HTTP/RPC metrics — no hand-written middleware. |
| zap + `otelzap` tee | in the logger | Application logs go to stdout **and** are teed into the OTLP log pipeline. |
| **OpenTelemetry Collector** | `monitoring` ns (cluster) / compose (local) | The post office: receive OTLP, process, fan out each signal to its backend. |
| **vmagent** | `monitoring` ns | Receives app metrics over OTLP, translates names to Prometheus style, relabels, and remote-writes to VictoriaMetrics. Also scrapes **infra** exporters. |
| **VictoriaMetrics** | backend | Stores metrics; PromQL. |
| **VictoriaLogs** | backend | Stores logs; LogsQL; `trace_id` is a first-class field. |
| **Tempo / Jaeger / VictoriaTraces** | backend | Store traces (cluster fans out to all three; VictoriaTraces is the local + pilot store). |
| **Pyroscope** | backend | Continuous profiles; linked from spans. |
| **Vector** | DaemonSet | Ships logs for everything that has **no** OTel SDK (databases, Kong access log, Postgres query plans, the frontend, infra pods). |
| **Grafana** | UI | One pane over all backends; pivots between signals via `trace_id`. |

---

## 3. Metrics — pull vs push

**Old (pull).** The service kept counters in memory and exposed them at
`/metrics`. Prometheus/vmagent connected **in** every 15 s and scraped them. The
service had to run an HTTP handler and register every metric by hand.

```go
// BEFORE — checkout-service/middleware/prometheus.go (client_golang, still live there)
var reqDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
    Name:    "request_duration_seconds",
    Buckets: []float64{0.005, 0.01, /* … */, 10},
}, []string{"method", "path", "code"})
// + r.GET("/metrics", gin.WrapH(promhttp.Handler()))   // scraped by ServiceMonitor job=microservices
```

**New (push).** The service builds nothing by hand. `otelgin` records the
semconv histogram automatically; the SDK's `PeriodicReader` **pushes** a
snapshot to the Collector every 15 s. There is no `/metrics` endpoint on the app
anymore.

```go
// AFTER — one call in main(), that's it
obs, _ := obsx.SetupObservability(ctx, obsx.ConfigFromEnv())
// otelgin (wired by the tracing middleware) emits http_server_request_duration_seconds automatically.
// No promauto, no /metrics handler, no ServiceMonitor.
```

```mermaid
sequenceDiagram
    participant P as Prometheus/vmagent
    participant S as Go service
    participant C as OTel Collector
    Note over P,S: OLD — pull
    loop every 15s
        P->>S: GET /metrics
        S-->>P: text exposition
    end
    Note over S,C: NEW — push
    loop every 15s
        S->>C: OTLP export (metric snapshot)
        C->>C: process + forward to vmagent → VictoriaMetrics
    end
```

The metric **names** changed too (`request_duration_seconds` →
`http_server_request_duration_seconds`, labels `code/path/method` →
`http_response_status_code/http_route/http_request_method`) because OTel uses
**semantic conventions**. vmagent translates the OTLP names to Prometheus style
on ingest. Full detail: [metrics/metrics-apps.md](metrics/metrics-apps.md).

---

## 4. Logs — Vector-only vs OTLP tee

**Old.** Three services used three logging libraries; all wrote JSON to stdout;
one Vector DaemonSet tailed every container and shipped the lines to
VictoriaLogs. The catch: `trace_id` was **not** a queryable field, so "show me
the logs for this trace" silently returned nothing.

**New (P4).** The fleet converged on `zapx`. The logger is **teed**: the same
lines still go to stdout (for `kubectl logs`), and a second core
(`obs.ZapCore`, an `otelzap` bridge) sends them over OTLP to the Collector →
VictoriaLogs, where `trace_id` **is** a real field. Vector stays — but only for
things without an SDK (databases, Kong access log, Postgres `auto_explain`
plans, the frontend). It skips the app pods so no line is ingested twice.

```mermaid
flowchart LR
    subgraph svc["Go service"]
        z["zap logger"]
        z --> so["stdout (kubectl logs)"]
        z -.->|"otelzap tee"| ex[/"OTLP log exporter"/]
    end
    subgraph noni["Non-instrumented workloads"]
        infra["DBs · Kong · frontend<br/>(no SDK)"]
        vec["Vector<br/>(skips app pods)"]
        infra -.->|"stdout"| vec
    end
    ex -.->|"OTLP :4318"| col[/"OTel Collector"/]
    col -->|"VL-Stream-Fields: service.name"| vl[(VictoriaLogs)]
    vec -->|"jsonline"| vl
    classDef otc fill:#a5d8ff,stroke:#1971c2,color:#111;
    classDef log fill:#d3f9d8,stroke:#2f9e44,color:#111;
    class ex,col otc;
    class vl log;
    style svc fill:#eef2ff,color:#111;
    style noni fill:#d3f9d8,color:#111;
```

Detail and the dual-path rationale: [logging/README.md](logging/README.md).

---

## 5. Traces — the `traceparent` thread

Traces were OpenTelemetry from the start, so nothing structural changed — but
they're the thread that ties the other signals together, so here's how they
flow. A request enters at Kong, which starts the root span and injects a **W3C
`traceparent`** header. Every hop (HTTP via `otelgin`, gRPC via `otelgrpc`)
reads that header, continues the same trace, and injects it onward. The SDK
samples with **ParentBased(10%)** — if the parent was sampled, the child is too,
so a trace is never half-captured. All spans push over OTLP to the Collector,
which fans out to Tempo + Jaeger + VictoriaTraces (cluster) or VictoriaTraces
(local).

```mermaid
flowchart LR
    kong["Kong<br/>root span + traceparent"] -->|"HTTP + traceparent"| a["service A<br/>(otelgin)"]
    a -->|"gRPC + traceparent"| b["service B<br/>(otelgrpc)"]
    a -.->|"OTLP"| col[/"OTel Collector"/]
    b -.->|"OTLP"| col
    col --> tempo[(Tempo)]
    col --> jaeger[(Jaeger)]
    col --> vt[(VictoriaTraces)]
    classDef otc fill:#a5d8ff,stroke:#1971c2,color:#111;
    classDef trace fill:#c5f6fa,stroke:#0c8599,color:#111;
    class col otc;
    class tempo,jaeger,vt trace;
```

Detail: [tracing/README.md](tracing/README.md).

---

## 6. Push vs pull — the tradeoffs

Moving from pull to push isn't free; it's a deliberate trade. The table is the
"why" behind D-1…D-14 in the RFC.

| | Pull (old) | Push (new) |
|---|---|---|
| Who connects | the monitoring system reaches **in** to each service | the service reaches **out** to the Collector |
| Liveness signal | `up{}` is free — a failed scrape = down | `up{}` doesn't exist; we synthesize **D-4 heartbeat-absence** on `go_goroutine_count` (~5 min staleness lag) |
| Discovery | ServiceMonitor must find every target | no target list — services just push |
| Network direction | monitoring → services (needs scrape reachability) | services → Collector (fits egress/NetworkPolicy) |
| Cardinality control | at scrape/relabel | at **vmagent** (one choke point) + SDK Views |
| Failure mode | missed scrape = gap | Collector/pipeline down = gap (so we alert on the pipeline itself) |

The big win isn't push for its own sake — it's **one instrumentation standard**
for all three signals and a **real `trace_id` correlation** that exemplars never
gave us on VictoriaMetrics (exemplars are unsupported; accepted as D-14).

---

## 7. One request, end to end

Putting it together — a single browser request, and where each signal goes.
Notice everything shares one `trace_id`.

```mermaid
sequenceDiagram
    participant U as Browser
    participant K as Kong (edge)
    participant A as product (otelgin)
    participant R as review (otelgrpc)
    participant C as OTel Collector
    participant B as VM · VLogs · Tempo
    U->>K: GET /product/v1/public/products/1/details
    K->>A: HTTP + traceparent (root span)
    A->>A: otelgin span + http_server_* metric + zap log (trace_id)
    A->>R: gRPC GetProductReviews + traceparent
    R->>R: otelgrpc span + rpc_server_* metric + access-log (trace_id)
    A-->>C: OTLP traces + metrics + logs
    R-->>C: OTLP traces + metrics + logs
    C->>B: fan out per signal
    Note over B: one trace_id joins the span, the metrics exemplar-free, and the logs
```

In Grafana you land on a metric spike, pivot to the trace by time+service, open
the trace, click **traces→logs** (filters VictoriaLogs by `trace_id`), and
**traces→profiles** (Pyroscope, via the per-span `pyroscope.profile.id`).

---

## 8. Inside the Collector — the governance pipeline

The Collector is where platform-wide policy lives, so one config governs every
service. Each signal has its own pipeline: **receiver → processors → exporters**,
with a **connector** (spanmetrics) deriving metrics from traces locally.

```mermaid
flowchart LR
    subgraph col["OpenTelemetry Collector"]
        rcv[/"otlp receiver<br/>:4318 (+ :4317 cluster)"/]
        ml[/"memory_limiter"/]
        d2c[/"deltatocumulative<br/>(metrics)"/]
        batch[/"batch"/]
        sm[/"spanmetrics connector<br/>(traces → RED metrics, local)"/]
        rcv --> ml --> batch
        ml --> d2c --> batch
        rcv --> sm
    end
    batch -->|"metrics"| vma[/"vmagent :8429<br/>(usePrometheusNaming,<br/>service_name→app relabel)"/]
    vma --> vm[(VictoriaMetrics)]
    batch -->|"logs (VL-Stream-Fields: service.name)"| vl[(VictoriaLogs)]
    batch -->|"traces"| tr[(Tempo · Jaeger · VictoriaTraces)]
    sm --> vm
    classDef otc fill:#a5d8ff,stroke:#1971c2,color:#111;
    classDef metric fill:#ffe8cc,stroke:#e8590c,color:#111;
    classDef log fill:#d3f9d8,stroke:#2f9e44,color:#111;
    classDef trace fill:#c5f6fa,stroke:#0c8599,color:#111;
    class rcv,ml,d2c,batch,sm otc;
    class vma,vm metric;
    class vl log;
    class tr trace;
    style col fill:#d0ebff,color:#111;
```

Why each processor matters: **memory_limiter** protects the Collector from OOM
under a telemetry burst; **deltatocumulative** normalizes metric temporality so
`rate()` stays correct; **batch** amortizes network cost; **vmagent** is the
single place name-translation, relabeling and cardinality control happen (D-1/2/3).
On the cluster, span-derived RED metrics come from Tempo's metrics-generator
instead of the local spanmetrics connector.

---

## 9. Correlation — the fields that stitch the pillars together

Correlation works because every signal carries the **same resource identity**
and the **same trace id**. These come from the SDK's `Resource` (semconv v1.41)
and the active span — set once in `obsx`, attached to everything.

| Field | Set by | Joins |
|---|---|---|
| `trace_id` | active span (W3C) | trace ↔ its logs (VictoriaLogs field) ↔ its span metrics |
| `service.name` | `OTEL_SERVICE_NAME` | which service produced any signal; Grafana traces→metrics/profiles |
| `k8s.namespace.name` / `k8s.pod.name` | Downward API env | which pod; log/metric/trace all agree |
| `deployment.environment.name` | `DEPLOYMENT_ENVIRONMENT` | local vs production separation |
| `pyroscope.profile.id` | `otel-profiling-go` span attr | span ↔ its CPU flame graph |

Grafana wires the pivots: Tempo `tracesToLogsV2` (tag `trace_id`),
`tracesToProfiles` (`service.name`→`service_name`), `tracesToMetrics`. Exemplars
(the old metric→trace link) are **not** used — VictoriaMetrics doesn't support
them; the `trace_id` log field replaces that path (D-14).

---

## 10. Summary

| Signal | Old (client_golang / Vector) | New (OpenTelemetry) | Transport | Backend | Correlation key |
|---|---|---|---|---|---|
| Metrics | `request_duration_seconds`, scraped `/metrics` | `http_server_request_duration_seconds`, otelgin | OTLP push → vmagent | VictoriaMetrics | `service.name`, time |
| Logs | 3 log schemas → stdout → Vector | zap + `otelzap` tee | OTLP push (Vector for infra) | VictoriaLogs | `trace_id` field |
| Traces | already OTel | otelgin/otelgrpc, W3C `traceparent` | OTLP push | Tempo · Jaeger · VictoriaTraces | `trace_id` |
| Profiles | already Pyroscope | `obsx.SetupProfiling()` | pprof push | Pyroscope | `pyroscope.profile.id` |
| Liveness | `up{}` (free with pull) | D-4 heartbeat-absence | — | VictoriaMetrics | `app` |

**Golden rule:** instrument once, in `pkg/obsx.SetupObservability`. A service
never imports the OTel SDK or a metrics library directly — that's what killed
the drift the old three-style world suffered from.

## References

- [OpenTelemetry policy (normative)](opentelemetry.md) — the rules this doc explains informally
- [Metrics deep-dive](metrics/metrics-apps.md) · [Tracing](tracing/README.md) · [Logging](logging/README.md) · [Profiling](profiling/README.md)
- [Observability hub](README.md) · [RFC-0014](../proposals/rfc/RFC-0014/)

_Last updated: 2026-07-09 — initial explainer for the RFC-0014 OTLP migration (old-vs-new)._
