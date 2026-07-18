# CNPGClusterLowDiskSpaceCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Status** | **Inactive on Kind** — local-path CSI does not emit `kubelet_volume_stats_*` |

## Meaning

PVC usage **>90%** for **5 minutes**.

## Impact

Imminent write failure — Postgres may crash when disk full. Data corruption risk
if WAL cannot be written.

## Diagnosis

See [CNPGClusterLowDiskSpaceWarning.md](CNPGClusterLowDiskSpaceWarning.md).

## Mitigation

1. **Emergency** — free WAL (`archive_command` working?) or expand PVC immediately.
2. Stop non-essential writers if disk cannot expand.
3. Follow [Emergency recovery](../../../databases/010.4-emergency-recovery.md) if
   instance down.

## Escalation

**P0** in production when active.
