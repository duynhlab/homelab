# OtelCollectorDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | [Rule manifest](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/observability/otel-collector-alerts.yaml) |
| **Metrics** | `up{job=~".*otel-collector.*"} == 0` |
| **Status** | active in repository configuration |
| **Validation** | Static comparison to rule and Collector values, 2026-10-23; no new runtime test |
| **Dashboard** | Observability → OTel Collector |
| **Local-stack** | present — the compose stack runs the same collector |

## Meaning

The independent Collector scrape returns `up == 0` for five minutes. This
can mean an unavailable process, an unreachable metrics endpoint or a scrape
configuration fault. A missing target produces no `up` series and is not covered
by this expression. The configured gateway has one replica.

## Impact

The collector is the **narrow waist** of the whole telemetry design — every
service exports OTLP to it, and it fans out to every backend. Losing it stops:

| Signal | Backend | Second copy? |
|---|---|---|
| Traces | VictoriaTraces + ClickHouse | — |
| Logs | VictoriaLogs + ClickHouse | — |
| Metrics | VictoriaMetrics (via remote write) | — |
| **Edge access log** | **ClickHouse only** (ADR-061) | **none** |

Applications keep running and keep trying to export; their SDK buffers absorb a
short outage and then drop.

Note what does *not* stop: vmagent scrapes VictoriaMetrics targets directly, so
scraped metrics keep arriving. It is the **pushed** OTLP telemetry that goes
dark, which is most of the application-level signal.

## Diagnosis

```bash
kubectl get pods -n monitoring | grep otel-collector
kubectl logs -n monitoring deploy/otel-collector-opentelemetry-collector --tail=100
kubectl describe pod -n monitoring -l app.kubernetes.io/name=opentelemetry-collector | tail -30
```

```promql
up{job=~".*otel-collector.*"} == 0

# Was it backpressuring before it died -- the usual precursor
otelcol_exporter_queue_size
otelcol_exporter_queue_capacity
```

For OOMs, compare exporter queues, input volume, stateful aggregation and
container memory before assigning a cause. Queue pressure is one possibility.

## Mitigation

1. **OOMKilled** → look at which exporter was queueing before the kill; the fix is
   usually the backend, not the collector's memory.
2. **Config error** → it is a HelmRelease; see
   [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md).
3. **Running but unscraped** → investigate the scrape path, then separately
   verify OTLP ingestion and backend freshness. Running is not delivery proof.
4. Record the outage window and observed delivery gap. SDK/edge queues and
   retries may absorb some interruptions; quantify what was lost rather than
   assuming the entire window is missing.

## Recovery validation

Confirm the target is scraped for two evaluation intervals, the Collector accepts
OTLP, exporter queues drain and a known request reaches the intended stores.
Record remaining gaps and check that the alert clears.

## Escalation

Critical. It is a single point of failure for application telemetry, so during
the outage the absence of *other* application alerts means nothing.

## Related

- [ClickHouseExporterUnhealthy](../clickhouse/ClickHouseExporterUnhealthy.md) —
  one exporter failing while the collector is up.
- [VMServiceDown](../victoriametrics/VMServiceDown.md) — a backend outage is the
  usual root cause behind a collector that fell over.
