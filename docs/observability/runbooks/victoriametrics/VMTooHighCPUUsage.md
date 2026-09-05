# VMTooHighCPUUsage

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `process_cpu_seconds_total` rate vs available cores |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

A VictoriaMetrics component is saturating its CPU allowance. Unlike memory, this
rarely kills the process — it makes it slow, which is harder to notice and
degrades everything reading from it.

## Impact

Queries slow down, which means **dashboards and `vmalert` rule evaluation** slow
down together. A `vmalert` that cannot finish its iteration inside the interval
starts missing them
([VMAlertTooManyMissedIterations](VMAlertTooManyMissedIterations.md)) — alerts
evaluated late, or not at all.

## Diagnosis

Separate ingestion cost from query cost — they have different fixes:

```promql
rate(process_cpu_seconds_total{job=~"vm.*"}[5m])

# Query side
sum(rate(vm_http_requests_total{path=~"/api/v1/query.*"}[5m]))
histogram_quantile(0.99, sum by (le) (rate(vm_request_duration_seconds_bucket[5m])))

# Ingest side
sum(rate(vm_rows_inserted_total[5m]))
rate(vm_slow_row_inserts_total[5m]) / rate(vm_rows_inserted_total[5m])
```

A heavy dashboard is a common cause and an easy one to confirm: check whether the
spike aligns with someone opening a board with a wide time range.

## Mitigation

1. **Query-driven** → the expensive query is the fix, not more CPU. Look for
   unbounded time ranges and high-cardinality `group by`.
2. **Ingest-driven with high slow-insert ratio** → this is really a churn or
   memory problem; see [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md).
3. **Genuinely undersized** → raise the CPU allowance. Note the Kind node's cores
   are shared.

## Escalation

Critical. Escalate if `vmalert` is missing iterations — that is alert coverage
quietly degrading.

## Related

- [VMTooHighQueryLoad](VMTooHighQueryLoad.md)
- [VMAlertTooManyMissedIterations](VMAlertTooManyMissedIterations.md)
- [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
