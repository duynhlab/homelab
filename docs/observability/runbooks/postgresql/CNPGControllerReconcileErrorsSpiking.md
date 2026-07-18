# CNPGControllerReconcileErrorsSpiking

| | |
|---|---|
| **Severity** | warning |
| **Source** | operator-health (global singleton) |

## Meaning

`increase(controller_runtime_reconcile_errors_total[10m]) > 5` — operator
reconcile loop failing repeatedly.

## Impact

Cluster desired state may drift — backups, failover, or upgrades stuck.

## Diagnosis

```bash
kubectl logs -n cloudnative-pg -l app.kubernetes.io/name=cloudnative-pg --tail=200 | grep -i error
kubectl get cluster,backup,scheduledbackup -A
```

## Mitigation

1. Read operator error — RBAC, webhook, invalid Cluster spec, object store.
2. Fix underlying CRD/manifest issue in GitOps repo.
3. `flux reconcile kustomization` for databases layer.

## Escalation

Ticket unless co-firing with operator down or cluster offline.
