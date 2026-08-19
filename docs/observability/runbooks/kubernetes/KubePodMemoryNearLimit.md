# KubePodMemoryNearLimit

| | |
|---|---|
| **Severity** | warning |
| **Category** | resources |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/pod-resources-alerts.yaml` |
| **Metrics** | `container_memory_working_set_bytes` (cAdvisor), `kube_pod_container_resource_limits` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Container memory working set exceeds 90% of its memory limit for 15 minutes.
The working set is what the kernel cannot reclaim, so the container is one
allocation spike away from the hard limit.

## Impact

OOMKill is imminent: if the working set touches the limit, the kernel kills
the container mid-request. Catching it here is the last chance to act before
[KubePodOOMKilled](KubePodOOMKilled.md) turns a warning into a crash.

## Diagnosis

- Memory limits too conservative for the workload
- Memory leak (gradually increasing over time)
- Large in-memory cache or data structure

### kubectl / logs

```bash
# Check memory limits
kubectl get pod -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].resources}'

# Check actual memory usage
kubectl top pod -n $NAMESPACE $POD --containers
```

### PromQL

```promql
# Alert expr
sum by (namespace, pod, container) (container_memory_working_set_bytes{container!="", container!="POD"})
/ sum by (namespace, pod, container) (
    label_replace(label_replace(label_replace(
    kube_pod_container_resource_limits{resource="memory"},
  "namespace", "$1", "exported_namespace", "(.+)"),
  "pod", "$1", "exported_pod", "(.+)"),
  "container", "$1", "exported_container", "(.+)")
  )
> 0.9

# Memory usage ratio
container_memory_working_set_bytes{namespace="$NAMESPACE", pod="$POD"}
/ kube_pod_container_resource_limits{resource="memory", namespace="$NAMESPACE", pod="$POD"}
```

## Mitigation

1. Increase memory limits if usage is stable at high levels.
2. If Go service: check heap profiles via Pyroscope, tune `GOMEMLIMIT`.
3. Check for memory leak pattern: steadily increasing `go_memory_used_bytes`
   (OTel runtime; the `go_memstats_*` client_golang gauges were retired at the
   RFC-0014 P3 cutover) without returning to baseline.

## Escalation

Ticket by default — a stable 90–95% working set is a sizing question. Page if
the trajectory is still climbing with no plateau, or if
[KubePodOOMKilled](KubePodOOMKilled.md) starts co-firing on the same pod.
Do not restart the pod just to reset the graph: a leak will march straight
back up, and you lose the live heap Pyroscope needs to name the culprit.

## Related

- [KubePodOOMKilled](KubePodOOMKilled.md) — fires if memory hits the hard limit.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
