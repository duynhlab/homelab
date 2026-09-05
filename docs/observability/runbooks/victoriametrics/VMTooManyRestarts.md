# VMTooManyRestarts

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `changes(process_start_time_seconds{...}[15m])` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

A VictoriaMetrics component has restarted repeatedly in a short window. It uses
`process_start_time_seconds` rather than the Kubernetes restart count, so it sees
the process restarting **for any reason** — including an in-place crash the pod
status may smooth over.

There is no `for:` on this rule: the `changes()` window is the dampening.

## Impact

Each restart loses in-flight state. For `vmagent` that is unflushed buffers; for
`vmsingle` it is the caches, so the first minutes after a restart are slow
([VMSingleTooHighSlowInsertsRate](VMSingleTooHighSlowInsertsRate.md)). A
crashlooping component is effectively down while appearing to run.

## Diagnosis

```bash
kubectl get pods -n monitoring | grep -E 'vmsingle|vmagent|vmalert'
kubectl describe pod -n monitoring <pod> | grep -A8 'Last State'
kubectl logs -n monitoring <pod> --previous --tail=80
```

The exit reason separates the three cases that matter:

| Reason | Cause |
|---|---|
| `OOMKilled` | Memory — [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md) |
| `Error` + config message | A bad rule or scrape config; the reloader sidecar log says which |
| `Error` + panic | Genuine bug; capture the stack before restarting again |

## Mitigation

Fix the reason, not the restart. Raising the memory limit is right for
`OOMKilled` and wrong for everything else. Config errors are fixed in the CR in
git — the operator regenerates the config, so editing the ConfigMap is reverted.

## Escalation

Critical. A flapping `vmalert` means alert evaluation is intermittent, which is
worse than it being cleanly down, because the gaps are invisible.

## Related

- [VMServiceDown](VMServiceDown.md)
- [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
