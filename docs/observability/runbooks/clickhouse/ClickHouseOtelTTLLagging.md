# ClickHouseOtelTTLLagging

Retention can stop while inserts and queries remain healthy; this alert makes
the 90-day OTel TTL an observable lifecycle invariant.

| Quick facts | |
|---|---|
| **Severity** | warning |
| **Metric** | `chi_clickhouse_table_partitions{database="otel",active="1"}` |
| **Threshold** | more than 93 active daily partitions for 6 hours |
| **Tables** | `otel_logs`, `otel_traces`, `otel_traces_trace_id_ts` |
| **Source** | `prometheusrules/observability/clickhouse-alerts.yaml` |
| **Local-stack** | not present — no Altinity table exporter |

## Meaning and impact

One OTel table retains more daily partitions than its 90-day DELETE TTL allows
after boundary and merge-scheduling headroom. Ingestion may remain healthy while
hot and cold storage grows without bound. The rule filters `active="1"` and
takes the maximum across replicas; inactive historical parts must not be added.

## Diagnosis

```promql
max by (database, table) (
  chi_clickhouse_table_partitions{
    database="otel",
    table=~"otel_logs|otel_traces|otel_traces_trace_id_ts",
    active="1"
  }
)
```

Authenticate interactively so the password is not exposed in shell history:

```bash
POD="<clickhouse-replica-pod>"
kubectl -n monitoring exec -it "$POD" -- clickhouse-client --ask-password
```

```sql
SELECT table, min(partition) AS oldest_partition,
       max(partition) AS newest_partition,
       uniqExact(partition) AS active_partitions,
       count() AS active_parts,
       formatReadableSize(sum(bytes_on_disk)) AS bytes
FROM system.parts
WHERE database = 'otel' AND active
GROUP BY table ORDER BY table;

SELECT event_time, table, partition_id, error, exception
FROM system.part_log
WHERE database = 'otel'
  AND event_time > now() - INTERVAL 24 HOUR
  AND (merge_reason = 'TTLDeleteMerge' OR error != 0)
ORDER BY event_time DESC LIMIT 100;
```

Correlate with `ClickHouseS3Errors`, disk pressure, failed merges, and replica
health. A count over 93 does not identify the failed stage by itself.

## Mitigation

1. Restore Keeper, replica writability, disk headroom, or RustFS access first.
2. Confirm merges are enabled and the background pool is progressing.
3. Let the normal TTL scheduler catch up while tracking the oldest partition.
4. Use `MATERIALIZE TTL` only for one confirmed table in a controlled window;
   it competes with ingestion.
5. Partition deletion is irreversible. Require owner approval and prove the
   entire partition is outside retention before using it.

## Recovery validation

- Oldest active data is inside the 90-day window.
- The full PromQL expression is at or below 93 for every table.
- Replicas agree on partition count and newest timestamp.
- TTL/S3 errors stop increasing and cold data remains queryable.

## Escalation

Include the PromQL result, `system.parts` summary, recent `system.part_log`
errors, disk usage, and co-firing alerts. Escalate before deleting data or when
replicas disagree, RustFS is unavailable, or the oldest partition keeps aging.

## References

- [ClickHouse alert runbooks](README.md)
- [ClickHouse platform guide](../../clickhouse/README.md)

---

_Last updated: 2026-09-14 — added live-signal coverage for stalled OTel TTL
retention using active per-table partition counts._
