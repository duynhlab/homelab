# KubeNodeNotReady

| | |
|---|---|
| **Severity** | critical |
| **Category** | nodes |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/node-alerts.yaml` |
| **Metrics** | `kube_node_status_condition` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Node Ready condition is false for 5 minutes. The kubelet has stopped
heartbeating healthily — after the eviction timeout the control plane starts
moving that node's pods elsewhere.

## Impact

Pods get evicted and stateful workloads are disrupted: everything scheduled on
this node is rescheduled (if capacity exists elsewhere) or lost from the
serving pool. On the single-node Kind cluster this is effectively the whole
platform going dark.

## Diagnosis

### kubectl / logs

```bash
kubectl get nodes
kubectl describe node $NODE
kubectl get events --field-selector involvedObject.name=$NODE
```

### PromQL

```promql
# Alert expr
kube_node_status_condition{condition="Ready", status="true"} == 0
```

## Mitigation

1. Check kubelet logs on the node.
2. In Kind: restart the Kind container (`docker restart kind-control-plane`).
3. Check for disk pressure or memory pressure conditions.

## Escalation

Page — a NotReady node means evictions and stateful disruption are already in
motion, and on this platform's node count there is no capacity slack to hide
behind. If every node flips NotReady at once, suspect the metrics pipeline or
API server before the hardware, and check
[KubeAPIServerDown](KubeAPIServerDown.md). Do not immediately drain or delete
the node: mass-rescheduling stateful pods off a node that is about to recover
does more damage than the blip itself.

## Related

- [KubeNodeMemoryPressure](KubeNodeMemoryPressure.md),
  [KubeNodeDiskPressure](KubeNodeDiskPressure.md) — pressure conditions that
  often precede NotReady.
- [KubeAPIServerDown](KubeAPIServerDown.md) — control-plane loss can present
  as all nodes NotReady.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
