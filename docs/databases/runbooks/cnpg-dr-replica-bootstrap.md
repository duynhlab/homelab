# Runbook: CNPG DR Replica (`cnpg-db-replica`) Bootstrap and Recovery

## Prerequisites

1. **Base backup in object store** — `cnpg-db-replica` bootstraps with `bootstrap.recovery` from Barman data at `s3://pg-backups-cnpg/cnpg-db/` (`serverName: cnpg-db-cluster`). At least one **completed** `Backup` for `cnpg-db` must exist before full-recovery can succeed.
2. **Backup credentials** — The `pg-backup-rustfs-credentials` Secret (managed by ClusterExternalSecret via ESO) must exist in the `product` namespace. ESO needs time to sync after `ClusterExternalSecret` is applied.
3. **GitOps order** — Flux `databases-cnpg-dr-local` has `dependsOn: [databases-local, secrets-local]` so primary cluster, ESO secrets, and backup schedules apply before the DR `Cluster`.
4. **Recovery-critical GUCs** — The replica `postgresql.parameters` must match or exceed the primary's `pg_controldata` values for `max_connections`, `max_worker_processes`, `max_wal_senders`, `max_prepared_xacts`, and `max_locks_per_xact`. Mismatches cause `FATAL: recovery aborted because of insufficient parameter settings`.
5. **WAL parameters** — Restored data keeps primary `wal_segment_size` (64MB). The DR `Cluster` must set `postgresql.parameters.min_wal_size` (and related WAL settings) so `min_wal_size >= 2 * wal_segment_size`; otherwise PostgreSQL exits with:
   `FATAL: "min_wal_size" must be at least twice "wal_segment_size"`.

## Verify backups

```bash
kubectl get backup,scheduledbackup -n product
kubectl get backup cnpg-db-initial -n product -o wide   # if using on-demand Backup CR
```

Wait for at least one backup with `PHASE=completed` for cluster `cnpg-db`.

```bash
kubectl get backup cnpg-db-initial -n product -o jsonpath='{.status.phase}{"\n"}'
# Expect: completed
```

## If `full-recovery` job shows Error

Check the job pod logs first — the root cause determines the fix:

```bash
kubectl logs -n product $(kubectl get pods -n product -l job-name -o name | grep full-recovery | tail -1) --tail=30
```

### Cause A: `secret "pg-backup-rustfs-credentials" not found`

The ESO-managed backup credential has not been materialized yet when the full-recovery job started. This is a race condition between `ClusterExternalSecret` sync and the DR cluster bootstrap.

**Why it happens:** `databases-cnpg-dr-local` depends on `databases-local` and `secrets-local`, but ESO needs time after its `ClusterExternalSecret` is applied to create the `ExternalSecret` and sync the actual `Secret` into the `product` namespace. If the DR cluster reconciles before the Secret is ready, every full-recovery attempt fails.

**Verify:**

```bash
kubectl get secret pg-backup-rustfs-credentials -n product
kubectl get externalsecret -n product
```

**Remediation (once the Secret exists):**

```bash
kubectl delete cluster cnpg-db-replica -n product
flux reconcile kustomization databases-cnpg-dr-local --with-source
```

CNPG will recreate the cluster and the full-recovery job will succeed with the Secret now in place.

### Cause B: No base backup completed yet

Recovery started before any base backup finished (race on first install).

**Verify:**

```bash
kubectl get backup -n product
# All PHASE should be "completed" for cnpg-db
```

**Remediation:**

1. Confirm a completed backup exists (see above).
2. Delete the DR cluster and let GitOps recreate it:

```bash
kubectl delete cluster cnpg-db-replica -n product
flux reconcile kustomization databases-cnpg-dr-local --with-source
```

## If pod `cnpg-db-replica-1` is CrashLoopBackOff after recovery

1. **Check postgres logs:**

```bash
kubectl logs -n product cnpg-db-replica-1 -c postgres --tail=80
```

2. **`min_wal_size` / `wal_segment_size` mismatch** — If you see:

   ```
   FATAL: "min_wal_size" must be at least twice "wal_segment_size"
   ```

   Restored data keeps primary `wal_segment_size` (64MB). Ensure `postgresql.parameters.min_wal_size` >= 128MB (we use `2GB` to match primary).

3. **Recovery-critical parameter mismatch** — If you see:

   ```
   FATAL: recovery aborted because of insufficient parameter settings
   ```
   ```
   DETAIL: max_connections = 100 is a lower setting than on the primary server, where its value was 200.
   ```

   PostgreSQL requires these replica GUCs to be **>= the primary values recorded in `pg_controldata`**:

   | Parameter | Primary value | Must match/exceed |
   |---|---|---|
   | `max_connections` | `200` | Yes |
   | `max_worker_processes` | `8` | Yes (default=8, OK) |
   | `max_wal_senders` | `10` | Yes (default=10, OK) |
   | `max_prepared_xacts` | `0` | Yes (default=0, OK) |
   | `max_locks_per_xact` | `64` | Yes (default=64, OK) |

   Add missing parameters to the replica `instance.yaml` and re-bootstrap.

4. After fixing the manifest, delete the DR cluster and re-bootstrap:

```bash
kubectl delete cluster cnpg-db-replica -n product
# push manifest: make flux-push
flux reconcile kustomization databases-cnpg-dr-local --with-source
```

## References

- [005-ha-dr-deep-dive.md](../005-ha-dr-deep-dive.md)
- [CloudNativePG replica cluster](https://cloudnative-pg.io/documentation/latest/replica_cluster/)
