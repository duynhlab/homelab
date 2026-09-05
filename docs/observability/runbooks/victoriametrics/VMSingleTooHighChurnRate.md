# VMSingleTooHighChurnRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmsingle-alerts.yaml` |
| **Metrics** | `vm_new_timeseries_created_total` vs ingested rows |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMSingle |
| **Local-stack** | present |

## Meaning

Too many **new** time series are being created relative to samples ingested.
Churn is the cardinality problem in motion: a label whose value changes often —
a pod name, a request id, a build hash — creates a fresh series each time, and
every one of them costs index space forever.

Churn is worse than raw cardinality, because the index keeps the dead series.

## Impact

Index growth, slower queries, and eventually disk. It is the usual cause behind
[VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md) on a platform whose
data volume is small.

## Diagnosis

**Read this cluster's numbers before believing the alert.** A rebuild makes every
series new: 228,469 series with 231,840 created in 24 h looks like 100 % churn and
simply means the cluster was recreated yesterday. Check uptime first.

```promql
sum(increase(vm_new_timeseries_created_total[1h]))
vm_cache_entries{type="storage/tsid"}          # total series
```

Then find the offender. VictoriaMetrics exposes this directly:

```bash
kubectl exec -n monitoring deploy/vmsingle-victoria-metrics -- \
  wget -qO- 'http://localhost:8428/api/v1/status/tsdb' | head -60
```

`seriesCountByMetricName` and `labelValueCountByLabelName` are the two lists that
matter. A label with thousands of values is the culprit.

## Mitigation

1. **Drop the offending label** at the source — a `metricRelabelConfig` on the
   scrape, or fixing the instrumentation that emits it.
2. **Stream aggregation** if the raw series are genuinely needed only in
   aggregate.
3. Do not raise the threshold. Churn that is real does not become acceptable by
   being unmeasured.

Known cost on this platform, for calibration: the per-pod ClickHouse `:9363`
scrape adds 3,148 metric names and 9,973 series — about 4.8 % of the total, of
which `ClickHouseErrorMetric_*` alone is 737 names (one per error code). That was
a deliberate trade, documented when it was made.

## Escalation

Warning. Escalate only if it is sustained and the cluster has been up long enough
for the number to mean something.

## Related

- [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)
- [VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md) — high churn
  makes inserts slow, so these often fire together.

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
