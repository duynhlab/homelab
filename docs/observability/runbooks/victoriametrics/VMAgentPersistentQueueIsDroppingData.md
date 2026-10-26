# VMAgentPersistentQueueIsDroppingData

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `vmagent_remotewrite_packets_dropped_total` |
| **Status** | active; query queue depth during the incident |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

vmagent's persistent queue is **discarding samples**. The queue exists so that a
VictoriaMetrics outage costs latency rather than data; dropping means that buffer
has been exhausted, either by time or by disk.

This is the end of a chain, never the start. Something downstream has been
refusing writes long enough to fill the buffer.

## Impact

**Permanent gaps in the metric store.** Dropped samples are not retried and
cannot be backfilled. Every dashboard, SLO and alert covering that window is
missing data, and an SLO computed over a gap is quietly wrong rather than
obviously broken.

## Diagnosis

Find the downstream cause first — the queue is reporting, not causing:

```promql
sum(rate(vmagent_remotewrite_packets_dropped_total[5m]))
sum(vm_persistentqueue_bytes_pending)
vm_persistentqueue_bytes_pending / vm_persistentqueue_bytes_max

# Is the destination healthy
up{job=~".*vmsingle.*"}
sum(rate(vmagent_remotewrite_errors_total[5m]))
```

```bash
kubectl logs -n monitoring deploy/vmagent-victoria-metrics --tail=100 | grep -iE 'drop|queue|remote'
```

Three shapes:

1. **Destination down** → [VMServiceDown](VMServiceDown.md).
2. **Destination up but rejecting** → disk full, or ingestion saturated. See
   [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md),
   [VMConcurrentInsertsHitTheLimit](VMConcurrentInsertsHitTheLimit.md).
3. **Queue disk full** → the buffer's own PV, a separate problem from the store's.

## Mitigation

1. Restore the destination. The queue drains on its own once writes succeed.
2. Do not restart vmagent merely to clear the symptom. Inspect the actual
   queue path and volume first: disk buffering survives only while its storage
   survives; the word “persistent” does not establish a Kubernetes PVC.
3. If the queue's own disk is the limit, that is a sizing decision to make after
   the incident, not during it.

## Recovery validation

Confirm the drop counter stops increasing, successful writes resume and pending
bytes drain. Verify new samples in the destination and record permanent gaps;
empty queues alone do not prove all samples arrived.

## Escalation

Critical, and the only alert in this group where **the damage is already done**
rather than pending. Record the window that was lost; someone will ask later why
a chart has a hole.

## Related

- [VMAgentPersistentQueueRunsOutOfSpaceIn4Hours](VMAgentPersistentQueueRunsOutOfSpaceIn4Hours.md)
  — the warning that precedes this.
- [VMServiceDown](VMServiceDown.md)
- [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)
