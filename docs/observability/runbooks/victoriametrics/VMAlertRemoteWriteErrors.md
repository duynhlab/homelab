# VMAlertRemoteWriteErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_remotewrite_errors_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

vmalert cannot write its rule results back to VictoriaMetrics. Buffered and
retried for now — the warning before
[VMAlertRemoteWriteDroppingData](VMAlertRemoteWriteDroppingData.md).

Note this is separate from **evaluation**: rules are still being evaluated and
alerts still fire. What is failing is persisting the results.

## Impact

None yet. Recording-rule series may show brief gaps if the buffer cycles.

## Diagnosis

```promql
sum(rate(vmalert_remotewrite_errors_total[5m]))
sum(rate(vmalert_remotewrite_total[5m]))
sum(rate(vmalert_execution_errors_total[5m]))    # is evaluation also affected
up{job=~".*vmsingle.*"}
```

If `vmalert_execution_errors_total` is also rising, the problem is bigger than
remote write — vmalert cannot *read* either, which means rules are evaluating
against nothing.

## Mitigation

Fix the destination. See
[VMAgentTooManyRemoteWriteErrors](VMAgentTooManyRemoteWriteErrors.md) — the same
destination, the same causes, a different client.

## Escalation

Warning. Escalate if dropping begins, or if evaluation errors accompany it.

## Related

- [VMAlertRemoteWriteDroppingData](VMAlertRemoteWriteDroppingData.md)
- [VMAlertAlertingRulesError](VMAlertAlertingRulesError.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
