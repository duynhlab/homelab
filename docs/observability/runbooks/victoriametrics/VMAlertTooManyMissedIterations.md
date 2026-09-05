# VMAlertTooManyMissedIterations

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_iteration_missed_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

A rule group takes longer to evaluate than its own interval, so evaluations are
**skipped**. This cluster runs 814 rules across many groups, most on a 30-second
interval.

A missed iteration is not an error — vmalert reports no failure. The rules simply
run less often than they claim to.

## Impact

Alert latency, and quietly weakened `for:` semantics. A rule with `for: 5m` and a
30-second interval expects ten consecutive evaluations; if half are missed, the
condition must persist far longer than five minutes before it fires. Alerts
become slower and less sensitive without any configuration changing.

## Diagnosis

```promql
sum by (group) (rate(vmalert_iteration_missed_total[5m]))
histogram_quantile(0.99, sum by (le, group) (rate(vmalert_iteration_duration_seconds_bucket[5m])))
sum by (group) (vmalert_iteration_duration_seconds_sum) / sum by (group) (vmalert_iteration_duration_seconds_count)
```

Compare mean duration against the group's interval — the groups where they are
close are the ones missing.

The cause is almost always **the datasource, not vmalert**: expensive queries
that VictoriaMetrics answers slowly.

```promql
histogram_quantile(0.99, sum by (le) (rate(vm_request_duration_seconds_bucket[5m])))
sum(rate(vm_concurrent_select_limit_reached_total[5m]))
```

## Mitigation

1. **Slow datasource** → [VMTooHighQueryLoad](VMTooHighQueryLoad.md) or
   [VMTooHighCPUUsage](VMTooHighCPUUsage.md).
2. **One expensive group** → pre-compute with a recording rule, which is exactly
   what the 525 existing ones are for.
3. **Lengthening the interval** is legitimate for a group that genuinely does not
   need 30-second resolution — but it is a deliberate reduction in detection
   speed, not a fix.

## Escalation

Warning. Escalate if a critical group is affected: slow alerting on a critical
path is close to no alerting.

## Related

- [VMTooHighQueryLoad](VMTooHighQueryLoad.md)
- [VMAlertAlertingRulesError](VMAlertAlertingRulesError.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
