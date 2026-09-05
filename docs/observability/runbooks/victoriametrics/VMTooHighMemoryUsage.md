# VMTooHighMemoryUsage

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `process_resident_memory_bytes` vs the container limit |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

A VictoriaMetrics component is near its memory ceiling. For `vmsingle` this is
the most consequential resource it has: cache sizes are derived from available
memory, so squeezing memory does not merely risk an OOM — it shrinks the tsid
cache and pushes inserts onto the slow path first.

## Impact

The order of degradation is worth knowing, because the early stages look like
performance problems rather than memory problems:

1. Caches shrink → cache misses rise.
2. Slow inserts rise ([VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md)).
3. Ingestion latency rises → vmagent's queue grows.
4. OOMKill → [VMTooManyRestarts](VMTooManyRestarts.md), and the cache rebuild
   makes stage 2 worse for a while.

## Diagnosis

```promql
process_resident_memory_bytes{job=~"vm.*|.*victoria.*"}
vm_cache_size_bytes / vm_cache_size_max_bytes
vm_cache_entries{type="storage/tsid"}
sum(increase(vm_new_timeseries_created_total[1h]))
```

```bash
kubectl top pods -n monitoring | grep -E 'vmsingle|vmagent|vmalert'
kubectl get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].resources.limits.memory}{"\n"}{end}' | grep vm
```

**Ask what grew.** Memory here is a function of series count, and series count is
a function of churn. A memory alert with a flat series count is a different
problem from one that tracks a cardinality increase.

## Mitigation

1. **Series growth is real and wanted** → raise the limit. VictoriaMetrics uses
   what it is given.
2. **Series growth is churn** → fix that instead; see
   [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md). Raising memory to hold
   junk series buys weeks, not a fix.
3. Note this is a Kind node with finite memory shared by every pod on it — the
   ceiling is not free.

## Escalation

Critical. Escalate before the OOM rather than after: a restart costs the caches
and makes the next hour worse.

## Related

- [VMTooManyRestarts](VMTooManyRestarts.md)
- [VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md)
- [VMSingleMetadataCacheUtilizationIsTooHigh](VMSingleMetadataCacheUtilizationIsTooHigh.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
