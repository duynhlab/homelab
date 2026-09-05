# KubeletTooManyPods

| | |
|---|---|
| **Severity** | warning |
| **Category** | capacity |
| **Source** | `.../prometheusrules/kubernetes/controlplane-alerts.yaml` |
| **Metrics** | `kubelet_running_pods` / `kubelet_node_config_assigned_pod_cidr_max_pods` |
| **Status** | 💤 **inert on Kind** — the denominator has **0 series** |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present |

## Meaning

A node is approaching its maximum pod count.

**It cannot fire on this platform.** `kubelet_running_pods` is present (8 kubelet
targets report it), but `kubelet_node_config_assigned_pod_cidr_max_pods` returns
**no series** — Kind's kubelet does not publish it. A ratio with an absent
denominator matches nothing, so the rule evaluates to silence and vmalert reports
no error, because a rule matching nothing is not a rule failing.

It is **kept, not deleted**, on the same policy as the PVC alerts: the metric
name is correct on a normal cluster, and deleting it would mean re-deriving it
later. The alert catalog marks it 💤 and lists it under "Alerts that are inert on
Kind, and why they are kept".

## Impact

On a cluster where it works: nearing the pod cap means new pods will go
`Pending` on that node, and the scheduler quietly loses a placement option.

Here: none. The signal simply does not exist.

## Diagnosis

Since the alert cannot fire, capacity has to be checked directly:

```bash
kubectl get nodes -o custom-columns='NODE:.metadata.name,PODS:.status.capacity.pods,ALLOC:.status.allocatable.pods'
for n in $(kubectl get nodes -o name); do
  echo "$n $(kubectl get pods -A --field-selector spec.nodeName=${n#node/} --no-headers | wc -l)"
done
```

```promql
# The numerator does exist, so this is usable even though the ratio is not
max by (instance) (kubelet_running_pods)
```

## Mitigation

If a node is genuinely near capacity, the answer is scheduling — spread the
workload or add a node. On Kind the cluster is three workers by definition, so
"add a node" means editing `scripts/kind-up.sh` and rebuilding.

To make the alert live on a real cluster, nothing needs changing: the expression
is correct, the metric will simply be there.

## Escalation

Not applicable here — it cannot fire. If pod capacity is genuinely a concern,
use the direct checks above rather than waiting for an alert that will not come.

## Related

- [KubeletDown](KubeletDown.md)
- [KubeNodeNotReady](KubeNodeNotReady.md)
- Catalog: **Alerts that are inert on Kind, and why they are kept**

---
_Last updated: 2026-09-05 — created; documents why this rule is inert rather than leaving it looking like coverage_
