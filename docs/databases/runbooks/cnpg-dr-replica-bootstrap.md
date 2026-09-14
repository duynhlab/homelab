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

The replica also has a daily `ScheduledBackup` (`product-db-replica-daily`) and
a seven-day retention window. Its write prefix therefore contains a complete,
independently restorable Barman chain rather than WAL alone. Normal DR bootstrap
still reads from `product-db/`; the replica prefix protects the promoted-cluster
case and is not the source for a routine re-clone.

## Rebuild invariant

Barman treats one `serverName` as one continuous WAL history. Before a newly
bootstrapped cluster starts archiving, its write destination for that
`serverName` must be empty. Deleting the Kubernetes `Cluster` deliberately does
not delete backups, so recreating `product-db-replica` with the unchanged
`product-db-replica-cluster` name fails closed with `Expected empty archive`.

The approved default is to rotate the DR **write** `serverName` in Git before
recreation. This preserves the old chain and gives the new cluster an empty
identity. Do not change the external recovery source: it must remain
`product-db-backup-store` / `product-db-cluster`.

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

## Owner-approved rebuild procedure

This procedure is intentionally manual: a rebuild destroys the current DR
Kubernetes cluster and changes the identity of its independent backup chain.
Record the change/incident ID and obtain database-owner approval first.

1. Prove the serving source is healthy and recoverable:

   ```bash
   kubectl -n product get cluster product-db
   kubectl -n product get backup --sort-by=.status.stoppedAt
   kubectl -n product get scheduledbackup product-db-every-6h product-db-daily
   ```

   Stop if `product-db` is degraded, no recent source backup exists, or
   continuous archiving is unhealthy. The replica is not a safe place to repair
   the source from while it is being destroyed.

2. Suspend the leaf reconciliation wave so Flux cannot recreate the old
   identity between steps:

   ```bash
   flux suspend kustomization databases-cnpg-dr-local -n flux-system
   ```

3. In a focused GitOps change, replace only this value in
   `clusters/product-db-replica/instance.yaml`:

   ```yaml
   spec:
     plugins:
       - name: barman-cloud.cloudnative-pg.io
         parameters:
           barmanObjectName: product-db-replica-backup-store
           serverName: product-db-replica-cluster-rYYYYMMDDNN
   ```

   Use a never-reused generation such as `r2026091401`. Leave the
   `externalClusters[].plugin.parameters.serverName: product-db-cluster` source
   unchanged. Run `make validate`, merge the change, and confirm Flux has fetched
   that revision while the Kustomization remains suspended.

4. If the old Cluster still exists, capture its status, then remove only the DR
   Cluster after approval:

   ```bash
   kubectl -n product get cluster product-db-replica -o yaml \
     > /tmp/product-db-replica-before-rebuild.yaml
   kubectl -n product delete cluster product-db-replica
   ```

   Keep the evidence file outside Git if it contains runtime metadata. Never
   delete `product-db`, either ObjectStore, or an object-store prefix in this
   step.

5. Resume and reconcile the DR wave:

   ```bash
   flux resume kustomization databases-cnpg-dr-local -n flux-system
   flux reconcile kustomization databases-cnpg-dr-local -n flux-system --with-source
   ```

6. Wait for three healthy instances and verify recovery before closing the
   change:

   ```bash
   kubectl -n product wait --for=condition=Ready \
     cluster/product-db-replica --timeout=20m
   kubectl cnpg status product-db-replica -n product
   flux get kustomization databases-cnpg-dr-local -n flux-system
   ```

   Confirm the designated primary is still in recovery, the two cascading
   replicas are healthy, the replay timestamp advances, and the new daily backup
   can write under the rotated identity.

The old generation becomes an intentional orphan. Inventory and remove it only
through a separate object-store cleanup change after its recovery window and
evidence-retention requirements expire. Prefix deletion is not part of this
rebuild runbook because a typo can erase the primary recovery source.

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
_Last updated: 2026-09-14 — documented the owner-approved Barman `serverName`
rotation required before a DR re-clone and corrected the stale WAL-only claim._
