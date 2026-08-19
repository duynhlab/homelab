# KubeHPAMaxedOut

| | |
|---|---|
| **Severity** | warning |
| **Category** | saturation |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/workload-alerts.yaml` |
| **Metrics** | `kube_horizontalpodautoscaler_status_current_replicas`, `kube_horizontalpodautoscaler_spec_max_replicas` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

HPA current replicas == max replicas for 15 minutes. The autoscaler has spent
its entire budget — whatever load pushed it there, there is no elasticity left.

## Impact

The service can't elastically absorb additional load: any further traffic
growth lands on already-saturated replicas as latency and errors. Not always
an incident — a load test or a flash of legitimate peak traffic pins the HPA
too — but the safety margin is gone while it lasts.

## Diagnosis

### kubectl / logs

```bash
kubectl get hpa -n $NAMESPACE $HPA
kubectl describe hpa -n $NAMESPACE $HPA
```

### PromQL

```promql
# Alert expr
kube_horizontalpodautoscaler_status_current_replicas
== kube_horizontalpodautoscaler_spec_max_replicas

# Check current vs max
kube_horizontalpodautoscaler_status_current_replicas{namespace="$NAMESPACE"}
/ kube_horizontalpodautoscaler_spec_max_replicas{namespace="$NAMESPACE"}
```

## Mitigation

1. If load is genuinely higher: increase `maxReplicas` in HPA spec.
2. If load is temporary: wait for scale-down.
3. Check if CPU/memory requests are too low (causing premature scale-up).

## Escalation

Ticket by default — pinned-at-max with healthy latency is a capacity-planning
note, not an emergency. Page if service latency or error-rate alerts co-fire
on the same workload, which means the ceiling is actively costing requests.
Do not crank `maxReplicas` sky-high as a reflex: on a small cluster the extra
pods just steal node capacity from neighbors, and if low requests caused a
premature scale-up, more replicas fix nothing.

## Related

- [KubePodCPUThrottlingHigh](KubePodCPUThrottlingHigh.md) — saturated replicas
  under CPU limits throttle before they scale.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
