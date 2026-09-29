# Monitoring and capacity — measuring to name the failing layer

A slow request can be waiting in a pool, on a lock, on vacuum debt, on WAL
flush, or on a saturated volume — and the query text looks identical in every
case. This chapter explains how PostgreSQL's statistics machinery works, what
its counters can and cannot prove, and the method that turns them into a named
failing layer instead of a guess.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Mastery — investigation method over the whole engine |
| **Prerequisites** | All previous chapters; especially [Locking](06-locking-and-wait-events.md), [Vacuum](07-vacuum-and-freezing.md), [Query processing](08-query-processing.md), [Replication](12-replication-and-slots.md) |
| **Deployment status** | Deployed — CNPG metrics exporter with custom queries, `pg_stat_statements`, `track_io_timing`, `auto_explain` on all clusters |
| **Platform scope** | Clusters `product-db`, `platform-db`, `product-db-replica`; the monitoring-queries ConfigMap and the PostgreSQL alert rules |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | The statistics system's mechanics, `pg_stat_statements` internals, the investigation loop, the capacity model, and the safe mitigation hierarchy |
| **Not this page** | Per-alert diagnosis — [PostgreSQL alert runbooks](../../observability/runbooks/postgresql/README.md); symptom-first triage — [Observability and troubleshooting](../observability-and-troubleshooting.md) |
| **Previous / next** | [Backup and PITR](13-backup-and-pitr.md) / [PostgreSQL internals learning path](README.md) |

## Questions this chapter answers

- Where do `pg_stat_*` numbers physically live, when are they updated, and
  what happens to them on a crash?
- Why can two reads of the same statistics view in one transaction disagree —
  or agree when the world has moved on?
- How does `pg_stat_statements` merge thousands of distinct SQL texts into a
  few hundred rows, and when does that lie to you?
- Which deployed metric answers which layer of the investigation loop?
- In what order do you mitigate, and why is failover last?

## Mental model

Every backend keeps private tallies — rows read, blocks hit, commits — and
publishes them to a shared-memory table when convenient, at most about once a
second. The views you query are windows onto that shared memory. Nothing polls
the workload from outside; the workload reports on itself, slightly late.

Picture a factory where each worker updates a wall chart on the way to a
break. The chart is close to true, never exact, and says nothing about a task
still in a worker's hands. The analogy stops at durability: the wall chart is
wiped clean by any unclean shutdown, because PostgreSQL persists statistics
only on a clean stop (Upstream invariant —
[cumulative statistics system](https://www.postgresql.org/docs/18/monitoring-stats.html)).
A dashboard restarting from zero after a crash is telling you about the crash,
not about a quiet workload.

Two layers sit above the raw tallies on this platform: the CNPG exporter turns
selected views into Prometheus series every 15 seconds, and alert rules turn
series into pages. Each hop adds interpretation — and each hop is somewhere a
number can mislead.

### Essential terms

| Term | Meaning here |
|---|---|
| `cumulative statistics` | Monotonic counters since the last reset, kept in shared memory (no stats collector process since PostgreSQL 15) |
| `stats_fetch_consistency` | Whether repeated reads in one transaction re-fetch (`none`) or reuse a cached snapshot (`cache`, the default) |
| `queryid` | The hash of a query's normalized shape; the key `pg_stat_statements` aggregates by |
| `deallocation` | Eviction of the least-executed `pg_stat_statements` entries when the `max` table is full |
| `saturation` | The state where backlog grows under steady load, regardless of any percentage threshold |

## How it works internally

### Invariants

- Counters are cumulative and reset-scoped: a value means nothing without the
  matching `stats_reset` timestamp, and different views reset independently
  (`pg_stat_database` per database, `pg_stat_statements` by its own function,
  bgwriter/checkpointer cluster-wide). (Upstream invariant —
  [monitoring statistics](https://www.postgresql.org/docs/18/monitoring-stats.html).)
- Statistics lag activity by up to roughly a second and exclude in-flight
  transactions; only `pg_stat_activity` (`track_activities`) is live.
  (Upstream invariant.)
- All counters are lost on crash or immediate shutdown and after PITR; they
  survive only clean shutdowns. (Upstream invariant.)
- Within a transaction, the default `stats_fetch_consistency = cache` freezes
  the first-read values per object — self-joins are stable, freshness is not.
  (Upstream invariant —
  [`stats_fetch_consistency`](https://www.postgresql.org/docs/18/runtime-config-statistics.html).)
- `pg_stat_statements` guarantees a bounded table (`max` entries), not a
  complete history: rare shapes are evicted, and evicted shapes restart from
  zero if they return. (Upstream invariant —
  [pg_stat_statements](https://www.postgresql.org/docs/18/pgstatstatements.html).)

### Lifecycle or sequence

One counter's journey, insert to alert:

1. A backend executes; its per-backend structs accumulate deltas.
2. Going idle (throttled to about once per second), it folds the deltas into
   shared memory.
3. `pg_stat_statements` intercepts at execution hooks instead: it normalizes
   the query (constants become `$1`; IN-lists squash to one element), hashes
   it to a `queryid`, and updates that entry — creating it if space allows, or
   evicting least-executed entries first when the table is full. Query texts
   live in an external file, not shared memory.
4. Every 15 seconds the CNPG exporter runs the SQL in the monitoring-queries
   ConfigMap against the instance and exposes the results as
   `cnpg_<query>_<column>` series with the instance role as a label.
5. VictoriaMetrics scrapes; alert rules such as `CNPGDeadlocksIncreasing`
   (rate over `pg_stat_database.deadlocks`) or `CNPGCheckpointPressure`
   (ratio from `pg_stat_checkpointer`) evaluate the series and page.

The deployed worked example (Repository fact —
[`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml)):
`pg_stat_statements` is exported scoped to `current_database()` with
`calls`, `total_exec_time`, block counters, and PostgreSQL 18's renamed
`shared_blk_read_time`/`shared_blk_write_time`; `pg_stat_io` is exported with
the PG 18 `read_bytes`/`write_bytes` columns; `pg_wait_events`,
`pg_blocking_queries`, `pg_long_running_transactions`, and
`pg_stat_progress_vacuum` cover the lock and maintenance layers those
chapters own.

### The investigation loop

Method, not procedure — each step names the evidence class it consumes:

1. Define the affected service, query shape, time window, and user impact.
2. Compare against a known-good baseline (dashboards outlive sessions;
   counters may not).
3. Identify the wait class before tuning —
   [locking chapter](06-locking-and-wait-events.md) owns the taxonomy.
4. Find the smallest unit — query, relation, backend, instance — that explains
   the aggregate.
5. Test one hypothesis with bounded evidence (`EXPLAIN` before
   `EXPLAIN ANALYZE`; [query chapter](08-query-processing.md)).
6. Apply the lowest-blast-radius mitigation (hierarchy below).
7. Verify both the database signal and the original request outcome.

### The capacity model

Capacity is several independent budgets, each with its own evidence:

| Budget | Deployed bound | Primary evidence |
|---|---|---|
| Connections and pool queues | `max_connections 200`; PgDog/PgBouncer pools of 30 | `pg_stat_activity` count vs state; pooler metrics ([Poolers](../poolers.md)) |
| Backend memory concurrency | `work_mem 32MB` × concurrent sorts/hashes; 1Gi pod limit | temp-file counters, `CNPGTempFileSpill` |
| CPU | pod requests/limits (100m/1Gi on `product-db`) | throttling metrics, active backends |
| Data/temp/WAL I/O | shared 10Gi PVC per instance | `pg_stat_io` (PG 18 byte columns), `track_io_timing` |
| WAL and replication throughput | 64 MB segments, `max_wal_size 8GB` | [chapter 04](04-wal-and-checkpoints.md) + [chapter 12](12-replication-and-slots.md) evidence |
| Vacuum capacity | 3 autovacuum workers, cost limit 200 | `pg_stat_progress_vacuum`, dead-tuple counters ([chapter 07](07-vacuum-and-freezing.md)) |
| Disk bytes and inodes | 10Gi `standard` PVCs on one Kind node filesystem | volume metrics; disk alerts |

Capacity is unsafe when backlog grows under steady load, even if no percentage
threshold has tripped. On this Kind host, remember all PVCs share one node
filesystem, so per-cluster disk numbers do not isolate blame (Inference from
the platform layout — the same caveat the ClickHouse curriculum records).

### The safe mitigation hierarchy

1. Stop or rate-limit the offending bounded workload.
2. Release an abandoned transaction through its owning application path.
3. Cancel a confirmed runaway query; terminate only when cancel cannot work.
4. Restore pool/concurrency controls.
5. Correct statistics, query, or index through the owning service workflow.
6. Scale resources only after proving the saturated budget and the expected
   recovery margin.

Failover is not on this list on purpose: it changes topology, moves the same
workload onto a colder cache, and — under the deployed quorum — trades a known
primary for a standby whose replay position you must verify first
([chapter 12](12-replication-and-slots.md)). Do not disable autovacuum as a
latency mitigation; that converts a visible incident into bloat and wraparound
risk ([chapter 07](07-vacuum-and-freezing.md)).

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Cumulative statistics + timing | `track_io_timing on`; `pg_stat_statements.track all`, `.max 10000` | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) parameters | Repository fact |
| Exporter over custom SQL | Identical ConfigMap on both operational clusters; 15 s scrape with instance-role label | [`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml); PodMonitors per cluster | Repository fact |
| Alerts over the series | Deep-signals group (blocked queries, deadlocks, autovacuum, cache hit, temp spill, checkpoint pressure, wraparound, slots, archive, long transactions) | [`deep-signals-alerts.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml) | Repository fact |
| Plan evidence at runtime | `auto_explain` ≥ 1 s, `ANALYZE on`, JSON format parsed by Vector into the log pipeline | Same manifest, `auto_explain.*`; format rationale in its comment | Repository fact |
| Historical plan regressions | Investigated from logs/traces, not fabricated live | [Plan-regression runbook](../../observability/runbooks/postgresql/plan-regression-investigation.md) | Repository fact |

Why it matters here: the exporter's 15-second cadence plus the engine's
once-per-second flush means a spike shorter than a scrape interval may never
appear in any dashboard — `pg_stat_activity` during the event is the only
witness. That asymmetry is why the investigation loop starts from impact and
time window, not from whichever chart moved.

## Observe it on the live cluster

One bounded sweep tying each capacity budget to its per-database counters,
with the reset timestamp that makes them interpretable.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Confirm the kubeconfig context, the pod that answered, and its role.
- Run only the read-only queries below.

### Query

```sql
SELECT
    datname,
    xact_commit,
    xact_rollback,
    deadlocks,
    temp_files,
    pg_size_pretty(temp_bytes) AS temp_volume,
    blks_hit,
    blks_read,
    round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
    stats_reset
FROM pg_stat_database
WHERE datname IN ('product', 'cart', 'order', 'payment', 'checkout', 'inventory')
ORDER BY datname
LIMIT 10;
```

```sql
SELECT
    calls,
    round(total_exec_time::numeric, 1) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    rows,
    left(query, 100) AS query_shape
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

```sql
SELECT
    dealloc,
    stats_reset
FROM pg_stat_statements_info
LIMIT 1;
```

### Observed example

```text
PENDING VERIFICATION — capture on the Ubuntu Kind cluster; see the verification worksheet in the pull request.
```

Observation context:

| Field | Value |
|---|---|
| **Observed at** | _pending_ |
| **Repository** | _pending_ |
| **Cluster/context** | _pending_ |
| **PostgreSQL** | _pending_ |
| **Cluster/instance/role** | _pending_ |
| **Database** | _pending_ |

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `stats_reset` per database | The zero point of every other column in that row | Counters from before the reset — or before the last crash — are gone; compare rates across a known interval, never lifetime totals |
| `cache_hit_pct` | Share of block requests served from shared buffers ([chapter 03](03-buffer-manager-and-io.md)) — the SQL behind the `CNPGLowCacheHitRatio` alert's intent | Not latency: a 99% ratio with slow disks can hurt more than 95% on fast ones; and OS page cache hits count as "reads" here |
| `temp_files` / `temp_volume` | Work that overflowed `work_mem 32MB` to disk | Which query did it — join to `pg_stat_statements.temp_blks_written` for shapes |
| Top-5 by `total_exec_time` | Where cumulative time went since the extension's own reset | Not a current regression: a lifetime total ranks history, not now; check `dealloc` before trusting completeness |
| `dealloc` > 0 | The 10000-entry table has evicted shapes; rankings undercount rare queries | How much was lost, or whether an absent shape never ran versus was evicted |
| `query_shape` with `$1` placeholders | Normalization by `queryid` — thousands of literal variants aggregated | Parameter-dependent behavior: one shape can hide one pathological bind value ([chapter 08](08-query-processing.md)) |

### What to notice

- Every number is an **observed example**, and every one is meaningless
  without its `stats_reset` — record both together, always.
- If the sweep looks healthy while users hurt, the failing layer is probably
  outside these counters: pool queueing, replica staleness, or the pod's own
  CPU throttle. That is the loop's step 3 sending you to a different chapter.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Crash / immediate shutdown | All cumulative counters reset | Dashboards drop to zero; rate() spikes then normalizes | `stats_reset` newer than the incident | Baselines must come from the metrics store, not the engine (Upstream invariant) |
| `pg_stat_statements` table full | Least-executed entries evicted on new shapes | Rankings silently incomplete | `pg_stat_statements_info.dealloc` climbing | Raise `.max` (memory + restart) or accept sampling of rare shapes (Upstream invariant) |
| Exporter query stalls or fails | Missing/stale series for that scrape | Gaps in dashboards; possible false "recovery" | exporter logs; scrape health | Custom-query SQL must stay cheap — it runs every 15 s on every instance (Inference) |
| Monitoring during an incident adds load | Statistics reads are cheap, but `EXPLAIN ANALYZE` and catalog scans are not | Investigation worsens the incident | `pg_stat_activity` showing the investigator | The safe session header and bounded labs exist for exactly this (Repository fact — [troubleshooting guide](../observability-and-troubleshooting.md)) |
| Counter interpreted without reset context | A restart masquerades as improvement, or lifetime totals as regression | Wrong mitigation chosen | `stats_reset` columns | Method failure, not engine failure — the loop's step 2 prevents it |

The invariant that survives every monitoring failure: `pg_stat_activity` and
the wait-event columns are live, backend-local truth. When cumulative history
is suspect, current activity is still trustworthy.

## Misconceptions and challenge questions

### “The stats collector process is a bottleneck to watch”

There has been no stats collector process since PostgreSQL 15; backends write
counters directly to shared memory. What remains worth watching is the
flush latency (up to ~1 s) and the transaction-local caching of reads —
neither involves a separate process (Upstream invariant —
[cumulative statistics system](https://www.postgresql.org/docs/18/monitoring-stats.html)).

### “Cache hit ratio below 99% means we need more memory”

The ratio is workload-shaped, not a health constant: an analytics scan over
cold data lowers it while performing exactly as designed, and
`shared_buffers 256MB` on this platform guarantees big sequential reads miss.
Act on it only alongside latency evidence (`pg_stat_io` timings,
`track_io_timing`) and the query shapes involved.

### Challenge: checkout p99 doubled, but this chapter's sweep is clean

`pg_stat_database` is calm, top statements unchanged, no temp spill. Name the
next three evidence sources in loop order and the chapter that owns each.

**Model answer:** (1) `pg_stat_activity` wait events during the window — is
time in `Lock`/`LWLock`/`IO`? ([Locking](06-locking-and-wait-events.md));
(2) pooler queue depth and the LSN-aware routing on PgDog — waiting outside
the engine never shows in engine counters ([Poolers](../poolers.md));
(3) replica replay lag if reads route to standbys
([Replication](12-replication-and-slots.md)). Only after those, revisit plans
with `auto_explain` history ([Query processing](08-query-processing.md)).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] Where statistics live, when they flush, and what a crash does to them —
      in your own words.
- [ ] Why `stats_reset` must accompany any counter you quote, and who owns
      each reset scope.
- [ ] The predicted effect of a full `pg_stat_statements` table on your
      top-queries ranking, and the field that reveals it.
- [ ] One row of the capacity sweep and the limit of what it proves about a
      user-facing latency complaint.
- [ ] Why failover sits outside the mitigation hierarchy.

## Related documentation

- [Observability and troubleshooting](../observability-and-troubleshooting.md) — symptom-first triage and the safe session header
- [PostgreSQL alert runbooks](../../observability/runbooks/postgresql/README.md) — per-alert procedures this chapter deliberately does not own
- [Locking and wait events](06-locking-and-wait-events.md) — the wait-class taxonomy the loop depends on
- [Query processing](08-query-processing.md) — plan evidence and `auto_explain`
- [PostgreSQL internals learning path](README.md) — the curriculum this chapter closes

## References

- [The cumulative statistics system](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [Statistics configuration (`stats_fetch_consistency`, `track_io_timing`)](https://www.postgresql.org/docs/18/runtime-config-statistics.html)
- [pg_stat_statements](https://www.postgresql.org/docs/18/pgstatstatements.html)
- [CloudNativePG monitoring](https://cloudnative-pg.io/docs/1.30/monitoring)

---
_Last updated: 2026-09-29 — first version: statistics mechanics, the deployed
exporter pipeline, the investigation loop, capacity model, and mitigation
hierarchy, absorbing the former monitoring-and-performance-investigation page._
