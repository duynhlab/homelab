# PostgresWALSizeHigh

| | |
|---|---|
| **Severity** | warning |
| **Source** | homelab-extra |
| **Clusters** | `platform-db`, `product-db` |

## Meaning

WAL directory size (`cnpg_collector_pg_wal`) exceeds **2 GB** for **15 minutes**.

## Impact

Large WAL retention increases disk use and recovery time. Often pairs with
archive failures or heavy write load.

## Diagnosis

```promql
cnpg_collector_pg_wal{value="size", cnpg_io_cluster="$CLUSTER"}
cnpg_collector_pg_wal_archive_status
```

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-1" -c postgres -- du -sh /var/lib/postgresql/data/pgdata/pg_wal
```

Check [CNPGWALArchiveFailing.md](CNPGWALArchiveFailing.md) and
[CNPGCheckpointPressure.md](CNPGCheckpointPressure.md).

## Mitigation

1. Fix archiving if `failed_count` increasing.
2. Tune `max_wal_size` / checkpoint settings.
3. Reduce bulk write burst if application-driven.

## Escalation

Page if WAL grows while archive failing — disk exhaustion path.
