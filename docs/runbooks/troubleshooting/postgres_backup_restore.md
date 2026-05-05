# PostgreSQL Backup and Restore Runbook

This runbook covers backup and restore procedures for the current PostgreSQL
clusters using RustFS (S3-compatible) object storage.

Reference docs:

- [Database DRP](../../databases/010-drp.md)
- [Backup Strategy](../../databases/006-backup-strategy.md)
- [Database Integration](../../databases/002-database-integration.md)

## Overview

| Cluster | Operator | Backup method | Restore method |
|---------|----------|---------------|----------------|
| `cnpg-db` | CloudNativePG | Barman object store + `Backup` / `ScheduledBackup` | Bootstrap recovery from `s3://pg-backups-cnpg/cnpg-db/` |
| `cnpg-db-replica` | CloudNativePG | Barman object store for its own DR prefix | Replica cluster or restore from object store |
| `auth-db` | Zalando | WAL-G via Spilo/operator env | Clone/restore from WAL-G object-store backup |
| `supporting-shared-db` | Zalando | WAL-G via Spilo/operator env | Clone/restore from WAL-G object-store backup |

## CloudNativePG: `cnpg-db`

### Prerequisites

- RustFS is running in namespace `rustfs`.
- Bucket `pg-backups-cnpg` exists.
- Secret `pg-backup-rustfs-credentials` exists in namespace `product`.
- `cnpg-db` has at least one completed base backup.
- `cnpg-db` reports `ContinuousArchiving=True`.

### Check backup health

```bash
kubectl get cluster,backup,scheduledbackup -n product
kubectl get cluster cnpg-db -n product -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason}{"\n"}{end}'
```

Expected:

- `Backup` resources show `completed`.
- `ScheduledBackup` resources have recent `LAST BACKUP`.
- `ContinuousArchiving=True`.
- `LastBackupSucceeded=True`.

### Trigger manual backup

If the CNPG kubectl plugin is installed:

```bash
kubectl cnpg backup cnpg-db -n product
```

Plain Kubernetes fallback:

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: cnpg-db-manual-$(date +%Y%m%d-%H%M)
  namespace: product
spec:
  cluster:
    name: cnpg-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
```

### Restore to a new cluster

Use the checked-in restore example as the starting point:

```bash
kubectl apply -f kubernetes/infra/configs/databases/clusters/cnpg-db/restore-cluster-example.yaml
kubectl get cluster -n product -w
```

The example restores from:

```yaml
externalClusters:
  - name: cnpg-db-backup
    plugin:
      name: barman-cloud.cloudnative-pg.io
      parameters:
        barmanObjectName: cnpg-db-backup-store
        serverName: cnpg-db-cluster
```

### Point-in-time recovery

To restore before a bad data change, add a recovery target to the restore
cluster manifest:

```yaml
bootstrap:
  recovery:
    source: cnpg-db-backup
    recoveryTarget:
      targetTime: "2026-05-05 03:00:00+00"
```

Use a timestamp just before the incident. After restore, validate schema, row
counts, and application smoke tests before routing traffic or extracting data.

### Validate CNPG restore

```bash
kubectl exec -it cnpg-db-restore-1 -n product -- psql -U product -d product -c "\dt"
kubectl exec -it cnpg-db-restore-1 -n product -- psql -U product -d product -c "SELECT count(*) FROM products;"
```

## CloudNativePG: `cnpg-db-replica`

`cnpg-db-replica` is a DR replica cluster that follows the `cnpg-db` backup/WAL
archive path. It is not part of the normal app write path.

Check status:

```bash
kubectl get cluster cnpg-db-replica -n product -o wide
kubectl get pods -n product -l cnpg.io/cluster=cnpg-db-replica
```

Before promotion:

- Confirm the original primary cluster is down or intentionally frozen.
- Confirm split-brain risk is controlled.
- Confirm the replay point is acceptable for the incident RPO.
- Get incident commander approval.

Promotion and cutover details live in [010-drp.md](../../databases/010-drp.md).

## Zalando: `auth-db` and `supporting-shared-db`

### WAL-G backup configuration

Zalando clusters use WAL-G through Spilo. Configuration is injected through:

- Operator config / pod environment ConfigMap.
- Namespace-local `pg-backup-rustfs-credentials` Secret.
- Cluster-specific `WALG_S3_PREFIX` values in the PostgreSQL manifest.

Current paths:

| Cluster | Path |
|---------|------|
| `auth-db` | `s3://pg-backups-zalando/auth-db/` |
| `supporting-shared-db` | `s3://pg-backups-zalando/user-db/` |

### Restore a Zalando cluster

1. Get source cluster UID:

```bash
kubectl get postgresql supporting-shared-db -n user -o jsonpath='{.metadata.uid}'
```

2. Create a clone cluster manifest:

```yaml
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  name: supporting-shared-db-restore
  namespace: user
spec:
  teamId: "platform"
  numberOfInstances: 1
  clone:
    cluster: supporting-shared-db
    uid: "<source-cluster-uid>"
    s3_endpoint: "http://rustfs-svc.rustfs.svc.cluster.local:9000"
    s3_force_path_style: true
  volume:
    size: 5Gi
  databases:
    user: user
    notification: notification.notification
    shipping: shipping.shipping
    review: review.review
  users:
    user: [createdb]
    notification.notification: [createdb]
    shipping.shipping: [createdb]
    review.review: [createdb]
  postgresql:
    version: "16"
```

3. Apply and verify:

```bash
kubectl apply -f supporting-shared-db-restore.yaml
kubectl get postgresql -n user -w
kubectl exec -it supporting-shared-db-restore-0 -n user -- psql -U user -d user -c "\l"
```

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
