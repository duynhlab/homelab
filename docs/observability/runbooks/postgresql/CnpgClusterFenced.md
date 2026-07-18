# CnpgClusterFenced

| | |
|---|---|
| **Severity** | critical |
| **Source** | homelab-extra |
| **Clusters** | `platform-db`, `product-db` |
| **Grafana** | CloudNativePG Cluster Overview |

## Meaning

`cnpg_collector_fencing_on == 1` for **1 minute** — the cluster is **fenced**.
CNPG blocks all write operations to prevent split-brain after operator
intervention or manual fencing.

## Impact

All writes fail. Read-only queries to replicas may still work depending on fence
mode. Applications see errors on any mutating path.

## Diagnosis

```bash
kubectl get cluster -n "$NAMESPACE" "$CLUSTER" -o yaml | grep -i fenced
kubectl cnpg status "$CLUSTER" -n "$NAMESPACE" 2>/dev/null || true
kubectl logs -n cloudnative-pg -l app.kubernetes.io/name=cloudnative-pg --tail=100
```

Check recent operator actions, failed failovers, or manual `cnpg fencing` commands.

## Mitigation

1. **Do not unfence blindly** — understand why fencing was applied (CNPG
   failure modes docs).
2. Follow [Emergency recovery](../../../databases/010.4-emergency-recovery.md)
   with IC approval.
3. After root cause fixed, unfence per CNPG procedure for your scenario.

## Escalation

**P0** — coordinated with database recovery owner; never unfence without IC
go/no-go.
