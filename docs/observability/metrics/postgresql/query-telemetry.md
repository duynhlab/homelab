# PostgreSQL query telemetry — pg_stat_ch into ClickHouse

`pg_stat_statements` tells you which statement is expensive in total;
`auto_explain` tells you why one slow execution was slow. Neither can say
*when p99 moved from 8 ms to 80 ms, for which application, and whether the
fast executions changed too*. **pg_stat_ch** records one event per statement
execution inside PostgreSQL and ships it to ClickHouse, where the platform
already keeps 90 days of logs and traces. This page is the signal's guide:
what is captured, how it flows, what it costs, and how to operate it.

| Quick facts | |
|---|---|
| Extension | `pg_stat_ch` 0.4.0 (ClickHouse, Apache-2.0), PostgreSQL 16–18 |
| Delivery | CNPG image-volume extension `ghcr.io/duynhlab/images/pg-stat-ch` (`/extensions/pg_stat_ch`), preloaded on `platform-db` and `product-db`; mounted but not preloaded on `product-db-replica` |
| Transport | Native ClickHouse protocol, LZ4, `clickhouse-clickhouse.monitoring.svc:9000`, user `pg_stat_ch` (INSERT-only) |
| Store | ClickHouse database `pg_stat_ch` (DDL image `clickhouse-ddl` ≥ 1.2.0): `events_raw` 7 days hot → RustFS cold, 90 days; rollups `query_stats_5m`, `db_app_user_1m`, `errors_recent` (30 days) |
| Loss model | Ring overflow or a failed insert **drops** events; nothing is retried and PostgreSQL is never slowed |
| Cost on PostgreSQL | ~2 % CPU in the extension; up to ~11 % TPS on a lock-heavy pgbench (upstream, 32 clients); ~4 MiB ring + 16 MiB string area per instance here |
| Health | `cnpg_pg_stat_ch_*` (custom query) → `PgStatChExportFailing`, `PgStatChDroppingEvents`, `PgStatChNotExporting` |
| Dashboard | `postgresql-query-telemetry` (Databases folder) |
| Not covered | plan capture (use auto_explain), statements on the DR replica, local-stack (its Postgres is Alpine/musl; the release binary is glibc) |

## What one event holds

Every statement — DML, DDL, utility, and statements that *failed* — becomes a
fixed set of 44 columns: start time and duration, `db_name`, `db_user`, `app`
(`application_name`), `client_addr`, `pid`, the `query_id` fingerprint that
`pg_stat_statements` and the auto_explain plans stream also carry
(`compute_query_id`), the normalised text (literals → `$N`, cut at 2 KB),
rows, shared/local/temp buffer counters, block read/write wait
(`track_io_timing`), WAL records/FPI/bytes, CPU user/sys from `getrusage`, JIT
timings, parallel workers planned vs launched, and on failure the SQLSTATE,
elevel and message. `db_name` is the cluster key on this platform because
every database name is unique across `platform-db` and `product-db`; the
extension's own instance columns are only filled on its Arrow/OTel path.

## How it flows

```mermaid
flowchart LR
    subgraph cluster["Kind cluster"]
        subgraph pg["CNPG cluster (platform-db, product-db)"]
            hooks["Executor + ProcessUtility<br/>+ emit_log hooks"]
            ring[("Shared-memory ring<br/>8192 slots + 16 MiB strings")]
            worker["pg_stat_ch bgworker<br/>flush every 1 s, ≤ 8192 / batch"]
            stats["pg_stat_ch_stats()"]
            hooks -->|"memcpy"| ring --> worker
            ring -.-> stats
        end
        subgraph ch["ClickHouse (monitoring)"]
            raw[("pg_stat_ch.events_raw<br/>7 d hot → cold, 90 d")]
            mv5["query_stats_5m"]
            mv1["db_app_user_1m"]
            err["errors_recent (30 d)"]
            raw --> mv5 & mv1 & err
        end
        worker -->|"native :9000, LZ4<br/>user pg_stat_ch, INSERT only"| raw
        exporter["CNPG exporter :9187<br/>custom query pg_stat_ch"] --> stats
        vm[("VictoriaMetrics")]
        exporter --> vm
        grafana["Grafana<br/>postgresql-query-telemetry"]
        raw & mv5 & err --> grafana
        vm -->|"cnpg_pg_stat_ch_*"| grafana
        alerts["vmalert<br/>PgStatCh* rules"]
        vm --> alerts
        job["clickhouse-schema Job<br/>(clickhouse-ddl image)"] -.->|"creates"| raw
    end
    classDef service fill:#cffafe,color:#164e63,stroke:#0891b2;
    classDef worker fill:#fef3c7,color:#78350f,stroke:#d97706;
    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    class hooks,stats service;
    class worker,job worker;
    class exporter,grafana,alerts platform;
    class ring,raw,mv5,mv1,err data;
    class vm metric;
```

The diagram answers *where an execution goes and who can lose it*. The hot
path is a `memcpy` into the ring under a try-lock; a full ring drops the event
and bumps `dropped_events`. The background worker owns the only network
connection; an insert failure discards that batch and bumps `send_failures`.
Both counters are what the exporter query scrapes and the three alerts watch.

## Why the pieces are shaped this way

- **Image volume, not a custom operand image.** CloudNativePG mounts the
  extension image read-only and appends its `lib/` and `share/` to
  `dynamic_library_path` / `extension_control_path`, which is enough for
  `shared_preload_libraries` to find it — the CNPG catalog ships `pgaudit` and
  `timescaledb` the same way. The image is built *inside* the pinned operand
  image and `ldd`-checked there, so a library mismatch fails the image build,
  not a pod start. It also leaves the operand image free for other work
  (RFC-0030's `pg_cron` image can coexist).
- **Own DDL, upstream columns.** The extension's `INSERT INTO events_raw
  (<44 columns>)` is the contract; `events_raw` keeps upstream's column names
  and types. Everything else is the platform's: `ReplicatedMergeTree` inside a
  `Replicated` database created per replica by the `clickhouse-schema` Job
  (the same bootstrap rule as `otel`, ADR-065), `ORDER BY (db_name, ts)`, the
  `hot_cold` policy and the 7/90-day TTL that `otel_logs` uses. Upstream's
  plain `MergeTree` with a 180-day TTL fits neither the three-replica store nor
  its retention.
- **An INSERT-only writer.** The CHI defines user `pg_stat_ch` with
  `GRANT INSERT ON pg_stat_ch.*` and nothing else, so the credential that sits
  in every PostgreSQL pod cannot read telemetry or touch `otel`. Grafana keeps
  reading as `default`.
- **The password reaches PostgreSQL through Flux, not git.** The extension
  takes its password only as a postmaster GUC, and CNPG only takes GUCs as
  literals in `Cluster.spec.postgresql.parameters`. The manifests therefore
  carry `${PG_STAT_CH_CLICKHOUSE_PASSWORD}`, and `databases-local` substitutes
  it at apply time (`postBuild.substituteFrom`) from the Secret ESO lands in
  `flux-system` — one OpenBAO path (`secret/local/infra/clickhouse/pg_stat_ch`)
  feeds both that Secret and the CHI's. Only the `${var}` form is substituted;
  the shell scripts in that path use `$VAR` and are untouched.
- **Sized for 1 Gi pods.** Upstream defaults (131072 slots, 64 MiB string
  area) are for tens of thousands of statements per second. The clusters run
  `queue_capacity: 8192`, `string_area_size: 16`, `flush_interval_ms: 1000`,
  `batch_max: 8192`: a one-second burst of ~8000 statements per instance fits,
  anything beyond is counted as dropped rather than buffered.
- **No new Flux edge.** `databases-local` does not wait for the ClickHouse
  waves: the extension tolerates an absent ClickHouse by dropping and
  counting, which the alerts surface, and the first successful flush needs no
  restart.

## Reading the data

The dashboard covers the routine questions. For ad-hoc work the two
rollups are cheap over long ranges and `events_raw` is the drill-down:

```sql
-- Which statements carried the last 24 h, with percentiles
SELECT query_id, db_name,
       countMerge(calls_state) AS calls,
       round(sumMerge(duration_sum_state) / 1e6, 1) AS total_s,
       round(arrayElement(quantilesTDigestMerge(0.5, 0.95, 0.99)(duration_q_state), 2) / 1000, 2) AS p95_ms,
       anyMerge(query_text_state) AS sample
FROM pg_stat_ch.query_stats_5m
WHERE bucket > now() - INTERVAL 24 HOUR
GROUP BY query_id, db_name
ORDER BY total_s DESC LIMIT 20;

-- What changed for one fingerprint between two moments
SELECT toStartOfFiveMinutes(ts) AS t, count() AS calls,
       quantile(0.95)(duration_us) / 1000 AS p95_ms,
       avg(shared_blks_read) AS avg_reads
FROM pg_stat_ch.events_raw
WHERE query_id = 123456789 AND ts BETWEEN '2026-10-13 13:00:00' AND '2026-10-13 16:00:00'
GROUP BY t ORDER BY t;
```

`query_id` joins to `cnpg_pg_stat_statements_*{queryid=…}` in VictoriaMetrics
and to the auto_explain plans stream in VictoriaLogs (`query_id` stream field),
which is how the
[plan-regression workflow](../../runbooks/postgresql/plan-regression-investigation.md)
now finds the *onset* below the 1 s auto_explain threshold.

## Operations

```bash
# Is the extension loaded and exporting? (database that owns the objects:
# product on product-db, user on platform-db)
kubectl exec -n product product-db-1 -c postgres -- psql -d product -c "SELECT * FROM pg_stat_ch_stats();"
kubectl exec -n product product-db-1 -c postgres -- psql -c "SHOW shared_preload_libraries;"

# Is the store receiving? (any replica; default user)
PW=$(kubectl -n monitoring get secret clickhouse-credentials -o jsonpath='{.data.password}' | base64 -d)
kubectl -n monitoring exec chi-clickhouse-otel-0-0-0 -c clickhouse -- clickhouse-client --password "$PW" -q \
  "SELECT db_name, count(), max(ts) FROM pg_stat_ch.events_raw WHERE ts > now() - INTERVAL 10 MINUTE GROUP BY db_name"

# Pause capture without a restart (reload-only GUC), then reconcile
#   pg_stat_ch.enabled: "off"   in the Cluster parameters
```

| Change | Effect | How |
|---|---|---|
| `pg_stat_ch.enabled`, `min_duration_us`, `sample_rate`, `flush_interval_ms`, `batch_max` | reload | edit `instance.yaml` parameters; CNPG reloads |
| `queue_capacity`, `string_area_size`, connection parameters | PostgreSQL restart | CNPG rolling restart (standbys first, then switchover) |
| extension image reference | pod replacement | move `extensions[].image.reference` on both clusters and the replica together with the operand digest the image was built against |
| new extension version | new image + possibly new DDL | `duynhlab/images` release, then the pins here; `events_raw` columns are the compatibility line |

Removing the extension is the reverse: drop `pg_stat_ch` from
`shared_preload_libraries` and the parameters (restart), remove the
`Database.spec.extensions` entry with `ensure: absent`, and only then the image
volume. The ClickHouse database stays until its TTL drains it.

Verification: repository review 2026-10-13 against pg_stat_ch v0.4.0 sources
and the CNPG 1.30 image-volume documentation; the DDL was exercised on a
throwaway ClickHouse 26.9 with the exporter's exact INSERT column list.
Runtime evidence from the Kind rollout is recorded in the pull request that
introduced the signal.

## References

- [pg_stat_ch](https://github.com/ClickHouse/pg_stat_ch) — README, `docs/reference/configuration.mdx`, `docs/reference/events-schema.mdx`
- [CloudNativePG 1.30 image-volume extensions](https://cloudnative-pg.io/docs/1.30/imagevolume_extensions/)
- [Flux post-build variable substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
- [ClickHouse `users.xml` grants](https://clickhouse.com/docs/operations/settings/settings-users#grants)
- [Extensions on CloudNativePG](../../../databases/extensions.md) — delivery model and the telemetry-extension comparison
- [Custom metrics reference](custom-metrics.md) — the `pg_stat_ch` exporter query
- Runbooks: [PgStatChExportFailing](../../runbooks/postgresql/PgStatChExportFailing.md), [PgStatChDroppingEvents](../../runbooks/postgresql/PgStatChDroppingEvents.md), [PgStatChNotExporting](../../runbooks/postgresql/PgStatChNotExporting.md)
