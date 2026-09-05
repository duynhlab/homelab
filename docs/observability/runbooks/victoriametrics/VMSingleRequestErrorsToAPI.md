# VMSingleRequestErrorsToAPI

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmsingle-alerts.yaml` |
| **Metrics** | `vm_http_request_errors_total` by `path` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMSingle |
| **Local-stack** | present |

## Meaning

VictoriaMetrics is returning errors on its HTTP API. The `path` label is what
makes this actionable, because read and write errors mean different things:

| Path | Caller | Meaning |
|---|---|---|
| `/api/v1/query`, `/query_range` | Grafana, vmalert | Queries failing — dashboards and alert rules |
| `/api/v1/write`, `/prometheus/api/v1/write` | vmagent | Ingestion failing — data at risk |
| `/api/v1/import` | backfill tooling | One-off, usually harmless |

## Impact

Write-path errors risk data loss (vmagent buffers, then drops). Read-path errors
break dashboards and, more quietly, break **alert evaluation** — vmalert reads
from here, so query errors can silence alerts without any alert saying so.

## Diagnosis

```promql
sum by (path) (rate(vm_http_request_errors_total[5m]))
sum by (path) (rate(vm_http_requests_total[5m]))          # denominator, for ratio

# Is vmalert affected -- this is the quiet one
sum(rate(vmalert_execution_errors_total[5m]))
```

```bash
kubectl logs -n monitoring deploy/vmsingle-victoria-metrics --tail=100 | grep -i error
```

Common causes here: a malformed PromQL from a dashboard (read path, harmless to
the store), a query that exceeds `-search.maxQueryDuration` on a heavy panel, or
genuine resource pressure.

## Mitigation

1. **Read errors from one dashboard** → fix the query; the store is fine.
2. **Read errors broadly** → check CPU and memory
   ([VMTooHighCPUUsage](VMTooHighCPUUsage.md),
   [VMTooHighMemoryUsage](VMTooHighMemoryUsage.md)).
3. **Write errors** → treat as urgent; check disk
   ([VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)) and vmagent's
   queue.

## Escalation

Warning for read errors, effectively critical for write errors. Say which path
when escalating.

## Related

- [VMSingleDiskRunsOutOfSpace](VMSingleDiskRunsOutOfSpace.md)
- [VMTooHighQueryLoad](VMTooHighQueryLoad.md)
- [VMAlertRemoteWriteErrors](VMAlertRemoteWriteErrors.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
