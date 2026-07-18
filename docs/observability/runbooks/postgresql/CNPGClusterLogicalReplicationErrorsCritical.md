# CNPGClusterLogicalReplicationErrorsCritical

| | |
|---|---|
| **Severity** | critical |
| **Source** | chart |
| **Status** | **Inactive on homelab** |

## Meaning

≥5 logical replication errors in **5 minutes**.

## Impact

Persistent replication failure — manual intervention required.

## Diagnosis

See [CNPGClusterLogicalReplicationErrors.md](CNPGClusterLogicalReplicationErrors.md).

## Mitigation

Same as warning — treat as urgent; may require subscription drop/recreate after
root cause fix.

## Escalation

**P1** when rule is active in production.
