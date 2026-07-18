# CNPGClusterLogicalReplicationStoppedCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Status** | **Inactive on homelab** |

## Meaning

Replication stopped with backlog **≥15 minutes**.

## Impact

Significant divergence — manual recovery likely.

## Diagnosis

See [CNPGClusterLogicalReplicationStopped.md](CNPGClusterLogicalReplicationStopped.md).

## Mitigation

Coordinate full resync with IC; may require new subscription and snapshot.

## Escalation

**P1** when active.
