# VictoriaTraces (pilot)

**VictoriaTraces** is deployed as a **pilot, third tracing backend** alongside [Tempo](./README.md)
and [Jaeger](./jaeger.md) — the OTel Collector fans the same OTLP traces to all three. The point of
the pilot is to evaluate the **VM-operator consolidation** story: tracing managed by the *same*
VictoriaMetrics Operator (and *same* storage engine) as metrics (`VMSingle`) and logs (`VLSingle`),
with **no object-storage dependency**.

> **Maturity caveat** — VictoriaTraces is **`v0.9.4` (0.x, pre-GA)**. This is a **pilot**, not a
> replacement: Tempo (durable on RustFS) + Jaeger stay. Any consolidation onto VictoriaTraces is a
> future decision (ADR), gated on ~1.0/GA and validating partial TraceQL
> compatibility against Tempo workflows. See the full [backends comparison](./backends-comparison.md).

## How it fits

```mermaid
flowchart LR
  Apps["10 services + 2 workers<br/>OTel SDK"] -->|OTLP| OC["OTel Collector"]
  OC -->|otlp/tempo| T["Tempo (durable · RustFS)"]
  OC -->|otlp/jaeger| J["Jaeger (in-memory)"]
  OC -->|otlphttp/victoriatraces| V["VictoriaTraces VTSingle :10428"]
  V --> G["Grafana (Jaeger datasource → /select/jaeger)"]
```

VictoriaTraces stores traces in the **VictoriaLogs engine** (traces-as-logs) — so the tightest
correlation is **log↔trace** via the same LogsQL your `VLSingle` already uses. A single port
**`:10428`** serves everything: OTLP-HTTP ingest, the Jaeger query API, LogsQL, and `/metrics`.

## Deployment — `VTSingle` (operator-managed)

CR: [`kubernetes/infra/configs/observability/tracing/victoriatraces/vtsingle.yaml`](../../../kubernetes/infra/configs/observability/tracing/victoriatraces/vtsingle.yaml)
— a drop-in `operator.victoriametrics.com/v1` CRD, same ops model as `VMSingle`/`VLSingle`:

| Field | Value |
|-------|-------|
| `image` | `victoriametrics/victoria-traces:v0.9.4` (pinned — 0.x, fast-moving) |
| operator | chart `0.66.2` / app `v0.73.1` (matching CRDs rendered by the same chart) |
| `retentionPeriod` | `7d` (matches VMSingle/VLSingle) |
| `storage` | 10Gi PVC (VictoriaLogs engine — **no object storage**) |
| `useStrictSecurity` | `true` (non-root, hardened) |
| metrics | operator auto-creates a `VMServiceScrape` (no manual ServiceMonitor) |

The operator creates a Service for the CR (VM-operator convention **`vtsingle-victoria-traces`** in
`monitoring`, port `10428`) — **verify the exact name at apply**:

```bash
kubectl get svc -n monitoring | grep victoria-traces
```

The standalone `victoria-metrics-operator-crds` chart is an alternative CRD
ownership model. This platform does not install it because the operator chart
already renders and upgrades matching CRDs; installing both would give two
Helm releases ownership of the same cluster-scoped resources.

## Ingestion (OTLP-HTTP)

The OTel Collector exports to VictoriaTraces over **OTLP-HTTP** (its gRPC `:4317` is TLS-by-default,
so HTTP is simpler). In
[`otel-collector.yaml`](../../../kubernetes/infra/controllers/tracing/otel-collector/otel-collector.yaml):

```yaml
exporters:
  otlphttp/victoriatraces:
    traces_endpoint: http://vtsingle-victoria-traces.monitoring.svc.cluster.local:10428/insert/opentelemetry/v1/traces
    tls: { insecure: true }
    compression: gzip
# pipelines.traces.exporters: [otlp/tempo, otlp/jaeger, otlphttp/victoriatraces]
```

## Querying

- **Grafana** — a **Jaeger-type** datasource (uid `victoriatraces`, there is no native VT datasource)
  pointed at the Jaeger query API: `http://vtsingle-victoria-traces.monitoring.svc.cluster.local:10428/select/jaeger`.
  `tracesToLogsV2`/`tracesToMetrics` are wired to VictoriaLogs/VictoriaMetrics like the other backends.
- **Tempo API** — v0.9.4 exposes partial Tempo/TraceQL-compatible search APIs,
  including Grafana Traces Drilldown support. This platform keeps the proven
  Jaeger datasource during the pilot; TraceQL metrics and pipelines remain a
  Tempo-only capability.
- **UI / API** — exposed at `victoriatraces.duynh.me` (Kong ingress → `:10428`).
- **LogsQL** (advanced, traces-as-logs) — `POST /select/logsql/query`, e.g.:

  ```bash
  curl -X POST "http://localhost:10428/select/logsql/query" \
    --data-urlencode 'query=resource.service.name:product' --data-urlencode 'limit=50'
  ```

  *(LogsQL field names map from OTLP attributes; verify the exact field syntax against your own
  trace data — the Jaeger datasource is the primary query path in Grafana.)*

## Try it locally (docker-compose)

The [`local-stack`](../../../local-stack/README.md) wires the same path on a laptop — no cluster
needed: the 10 services and 2 workers emit OTLP-HTTP to an **OTel Collector**,
which re-exports to a single-node **VictoriaTraces** container, and you audit traces in a bundled **Grafana**.

```bash
cd local-stack && docker compose up -d --build
# generate spans: log in alice/password123 at http://localhost:3001 and run a checkout
open http://localhost:3002   # Grafana → Explore → VictoriaTraces → pick a service
```

The collector is mandatory because the services' standard OTLP-HTTP SDK posts to `…/v1/traces`,
which can't be retargeted at VictoriaTraces' `/insert/opentelemetry/v1/traces` ingest path directly.
Quick ingest check: `curl 'http://localhost:10428/select/jaeger/api/services'`.

## Status

Pilot, wired in the manifests — the collector's 3-way fan-out exporter and the Grafana
`victoriatraces` datasource are both deployed config (`otel-collector.yaml`,
`datasource-victoriatraces.yaml`); v0.9.4 verified standalone (ingests OTLP-HTTP traces; the
Jaeger API returns them). Tempo + Jaeger are unchanged and Tempo stays primary/durable.
See [backends-comparison.md](./backends-comparison.md) for the decision context.

---
_Last updated: 2026-07-14 — VictoriaTraces v0.9.4 and VM Operator v0.73.1 compatibility review._
