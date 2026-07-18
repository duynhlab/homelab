# CNPGClusterLowDiskSpaceWarning

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Status** | **Inactive on Kind** — local-path CSI does not emit `kubelet_volume_stats_*` |

## Meaning

PVC usage **>70%** for **5 minutes** (PGDATA, WAL, or tablespace PVCs).

## Impact

Proactive capacity signal — add storage before critical threshold.

## Diagnosis

> On Kind homelab this alert does not fire. Documented for production clusters
> with kubelet volume stats enabled.

```promql
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.7
```

```bash
kubectl get pvc -n "$NAMESPACE" -l cnpg.io/cluster=$CLUSTER
```

Also monitor `cnpg_pg_database_size_bytes` and
[signals/capacity-planning.md](../../metrics/postgresql/signals/capacity-planning.md).

## Mitigation

1. Expand PVC if storage class allows volume expansion.
2. Run VACUUM / drop bloat; check WAL archive — [CNPGWALArchiveFailing.md](CNPGWALArchiveFailing.md).
3. Review top tables via pg-maintenance dashboard.

## Escalation

Ticket in warning; page at critical threshold.
