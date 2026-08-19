# KubeNodePIDPressure

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

Node PIDPressure condition is true for 5 minutes. The node is running low on
available process IDs — something is spawning processes (or threads) faster
than it reaps them.

## Impact

No new processes can start and the node becomes unstable: health probes that
exec, log shippers, and the kubelet's own helpers all begin failing in
confusing ways. Fork failures rarely stay contained to the offending pod.

## Diagnosis

### kubectl / logs

```bash
kubectl describe node $NODE | grep -A10 "Conditions"
# Check process count in Kind:
docker exec kind-control-plane ps aux | wc -l
```

### PromQL

```promql
# Alert expr
kube_node_status_condition{condition="PIDPressure", status="true"} == 1
```

## Mitigation

1. Identify pods with goroutine leaks (check `MicroserviceGoroutineLeak`
   alert).
2. Kill runaway processes.
3. Increase PID limits if configured.

## Escalation

Ticket by default — a single leaking workload identified via
`MicroserviceGoroutineLeak` is a fix-the-service ticket. Page if fork
failures are spreading (probes failing across namespaces) or the node is
heading toward [KubeNodeNotReady](KubeNodeNotReady.md). Do not raise the PID
limit as the first move — it buys minutes while hiding the leak, and the
limit exists precisely to keep one runaway pod from exhausting the kernel's
process table.

## Related

- [KubeNodeNotReady](KubeNodeNotReady.md) — where sustained PID exhaustion ends.
- `MicroserviceGoroutineLeak` (microservices runbooks) — the usual culprit
  signal on this platform.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
