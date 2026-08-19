# KubeAPIServerDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/apiserver-alerts.yaml` |
| **Metrics** | `up{job="apiserver"}` (kube-apiserver ServiceMonitor scrape) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

API server is unreachable for 5 minutes (`absent(up{job="apiserver"} == 1)`).
Because the expr uses `absent()`, it also fires if the scrape target vanishes
— verify with `kubectl` before concluding the control plane itself is dead.

## Impact

Control plane down — the cluster is unmanageable: no deploys, no Flux
reconciliation, no scaling, no self-healing, no kubectl. Already-running pods
keep serving for a while, but every recovery mechanism the platform relies on
is offline.

## Diagnosis

### kubectl / logs

```bash
kubectl cluster-info
# In Kind:
docker ps | grep control-plane
docker logs kind-control-plane 2>&1 | tail -50
```

### PromQL

```promql
# Alert expr
absent(up{job="apiserver"} == 1)
```

## Mitigation

1. In Kind: `docker restart kind-control-plane`.
2. Check etcd health (API server depends on it).
3. Check for resource exhaustion on control plane node.

## Escalation

Page — control-plane-down is the cluster-unmanageable class, and every other
alert's mitigation depends on the API server answering. Expect a wave of
co-firing alerts ([KubeNodeNotReady](KubeNodeNotReady.md), Flux failures)
that are all downstream of this one — fix here first. Do not start "fixing"
workloads that look broken while the API server is out: kubectl mutations
queued against a flapping control plane land unpredictably when it returns.

## Related

- [KubeAPIServerHighLatency](KubeAPIServerHighLatency.md),
  [KubeAPIServerErrorRate](KubeAPIServerErrorRate.md),
  [KubeAPIServerHighInflight](KubeAPIServerHighInflight.md) — the degraded
  precursors to a full outage.
- [KubeNodeNotReady](KubeNodeNotReady.md) — all nodes NotReady at once usually
  means the control plane, not the nodes.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
