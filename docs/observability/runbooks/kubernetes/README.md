# Kubernetes Alert Runbooks

Per-alert investigation guides for the Kubernetes infrastructure alerts — the
USE Method (Utilization, Saturation, Errors) applied to pod resources,
workloads and storage, nodes, the API server (Four Golden Signals), and
container networking. Metrics come from kube-state-metrics (`kube_*`),
cAdvisor via the kubelet (`container_*`), the kubelet itself
(`kubelet_volume_stats_*`), and the kube-apiserver (`apiserver_*`). One file
per alert name.

| Quick facts | |
|---|---|
| Alert rules | [`prometheusrules/kubernetes/`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/) |
| Alert catalog | [§5 Kubernetes](../../alerting/alert-catalog.md#5-kubernetes) |
| Template | [`_TEMPLATE.md`](../_TEMPLATE.md) |

## Index

| Alert | Sev | Source | Status | Runbook |
|-------|-----|--------|--------|---------|
| **Pod resources** (`pod-resources-alerts.yaml`) | | | | |
| KubePodCPUThrottlingHigh | warning | pod-resources-alerts | active | [KubePodCPUThrottlingHigh.md](KubePodCPUThrottlingHigh.md) |
| KubePodMemoryNearLimit | warning | pod-resources-alerts | active | [KubePodMemoryNearLimit.md](KubePodMemoryNearLimit.md) |
| KubePodOOMKilled | critical | pod-resources-alerts | active | [KubePodOOMKilled.md](KubePodOOMKilled.md) |
| KubePodCrashLooping | critical | pod-resources-alerts | active | [KubePodCrashLooping.md](KubePodCrashLooping.md) |
| KubePodNotReady | warning | pod-resources-alerts | active | [KubePodNotReady.md](KubePodNotReady.md) |
| **Workloads & storage** (`workload-alerts.yaml`) | | | | |
| KubeDeploymentReplicasMismatch | warning | workload-alerts | active | [KubeDeploymentReplicasMismatch.md](KubeDeploymentReplicasMismatch.md) |
| KubeStatefulSetReplicasMismatch | warning | workload-alerts | active | [KubeStatefulSetReplicasMismatch.md](KubeStatefulSetReplicasMismatch.md) |
| KubeJobFailed | warning | workload-alerts | active | [KubeJobFailed.md](KubeJobFailed.md) |
| KubeHPAMaxedOut | warning | workload-alerts | active | [KubeHPAMaxedOut.md](KubeHPAMaxedOut.md) |
| KubePersistentVolumeFillingUp | warning | workload-alerts | inactive on Kind | [KubePersistentVolumeFillingUp.md](KubePersistentVolumeFillingUp.md) |
| KubePersistentVolumeFillingUpCritical | critical | workload-alerts | inactive on Kind | [KubePersistentVolumeFillingUpCritical.md](KubePersistentVolumeFillingUpCritical.md) |
| **Nodes** (`node-alerts.yaml`) | | | | |
| KubeNodeNotReady | critical | node-alerts | active | [KubeNodeNotReady.md](KubeNodeNotReady.md) |
| KubeNodeMemoryPressure | warning | node-alerts | active | [KubeNodeMemoryPressure.md](KubeNodeMemoryPressure.md) |
| KubeNodeDiskPressure | warning | node-alerts | active | [KubeNodeDiskPressure.md](KubeNodeDiskPressure.md) |
| KubeNodePIDPressure | warning | node-alerts | active | [KubeNodePIDPressure.md](KubeNodePIDPressure.md) |
| KubeNodeUnschedulable | warning | node-alerts | active | [KubeNodeUnschedulable.md](KubeNodeUnschedulable.md) |
| **API server** (`apiserver-alerts.yaml`) | | | | |
| KubeAPIServerDown | critical | apiserver-alerts | active | [KubeAPIServerDown.md](KubeAPIServerDown.md) |
| KubeAPIServerHighLatency | warning | apiserver-alerts | active | [KubeAPIServerHighLatency.md](KubeAPIServerHighLatency.md) |
| KubeAPIServerErrorRate | warning | apiserver-alerts | active | [KubeAPIServerErrorRate.md](KubeAPIServerErrorRate.md) |
| KubeAPIServerHighInflight | warning | apiserver-alerts | active | [KubeAPIServerHighInflight.md](KubeAPIServerHighInflight.md) |
| **Network** (`network-rules.yaml`) | | | | |
| KubeContainerNetworkErrors | warning | network-rules | active | [KubeContainerNetworkErrors.md](KubeContainerNetworkErrors.md) |

## Domain specifics

- **Extra quick-facts rows:** none beyond the standard template set.
- **Diagnosis dialect:** kubectl-first, PromQL second — the fastest evidence
  for infrastructure alerts is usually `kubectl describe`/`kubectl top`, with
  PromQL for verifying thresholds and trends.
- **Dashboards:** all boards live in the Grafana **Observability** folder
  (default board: Kubernetes cluster overview).
- **Local-stack:** none of these alerts exist on local-stack — the compose
  stack has no Kubernetes, so every runbook carries the same "not present"
  row.

## Template

New runbooks follow [`_TEMPLATE.md`](../_TEMPLATE.md) (Meaning → Impact →
Diagnosis → Mitigation → Escalation).

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
