# local-stack

Docker-compose end-to-end stack for the duynhlab platform: Postgres (8 DBs) + Redis +
per-service golang-migrate migrations + the 8 Go services + a Temporal dev server + the
order-fulfillment worker + a Kong DB-less gateway (mirrors the in-cluster Kong) + the React SPA,
plus a tracing backend (below). Build contexts point at sibling repos (`../../<service>`), so all
service repos must be checked out next to `homelab/`.

```bash
cd local-stack
docker compose up -d --build
```

| What | URL |
|------|-----|
| SPA (frontend) | http://localhost:3001 |
| API gateway (Kong) | http://localhost:8080 |
| Temporal Web UI | http://localhost:8233 |
| **Grafana (traces)** | **http://localhost:3002** |
| VictoriaTraces (API/UI) | http://localhost:10428 |

Demo login: **`alice` / `password123`** (by **username**). A checkout drives the
`OrderFulfillmentWorkflow` saga — watch it in the Temporal UI.

## Tracing / audit with VictoriaTraces

Tracing is **on** in this stack. The path mirrors the cluster:

```
8 services (OTLP-HTTP) → otel-collector :4318 → VictoriaTraces :10428 → Grafana :3002
```

The **OTel Collector is required**: the services' standard OTLP-HTTP SDK posts to `…/v1/traces`,
which can't be retargeted at VictoriaTraces' non-standard `/insert/opentelemetry/v1/traces` ingest
path directly. The collector receives standard OTLP and re-exports to VT.

- Tracing is enabled for all 8 services via the shared `x-svc-env` anchor
  (`TRACING_ENABLED=true`, `OTEL_COLLECTOR_ENDPOINT=otel-collector:4318`, `OTEL_SAMPLE_RATE=1.0`).
- Collector config: [`observability/otel-collector-config.yaml`](observability/otel-collector-config.yaml).
- Grafana datasource (auto-provisioned, Jaeger-type → VT's Jaeger query API):
  [`observability/grafana/provisioning/datasources/victoriatraces.yaml`](observability/grafana/provisioning/datasources/victoriatraces.yaml).

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

> VictoriaTraces is **v0.6.0 (0.x, pre-GA)** — same pin as the cluster pilot. See
> [`docs/observability/tracing/victoriatraces.md`](../docs/observability/tracing/victoriatraces.md).
