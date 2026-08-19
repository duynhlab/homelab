# KubePodOOMKilled

| | |
|---|---|
| **Severity** | critical |
| **Category** | resources |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/pod-resources-alerts.yaml` |
| **Metrics** | `kube_pod_container_status_last_terminated_reason` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

A container is terminated with OOMKilled reason (fires immediately, `for: 0m`,
on any OOMKill seen in the last 15 minutes). The kernel killed the container
because its working set hit the memory limit — in-flight work died with it.

## Impact

A crash with possible data corruption: requests in flight were dropped, and
anything the process had buffered but not flushed is gone. Repeated OOMKills
turn into [KubePodCrashLooping](KubePodCrashLooping.md) and take the service
out entirely.

## Diagnosis

- Container exceeded its memory limit
- Memory leak
- Spike in request volume causing temporary memory pressure

### kubectl / logs

```bash
# Check terminated container status
kubectl describe pod -n $NAMESPACE $POD | grep -A5 "Last State"

# Check previous container logs
kubectl logs -n $NAMESPACE $POD -c $CONTAINER --previous --tail=200
```

### PromQL

```promql
# Alert expr
increase(kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}[15m]) > 0

# Check memory trajectory before OOM
container_memory_working_set_bytes{namespace="$NAMESPACE", pod=~"$POD.*"}
```

## Mitigation

1. Increase memory limits.
2. For Go services: set `GOMEMLIMIT` to ~90% of the memory limit to trigger GC
   before OOM.
3. Investigate heap profiles in Pyroscope for memory leak detection.

## Escalation

Page — this is the crash-plus-possible-data-corruption class, and a single
OOMKill on a stateful workload (database, Temporal worker) warrants immediate
eyes even if the pod restarted cleanly. A one-off kill on a stateless replica
that recovered can be downgraded to a ticket after checking the trajectory.
Do not just bump the limit and close: without a heap profile you are feeding a
leak a bigger meal, and the kill comes back on a slower fuse.

## Related

- [KubePodMemoryNearLimit](KubePodMemoryNearLimit.md) — the early warning for
  this alert.
- [KubePodCrashLooping](KubePodCrashLooping.md) — where repeated OOMKills end up.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
