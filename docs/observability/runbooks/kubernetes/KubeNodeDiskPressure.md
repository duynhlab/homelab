# KubeNodeDiskPressure

| | |
|---|---|
| **Severity** | warning |
| **Category** | nodes |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/node-alerts.yaml` |
| **Metrics** | `kube_node_status_condition` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Node DiskPressure condition is true for 5 minutes. Node filesystem or image
storage has crossed the kubelet's eviction threshold — the kubelet begins
garbage-collecting images and evicting pods to reclaim disk.

## Impact

Evictions plus image GC, with data risk on top: pods writing to node-local
storage (emptyDir, container logs, local-path PVs) can lose data or hit
ENOSPC. On Kind all PVs are local-path on this same disk, so database volumes
share the fate of the node filesystem.

## Diagnosis

### kubectl / logs

```bash
kubectl describe node $NODE | grep -A10 "Conditions"
# In Kind:
docker exec kind-control-plane df -h
docker exec kind-control-plane crictl images
```

### PromQL

```promql
# Alert expr
kube_node_status_condition{condition="DiskPressure", status="true"} == 1
```

## Mitigation

1. Clean up unused images: `docker exec kind-control-plane crictl rmi --prune`.
2. Check for large log files or WAL accumulation.
3. Expand disk allocation for Docker/Kind.

## Escalation

Ticket by default — image pruning usually clears it in minutes. Page if the
disk keeps filling after pruning, if evictions reach database pods, or if
[KubePersistentVolumeFillingUpCritical](KubePersistentVolumeFillingUpCritical.md)
co-fires (shared local-path disk). Do not delete directories inside the
node's container-runtime or PV storage paths by hand — pruning through
`crictl` is safe, hand-deleting under `/var/lib` is how volumes get corrupted.

## Related

- [KubePersistentVolumeFillingUp](KubePersistentVolumeFillingUp.md) — the
  per-volume view; on Kind both alerts watch the same physical disk.
- [KubeNodeNotReady](KubeNodeNotReady.md) — where unresolved pressure ends.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
