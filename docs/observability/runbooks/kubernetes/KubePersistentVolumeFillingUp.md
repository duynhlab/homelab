# KubePersistentVolumeFillingUp

| | |
|---|---|
| **Severity** | warning |
| **Category** | storage |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/workload-alerts.yaml` |
| **Metrics** | `kubelet_volume_stats_available_bytes`, `kubelet_volume_stats_capacity_bytes` (kubelet) |
| **Status** | inactive on Kind — local-path CSI reports no kubelet VolumeStats |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

PVC has less than 15% free space for 10 minutes. This is the early tripwire:
enough headroom remains to act deliberately before
[KubePersistentVolumeFillingUpCritical](KubePersistentVolumeFillingUpCritical.md)
takes over at 5%.

## Impact

Write failures are imminent if the trend continues: the workload behind the
PVC (usually a database or queue) will start returning ENOSPC, and databases
can corrupt or fence on a full volume. The 15% band is the window in which
expansion is still a calm operation.

## Diagnosis

### kubectl / logs

```bash
# Check PVC usage
kubectl exec -n $NAMESPACE $POD -- df -h /path/to/mount

# Check PVC capacity
kubectl get pvc -n $NAMESPACE $PVC -o jsonpath='{.status.capacity.storage}'
```

### PromQL

```promql
# Alert expr
kubelet_volume_stats_available_bytes
/ kubelet_volume_stats_capacity_bytes
< 0.15
and kubelet_volume_stats_capacity_bytes > 0

# PVC utilization
1 - kubelet_volume_stats_available_bytes{namespace="$NAMESPACE", persistentvolumeclaim="$PVC"}
    / kubelet_volume_stats_capacity_bytes{namespace="$NAMESPACE", persistentvolumeclaim="$PVC"}
```

## Mitigation

1. Expand PVC if StorageClass supports volume expansion.
2. For database PVCs: check WAL accumulation, run VACUUM, or investigate
   replication lag.
3. Clean up old data/logs if applicable.

## Escalation

Ticket — at 15% free there is time to expand or clean up on business hours,
unless the fill rate says otherwise: extrapolate the trend, and page if the
volume will cross 5% before anyone would pick up the ticket, or if the
critical twin is already firing. Do not delete WAL segments or database files
by hand to reclaim space — that converts a capacity problem into a data-loss
incident.

## Related

- [KubePersistentVolumeFillingUpCritical](KubePersistentVolumeFillingUpCritical.md)
  — the 5% escalation of this alert.
- [KubeNodeDiskPressure](KubeNodeDiskPressure.md) — node-level disk exhaustion
  with pod evictions.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
