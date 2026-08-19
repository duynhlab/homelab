# KubeNodeUnschedulable

| | |
|---|---|
| **Severity** | warning |
| **Category** | nodes |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/node-alerts.yaml` |
| **Metrics** | `kube_node_spec_unschedulable` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Node is cordoned (unschedulable) for 5 minutes. Existing pods keep running,
but no new pods will land on this node — this alert mostly exists to catch a
cordon someone forgot to lift after maintenance.

## Impact

Cluster scheduling capacity is reduced: rollouts, HPA scale-ups, and evicted
pods all have one fewer node to land on. On a small cluster a lingering
cordon can quietly block every new pod from scheduling.

## Diagnosis

### kubectl / logs

```bash
kubectl get nodes -o wide
kubectl describe node $NODE | grep -i taint
```

### PromQL

```promql
# Alert expr
kube_node_spec_unschedulable == 1
```

## Mitigation

1. If intentional (maintenance): no action needed.
2. If accidental: `kubectl uncordon $NODE`.

## Escalation

Ticket — a cordon is a deliberate, reversible state, and the fix is one
command once you know whether it was intentional. Page only if the reduced
capacity is actively stranding pods (co-firing
[KubePodNotReady](KubePodNotReady.md) with Pending pods and nowhere to
schedule them). Do not uncordon a node you did not cordon without asking who
did and why — you may be re-enabling scheduling onto a node mid-maintenance
or mid-diagnosis.

## Related

- [KubePodNotReady](KubePodNotReady.md) — Pending pods are how a forgotten
  cordon becomes visible.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
