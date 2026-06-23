# Tracing Backends: Tempo vs Jaeger vs VictoriaTraces

A decision-oriented comparison of the three tracing backends on this platform. **All three now run**
— the OTel Collector fans the same traces to each: **Tempo** + **Jaeger** are the established pair,
and **VictoriaTraces** is deployed as a **pilot 3rd backend** (`VTSingle`, image `v0.6.0`) to evaluate
the "consolidate tracing into the VM operator" story. See [victoriatraces.md](victoriatraces.md).

> **TL;DR** — **Tempo** is the durable backend (object storage on **RustFS**, TraceQL, native Grafana
> correlation); **Jaeger** is a secondary in-memory UI kept for learning; **VictoriaTraces** is a
> **pilot** (3rd fan-out) — the strategic "tracing in the VM operator beside metrics + logs" play, but
> still **`v0.x` (pre-GA)** with **no TraceQL**. Not replacing Tempo/Jaeger; a future ADR decides any consolidation.

## What runs today

```mermaid
flowchart LR
  Apps["8 services (OTel SDK)"] -->|OTLP| OC["OTel Collector"]
  OC -->|otlp/tempo| T["Tempo 2.10.5<br/>(durable · RustFS S3)"]
  OC -->|otlp/jaeger| J["Jaeger v2 all-in-one<br/>(in-memory · ephemeral)"]
  OC -->|otlphttp/victoriatraces| V["VictoriaTraces v0.6.0<br/>(pilot · VLogs engine)"]
  T --> G["Grafana (TraceQL +<br/>traces↔logs↔metrics)"]
  J --> JU["Jaeger UI"]
  V --> G
```

The OTel Collector fans the **same** traces to all three backends — see
[architecture.md](architecture.md). Tempo is durable; Jaeger is ephemeral by choice (see
[jaeger.md](jaeger.md#storage--in-memory-here-and-why-vs-tempo-on-rustfs)); VictoriaTraces is the
pilot (see [victoriatraces.md](victoriatraces.md)).

## Side-by-side

| Dimension | **Grafana Tempo** | **Jaeger** | **VictoriaTraces** |
|-----------|-------------------|------------|--------------------|
| Maturity | Mature, GA | Mature, GA (v2 = OTel-Collector distro) | **`v0.6.0` — 0.x, pre-GA (piloted here)** |
| Storage | **Object storage** (S3/GCS/Azure/local) — uses **RustFS** here | memory / badger / ES / OpenSearch / Cassandra / ClickHouse — **no object storage** | stores traces in the **VictoriaLogs engine**; **no object storage needed** |
| Ingestion | OTLP, Jaeger, Zipkin | OTLP (v2), Jaeger, Zipkin | **OTLP only** |
| Query | **TraceQL** (scoped attrs + structural operators `>>`/`~`) | tag / duration / service filters (no query language) | **LogsQL** + **Jaeger query API** — **no TraceQL** |
| Grafana | **Native datasource** + traces↔logs↔metrics↔profiles correlation | Jaeger datasource / standalone UI | via the **Jaeger datasource** (no native VT datasource) |
| Service graph / span metrics | metrics-generator → remote_write to VM | dependency graph; SPM (needs a metrics backend) | built-in service-graph generation |
| Operator on this platform | Helm/manifests | Helm chart (all-in-one) | **`VTSingle`/`VTCluster` CRDs** — drop-in to the **VictoriaMetrics Operator** |
| Correlation sweet spot | single-pane Grafana across all 4 pillars | own UI | tightest **log↔trace** (traces *are* VictoriaLogs data, same LogsQL) |

## Trade-offs for this platform

The platform already runs the **VictoriaMetrics Operator** (VMSingle/VMAgent/VMAlert) and
**VictoriaLogs (VLSingle)** for metrics + logs, plus **RustFS** (S3). That shapes the call:

- **Tempo** fits the *capability* requirements best: TraceQL (relational span queries), durable
  object storage on the RustFS we already run, and native Grafana correlation with VM + VictoriaLogs
  + Pyroscope. It is mature and already wired. Cost: it is a Grafana-ecosystem component (one more
  "vendor"), and depends on object storage (which we have).
- **Jaeger** uniquely offers its standalone UI (trace compare, dependency graph). With **no S3
  backend** and in-memory storage it is not a durable store; here it is intentionally a **learning /
  comparison** UI, not the system of record.
- **VictoriaTraces** is the *consolidation* play: tracing would join metrics + logs under one
  operator, one ops model, one query family (**LogsQL**), with no object-storage dependency.
  Against that: **`v0.6.0`** (0.x, pre-GA) and **no TraceQL** — and Grafana sees it as a
  **Jaeger datasource**, so existing Tempo/TraceQL correlation links would be re-pointed.

## Recommendation / roadmap

1. **Now:** **Tempo** is the durable backend (RustFS S3, 7-day retention); **Jaeger** in-memory is
   the secondary learning UI; **VictoriaTraces** (`VTSingle` v0.6.0) is **deployed as a pilot 3rd
   backend** (drop-in operator CRD, no object-storage dependency) — see
   [victoriatraces.md](victoriatraces.md). Evaluate LogsQL-trace querying + the Jaeger-datasource
   correlation on real data.
2. **Adopt VictoriaTraces as the sole backend only when** it reaches ~1.0/GA **and** the
   **TraceQL → LogsQL** trade-off is acceptable — for the prize of consolidating tracing into the
   VM operator beside metrics + logs. Decide via a future ADR.

## References

- [Tracing guide](./README.md) · [Architecture](./architecture.md) · [Jaeger guide](./jaeger.md)
- VictoriaMetrics Operator (metrics + logs today): [observability metrics](../metrics/README.md)
- Grafana Tempo: <https://grafana.com/docs/tempo/latest/> · Jaeger: <https://www.jaegertracing.io/docs/> · VictoriaTraces: <https://docs.victoriametrics.com/victoriatraces/>
