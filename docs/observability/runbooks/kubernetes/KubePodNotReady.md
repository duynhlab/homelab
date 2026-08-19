# KubePodNotReady

| | |
|---|---|
| **Severity** | warning |
| **Category** | resources |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/pod-resources-alerts.yaml` |
| **Metrics** | `kube_pod_status_phase` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Pod stuck in Pending/Unknown state for 15 minutes. The pod never started
running at all — it is waiting on scheduling, storage, or an image, which is a
different failure class from a crash.

## Impact

The workload can't run: whatever this pod was meant to serve or process is
simply absent. For a scaled Deployment that means reduced capacity; for a
singleton (Job, operator, StatefulSet member) it means the function is missing
entirely.

## Diagnosis

- Insufficient cluster resources (CPU/memory)
- Node affinity/taint preventing scheduling
- PVC not bound
- Image pull failure

### kubectl / logs

```bash
# Check pod events for scheduling issues
kubectl describe pod -n $NAMESPACE $POD

# Check node resources
kubectl describe nodes | grep -A5 "Allocated resources"

# Check PVC status
kubectl get pvc -n $NAMESPACE
```

### PromQL

```promql
# Alert expr
sum by (namespace, pod) (
  max by (namespace, pod) (kube_pod_status_phase{phase=~"Pending|Unknown"})
) > 0
```

## Mitigation

1. If resource constrained: scale down other workloads or add nodes.
2. If PVC issue: check StorageClass and provisioner.
3. If image pull: verify image exists and credentials are correct.

## Escalation

Ticket by default — a single Pending pod with healthy siblings is a scheduling
puzzle, not an incident. Page when many pods across namespaces go Pending at
once (cluster out of capacity) or when a node-class alert such as
[KubeNodeNotReady](KubeNodeNotReady.md) co-fires. Do not force the issue by
deleting taints or slashing other workloads' requests to make room — that
trades one stuck pod for cluster-wide contention.

## Related

- [KubeNodeUnschedulable](KubeNodeUnschedulable.md) — cordoned nodes shrink
  the schedulable pool.
- [KubeDeploymentReplicasMismatch](KubeDeploymentReplicasMismatch.md) —
  Pending pods keep the Deployment below desired replicas.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
