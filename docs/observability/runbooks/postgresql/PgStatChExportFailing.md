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
**10 minutes** on a cluster: the pg_stat_ch background worker failed to
export. The extension never back-pressures PostgreSQL, by design. What the
failure costs depends on its kind (see the `last_error_text` table):

- **Cannot connect** (`Failed to connect to exporter backend`): events wait
  in the ring and drain when ClickHouse returns. Loss starts only when the
  ring is full, which `PgStatChDroppingEvents` reports — on Kind after
  7–15 minutes.
- **Connected but rejected** (privileges, schema, codec): each failed batch
  is lost on the spot and is **not** counted in `dropped_events`. Size it with
  `enqueued_events − exported_events − queue_size` (a dropped event never entered the ring, so it is not in `enqueued_events`).

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
`product-db`, `user` on `platform-db`). Every instance exports on its own, so
check the one the alert's `pod` label names; the primary is the usual one:

```bash
POD=$(kubectl get pod -n "$NAMESPACE" -l "cnpg.io/cluster=$CLUSTER,cnpg.io/instanceRole=primary" -o name)
kubectl exec -n "$NAMESPACE" "$POD" -c postgres -- \
  psql -d "$DB" -c "SELECT send_failures, last_success_ts, last_error_ts, last_error_text FROM pg_stat_ch_stats();"
```

`last_error_text` is never cleared. It describes the current failure only when
`last_error_ts` is newer than `last_success_ts`; otherwise it is history. The
extension does not log export failures, so `kubectl logs` shows nothing.

| `last_error_text` says | Cause |
|---|---|
| authentication / `Code: 516` | the `pg_stat_ch` ClickHouse user or its password: compare the `clickhouse-pg-stat-ch` Secret in `monitoring` (CHI user) with the one in `flux-system` (Flux-substituted Cluster parameter) — both come from one OpenBAO path, so a drift means ESO has not refreshed one of them yet |
| `Code: 81` unknown database / `Code: 60` unknown table | the `clickhouse-schema` Job has not created `pg_stat_ch` — check it is green on the current DDL image digest |
| `Code: 497` / not enough privileges | the CHI `pg_stat_ch/grants/query` block was changed; it needs `GRANT INSERT ON pg_stat_ch.*` |
| `Code: 16` / `No such column` | the DDL image and the extension version disagree on `events_raw`'s columns — a schema change that was not column-for-column compatible |
| `ZSTD frame received but no codec configured` | the server answered with ZSTD, the ClickHouse 26 default; the extension decodes LZ4 only. The CHI `pg_stat_ch` profile must keep `network_compression_method: LZ4` and the user must point at it (`pg_stat_ch/profile: pg_stat_ch`) |
| `Not enough privileges … while pushing to view pg_stat_ch.…_mv` | a rollup view lost `SQL SECURITY DEFINER` (DDL image older than 1.2.1, or a view recreated by hand), so ClickHouse checks `SELECT` on `events_raw` against the INSERT-only writer. Fix the view, never grant the writer `SELECT` |
| `Failed to connect to exporter backend` / timeout | ClickHouse down or rolling; `ClickHouseServerDown` co-fires |

### ClickHouse side

```bash
PW=$(kubectl -n monitoring get secret clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl -n monitoring exec chi-clickhouse-otel-0-0-0 -c clickhouse -- clickhouse-client --password "$PW" -q \
  "SELECT event_time, type, exception_code, exception FROM system.query_log WHERE user='pg_stat_ch' AND exception_code != 0 ORDER BY event_time DESC LIMIT 5"
```

Filter on `exception_code`, not on `type`: privilege failures while pushing to
a view and broken connections are logged as `ExceptionWhileProcessing`.

A view's definer is visible in its DDL; all three must say `SQL SECURITY
DEFINER`:

```bash
kubectl -n monitoring exec chi-clickhouse-otel-0-0-0 -c clickhouse -- clickhouse-client --password "$PW" -q \
  "SELECT name, extract(create_table_query, 'SQL SECURITY [A-Z]+') FROM system.tables WHERE database='pg_stat_ch' AND engine='MaterializedView'"
```

## Mitigation

1. Fix the cause the error text names (schema, view definer, codec, grant,
   ClickHouse availability). None of these needs a PostgreSQL restart: the
   worker reconnects on the next flush, and `SELECT pg_stat_ch_flush();` starts
   one now. A view created before DDL 1.2.1 is fixed in place with
   `ALTER TABLE pg_stat_ch.<view> MODIFY DEFINER = default SQL SECURITY DEFINER`
   on one replica (the Replicated database propagates it).
2. Credential drift: `kubectl -n flux-system annotate externalsecret
   clickhouse-pg-stat-ch force-sync=$(date +%s) --overwrite` (and the same in
   `monitoring`), then `flux reconcile kustomization databases-local`. The
   password is a postmaster parameter, so the new value takes effect only after
   CNPG's rolling restart of the cluster.
3. Confirm recovery: `send_failures` stops increasing and
   `cnpg_pg_stat_ch_last_success_age_seconds` drops below the flush interval.
4. Events still in the ring arrive late with their original timestamps;
   rejected batches and dropped events cannot be recovered. Note the window on
   the incident if percentiles from that period are quoted.

## Escalation

Ticket. Escalate only if it co-fires with `ClickHouseServerDown` or the
`clickhouse-schema` Job is red, which are platform incidents in their own right.
