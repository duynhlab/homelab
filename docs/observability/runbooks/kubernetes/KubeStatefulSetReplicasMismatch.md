# KubeStatefulSetReplicasMismatch

| | |
|---|---|
| **Severity** | warning |
| **Category** | workloads |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/workload-alerts.yaml` |
| **Metrics** | `kube_statefulset_status_replicas_ready`, `kube_statefulset_status_replicas` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

StatefulSet ready replicas != desired replicas for 15 minutes. Because
StatefulSets scale strictly in order, one stuck member blocks every member
behind it — the mismatch usually points at a single wedged pod.

## Impact

Data-consistency risk: stateful members (databases, queues, Temporal) run
below quorum or without their replica safety margin, so the next failure can
mean data loss instead of a failover. Ordered scaling also means the set
cannot self-heal past the stuck member.

## Diagnosis

### kubectl / logs

```bash
kubectl get statefulset -n $NAMESPACE $STATEFULSET
kubectl describe statefulset -n $NAMESPACE $STATEFULSET
kubectl get pvc -n $NAMESPACE -l app=$STATEFULSET
```

### PromQL

```promql
# Alert expr
kube_statefulset_status_replicas_ready
!= kube_statefulset_status_replicas
```

## Mitigation

1. StatefulSets scale sequentially; check if a pod is stuck.
2. Verify PVCs are bound for each replica.
3. For database StatefulSets: check operator status (Zalando/CNPG).

## Escalation

Ticket by default, but treat database-backing StatefulSets with more urgency:
page if the mismatch takes a data store below its replica quorum or if the
operator's own alerts (CNPG HA warnings) co-fire. Do not delete the stuck
pod's PVC to "unstick" it — for stateful workloads that volume *is* the data,
and the operator, not you, decides when a member is disposable.

## Related

- [KubePodNotReady](KubePodNotReady.md) — unbound PVCs leave the member Pending.
- [KubePersistentVolumeFillingUp](KubePersistentVolumeFillingUp.md) — full
  volumes are a common way stateful members wedge.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
