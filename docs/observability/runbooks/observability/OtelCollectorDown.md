# OtelCollectorDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/otel-collector-alerts.yaml` |
| **Metrics** | `up{job=~".*otel-collector.*"} == 0` |
| **Status** | active |
| **Dashboard** | Observability → OTel Collector |
| **Local-stack** | present — the compose stack runs the same collector |

## Meaning

The OpenTelemetry Collector is not being scraped. It is a **single deployment**
on this platform, so there is no redundancy: it is down or it is not.

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

A collector that OOMs is nearly always a collector whose exporter queue filled
first, because a backend stopped accepting. Check which exporter.

## Mitigation

1. **OOMKilled** → look at which exporter was queueing before the kill; the fix is
   usually the backend, not the collector's memory.
2. **Config error** → it is a HelmRelease; see
   [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md).
3. **Running but unscraped** → a monitoring failure, not an outage. The telemetry
   pipeline is fine.
4. Record the outage window. The edge access log for that period is gone and
   cannot be recovered.

## Escalation

Critical. It is a single point of failure for application telemetry, so during
the outage the absence of *other* application alerts means nothing.

## Related

- [ClickHouseExporterUnhealthy](../clickhouse/ClickHouseExporterUnhealthy.md) —
  one exporter failing while the collector is up.
- [VMServiceDown](../victoriametrics/VMServiceDown.md) — a backend outage is the
  usual root cause behind a collector that fell over.

---
_Last updated: 2026-09-05 — created; this alert had no runbook_
