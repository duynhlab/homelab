# VMAgentPersistentQueueRunsOutOfSpaceIn12Hours

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `predict_linear` over `vm_persistentqueue_bytes_pending` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

The same prediction as the 4-hour rule, with a longer horizon. The pair is a
deliberate ladder: 12 hours is "look at this today", 4 hours is "act now".

A slow fill is often more interesting than a fast one — a fast fill has an
obvious cause, while a slow one means remote write is *almost* keeping up, which
tends to be a capacity trend rather than an outage.

## Impact

None yet.

## Diagnosis

```promql
vm_persistentqueue_bytes_pending
deriv(vm_persistentqueue_bytes_pending[2h])          # is it really rising, or noisy
sum(rate(vmagent_remotewrite_errors_total[5m]))
```

Check whether the queue ever drains. A sawtooth that returns to zero is healthy
back-pressure; a monotonic climb is the problem.

## Mitigation

Same causes as the 4-hour rule, with time to fix them properly rather than
mitigate. If the trend is capacity rather than failure, the honest fixes are
fewer scraped series or a faster destination.

## Escalation

Warning. Escalate only if it becomes the 4-hour alert.

## Related

- [VMAgentPersistentQueueRunsOutOfSpaceIn4Hours](VMAgentPersistentQueueRunsOutOfSpaceIn4Hours.md)
- [VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
