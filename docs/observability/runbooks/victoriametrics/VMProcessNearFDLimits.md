# VMProcessNearFDLimits

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `process_open_fds` vs `process_max_fds` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

A component is close to its file-descriptor limit. VictoriaMetrics uses
descriptors for two very different things — **data part files** and **network
connections** — and which one is growing decides the fix.

## Impact

Hitting the limit is abrupt and total: new connections are refused and new part
files cannot be created, so both querying and ingestion fail at once. Unlike
memory pressure there is no gradual degradation to warn you.

## Diagnosis

```promql
process_open_fds / process_max_fds
process_open_fds{job=~"vm.*"}
vm_parts{type!=""}                       # part files -- storage side
vm_tcplistener_conns                     # connections -- network side
```

```bash
kubectl exec -n monitoring deploy/vmsingle-victoria-metrics -- sh -c 'ls /proc/1/fd | wc -l' 2>/dev/null
kubectl exec -n monitoring deploy/vmsingle-victoria-metrics -- sh -c 'cat /proc/1/limits | grep -i "open files"' 2>/dev/null
```

Many part files usually means merges are not keeping up. Many connections usually
means a client is not reusing them.

## Mitigation

1. **Part files growing** → merge pressure; often downstream of churn.
2. **Connections growing** → find the client. A misbehaving scraper or a dashboard
   opening a connection per panel refresh will do it.
3. Raising the `nofile` ulimit is legitimate for a genuinely large deployment and
   a band-aid otherwise.

## Escalation

Critical — the failure mode is a cliff, not a slope.

## Related

- [VMServiceDown](VMServiceDown.md)
- [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
