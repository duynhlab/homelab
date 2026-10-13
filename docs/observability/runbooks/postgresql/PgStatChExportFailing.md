# PgStatChExportFailing

| | |
|---|---|
| **Severity** | warning |
| **Source** | homelab-authored (`pg-stat-ch-alerts.yaml`) |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | `pg_stat_ch` (`send_failures`, `last_error_age_seconds`) |
| **Grafana** | postgresql-query-telemetry → *Exporter health* |

## Meaning

Fires when `increase(cnpg_pg_stat_ch_send_failures[10m]) > 0` holds for
**10 minutes** on a cluster: the pg_stat_ch background worker dequeued a batch
of query events, the ClickHouse insert failed, and the batch was discarded.
The extension never retries and never back-pressures PostgreSQL, by design.

## Impact

Query telemetry in ClickHouse `pg_stat_ch.events_raw` has a gap for the
affected cluster; percentiles, top statements and error history for the window
are incomplete or missing. PostgreSQL itself is unaffected — this is an
observability-pipeline alert, not a database alert.

## Diagnosis

### PromQL

```promql
sum by (cnpg_io_cluster, pod) (increase(cnpg_pg_stat_ch_send_failures[10m]))
max by (cnpg_io_cluster) (cnpg_pg_stat_ch_last_error_age_seconds)
```

### kubectl / psql — the error text

`pg_stat_ch_stats()` keeps the last error. Query it on any instance of the
cluster, in the database that owns the extension objects (`product` on
`product-db`, `user` on `platform-db`):

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-1" -c postgres -- \
  psql -d "$DB" -c "SELECT send_failures, last_error_ts, last_error_text FROM pg_stat_ch_stats();"
```

| `last_error_text` says | Cause |
|---|---|
| authentication / `Code: 516` | the `pg_stat_ch` ClickHouse user or its password: compare the `clickhouse-pg-stat-ch` Secret in `monitoring` (CHI user) with the one in `flux-system` (Flux-substituted Cluster parameter) — both come from one OpenBAO path, so a drift means ESO has not refreshed one of them yet |
| `Code: 81` unknown database / `Code: 60` unknown table | the `clickhouse-schema` Job has not created `pg_stat_ch` — check it is green on the current DDL image digest |
| `Code: 497` / not enough privileges | the CHI `pg_stat_ch/grants/query` block was changed; it needs `GRANT INSERT ON pg_stat_ch.*` |
| `Code: 16` / `No such column` | the DDL image and the extension version disagree on `events_raw`'s columns — a schema change that was not column-for-column compatible |
| connection refused / timeout | ClickHouse down or rolling; `ClickHouseServerDown` co-fires |

### ClickHouse side

```bash
PW=$(kubectl -n monitoring get secret clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl -n monitoring exec chi-clickhouse-otel-0-0-0 -c clickhouse -- clickhouse-client --password "$PW" -q \
  "SELECT event_time, user, exception FROM system.query_log WHERE user='pg_stat_ch' AND type='ExceptionBeforeStart' ORDER BY event_time DESC LIMIT 5"
```

## Mitigation

1. Fix the cause the error text names (credential, schema, grant, ClickHouse
   availability). No PostgreSQL restart is needed for any of them: the worker
   reconnects on the next flush.
2. Credential drift: `kubectl -n flux-system annotate externalsecret
   clickhouse-pg-stat-ch force-sync=$(date +%s) --overwrite` (and the same in
   `monitoring`), then `flux reconcile kustomization databases-local`.
3. Confirm recovery: `send_failures` stops increasing and
   `cnpg_pg_stat_ch_last_success_age_seconds` drops below the flush interval.
4. The lost window cannot be recovered; note it on the incident if percentiles
   from that period are quoted.

## Escalation

Ticket. Escalate only if it co-fires with `ClickHouseServerDown` or the
`clickhouse-schema` Job is red, which are platform incidents in their own right.
