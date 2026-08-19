# KubePodCrashLooping

| | |
|---|---|
| **Severity** | critical |
| **Category** | resources |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/pod-resources-alerts.yaml` |
| **Metrics** | `kube_pod_container_status_waiting_reason` (kube-state-metrics) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Container is in CrashLoopBackOff for 10 minutes. The kubelet keeps restarting
the container and it keeps dying — after 10 minutes of backoff this is a
failure mode, not a slow start.

## Impact

The service behind this pod is unavailable (or degraded, if other replicas
still hold the line). Every crash-restart cycle also resets caches and
connections, so even partial capacity performs worse than the replica count
suggests.

## Diagnosis

- Application startup failure (missing config, database unavailable)
- Readiness/liveness probe misconfiguration
- Dependency not ready (database, secrets, ConfigMap)

### kubectl / logs

```bash
# Check pod events
kubectl describe pod -n $NAMESPACE $POD

# Check previous container logs
kubectl logs -n $NAMESPACE $POD --previous --tail=200

# Check if dependencies are ready
kubectl get pods -n $NAMESPACE
kubectl get externalsecrets -n $NAMESPACE
```

### PromQL

```promql
# Alert expr
max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m]) == 1
```

## Mitigation

1. Fix the root cause from container logs.
2. Check if database migrations completed (`kubectl get jobs -n $NAMESPACE`).
3. Verify ExternalSecret sync status if secrets are missing.

## Escalation

Page if the crashing pod is the last (or only) replica of a service, a
database instance, or anything on the checkout path — that is a user-facing
outage. Ticket if healthy replicas are absorbing traffic and the loop is
confined to one pod during a rollout. Do not `kubectl delete pod` repeatedly
hoping it sticks: the loop is deterministic, and each delete only destroys the
`--previous` logs that name the real cause.

## Related

- [KubePodOOMKilled](KubePodOOMKilled.md) — repeated OOMKills present as a
  crash loop.
- [KubeDeploymentReplicasMismatch](KubeDeploymentReplicasMismatch.md) —
  co-fires when the loop keeps a Deployment below desired replicas.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
