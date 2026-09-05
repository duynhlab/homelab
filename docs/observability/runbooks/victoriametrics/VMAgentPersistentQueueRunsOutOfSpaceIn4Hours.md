# VMAgentPersistentQueueRunsOutOfSpaceIn4Hours

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `predict_linear` over `vm_persistentqueue_bytes_pending` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

At the current fill rate the persistent queue is full within **4 hours** — after
which vmagent starts dropping
([VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md)).

A filling queue means remote write is failing or too slow. The queue is doing its
job; the clock is the alert.

## Impact

None yet. This is the last comfortable moment to act before data loss.

## Diagnosis

```promql
vm_persistentqueue_bytes_pending
predict_linear(vm_persistentqueue_bytes_pending[1h], 4*3600) > vm_persistentqueue_bytes_max
sum(rate(vmagent_remotewrite_errors_total[5m]))
sum(rate(vmagent_remotewrite_duration_seconds_count[5m]))
```

Why is remote write not keeping up? Usually one of:

- the destination is erroring →
  [VMAgentTooManyRemoteWriteErrors](VMAgentTooManyRemoteWriteErrors.md)
- the destination is slow → [VMConcurrentInsertsHitTheLimit](VMConcurrentInsertsHitTheLimit.md)
- the connection is saturated →
  [VMAgentRemoteWriteConnectionIsSaturated](VMAgentRemoteWriteConnectionIsSaturated.md)

## Mitigation

Fix the write path. Nothing about vmagent itself needs changing — it is buffering
correctly.

If the destination cannot be restored inside the window, reducing what is scraped
buys time by lowering the fill rate. That is a deliberate trade, and it is better
than an uncontrolled drop.

## Escalation

Critical, with a 4-hour fuse. Escalate on the destination.

## Related

- [VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md)
- [VMAgentPersistentQueueRunsOutOfSpaceIn12Hours](VMAgentPersistentQueueRunsOutOfSpaceIn12Hours.md)
- [VMAgentTooManyRemoteWriteErrors](VMAgentTooManyRemoteWriteErrors.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
