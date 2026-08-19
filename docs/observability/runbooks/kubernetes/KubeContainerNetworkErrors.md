# KubeContainerNetworkErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | network |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/network-rules.yaml` |
| **Metrics** | `container_network_receive_errors_total`, `container_network_transmit_errors_total` (cAdvisor) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Network error rate exceeds 1 error/sec for 10 minutes. These are
interface-level receive/transmit errors on the pod's veth — a lower layer
than the HTTP/gRPC errors the service alerts watch.

## Impact

Packet loss makes inter-service communication unreliable: retries and
timeouts inflate tail latency in ways application dashboards can't explain,
because the requests never cleanly fail. gRPC east-west calls and database
connections on the affected pod all degrade together.

## Diagnosis

### kubectl / logs

```bash
kubectl describe pod -n $NAMESPACE $POD
kubectl get networkpolicies -n $NAMESPACE
```

### PromQL

```promql
# Alert expr
sum by (namespace, pod) (
  rate(container_network_receive_errors_total[5m])
  + rate(container_network_transmit_errors_total[5m])
) > 1

sum by (namespace, pod) (
  rate(container_network_receive_errors_total[5m])
  + rate(container_network_transmit_errors_total[5m])
)
```

## Mitigation

1. Check CNI plugin health (in Kind: kindnet).
2. Review NetworkPolicies that might be causing drops.
3. Check for DNS resolution issues.

## Escalation

Ticket by default — a single pod's interface errors are a pod or CNI quirk;
recreate the pod and watch. Page if errors appear on many pods across
namespaces at once (CNI or node NIC problem) or if service latency/error
alerts co-fire on the affected paths. Do not start deleting NetworkPolicies
to "rule them out": policies drop packets by design, and removing them opens
east-west traffic the security model depends on — inspect them read-only
instead.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
