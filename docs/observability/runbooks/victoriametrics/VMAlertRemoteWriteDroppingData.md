# VMAlertRemoteWriteDroppingData

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_remotewrite_dropped_rows_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

vmalert is **discarding the results of its own rules**. It writes recording-rule
output and `ALERTS` series back to VictoriaMetrics; when that write fails past
its buffer, the rows are dropped.

This cluster evaluates **525 recording rules**. Their output is what many alerts
and dashboards read — dropping it does not merely lose a metric, it removes the
input other rules depend on.

## Impact

Two losses, and the second is the dangerous one:

1. **Recording-rule series get gaps.** Any alert built on a recorded series
   (`edge:*`, `rfc0021:*`, `slo:*`) evaluates against missing data. A rule whose
   input is absent returns nothing, and a rule returning nothing looks exactly
   like a healthy rule.
2. **`ALERTS` history is incomplete**, so post-incident review cannot reconstruct
   what fired.

## Diagnosis

```promql
sum(rate(vmalert_remotewrite_dropped_rows_total[5m]))
sum(rate(vmalert_remotewrite_errors_total[5m]))
vmalert_remotewrite_send_duration_seconds_count

up{job=~".*vmsingle.*"}                     # the destination
```

```bash
kubectl logs -n monitoring deploy/vmalert-victoria-metrics --tail=100 | grep -i 'remote\|drop'
```

The destination is nearly always the cause — the same VictoriaMetrics that
vmagent writes to. Check whether vmagent is also struggling; if both are, it is
the store.

## Mitigation

1. Restore the destination —
   [VMServiceDown](VMServiceDown.md),
   [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md).
2. Do not restart vmalert to clear it; the in-flight buffer goes with it.
3. After recovery, treat recorded series as suspect for the outage window. A
   recording rule does not backfill.

## Escalation

Critical. Say explicitly that recording-rule output was lost — otherwise someone
will later read a flat `edge:rq_429_ratio:rate5m` as "no 429s" rather than "no
data".

## Related

- [VMAlertRemoteWriteErrors](VMAlertRemoteWriteErrors.md) — the errors that
  precede dropping.
- [VMServiceDown](VMServiceDown.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
