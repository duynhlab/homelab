# VMSingleDiskRunsOutOfSpace

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmsingle-alerts.yaml` |
| **Metrics** | `vm_free_disk_space_bytes`, `vm_data_size_bytes` |
| **Status** | active · currently ~321 GB free |
| **Dashboard** | VictoriaMetrics → VMSingle |
| **Local-stack** | present |

## Meaning

VictoriaMetrics is nearly out of disk. When it runs out it **stops accepting
writes** and switches to read-only — it does not crash, which makes this easy to
miss: dashboards keep answering while nothing new arrives.

As everywhere on this platform, the disk is a **local-path PV**: a hostPath
directory on the Kind node, no quota, shared with every other pod on that worker.
Growing the PVC is not available (`allowVolumeExpansion` unset).

## Impact

**The monitoring system stops recording.** Every alert on this platform reads
from here, so the loss compounds: no new samples means no alerts on anything, and
the gap is permanent — backfill is not possible for data never ingested.

VictoriaLogs, VictoriaTraces and ClickHouse are separate stores and keep working.

## Diagnosis

```promql
vm_free_disk_space_bytes{job=~".*vmsingle.*"}
vm_data_size_bytes
sum(vm_rows{type="indexdb"})            # index, which grows with churn not volume
```

```bash
kubectl exec -n monitoring deploy/vmsingle-victoria-metrics -- df -h /storage 2>/dev/null \
  || kubectl exec -n monitoring statefulset/vmsingle-victoria-metrics -- df -h
kubectl get pods -n monitoring -o wide | grep vmsingle    # which node shares this disk
```

Decide which of three it is:

1. **Genuine growth** — series count rising steadily; retention is doing its job
   and the volume simply outgrew the disk.
2. **Churn, not volume** — indexdb growing faster than data. See
   [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md).
3. **Not VictoriaMetrics** — the node's filesystem is shared. Something else on
   that worker may be the growth.

## Mitigation

1. Reduce retention (`-retentionPeriod`) — the fastest lever, and a deliberate
   change rather than an incident action.
2. Drop series you do not query. A cardinality audit finds them; the
   `ClickHouseErrorMetric_*` family alone is 737 metric names and ~4.8 % of all
   series on this platform.
3. Free space on the node.
4. Do **not** delete the storage directory to reclaim space — that is the
   monitoring history.

## Escalation

Critical, and escalate on the node. Once VictoriaMetrics goes read-only the
platform is flying blind, and every other alert's silence becomes meaningless.

## Related

- [VMSingleDiskRunsOutOfSpaceIn3Days](VMSingleDiskRunsOutOfSpaceIn3Days.md) — the
  predictive warning that should have fired first.
- [VMSingleTooHighChurnRate](VMSingleTooHighChurnRate.md) — the usual cause of
  index growth.

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
