# CNPGWALArchiveFailing

| | |
|---|---|
| **Severity** | critical |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | — (built-in `cnpg_pg_stat_archiver_*`) |
| **Grafana** | CloudNativePG Cluster Overview |

## Meaning

`increase(cnpg_pg_stat_archiver_failed_count[30m]) > 0` for **5 minutes** —
`archive_command` (Barman/cloud plugin) failed at least once recently.

## Impact

WAL segments accumulate in `pg_wal`; PITR and base backups become unreliable.
`PostgresBackupTooOld` may still look healthy while archiving is broken — this
alert closes that gap.

## Diagnosis

### PromQL

```promql
increase(cnpg_pg_stat_archiver_failed_count[30m])
cnpg_collector_pg_wal_archive_status{status="ready"}
```

### kubectl

```bash
kubectl get cluster,backup,scheduledbackup -n "$NAMESPACE"
kubectl logs -n "$NAMESPACE" "${CLUSTER}-1" -c postgres --tail=100 | grep -i archive
kubectl get objectstore -n "$NAMESPACE"
```

See [postgres-backup-restore.md](../../../databases/runbooks/postgres-backup-restore.md)
for Barman/RustFS connectivity checks.

## Mitigation

1. Verify object store (RustFS) reachable from cluster namespace.
2. Check Barman plugin / CNPG backup credentials (ESO secrets).
3. Retry failed backup job; confirm `last_archived_wal` advances in logs.
4. Monitor [PostgresWALSizeHigh.md](PostgresWALSizeHigh.md) while fixing archive.

## Escalation

**P1** — page if archiving fails >1h or WAL directory grows rapidly. PITR window
at risk.
