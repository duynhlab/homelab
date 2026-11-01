# ClickHouseSystemTablesLarge

ClickHouse's own log tables (`system.*`) share the replica's data volume with
the `otel` data. One of them without a TTL grows until it competes for that
disk; this alert catches the growth before it reaches the disk alerts.

| Quick facts | |
|---|---|
| **Severity** | warning |
| **Metric** | `chi_clickhouse_table_parts_bytes{database="system",active="1"}`, summed per replica |
| **Threshold** | more than 2 GiB (20 % of the 10Gi data PVC) for 1 hour |
| **Baseline** | about 0.15 GiB per replica on Kind, 2026-10-29 |
| **Source** | `prometheusrules/observability/clickhouse-alerts.yaml` |
| **Local-stack** | not present — no Altinity table exporter |

## Meaning and impact

The 7-day and 30-day TTLs in the CHI file `02-system-log-retention.xml` keep
every declared log table bounded. Crossing 2 GiB usually means one of these:

- a log table that was not created before, now written by a new feature, with
  no TTL upstream (`opentelemetry_span_log` was the last one);
- a `*_N` leftover: when a server upgrade or a config change alters a log
  table's schema, ClickHouse renames the old table to `<name>_0` and never
  drops it. A leftover keeps its old TTL, so it empties out unless the
  original had none;
- a TTL that stopped retiring parts (merges stuck, disk or Keeper trouble).

Nothing breaks at the threshold itself. The risk is the next stage:
`ClickHouseDiskAlmostFull`, then refused inserts.

## Diagnosis

Which tables, on which replica:

```promql
topk(5, sum by (hostname, table) (
  chi_clickhouse_table_parts_bytes{database="system", active="1"}
))
```

Authenticate interactively so the password is not exposed in shell history:

```bash
POD="<clickhouse-replica-pod>"
kubectl -n monitoring exec -it "$POD" -c clickhouse -- clickhouse-client --ask-password
```

Size and retention per table. Read the TTL **number**: a `'TTL'` substring
match is wrong, because a `metric_log` column comment contains the word.

```sql
SELECT table,
       formatReadableSize(sum(bytes_on_disk)) AS size,
       min(partition) AS oldest_partition,
       extractAll(any(t.create_table_query), 'toIntervalDay\\((\\d+)\\)') AS ttl_days
FROM system.parts AS p
INNER JOIN system.tables AS t ON t.database = p.database AND t.name = p.table
WHERE p.database = 'system' AND p.active
GROUP BY table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 10;
```

An empty `ttl_days` is a table without a TTL. A name ending in `_0`, `_1`, …
is an upgrade leftover.

## Mitigation

1. **Table without a TTL.** Add a block for it to `02-system-log-retention.xml`
   in `kubernetes/infra/configs/clickhouse/clickhouseinstallation.yaml`. Use
   the merge form (`partition_by`, `ttl`, `settings`) unless the table needs
   `replace="1"`. Once a replica has loaded the new config (the operator rolls
   the pods) and the table next flushes, the server renames the old table to
   `<name>_0` or the next free `_N` and creates the new one with the TTL. Run
   `SYSTEM FLUSH LOGS` to force it, then check `ttl_days` on every replica.
2. **`*_N` leftovers.** They are never written again. One with a TTL empties
   itself; one without (empty `ttl_days`) stays forever. After confirming that
   nothing reads it, drop it on **each** replica (they are local, not
   replicated):
   `DROP TABLE system.<name>_0 SYNC`. Dropping is irreversible; record the
   table names and sizes first.
3. **TTL present but not retiring.** Treat it as a merge problem: check
   `system.part_log` for failed `TTLDeleteMerge` rows and the disk/Keeper
   alerts, as in [ClickHouseOtelTTLLagging](ClickHouseOtelTTLLagging.md).

## Recovery validation

- The PromQL expression is under 2 GiB on every replica.
- Every large `system.*` table shows a `ttl_days` value.
- No `*_N` table without a TTL remains on any replica.

## Escalation

Include the `topk` result, the `system.parts` table above for the firing
replica, and any co-firing disk or merge alerts. Escalate before dropping a
table that is not an upgrade leftover.

## References

- [ClickHouse alert runbooks](README.md)
- [ClickHouse platform guide — the engine's own log tables](../../clickhouse/README.md#the-engines-own-log-tables)
