# VMConcurrentInsertsHitTheLimit

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `vm_concurrent_insert_limit_reached_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

Concurrent inserts have hit their ceiling, so ingestion requests are queueing.
The limit is deliberate back-pressure — VictoriaMetrics would rather make vmagent
wait than thrash.

## Impact

vmagent's remote write slows, and its persistent queue absorbs the difference.
While the queue holds, nothing is lost. The chain only becomes data loss at
[VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md).

## Diagnosis

Ask whether the cause is *volume* or *cost per insert* — they look identical from
this alert and have opposite fixes:

```promql
sum(rate(vm_concurrent_insert_limit_reached_total[5m]))
sum(rate(vm_rows_inserted_total[5m]))                                  # volume
rate(vm_slow_row_inserts_total[5m]) / rate(vm_rows_inserted_total[5m]) # cost
sum(vm_persistentqueue_bytes_pending)                                  # downstream effect
```

High volume with a low slow-insert ratio is genuine load. A modest volume with a
high ratio means each insert is expensive, which is churn or memory.

## Mitigation

1. **Cost per insert** → [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md)
   or [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md).
2. **Genuine volume** → reduce what is scraped, or give the store more CPU.
3. Raising the concurrency limit moves the queue rather than shortening it.

## Escalation

Warning. Escalate if the vmagent queue is growing rather than flat.

## Related

- [VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md)
- [VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
