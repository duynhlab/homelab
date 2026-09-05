# VMSingleDiskRunsOutOfSpaceIn3Days

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmsingle-alerts.yaml` |
| **Metrics** | `predict_linear` over `vm_free_disk_space_bytes` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMSingle |
| **Local-stack** | present |

## Meaning

Extrapolating the current trend, the disk runs out within **3 days**. Predictive,
not reactive — the point is to give you three days of daylight rather than a
midnight page.

Being a prediction, it is only as good as the window. A one-off ingest spike
(a load test, a cardinality experiment) skews `predict_linear` and produces a
forecast that never arrives. Look at the trend before acting on the number.

## Impact

None yet. This is the warning that
[VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md) is coming.

## Diagnosis

```promql
# The prediction, and the raw trend behind it
predict_linear(vm_free_disk_space_bytes[6h], 3*24*3600) < 0
deriv(vm_free_disk_space_bytes[6h])
vm_free_disk_space_bytes

# Is it data or index -- they have different fixes
vm_data_size_bytes
sum(vm_rows{type="indexdb"})
sum(increase(vm_new_timeseries_created_total[24h]))
```

**Caveat on this cluster:** churn readings are inflated for the first day after a
rebuild, because every series is new. A `make down`/`make up` yesterday makes a
24-hour churn number meaningless today.

## Mitigation

Same levers as the critical, with time to choose properly: retention, cardinality
reduction, or node disk. Prefer the cardinality audit — it is the only one that
makes the problem smaller rather than deferring it.

## Escalation

Critical by label, but it is a three-day warning. Treat it as scheduled work
unless `deriv()` says the slope is steepening.

## Related

- [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)
- [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
