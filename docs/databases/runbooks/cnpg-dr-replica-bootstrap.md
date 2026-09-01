# Runbook: CNPG DR Replica Bootstrap

This runbook is a focused pointer for `product-db-replica` bootstrap and recovery
checks. The canonical DRP now lives in [../disaster-recovery.md](../disaster-recovery.md); the CNPG
technical flow lives in the [disaster recovery plan](../disaster-recovery.md)
and the PostgreSQL [replication fundamentals](../fundamentals/replication.md).

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

It also archives its **own WAL** (as `isWALArchiver: true`) under a separate
prefix:

```text
s3://pg-backups-cnpg/product-db-replica/
```

That prefix receives **WAL only**: the replica has no `Backup`/`ScheduledBackup`
manifest, so no base backup anchors the chain and the prefix is **not
independently restorable**. Restores always come from the `product-db` prefix.

## Quick Checks

```bash
kubectl get cluster,backup,scheduledbackup -n product
kubectl get cluster product-db product-db-replica -n product -o wide
kubectl get pods -n product -l cnpg.io/cluster=product-db-replica
```

Expected:

- `product-db` has a recent completed backup.
- `product-db` reports `ContinuousArchiving=True`.
- `product-db-replica` reaches healthy state with three ready pods (designated
  primary plus two cascading standbys).

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
[../disaster-recovery.md](../disaster-recovery.md). Do not promote the DR replica until split-brain
risk is controlled and the incident owner approves cutover.

Promotion semantics: the replica **cluster** transitions via
`spec.replica.enabled: false` (a GitOps-committed change — see
[emergency-recovery.md](./emergency-recovery.md)), not via
`kubectl cnpg promote`. Disabling replication is **one-way**: turning it back
into a replica requires destroying the cluster and re-bootstrapping (re-cloning)
from the then-current primary.

---
_Last updated: 2026-09-01 — the cluster now runs 3 instances and takes its own daily base backup, so its prefix is a restorable chain. Previously 2026-08-31 — promotion/re-clone semantics documented._
