# PgStatChNotExporting

| | |
|---|---|
| **Severity** | warning |
| **Source** | homelab-authored (`pg-stat-ch-alerts.yaml`) |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_ch` (`enqueued_events`, `exported_events`, `queue_usage_pct`) |
| **Grafana** | postgresql-query-telemetry → *Exporter health* |

## Meaning

Fires when, for **15 minutes**, a cluster enqueued query events
(`increase(cnpg_pg_stat_ch_enqueued_events[15m]) > 0`) but exported none
(`increase(cnpg_pg_stat_ch_exported_events[15m]) == 0`). Unlike
[PgStatChExportFailing](PgStatChExportFailing.md) there is no failure being
counted either: the background worker is not running, or it never completes a
flush (the native-protocol socket has a 30 s timeout, so a black-holed
ClickHouse address stalls every cycle without an error).

## Impact

No query telemetry reaches ClickHouse for the cluster. The ring fills within
seconds at normal load and [PgStatChDroppingEvents](PgStatChDroppingEvents.md)
follows. PostgreSQL is unaffected.

## Diagnosis

### kubectl — is the worker alive?

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-1" -c postgres -- \
  psql -c "SELECT pid, backend_type, state, wait_event FROM pg_stat_activity WHERE backend_type LIKE '%pg_stat_ch%';"
kubectl logs -n "$NAMESPACE" "${CLUSTER}-1" -c postgres | grep -i pg_stat_ch | tail -20
```

No row: the worker did not start. The log says why — the usual cause is a
restart where `pg_stat_ch` was removed from `shared_preload_libraries` (then
nothing enqueues either and this alert cannot fire) or a crash loop of the
worker, which PostgreSQL logs with its exit status and restarts after 5 s.

### kubectl — can it reach ClickHouse?

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-1" -c postgres -- \
  sh -c 'timeout 5 bash -c "</dev/tcp/clickhouse-clickhouse.monitoring.svc.cluster.local/9000" && echo open || echo closed'
```

`closed` with ClickHouse pods Ready means a network path problem: on an
enforcing CNI a NetworkPolicy on `monitoring` would have to admit `product`
and `platform`; on Kind (kindnet) there is no egress policy today.

### PromQL

```promql
max by (cnpg_io_cluster, pod) (cnpg_pg_stat_ch_queue_usage_pct)
max by (cnpg_io_cluster) (cnpg_pg_stat_ch_last_success_age_seconds)
```

## Mitigation

1. Network path: fix the policy or the Service; the worker's next flush
   succeeds by itself.
2. Worker crash loop: the PostgreSQL log carries the message. Disable
   collection without a restart while investigating —
   `ALTER SYSTEM` is off on CNPG, so set `pg_stat_ch.enabled: "off"` in
   `instance.yaml` (reload-only) and reconcile.
3. Confirm recovery: `exported_events` increases, `queue_usage_pct` falls to ~0.

## Escalation

Ticket, unless ClickHouse itself is unreachable for every client — then it is
the `ClickHouseServerDown` incident.
