# VMSingleMetadataCacheUtilizationIsTooHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmsingle-alerts.yaml` |
| **Metrics** | `vm_cache_size_bytes` / `vm_cache_size_max_bytes` for metadata caches |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMSingle |
| **Local-stack** | present |

## Meaning

A metadata cache is close to its ceiling. Once full, entries are evicted and
lookups fall back to disk — which is the mechanism behind
[VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md).

Cache sizes are derived from available memory, so this alert is usually saying
*the working set has outgrown the memory given to VictoriaMetrics*, not that a
cache is misconfigured.

## Impact

None immediately. It is the leading indicator: cache pressure → slow inserts →
ingestion latency → vmagent queue growth.

## Diagnosis

```promql
vm_cache_size_bytes / vm_cache_size_max_bytes
sum by (type) (vm_cache_entries)
rate(vm_cache_misses_total[5m]) / rate(vm_cache_requests_total[5m])
```

The `type` label names which cache — `storage/tsid` is the series index and the
one that matters most for ingestion.

## Mitigation

1. **Reduce the working set** — fewer series is the durable fix. See
   [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md).
2. **Give it more memory** — legitimate if the series count is genuinely needed.
   VictoriaMetrics sizes its caches from what it is allowed to use.
3. Both are deliberate changes; neither is an incident action.

## Escalation

Warning, and usually informational. It matters as the early half of a chain whose
later stages are the ones that hurt.

## Related

- [VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md) — the next
  link.
- [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md)
- [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
