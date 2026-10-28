# Kubernetes substrate

Pod, workload, storage, node, and API-server failures under everything else.
Often the real cause when an "app" or "database" symptom has no application
explanation.

## Authoritative docs

- Per-alert (pods, workloads, storage, nodes, API server, network):
  [kubernetes runbooks](../../../../../docs/observability/runbooks/kubernetes/README.md).
- Bring-up substrate gotchas (podman sockets, sysctls, VM disk):
  [platform/setup.md](../../../../../docs/platform/setup.md).

## Diagnose (read-only first)

```bash
kubectl get pods -A | grep -vE ' Running| Completed'
kubectl describe pod <pod> -n <ns>          # events: scheduling, probes, image
kubectl logs <pod> -n <ns> --previous --tail=100   # last crash
kubectl get pvc -A | grep -v ' Bound'
kubectl top pods -n <ns>                     # if metrics-server is up
```

| Symptom | First look |
|---|---|
| CrashLoopBackOff | `--previous` logs, then the app/DB domain for the real error |
| OOMKilled | memory limit vs working set; `KubePodOOMKilled` runbook |
| Pending pod | node resources, PVC binding, taints/affinity |
| PVC filling | `KubePersistentVolumeFillingUp`; storage, not app |
| API `EOF` / `Forbidden` on bring-up | often Kyverno webhook or a near-full podman VM, not RBAC — [setup.md](../../../../../docs/platform/setup.md) |

## Boundary

The substrate rarely has a one-command fix that is safe on prod. Scaling,
cordoning, and PVC deletion change state — get approval and route a persistent
cause to its owning domain (image/app, storage, policy).
