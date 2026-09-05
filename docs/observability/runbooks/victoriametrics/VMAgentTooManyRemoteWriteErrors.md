# VMAgentTooManyRemoteWriteErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `vmagent_remotewrite_errors_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

vmagent cannot deliver to its remote-write destination. Samples are retried and
buffered in the persistent queue, so nothing is lost yet — this is the alert that
starts the clock the queue alerts finish.

## Impact

None immediately. The chain is: errors → queue fills →
[VMAgentPersistentQueueRunsOutOfSpaceIn4Hours](VMAgentPersistentQueueRunsOutOfSpaceIn4Hours.md)
→ [VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md),
where it becomes permanent.

## Diagnosis

```promql
sum(rate(vmagent_remotewrite_errors_total[5m]))
sum(rate(vmagent_remotewrite_requests_total[5m]))
vm_persistentqueue_bytes_pending                       # is the buffer growing
up{job=~".*vmsingle.*"}                                # is the destination alive
```

```bash
kubectl logs -n monitoring deploy/vmagent-victoria-metrics --tail=100 | grep -i 'remote\|write\|4[0-9][0-9]\|5[0-9][0-9]'
```

The HTTP status in the log is the fastest discriminator: 5xx is the destination
failing, 4xx is usually a payload the destination refuses, and a connection error
is the network or the destination being gone.

## Mitigation

Work the destination. vmagent needs no change — retrying and buffering is
correct behaviour.

- Destination down → [VMServiceDown](VMServiceDown.md)
- Destination full → [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)
- Destination saturated →
  [VMConcurrentInsertsHitTheLimit](VMConcurrentInsertsHitTheLimit.md)

## Escalation

Warning. Escalate when the queue starts growing rather than holding flat.

## Related

- [VMAgentPersistentQueueRunsOutOfSpaceIn4Hours](VMAgentPersistentQueueRunsOutOfSpaceIn4Hours.md)
- [VMAgentRemoteWriteConnectionIsSaturated](VMAgentRemoteWriteConnectionIsSaturated.md)
- [VMServiceDown](VMServiceDown.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
