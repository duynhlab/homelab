# PostgreSQL Backup and Restore Runbook

This runbook covers backup/restore procedures for the 4 PostgreSQL clusters using RustFS (S3-compatible) as object storage. Reference: [docs/databases/backup.md](../../databases/backup.md).

## Table of Contents

1. [Overview](#overview)
2. [CloudNativePG (product-db, transaction-shared-db)](#cloudnativepg-product-db-transaction-shared-db)
3. [Zalando (auth-db, supporting-shared-db)](#zalando-auth-db-supporting-shared-db)
4. [Verification Checklist](#verification-checklist)

---

## Overview

| Cluster         | Operator      | Backup Method | Restore Method |
|-----------------|---------------|---------------|----------------|
| product-db      | CloudNativePG | barmanObjectStore + ScheduledBackup | Bootstrap recovery from object store |
| transaction-shared-db  | CloudNativePG | barmanObjectStore + ScheduledBackup | Bootstrap recovery from object store |
| auth-db         | Zalando       | WAL-G (operator-level) | Clone from S3 / pg_restore |
| supporting-shared-db   | Zalando       | WAL-G (operator-level) | Clone from S3 / pg_restore |

---

## CloudNativePG (product-db, transaction-shared-db)

### Prerequisites

- RustFS running in `rustfs` namespace
- Buckets `pg-backups-zalando` / `pg-backups-cnpg` created (CronJob `setup-pg-backup-buckets` in rustfs namespace)
- Secret `pg-backup-rustfs-credentials` in cluster namespace
- At least one successful base backup + WAL archiving

### Manual Backup (product-db)

```bash
# Trigger immediate backup
kubectl cnpg backup product-db -n product

# Or create Backup CR
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: product-db-manual-$(date +%Y%m%d-%H%M)
  namespace: product
spec:
  cluster:
    name: product-db
  method: barmanObjectStore
EOF
```

### List Backups

```bash
kubectl cnpg backup list product-db -n product
```

### Restore to New Cluster (product-db)

1. **Create restore cluster manifest** (example: `product-db-restore`):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: product-db-restore
  namespace: product
  annotations:
    # Required: skip WAL archive check when restoring to new cluster name
    cnpg.io/skipEmptyWalArchiveCheck: "enabled"
spec:
  instances: 1  # Start with 1 for restore, scale after
  imageName: ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie
  bootstrap:
    recovery:
      source: product-db-backup
      database: product
      owner: product
      secret:
        name: product-db-secret
  externalClusters:
    - name: product-db-backup
      barmanObjectStore:
        destinationPath: s3://pg-backups-cnpg/product-db/
        endpointURL: http://rustfs-svc.rustfs.svc.cluster.local:9000
        serverName: product-db  # Matches backup path prefix
        s3Credentials:
          accessKeyId:
            name: pg-backup-rustfs-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: pg-backup-rustfs-credentials
            key: ACCESS_SECRET_KEY
        wal:
          maxParallel: 4
  storage:
    size: 10Gi
    storageClass: standard
  resources:
    requests:
      memory: "128Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
```

2. **Apply and wait**:

```bash
kubectl apply -f product-db-restore.yaml
kubectl get cluster -n product -w
# Wait until status: Cluster in healthy state
```

3. **Verify**:

```bash
kubectl exec -it product-db-restore-1 -n product -- psql -U product -d product -c "\dt"
kubectl exec -it product-db-restore-1 -n product -- psql -U product -d product -c "SELECT count(*) FROM products;"
```

### Point-in-Time Recovery (PITR)

To restore to a specific timestamp (e.g., before a DROP TABLE):

1. **Note the incident time** (e.g., `2025-01-28 10:30:00+00`)

2. **Add recoveryTarget to bootstrap.recovery**:

```yaml
bootstrap:
  recovery:
    source: product-db-backup
    recoveryTarget:
      targetTime: "2025-01-28 10:29:00+00"  # Just before incident
    database: product
    owner: product
    secret:
      name: product-db-secret
```

3. **Apply and verify** as in "Restore to New Cluster" above.

### Verification Checklist (CNPG)

- [ ] Backup CR shows `Completed` status
- [ ] WAL files visible in RustFS: `s3://pg-backups-cnpg/product-db/` (via mc or aws cli)
- [ ] Restore cluster reaches `Cluster in healthy state`
- [ ] Schema matches: `\dt` shows expected tables
- [ ] Row counts match (or expected for PITR)
- [ ] Application can connect and query

---

## Zalando (auth-db, supporting-shared-db)

### WAL-G Backup Configuration

Zalando clusters use WAL-G for PITR backup to RustFS. Configuration is operator-level:
- **ConfigMap**: `postgres-operator/zalando-walg-config` (non-sensitive)
- **Secret**: `pg-backup-rustfs-credentials` (per cluster namespace: user, auth, review)
- **Bucket**: `pg-backups-zalando` with cluster-specific paths (spilo/{cluster-name}/...)

### Restore to New Cluster (supporting-shared-db)

1. **Get source cluster UID**:

```bash
kubectl get postgresql supporting-shared-db -n user -o jsonpath='{.metadata.uid}'
```

2. **Create clone cluster** with `clone` section (uses WAL-G env from pod_environment_configmap/secret):

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
    uid: "<paste-source-cluster-uid>"
    s3_endpoint: "http://rustfs-svc.rustfs.svc.cluster.local:9000"
    s3_force_path_style: true
  volume:
    size: 5Gi
  databases:
    user: user
    notification: notification.notification
    shipping: shipping.shipping
  users:
    user: [createdb]
    notification.notification: [createdb]
    shipping.shipping: [createdb]
  postgresql:
    version: "16"
```

3. **Apply and verify**:

```bash
kubectl apply -f supporting-shared-db-restore.yaml
kubectl get postgresql -n user -w
kubectl exec -it supporting-shared-db-restore-0 -n user -- psql -U user -d user -c "\l"
```

### Selective Restore (Logical pg_dump)

For single-DB restore (e.g., only `notification` from supporting-shared-db):

1. **Take logical backup** (manual or enable `enableLogicalBackup` on cluster)
2. **Restore to target**:

```bash
# From backup file in S3
pg_restore -h target-host -U notification -d notification -Fc backup_notification.dump
```

---

## Verification Checklist

### After Restore

1. **Schema**: `\dt` in each database
2. **Row counts**: `SELECT count(*) FROM <main_tables>`
3. **Application smoke test**: curl API endpoints that use the DB
4. **Connection**: Verify pooler/direct connection works
5. **Secrets**: Ensure app secrets (product-db-secret, etc.) exist and match

### Common Issues

| Issue | Resolution |
|-------|------------|
| `Expected empty archive` | Add `cnpg.io/skipEmptyWalArchiveCheck: "enabled"` when restoring to new cluster name |
| Bucket not found | CronJob `setup-pg-backup-buckets` in rustfs namespace creates buckets every 30min; trigger manually if needed |
| S3 connection refused | Verify RustFS service: `kubectl get svc -n rustfs` |
| No backups listed | Ensure WAL archiving is active; check cluster status and backup CRs |

---

## Related Documentation

- [backup.md](../../databases/backup.md) - Strategy, retention, bucket layout
- [database.md](../../databases/database.md) - Cluster architecture
- [RustFS README](../../../kubernetes/infra/controllers/storage/rustfs/README.md) - Object storage setup
