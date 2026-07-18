# OtelMetricsPipelineExportFailures

| | |
|---|---|
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning

**Fires when**: `otelcol_exporter_send_failed_metric_points_total` rate >0 for 5 minutes.

**Severity**: critical

While firing, OTLP-path liveness and RED alerts may be blind.

**Investigation**:

```bash
kubectl logs -n monitoring deploy/otel-collector --tail=100
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
```

```promql
sum by (exporter) (rate(otelcol_exporter_send_failed_metric_points_total[5m]))
```

**Resolution**: Fix collector → vmagent connectivity; see [observability-deep-dive.md](../observability-deep-dive.md).

## Diagnosis

**Fires when**: `otelcol_exporter_send_failed_metric_points_total` rate >0 for 5 minutes.

**Severity**: critical

While firing, OTLP-path liveness and RED alerts may be blind.

**Investigation**:

```bash
kubectl logs -n monitoring deploy/otel-collector --tail=100
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
```

```promql
sum by (exporter) (rate(otelcol_exporter_send_failed_metric_points_total[5m]))
```

**Resolution**: Fix collector → vmagent connectivity; see [observability-deep-dive.md](../observability-deep-dive.md).
