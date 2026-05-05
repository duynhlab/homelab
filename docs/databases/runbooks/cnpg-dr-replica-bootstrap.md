# Runbook: CNPG DR Replica Bootstrap

This runbook is a focused pointer for `cnpg-db-replica` bootstrap and recovery
checks. The canonical DRP now lives in [../010-drp.md](../010-drp.md); the CNPG
technical flow lives in [../005-ha-dr-deep-dive.md](../005-ha-dr-deep-dive.md).

## When to Use

Use this page when:

- `cnpg-db-replica` does not bootstrap from the RustFS backup path.
- The recovery job reports `full-recovery` errors.
- The DR replica pod loops while replaying WAL.
- You need the quick checks before promoting or rebuilding the DR replica.

## Current Topology

`cnpg-db-replica` is a separate CloudNativePG `Cluster` in namespace `product`.
It recovers from `cnpg-db` backups and WAL in:

```text
s3://pg-backups-cnpg/cnpg-db/
```

It also has its own backup prefix after bootstrap:

```text
s3://pg-backups-cnpg/cnpg-db-replica/
```

## Quick Checks

```bash
kubectl get cluster,backup,scheduledbackup -n product
kubectl get cluster cnpg-db cnpg-db-replica -n product -o wide
kubectl get pods -n product -l cnpg.io/cluster=cnpg-db-replica
```

Expected:

- `cnpg-db` has a recent completed backup.
- `cnpg-db` reports `ContinuousArchiving=True`.
- `cnpg-db-replica` reaches healthy state with one ready pod.

## Common Failure Points

| Symptom | Check |
|---------|-------|
| No base backup found | Verify `Backup` resources are completed and the RustFS prefix is correct |
| WAL replay stops | Check archived WAL availability and `archive_timeout` behavior on `cnpg-db` |
| Credentials error | Verify `pg-backup-rustfs-credentials` exists in namespace `product` |
| Wrong server name | Ensure restore source uses `serverName: cnpg-db-cluster` |
| Archive collision | Do not reuse a non-empty WAL archive path without understanding CNPG archive safety checks |

## Escalation Path

For incident decisions, use the recovery decision flow in
[../010-drp.md](../010-drp.md). Do not promote the DR replica until split-brain
risk is controlled and the incident owner approves cutover.
