# KubePersistentVolumeFillingUpCritical

| | |
|---|---|
| **Severity** | critical |
| **Category** | storage |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/workload-alerts.yaml` |
| **Metrics** | `kubelet_volume_stats_available_bytes`, `kubelet_volume_stats_capacity_bytes` (kubelet) |
| **Status** | inactive on Kind — local-path CSI reports no kubelet VolumeStats |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

PVC has less than 5% free space for 5 minutes — the escalation of
[KubePersistentVolumeFillingUp](KubePersistentVolumeFillingUp.md); same
investigation queries apply. At this level the next burst of writes can take
the volume to zero.

## Impact

Immediate data-loss risk: the workload is minutes from ENOSPC, and databases
can corrupt or fence on a full volume. Whatever fills the volume next —
a checkpoint, a WAL burst, a log rotation — hits the wall mid-write.

## Diagnosis

Same investigation queries as
[KubePersistentVolumeFillingUp](KubePersistentVolumeFillingUp.md).

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
< 0.05
and kubelet_volume_stats_capacity_bytes > 0
```

## Mitigation

1. Act immediately — expand the PVC now (or free space) before the workload
   hits ENOSPC; databases can corrupt or fence on a full volume.
2. If expansion is impossible, scale the writer down while you free space.

## Escalation

Page — this is the immediate-data-loss class; someone must be expanding the
volume or stopping the writer within minutes, not triaging a ticket. Stay
paged until free space is back above the 15% warning band, not merely above
5%. Do not restart the pod to "flush" space, and never hand-delete WAL or
data files — a restart on a full volume can leave a database unable to
recover at all.

## Related

- [KubePersistentVolumeFillingUp](KubePersistentVolumeFillingUp.md) — the 15%
  early warning this alert escalates from.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
