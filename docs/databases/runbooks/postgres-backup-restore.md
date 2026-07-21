# PostgreSQL Backup and Restore Runbook

This runbook covers backup and restore procedures for the current PostgreSQL
clusters using RustFS (S3-compatible) object storage.

Reference docs:

- [Database DRP](../010-drp.md)
- [Backup Strategy](../006-backup-strategy.md)
- [Database Integration](../002-database-integration.md)

## Overview

| Cluster | Operator | Backup method | Restore method |
|---------|----------|---------------|----------------|
| `platform-db` | CloudNativePG | Barman object store + `Backup` / `ScheduledBackup` | Bootstrap recovery from `s3://pg-backups-cnpg/platform-db/` |
| `product-db` | CloudNativePG | Barman object store + `Backup` / `ScheduledBackup` | Bootstrap recovery from `s3://pg-backups-cnpg/product-db/` |
| `product-db-replica` | CloudNativePG | Barman object store for its own DR prefix | Replica cluster or restore from object store |

## CloudNativePG: `platform-db`

### Prerequisites

- RustFS is running in namespace `rustfs`.
- Bucket `pg-backups-cnpg` exists.
- Secret `pg-backup-rustfs-credentials` exists in namespace `platform`.
- `platform-db` has at least one completed base backup.
- `platform-db` reports `ContinuousArchiving=True`.

### Check backup health

```bash
kubectl get cluster,backup,scheduledbackup -n platform
kubectl get cluster platform-db -n platform -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}'
```

Expected:

- `Backup` resources show `completed`.
- `ScheduledBackup` resources have recent `LAST BACKUP`.
- `ContinuousArchiving=True`.
- `LastBackupSucceeded=True`.

### Trigger manual backup

If the CNPG kubectl plugin is installed:

```bash
kubectl cnpg backup platform-db -n platform
```

Plain Kubernetes fallback:

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: platform-db-manual-$(date +%Y%m%d-%H%M)
  namespace: platform
spec:
  cluster:
    name: platform-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
```

### Restore to a new cluster

Use a restore manifest patterned on
`kubernetes/infra/configs/databases/clusters/platform-db/instance.yaml` with
`bootstrap.recovery` pointing at the Barman object store:

```yaml
externalClusters:
  - name: platform-db-backup
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: platform-db-backup-store
        serverName: platform-db-cluster
```

### Point-in-time recovery

Add a recovery target to the restore cluster manifest:

```yaml
bootstrap:
  recovery:
    source: platform-db-backup
    recoveryTarget:
      targetTime: "2026-05-05 03:00:00+00"
```

Use a timestamp just before the incident. After restore, validate schema, row
counts, and application smoke tests before routing traffic or extracting data.

### Validate CNPG restore

```bash
kubectl exec -it platform-db-restore-1 -n platform -- psql -U auth -d auth -c "\dt"
kubectl exec -it platform-db-restore-1 -n platform -- psql -U user -d user -c "SELECT count(*) FROM users;"
```

## CloudNativePG: `product-db`

### Prerequisites

- RustFS is running in namespace `rustfs`.
- Bucket `pg-backups-cnpg` exists.
- Secret `pg-backup-rustfs-credentials` exists in namespace `product`.
- `product-db` has at least one completed base backup.
- `product-db` reports `ContinuousArchiving=True`.

### Check backup health

```bash
kubectl get cluster,backup,scheduledbackup -n product
kubectl get cluster product-db -n product -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}'
```

Expected:

- `Backup` resources show `completed`.
- `ScheduledBackup` resources have recent `LAST BACKUP`.
- `ContinuousArchiving=True`.
- `LastBackupSucceeded=True`.

### Trigger manual backup

If the CNPG kubectl plugin is installed:

```bash
kubectl cnpg backup product-db -n product
```

Plain Kubernetes fallback:

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: product-db-manual-$(date +%Y%m%d-%H%M)
  namespace: product
spec:
  cluster:
    name: product-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
```

### Restore to a new cluster

Use the checked-in restore example as the starting point:

```bash
kubectl apply -f kubernetes/infra/configs/databases/clusters/product-db/restore-cluster-example.yaml
kubectl get cluster -n product -w
```

The example restores from:

```yaml
externalClusters:
  - name: product-db-backup
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: product-db-backup-store
        serverName: product-db-cluster
```

### Point-in-time recovery

To restore before a bad data change, add a recovery target to the restore
cluster manifest:

```yaml
bootstrap:
  recovery:
    source: product-db-backup
    recoveryTarget:
      targetTime: "2026-05-05 03:00:00+00"
```

Use a timestamp just before the incident. After restore, validate schema, row
counts, and application smoke tests before routing traffic or extracting data.

### Validate CNPG restore

```bash
kubectl exec -it product-db-restore-1 -n product -- psql -U product -d product -c "\dt"
kubectl exec -it product-db-restore-1 -n product -- psql -U product -d product -c "SELECT count(*) FROM products;"
```

## CloudNativePG: `product-db-replica`

`product-db-replica` is a DR replica cluster that follows the `product-db` backup/WAL
archive path. It is not part of the normal app write path.

Check status:

```bash
kubectl get cluster product-db-replica -n product -o wide
kubectl get pods -n product -l cnpg.io/cluster=product-db-replica
```

Before promotion:

- Confirm the original primary cluster is down or intentionally frozen.
- Confirm split-brain risk is controlled.
- Confirm the replay point is acceptable for the incident RPO.
- Get incident commander approval.

Promotion and cutover details live in [010-drp.md](../010-drp.md).

## Validation Checklist

- [ ] Backup or restore resource reached successful state.
- [ ] WAL archive health was checked.
- [ ] Restored cluster reached healthy state.
- [ ] Schema list matches expected databases.
- [ ] Row counts for critical tables match the expected restore target.
- [ ] Application smoke test passed.
- [ ] Credentials and pooler/direct endpoints are correct.
- [ ] RTO/RPO evidence was recorded.

## Common Issues

| Issue | Resolution |
|-------|------------|
| `Expected empty archive` | Use `cnpg.io/skipEmptyWalArchiveCheck: "enabled"` only when restoring to a new archive path and after understanding archive collision risk |
| Bucket not found | Verify the RustFS bucket setup job and RustFS service |
| No backups listed | Check `Backup`, `ScheduledBackup`, cluster backup config, and object-store credentials |
| Restore starts but never becomes healthy | Check recovery job logs, WAL availability, PostgreSQL image version, and recovery-critical GUC parity |
| Application cannot connect after restore | Verify service DNS, pooler config, database owner secrets, and `sslmode` requirements |

## Evidence to Capture

For every restore drill or incident recovery, capture:

- Backup ID and completion timestamp.
- Recovery target timestamp or LSN.
- Restore start/end timestamps.
- Cluster status output.
- Row-count/schema validation output.
- Application smoke test result.
- Final measured RTO and estimated RPO.

---
_Last updated: 2026-07-21 — Moved from `docs/runbooks/troubleshooting/` to domain runbooks._
