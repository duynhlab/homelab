# Runbook: CNPG DR Replica Bootstrap

This runbook is a focused pointer for `product-db-replica` bootstrap and recovery
checks. The canonical DRP now lives in [../010-drp.md](../010-drp.md); the CNPG
technical flow lives in [../005-ha-dr-deep-dive.md](../005-ha-dr-deep-dive.md).

## When to Use

Use this page when:

- `product-db-replica` does not bootstrap from the RustFS backup path.
- The recovery job reports `full-recovery` errors.
- The DR replica pod loops while replaying WAL.
- You need the quick checks before promoting or rebuilding the DR replica.

## Current Topology

`product-db-replica` is a separate CloudNativePG `Cluster` in namespace `product`.
It recovers from `product-db` backups and WAL in:

```text
s3://pg-backups-cnpg/product-db/
```

It also has its own backup prefix after bootstrap:

```text
s3://pg-backups-cnpg/product-db-replica/
```

## Quick Checks

```bash
kubectl get cluster,backup,scheduledbackup -n product
kubectl get cluster product-db product-db-replica -n product -o wide
kubectl get pods -n product -l cnpg.io/cluster=product-db-replica
```

Expected:

- `product-db` has a recent completed backup.
- `product-db` reports `ContinuousArchiving=True`.
- `product-db-replica` reaches healthy state with one ready pod.

## Common Failure Points

| Symptom | Check |
|---------|-------|
| No base backup found | Verify `Backup` resources are completed and the RustFS prefix is correct |
| WAL replay stops | Check archived WAL availability and `archive_timeout` behavior on `product-db` |
| Credentials error | Verify `pg-backup-rustfs-credentials` exists in namespace `product` |
| Wrong server name | Ensure restore source uses `serverName: product-db-cluster` |
| Archive collision | Do not reuse a non-empty WAL archive path without understanding CNPG archive safety checks |

## Escalation Path

For incident decisions, use the recovery decision flow in
[../010-drp.md](../010-drp.md). Do not promote the DR replica until split-brain
risk is controlled and the incident owner approves cutover.

---
_Last updated: 2026-07-11_
