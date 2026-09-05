# VMTooHighQueryLoad

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | concurrent-select queue vs its limit |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

Queries are queueing. VictoriaMetrics bounds concurrent selects; past that,
requests wait rather than pile onto the CPU. This alert says the bound is being
reached.

Two very different callers produce it: **Grafana** (someone is looking) and
**vmalert** (814 rules, every 30 s, forever). Only one of them is bursty.

## Impact

Dashboards feel slow. More importantly, `vmalert` queries queue behind them, and
a rule that cannot complete inside its interval is a rule that evaluates late —
see [VMAlertTooManyMissedIterations](VMAlertTooManyMissedIterations.md).

## Diagnosis

```promql
sum(rate(vm_http_requests_total{path=~"/api/v1/query.*"}[5m]))
histogram_quantile(0.99, sum by (le) (rate(vm_request_duration_seconds_bucket[5m])))
sum(rate(vm_concurrent_select_limit_reached_total[5m]))

# Split the two callers apart
sum by (path) (rate(vm_http_requests_total[5m]))
```

Find the expensive query rather than guessing:

```bash
kubectl exec -n monitoring deploy/vmsingle-victoria-metrics -- \
  wget -qO- 'http://localhost:8428/api/v1/status/top_queries' | head -40
```

## Mitigation

1. **One heavy dashboard** → fix the query. Wide time ranges over
   high-cardinality `group by` are the usual shape.
2. **vmalert-driven** → recording rules exist for exactly this: pre-aggregate
   what many alerts recompute. This platform already has 525 of them.
3. Raising the concurrency limit trades queueing for CPU contention; it does not
   add capacity.

## Escalation

Warning. Escalate if alert evaluation is affected — that is coverage loss, not
slowness.

## Related

- [VMTooHighCPUUsage](VMTooHighCPUUsage.md)
- [VMAlertTooManyMissedIterations](VMAlertTooManyMissedIterations.md)
- [VMSingleRequestErrorsToAPI](VMSingleRequestErrorsToAPI.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
