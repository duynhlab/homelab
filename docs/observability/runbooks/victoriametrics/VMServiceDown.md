# VMServiceDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `up{job=~"vm.*|.*victoria.*"} == 0` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

A VictoriaMetrics-family component is unscraped for 2 minutes. Nine jobs are in
scope on this cluster, and they are **not** equivalent:

| Job | Losing it costs |
|---|---|
| `vmsingle-victoria-metrics` | The metric store — everything |
| `vmagent-victoria-metrics` | Ingestion; the queue buffers, then drops |
| `vmalert-victoria-metrics` | **All alert evaluation.** 814 rules stop |
| `vmalertmanager-victoria-metrics` | Alert delivery; rules still fire into nothing |
| `vlsingle-victoria-logs` | Log store |
| `vtsingle-victoria-traces` | Trace store |
| `*-reloader-http` (×3) | Config reload sidecars — least urgent |

## Impact

**The self-referential problem is the point.** If `vmsingle` is down, the alert
about it comes from the system that is down. If `vmalert` is down, no alert fires
at all — including this one. The platform's guard for that is the **Watchdog**
alert, which always fires; if Watchdog stops arriving, the alert pipeline itself
is broken.

## Diagnosis

```bash
kubectl get pods -n monitoring | grep -E 'vmsingle|vmagent|vmalert|victoria'
kubectl logs -n monitoring <pod> --previous --tail=50
kubectl describe pod -n monitoring <pod> | tail -30
```

```promql
up{job=~"vm.*|.*victoria.*"} == 0
count(up{job=~"vm.*|.*victoria.*"})     # 9 on this cluster
```

Check whether it is the pod or the scrape — a running pod that is unscraped is a
ServiceMonitor problem, not an outage.

## Mitigation

1. **OOMKilled** → the usual cause for `vmsingle`; see
   [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md). Restarting without
   addressing memory just repeats it.
2. **Disk full** → [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md).
3. **CrashLoop with a config error** → check the reloader sidecar and the
   generated config; a bad rule or scrape config stops startup.
4. It is operator-managed (`VMSingle`/`VMAgent`/`VMAlert` CRs). Fix the CR in
   git, not the Deployment.

## Escalation

Critical. Name the component — "VictoriaMetrics is down" is nine different
incidents, and `vmalert` being down means you will not be told about any of the
others.

## Related

- [VMTooManyRestarts](VMTooManyRestarts.md) — flapping rather than down.
- [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md) — the usual cause.
- [VMAgentPersistentQueueIsDroppingData](VMAgentPersistentQueueIsDroppingData.md)
  — what a long `vmsingle` outage does to ingestion.

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
