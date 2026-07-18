# AlertName

| | |
|---|---|
| **Severity** | warning / critical |
| **Category** | availability / errors / latency / traffic / runtime / database |
| **Source** | [`microservices/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |
| **Metrics** | primary OTLP series used by the alert expr |

## Meaning

What fires, threshold, and `for` duration.

## Impact

User-facing or operational consequence.

## Diagnosis

### PromQL

```promql
# Alert expr + drill-down
```

### kubectl / logs

```bash
kubectl get pods -n $NAMESPACE -l app=$APP
kubectl logs -n $NAMESPACE -l app=$APP --tail=200
```

### Grafana

Microservices Observability dashboard rows/panels to check.

### Traces / logs

Find `trace_id` in VictoriaLogs → open in Tempo (no exemplars — RFC-0014 D-14).

## Mitigation

Resolution steps and related alerts.

## Escalation

When to page, rollback, or escalate.
