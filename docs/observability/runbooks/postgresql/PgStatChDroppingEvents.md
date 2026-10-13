# PgStatChDroppingEvents

| | |
|---|---|
| **Severity** | warning |
| **Source** | homelab-authored (`pg-stat-ch-alerts.yaml`) |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_ch` (`dropped_events`, `queue_usage_pct`, `dsa_oom_count`) |
| **Grafana** | postgresql-query-telemetry → *Exporter health* |

## Meaning

Fires when `increase(cnpg_pg_stat_ch_dropped_events[10m]) > 0` holds for
**10 minutes**: backends found the shared-memory ring full and dropped their
events on the spot (an atomic counter bump, no lock, no wait). The ring holds
`pg_stat_ch.queue_capacity` events — **8192** on both clusters — and is drained
every `flush_interval_ms` (1000 ms) in batches of up to `batch_max` (8192).

## Impact

The statements that were dropped are invisible in ClickHouse, so percentiles
and counts for the window under-report — and they under-report the **busiest**
moments, which is exactly when the ring fills. PostgreSQL is unaffected.

## Diagnosis

Two different situations fill the ring; tell them apart first.

### 1. ClickHouse is not draining (secondary symptom)

```promql
sum by (cnpg_io_cluster) (increase(cnpg_pg_stat_ch_send_failures[10m]))
max by (cnpg_io_cluster) (cnpg_pg_stat_ch_last_success_age_seconds)
```

If failures are rising or the last success is old, this alert is the
consequence — go to
[PgStatChExportFailing](PgStatChExportFailing.md) or
[PgStatChNotExporting](PgStatChNotExporting.md). Do not resize the ring to
mask an export problem.

### 2. Sustained throughput above the ring (true overflow)

```promql
# events/s captured vs the ring's 1-second budget (8192)
sum by (cnpg_io_cluster) (rate(cnpg_pg_stat_ch_enqueued_events[5m]))
max by (cnpg_io_cluster, pod) (cnpg_pg_stat_ch_queue_usage_pct)
```

Over ~8000 statements/s per instance the ring cannot absorb a one-second
flush gap. Confirm with the dashboard's *Statements/s by application* panel:
a load test, a runaway loop or a chatty new service is usually the source.

### kubectl / psql

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-1" -c postgres -- \
  psql -d "$DB" -c "SELECT * FROM pg_stat_ch_stats();"
```

`dsa_oom_count > 0` is a sibling symptom: query texts were lost (events kept)
because the 16 MiB `string_area_size` filled — same cause, same fix.

## Mitigation

1. If the cause is a workload spike, nothing to change: the counters stop
   once it passes, and the dashboard's exporter-health row marks the window.
2. For a lasting throughput increase, either sample — `pg_stat_ch.min_duration_us`
   with `pg_stat_ch.sample_rate` keeps every slow statement and a fraction of
   the fast ones, reload-only — or raise `queue_capacity` (power of two;
   16384 ≈ 8 MiB of shared memory) and `string_area_size`, which need a
   PostgreSQL restart through the CNPG rollout. Both are `Cluster` parameters
   in `instance.yaml`; the pods have a 1 Gi memory limit, so size with the
   memory comment there in view.
3. `flush_interval_ms` can drop to 500 ms (reload) before touching memory.

## Escalation

Ticket. The dropped window is gone; the only urgent case is when the same
spike also fires a latency or connection alert, which is then the incident.
