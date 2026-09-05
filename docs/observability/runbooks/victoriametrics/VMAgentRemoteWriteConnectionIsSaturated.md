# VMAgentRemoteWriteConnectionIsSaturated

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `vmagent_remotewrite_send_duration_seconds_total` vs wall time |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

The remote-write connection is busy sending close to 100 % of the time. Not
failing — **saturated**. vmagent has no idle capacity left to absorb a burst.

The distinction from
[VMAgentTooManyRemoteWriteErrors](VMAgentTooManyRemoteWriteErrors.md) matters:
there, writes fail; here, they all succeed and there is simply no headroom.

## Impact

None while volume is steady. The risk is that any increase now goes straight to
the queue, so a saturated connection turns a small spike into a backlog.

## Diagnosis

```promql
rate(vmagent_remotewrite_send_duration_seconds_total[5m])     # -> 1.0 means fully busy
sum(rate(vm_rows_inserted_total[5m]))
vm_persistentqueue_bytes_pending
```

Is the bottleneck vmagent, the network, or the destination?

```promql
histogram_quantile(0.99, sum by (le) (rate(vmagent_remotewrite_duration_seconds_bucket[5m])))
rate(vm_slow_row_inserts_total[5m]) / rate(vm_rows_inserted_total[5m])   # destination-side cost
```

A high slow-insert ratio at the destination means the destination is the limit,
not the connection.

## Mitigation

1. **Destination-limited** → fix that; more concurrency will not help.
2. **Genuinely more volume than one connection carries** → increase remote-write
   concurrency (`-remoteWrite.queues`).
3. **Volume that should not exist** → the cheapest fix is scraping less. See
   [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md).

## Escalation

Warning, informational on its own. It matters as context when a queue alert
follows.

## Related

- [VMAgentTooManyRemoteWriteErrors](VMAgentTooManyRemoteWriteErrors.md)
- [VMConcurrentInsertsHitTheLimit](VMConcurrentInsertsHitTheLimit.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
