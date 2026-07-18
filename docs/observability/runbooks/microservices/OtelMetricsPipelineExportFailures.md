# OtelMetricsPipelineExportFailures

| | |
|---|---|
| **Severity** | critical |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning

Fires when `otelcol_exporter_send_failed_metric_points` rate >0 for 5 minutes.
While firing, OTLP-path liveness and RED alerts may be blind — the collector is
dropping metric points before they reach VictoriaMetrics.

## Diagnosis

```bash
kubectl logs -n monitoring deploy/otel-collector --tail=100
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
```

```promql
sum by (exporter) (rate(otelcol_exporter_send_failed_metric_points[5m]))
```

## Resolution

Fix collector → vmagent connectivity; see [observability-deep-dive.md](../observability-deep-dive.md).
