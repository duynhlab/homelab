# KubePodCPUThrottlingHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | resources |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/pod-resources-alerts.yaml` |
| **Metrics** | `container_cpu_cfs_throttled_periods_total`, `container_cpu_cfs_periods_total` (cAdvisor) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Container CPU throttling exceeds 25% of CFS periods for 15 minutes. The
container repeatedly hits its CFS quota ceiling — it wants more CPU than its
limit allows, so the kernel pauses it every scheduling period.

## Impact

Request latency rises while the container waits out throttled periods — an SLA
risk for user-facing services. The workload keeps running, so this degrades
rather than breaks; sustained throttling on hot-path services is what hurts.

## Diagnosis

- CPU limits too low for the workload
- Bursty CPU usage hitting CFS quota ceiling
- Noisy neighbor on the same node consuming CPU

### kubectl / logs

```bash
# Check container resource limits
kubectl get pod -n $NAMESPACE $POD -o jsonpath='{.spec.containers[*].resources}'

# Check actual CPU usage vs limits
kubectl top pod -n $NAMESPACE $POD --containers
```

### PromQL

```promql
# Alert expr
sum by (namespace, pod, container) (
  increase(container_cpu_cfs_throttled_periods_total{container!=""}[5m])
)
/ sum by (namespace, pod, container) (
  increase(container_cpu_cfs_periods_total{container!=""}[5m])
) > 0.25

# Verify throttling percentage
sum by (namespace, pod, container) (
  increase(container_cpu_cfs_throttled_periods_total{namespace="$NAMESPACE", pod="$POD"}[5m])
) / sum by (namespace, pod, container) (
  increase(container_cpu_cfs_periods_total{namespace="$NAMESPACE", pod="$POD"}[5m])
)
```

## Mitigation

1. Increase CPU limits if the workload genuinely needs more CPU.
2. Consider removing CPU limits entirely (use requests only) — the widely
   adopted guidance for latency-sensitive workloads; requests still guarantee
   scheduling while limits add throttling with no isolation benefit.
3. If the service is a Go app, check `GOMAXPROCS` aligns with CPU requests.

## Escalation

Ticket by default — throttling is a tuning problem, not an outage. Page only
if a latency SLO burn-rate alert or `MicroserviceHighLatency` co-fires on the
throttled service, which means shoppers are feeling it. Do not delete the CPU
limit in a panic without checking node headroom first: an unlimited hot loop
can starve every neighbor on the node and turn one slow pod into a node-wide
incident.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
