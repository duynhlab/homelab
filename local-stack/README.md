# local-stack

Docker-compose end-to-end stack for the duynhlab platform: Postgres (8 DBs) + Redis +
per-service golang-migrate migrations + the 8 Go services + a Temporal dev server + the
order-fulfillment worker + a Kong DB-less gateway (mirrors the in-cluster Kong) + the React SPA,
plus a tracing + span-metrics stack (below). Build contexts point at sibling repos
(`../../<service>`), so all service repos must be checked out next to `homelab/`.

```bash
cd local-stack
docker compose up -d --build
```

| What | URL |
|------|-----|
| SPA (frontend) | http://localhost:3001 |
| API gateway (Kong) | http://localhost:8080 |
| Temporal Web UI | http://localhost:8233 |
| **Grafana** (traces + RED dashboard) | **http://localhost:3002** |
| VictoriaTraces (API/UI) | http://localhost:10428 |
| VictoriaMetrics (PromQL/UI) | http://localhost:8428 |

Demo login: **`alice` / `password123`** (by **username**). A checkout drives the
`OrderFulfillmentWorkflow` saga — watch it in the Temporal UI.

## Tracing / audit with VictoriaTraces

Tracing is **on** in this stack. The collector both stores traces (VictoriaTraces) and derives
RED metrics from spans (VictoriaMetrics) — mirroring the cluster, with the spanmetrics connector
standing in for Tempo's metrics-generator locally:

```
                                   ┌→ VictoriaTraces :10428 ──→ Grafana Explore (waterfall)
8 services (OTLP-HTTP) → otel-collector :4318
                                   └→ spanmetrics → VictoriaMetrics :8428 → Grafana RED dashboard
```

The **OTel Collector is required**: the services' standard OTLP-HTTP SDK posts to `…/v1/traces`,
which can't be retargeted at VictoriaTraces' non-standard `/insert/opentelemetry/v1/traces` ingest
path directly. The collector receives standard OTLP and re-exports to VT.

- Tracing is enabled for all 8 services via the shared `x-svc-env` anchor
  (`TRACING_ENABLED=true`, `OTEL_COLLECTOR_ENDPOINT=otel-collector:4318`, `OTEL_SAMPLE_RATE=1.0`),
  with a per-service `OTEL_SERVICE_NAME` so trace/metric service names are real (`auth`, `product`,
  …) instead of the container hostname.
- Collector uses the **contrib** image (the `spanmetrics` connector lives there). Config:
  [`observability/otel-collector-config.yaml`](observability/otel-collector-config.yaml).
- Grafana datasources (auto-provisioned): **VictoriaTraces** (Jaeger-type → `/select/jaeger`) and
  **VictoriaMetrics** (Prometheus-type) under
  [`observability/grafana/provisioning/datasources/`](observability/grafana/provisioning/datasources/).

### Audit traces

1. Generate spans — log in (`alice`/`password123`) at http://localhost:3001 and run a checkout
   (exercises auth → user → product → cart → order → shipping → notification).
2. **Grafana** http://localhost:3002 → **Explore** → **VictoriaTraces** → pick a service → open a
   trace to inspect the span waterfall. (Anonymous admin; no login.)
3. **CLI checks:**
   ```bash
   docker logs otel-collector                                  # debug exporter shows span counts
   curl 'http://localhost:10428/select/jaeger/api/services'    # list services with traces
   curl -XPOST 'http://localhost:10428/select/logsql/query' \
     --data-urlencode 'query=* | count()'                      # total spans ingested
   ```

### RED dashboard (span metrics)

The collector's **spanmetrics connector** derives request rate / error rate / latency from spans
and remote-writes them to VictoriaMetrics as `spanmetrics_calls_total` +
`spanmetrics_duration_milliseconds_*` (labels `service_name`, `span_kind`, `status_code`,
`http_route`). Open **Grafana → Dashboards → "RED — span metrics (local-stack)"** (auto-provisioned;
[`red-spanmetrics.json`](observability/grafana/dashboards/red-spanmetrics.json)). Panels populate
while traffic flows (the `rate()` windows read empty when the stack is idle). Sample query:

```promql
histogram_quantile(0.95, sum by (le,service_name)(rate(spanmetrics_duration_milliseconds_bucket[5m])))
```

> Locally this stands in for the cluster's span metrics (Tempo metrics-generator). VictoriaTraces is
> **v0.6.0 (0.x, pre-GA)** — same pin as the cluster pilot. See
> [`docs/observability/tracing/victoriatraces.md`](../docs/observability/tracing/victoriatraces.md).
