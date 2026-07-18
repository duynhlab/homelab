# CNPGClusterLogicalReplicationLaggingCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Status** | **Inactive on homelab** |

## Meaning

Lag **>300s** or buffered **>4 GB**.

## Impact

Disk exhaustion on subscriber; long recovery to catch up.

## Diagnosis

See [CNPGClusterLogicalReplicationLagging.md](CNPGClusterLogicalReplicationLagging.md).

## Mitigation

Pause non-critical publishers if needed; scale subscriber; consider resync.

## Escalation

**P1** when active in production.
