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

## Rule out a switchover first

**A planned promotion always fires this alert.** The newly promoted primary fails
to archive its timeline history file exactly once, and because the expression is
`increase(…[30m]) > 0`, that single artefact holds a **critical** alert for half
an hour on a cluster whose archiving is fine.

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-<primary>" -c postgres -- psql -U postgres -tAc \
  "select archived_count, failed_count, last_failed_wal, last_failed_time from pg_stat_archiver;"
kubectl get cluster "$CLUSTER" -n "$NAMESPACE" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}'
```

It is the benign case when **all** of these hold:

- `last_failed_wal` ends in `.history` (e.g. `00000002.history`), not a WAL segment;
- `last_failed_time` sits inside a promotion window;
- `archived_count` is still advancing;
- the cluster's `ContinuousArchiving` condition is `True`.

Measured on 2026-08-06 during
[drill DR-2026-08-B](../../../proposals/rfc/RFC-0021/gameday.md#g3--cnpg-switchover-under-load):
`failed_count = 1`, `last_failed_wal = 00000002.history`, 9 s after the promote,
with `ContinuousArchiving: True` and `LastBackupSucceeded: True` throughout.
Real archive breakage looks different — `failed_count` keeps climbing and
`last_failed_wal` names a segment.

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
