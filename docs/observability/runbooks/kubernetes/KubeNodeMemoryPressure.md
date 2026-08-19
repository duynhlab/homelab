# KubeNodeMemoryPressure

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

Node MemoryPressure condition is true for 5 minutes. Node memory has crossed
the kubelet's eviction threshold — the kubelet is preparing to (or already
starting to) evict pods to reclaim memory.

## Impact

The kubelet evicts pods, starting with those exceeding their requests —
workloads disappear from the node without crashing, and BestEffort pods go
first. Left unresolved, the node can spiral into OOM kills and eventually
NotReady.

## Diagnosis

### kubectl / logs

```bash
kubectl describe node $NODE | grep -A10 "Conditions"
kubectl top pods --all-namespaces --sort-by=memory | head -20
```

### PromQL

```promql
# Alert expr
kube_node_status_condition{condition="MemoryPressure", status="true"} == 1
```

## Mitigation

1. Identify and scale down memory-heavy pods.
2. Add memory limits to unbounded pods.
3. In Kind: increase Docker memory allocation.

## Escalation

Ticket by default — pressure with no evictions yet is a capacity signal.
Page if evictions are actively hitting stateful or checkout-path pods, or if
[KubeNodeNotReady](KubeNodeNotReady.md) co-fires on the same node. Do not
respond by deleting the kubelet's chosen eviction victims yourself or by
loosening eviction thresholds — the pressure just re-selects new victims, and
the node needs memory freed, not different casualties.

## Related

- [KubePodOOMKilled](KubePodOOMKilled.md) — the per-container face of the same
  exhaustion.
- [KubeNodeNotReady](KubeNodeNotReady.md) — where unresolved pressure ends.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
