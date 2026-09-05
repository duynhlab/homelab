# VMSingleTooHighSlowInsertsRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmsingle-alerts.yaml` |
| **Metrics** | `vm_slow_row_inserts_total` / `vm_rows_inserted_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMSingle |
| **Local-stack** | present |

## Meaning

Too many inserts are taking the **slow path**. VictoriaMetrics keeps a per-series
in-memory index for fast ingestion; when a sample's series is not in that cache
it falls back to the slow path, which touches the on-disk index.

So this is a cache-miss alert. The two things that cause it are **more series
than the cache holds** and **churn**, which fills the cache with series that will
never be seen again.

## Impact

Ingestion CPU rises and insert latency grows. At the extreme, vmagent's remote
write backs up and its persistent queue starts filling — which is where data loss
begins.

## Diagnosis

```promql
rate(vm_slow_row_inserts_total[5m]) / rate(vm_rows_inserted_total[5m])
vm_cache_entries{type="storage/tsid"}
sum(increase(vm_new_timeseries_created_total[1h]))       # churn feeding the misses

# Is the pressure reaching vmagent
sum(vm_persistentqueue_bytes_pending)
```

An empty result for the ratio means no inserts are taking the slow path at all —
that is the healthy state, not a broken query.

## Mitigation

1. **Churn** → the real fix. See
   [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md).
2. **Memory** → the tsid cache is sized from available memory; a VMSingle that is
   memory-constrained cannot hold its working set. Check
   [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md).
3. Adding CPU treats the symptom and leaves the index growing.

## Escalation

Warning. Escalate if `vm_persistentqueue_bytes_pending` is rising with it — that
chain ends in dropped samples.

## Related

- [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md)
- [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md)
- [VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
