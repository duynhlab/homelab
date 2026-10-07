# Query processing — how SQL becomes a plan and then rows

The same SQL text can run in milliseconds or minutes depending on a plan you
never wrote. This chapter follows a statement from text to rows, so that a
surprising plan on `product-db` becomes evidence to read instead of a mystery
to tune around.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Practitioner — the read path from SQL text to executor output |
| **Prerequisites** | [Buffer manager and I/O](03-buffer-manager-and-io.md); [MVCC and snapshots](05-mvcc-and-snapshots.md); glossary terms page, tuple, snapshot |
| **Deployment status** | Deployed — every statement on `platform-db` and `product-db` passes through this path |
| **Platform scope** | All CNPG clusters; planner GUCs and `auto_explain`/`pg_stat_statements` from the Cluster manifests |
| **Evidence context** | Live Kind cluster `kind-homelab`, 2026-10-01 02:43 UTC, PostgreSQL 18.1 — read-only lab below; other rows are labelled by evidence class |
| **This page owns** | Parse → rewrite → plan → execute, the cost model, and how to read plan evidence |
| **Not this page** | Index internals and access-method choice — [Indexes and access methods](09-indexes-and-access-methods.md); workload capacity — [Monitoring and capacity](14-monitoring-and-capacity.md) |
| **Previous / next** | [Vacuum and freezing](07-vacuum-and-freezing.md) / [Indexes and access methods](09-indexes-and-access-methods.md) |

## Questions this chapter answers

- Which four stages transform SQL text into rows, and what does each stage
  consume and produce?
- What does a cost number in `EXPLAIN` actually measure, and which deployed
  settings shape it?
- When does the planner switch from exhaustive search to the genetic optimizer?
- Which evidence separates a bad estimate from a bad plan from a slow
  execution?
- How do the deployed `auto_explain` and `pg_stat_statements` capture plans and
  workload without you asking?

## Mental model

PostgreSQL never executes your SQL text. It executes a **plan tree**: a stack
of operators (scan, join, sort, aggregate) chosen from many equivalent
candidates. The planner prices each candidate using statistics about your data
and a handful of cost constants, then hands the cheapest one to the executor.
The executor pulls rows through the tree one node at a time.

Think of a courier quoting delivery routes from a map, not from traffic: the
quote is only as good as the map's freshness (statistics) and the assumed
speed per road type (cost constants). The analogy stops there — the planner
never re-routes mid-delivery; once execution starts, the plan is fixed for
that statement.

### Essential terms

| Term | Meaning here |
|---|---|
| `query tree` | The parsed, rewritten internal form of the statement, before any execution strategy exists |
| `path` | A cut-down candidate strategy the planner prices; the cheapest path is expanded into the plan tree |
| `plan node` | One operator in the tree (Seq Scan, Index Scan, Hash Join, Sort, Aggregate) that the executor runs |
| `cost` | A unitless estimate built from page-fetch and per-row constants; not a prediction of milliseconds |
| `selectivity` | The estimated fraction of rows a predicate keeps, derived from statistics |

## How it works internally

### Invariants

- Every statement passes parse → rewrite → plan → execute; there is no cached
  bypass of correctness, only of repeated work (prepared statements reuse the
  parse/plan output, not the execution). (Upstream invariant —
  [the path of a query](https://www.postgresql.org/docs/18/query-path.html).)
- The planner chooses by estimated cost alone. It guarantees the cheapest
  *estimated* path among those it examined, not the fastest execution.
  (Upstream invariant —
  [planner/optimizer](https://www.postgresql.org/docs/18/planner-optimizer.html).)
- Plans read through a snapshot: two identical statements can return different
  rows across transactions, but one executing plan sees one consistent
  snapshot ([MVCC and snapshots](05-mvcc-and-snapshots.md) owns why).
- Cost numbers are not comparable across machines or settings — they are a
  function of the cost GUCs in force when the plan was made.

### Lifecycle or sequence

1. **Parse.** The parser checks syntax and builds a query tree. Names are
   resolved against the catalogs; a missing column fails here, before any
   planning.
2. **Rewrite.** The rule system transforms the tree — most visibly, a query
   against a view becomes a query against its base tables. (Upstream
   invariant — [rule system](https://www.postgresql.org/docs/18/rules-views.html).)
3. **Plan.** The planner generates *paths* for each relation (sequential scan,
   index scans that match predicates) and each join order/method, prices them,
   and expands the cheapest into a plan tree. With 12 or more `FROM` items
   (`geqo_threshold` default 12) it abandons exhaustive search for the
   genetic optimizer, which samples join orders instead of enumerating them.
   (Upstream invariant —
   [GEQO](https://www.postgresql.org/docs/18/runtime-config-query.html).)
4. **Execute.** The executor recursively pulls rows through the plan nodes,
   reading pages via the buffer manager ([chapter 03](03-buffer-manager-and-io.md)),
   checking tuple visibility against the snapshot, evaluating quals, and
   returning rows to the client.

Cost pricing uses per-page and per-row constants. The two most consequential:
`seq_page_cost` (default 1.0) and `random_page_cost` (default 4.0 upstream;
**1.1 on this platform** — SSD-appropriate). A lower random-page penalty makes
index scans win earlier. `effective_cache_size` (deployed **1.5GB**) tells the
planner how much of an index is probably already cached; it prices reads, it
does not allocate memory. (Upstream invariant —
[planner cost constants](https://www.postgresql.org/docs/18/runtime-config-query.html);
repository fact — [`product-db` GUCs](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml).)

Join methods and when each wins:

| Method | Wins when | Loses when |
|---|---|---|
| Nested loop | Outer side is small and inner side has a cheap parameterized index path | Outer row count explodes — per-loop work multiplies |
| Hash join | Both sides large, equality join, hash fits in `work_mem` (deployed 32MB) | Hash spills to temp files (`log_temp_files 0` logs every spill) |
| Merge join | Both inputs already sorted or cheaply sortable, range-friendly | Sort cost dominates unsorted large inputs |

Parallelism: the planner can split eligible scans/joins/aggregates across
workers — deployed caps are `max_parallel_workers_per_gather 4` within
`max_parallel_workers 8` (repository fact, same GUC block).

### What to notice

- Statistics enter only at the **plan** stage. `ANALYZE` (autovacuum's analyze
  runs at the deployed 0.05 scale factor — [chapter 07](07-vacuum-and-freezing.md))
  refreshes them; a plan made from stale statistics stays wrong until
  re-planning happens.
- The executor never revisits the planner's choice. A misestimate surfaces as
  actual-vs-estimated row divergence, not as a plan change mid-flight.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| `random_page_cost` default 4.0 | `1.1` on both operational clusters (SSD assumption) | [`instance.yaml` planner block](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| `effective_cache_size` | `1.5GB` against a 1Gi pod memory limit — the planner is told about node-level page cache the pod's limit does not cap | same GUC block | Repository fact |
| Statistics resolution | `default_statistics_target 100` (upstream default) declared explicitly | same GUC block | Repository fact |
| Plan capture for slow statements | `auto_explain.log_min_duration 1s`, `log_analyze on`, `log_format json` — Vector parses the JSON payload into the log pipeline | [`instance.yaml` auto_explain block](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| Workload history | `pg_stat_statements.track all`, `max 10000`, exported by the monitoring ConfigMap | [`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |
| Temp-file spill visibility | `log_temp_files 0` + `CNPGTempFileSpill` alert | [`deep-signals-alerts.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml) | Repository fact |

The `auto_explain` JSON format is load-bearing: Vector's parser reads the
payload after `plan:` as JSON, so the upstream default `text` format would
divert every captured plan to the parse-failure sink instead of the log
pipeline (repository fact — comment in the GUC block).

## Observe it on the live cluster

This lab reads one plan and one workload ranking. It is read-only: plain
`EXPLAIN` never executes the statement, and the `pg_stat_statements` read is a
bounded catalog query.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; never through PgDog.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Confirm the kubeconfig context, the instance pod, and its role before reading.
- Run only the read-only commands shown below.

### Query

Plan shape without execution — the catalogs are always present, so this works
on any database:

```sql
EXPLAIN (FORMAT TEXT)
SELECT c.relname, c.relpages, c.reltuples
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'pg_catalog'
ORDER BY c.relpages DESC
LIMIT 10;
```

Workload ranking since the last reset — note the reset timestamp first:

```sql
SELECT stats_reset
FROM pg_stat_statements_info;
```

```sql
SELECT
    left(query, 80) AS query_sample,
    calls,
    round(total_exec_time::numeric, 1) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    rows,
    shared_blks_hit,
    shared_blks_read
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Observed example

```text
-- product-db-1 (primary), database postgres
Limit  (cost=23.71..23.73 rows=10 width=72)
  ->  Sort  (cost=23.71..23.97 rows=104 width=72)
        Sort Key: c.relpages DESC
        ->  Hash Join  (cost=1.06..21.46 rows=104 width=72)
              Hash Cond: (c.relnamespace = n.oid)
              ->  Seq Scan on pg_class c  (cost=0.00..18.15 rows=415 width=76)
              ->  Hash  (cost=1.05..1.05 rows=1 width=4)
                    ->  Seq Scan on pg_namespace n  (cost=0.00..1.05 rows=1 width=4)
                          Filter: (nspname = 'pg_catalog'::name)

pg_stat_statements_info.stats_reset: 2026-09-30 13:45:30 UTC

query_sample (first 80 chars)                           calls  total_ms   mean_ms
SELECT location, … FROM pg_backup_start($1, $2) …       1      218318.1   218318.13
SELECT datname, pg_database_size(datname) …             1044   12555.4    12.03
SELECT … pg_stat_statements.queryid … (exporter)        1044   5257.8     5.04
SELECT … pg_stat_statements.queryid … (exporter)        1042   4970.6     4.77
SELECT … pg_stat_statements.queryid … (exporter)        1041   4509.8     4.33
… five more exporter/catalog queries, 2.3–2.8 s total each
```

Observation context:

| Field | Value |
|---|---|
| **Observed at** | 2026-10-01 02:43 UTC |
| **Repository** | `main` at `b884a26c` (what Flux served); chapters on `docs/pg-internals-chapters` |
| **Cluster/context** | `kind-homelab`; both clusters created 2026-09-30 ≈13:45 UTC (the `stats_reset` epoch below) |
| **PostgreSQL** | `PostgreSQL 18.1 (Debian 18.1-1.pgdg13+2)`, image `ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie` |
| **Cluster/instance** | `product-db` / `product-db-1` |
| **CNPG role** | `primary` (pod label `cnpg.io/instanceRole`; `kubectl cnpg status` could not proxy to the pods in this run) |
| **PostgreSQL recovery state** | `pg_is_in_recovery() = f` |
| **Synchronous state** | `ANY 1 ("product-db-2","product-db-3","product-db-1")`; both standbys `streaming`, `sync_state = quorum` |
| **Database** | `postgres` |

What this run showed:

- The catalog plan is all sequential scans plus a hash join. With 415 `pg_class` rows, the seq-scan path is genuinely cheapest, which is what the text above predicts.
- The top statement by total time is CNPG's `pg_backup_start()` call from the first backup (one call, 218 s). That time is the call waiting for a spread checkpoint (`checkpoint_completion_target 0.9` of `checkpoint_timeout 15min`), not CPU. [13](13-backup-and-pitr.md) explains the backup API.
- Every other top-10 entry is the exporter's own custom SQL, about 1,040 calls each since the reset. On an idle lab cluster, monitoring is the workload. This is the reason to read rankings as deltas over a window.

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `cost=a..b` on a plan node | Startup and total estimated cost in cost units under the deployed constants | Nothing about milliseconds; not comparable to a plan made under other GUCs |
| `rows=` estimate on each node | The planner's cardinality belief from statistics | Not the actual row count — only `EXPLAIN ANALYZE` shows both |
| Node choice (Seq Scan vs Index Scan) | The cheapest path under `random_page_cost 1.1` and current statistics | Not that the alternative was impossible — only that it priced higher |
| `pg_stat_statements.calls`/`total_exec_time` | Cumulative workload shape since `stats_reset` | Not a current regression — lifetime totals need deltas over a known interval |
| `query` with `$1` placeholders | Statements are normalized by query ID; constants are stripped | Two different literal values are the same entry — you cannot recover the parameter |
| `shared_blks_hit` vs `shared_blks_read` | Buffer-cache effectiveness for that statement shape ([chapter 03](03-buffer-manager-and-io.md)) | Not OS-cache misses — a `read` may still come from kernel cache |

### What to notice

- Every value is an **observed example**. The top-ranked statement changes
  with workload, and `stats_reset` moves on restart or explicit reset.
- The plan over `pg_class` may itself use a Seq Scan — on tiny relations the
  sequential path is genuinely cheapest, which is the cost model working, not
  failing.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Stale or unrepresentative statistics | Planner misprices paths; cardinality estimates diverge from reality | A previously fast query picks a bad join order or scan | `auto_explain` JSON plans (deployed ≥1s); estimated vs actual rows | `ANALYZE` via autovacuum or the owning service's maintenance; never disable autovacuum ([chapter 07](07-vacuum-and-freezing.md)) |
| Correlated predicates | Independent-column selectivity multiplies wrongly | Rows estimate off by orders of magnitude on multi-column filters | Plan shows tiny estimate, huge actual | Extended statistics are a schema change owned by the service repo |
| Hash/sort exceeds `work_mem` (32MB) | Spill to temp files | Latency spike, disk churn | `log_temp_files 0` log lines; `CNPGTempFileSpill` alert | Bounded query rework beats a global `work_mem` raise — 200 connections × 32MB already outsizes the 1Gi pod limit |
| ≥12 FROM items | GEQO samples join orders instead of exhaustive search | Plan quality varies; plans can change without data changes | `EXPLAIN` across runs; `geqo_threshold` in `pg_settings` | Deterministic per `geqo_seed`, but treat many-join queries as a design smell |
| Plan regression after data growth | Same SQL, new cheapest path | Latency step-change with unchanged code | [plan-regression runbook](../../observability/runbooks/postgresql/plan-regression-investigation.md); `pg_stat_statements` deltas | Investigate estimates first; forcing planner GUCs is the last resort, scoped and temporary |

During any of these, the correctness invariant holds — plans are never wrong
about *results*, only about *speed*. What is unavailable is predictable
latency until estimates and reality re-converge.

## Misconceptions and challenge questions

### “The planner knows how long the query will take”

It never does. Costs are unitless arithmetic over page and row constants —
under this platform's `random_page_cost 1.1`, an index path prices ~4×
cheaper relative to upstream defaults, changing *choices*, not clock time.
`EXPLAIN ANALYZE` is the only view of actual time, and even it excludes
client transfer unless `SERIALIZE` is requested (upstream invariant —
[`EXPLAIN` options](https://www.postgresql.org/docs/18/sql-explain.html)).

### “`EXPLAIN ANALYZE` is only EXPLAIN with timing added”

It **executes** the statement. On a write it performs the write (only the
output is discarded — WAL and table changes are real). On this platform's
shared clusters, `EXPLAIN ANALYZE` is acceptable only on bounded, read-only
SELECTs inside the safe session header. In PostgreSQL 18, `ANALYZE` also
implies `BUFFERS` by default (upstream invariant —
[using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html)), so
buffer evidence arrives without asking.

### Challenge: a nightly report joins 14 tables and its plan changed overnight with no deploy and no data load

**Model answer:** 14 FROM items exceeds `geqo_threshold` (12), so the genetic
optimizer plans this query. GEQO is randomized but seeded (`geqo_seed`), so
the usual suspect is not GEQO drift itself but a statistics refresh —
autovacuum analyze ran ([chapter 07](07-vacuum-and-freezing.md)) and changed
the cost landscape. Check `pg_stat_user_tables.last_autoanalyze` against the
plan-change time, then compare the captured `auto_explain` JSON plans before
and after.

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The four stages from SQL text to rows, and which stage statistics enter.
- [ ] What a cost number is made of, and why `random_page_cost 1.1` changes
      plan choices on this platform.
- [ ] What happens to planning at 12+ FROM items and why it stays
      deterministic per seed.
- [ ] One `pg_stat_statements` row and what its lifetime totals cannot prove.
- [ ] The trade-off `auto_explain.log_analyze on` accepts to capture real
      plans.

## Related documentation

- [Indexes and access methods](09-indexes-and-access-methods.md) — the access
  paths the planner prices
- [Monitoring and capacity](14-monitoring-and-capacity.md) — workload history
  and the investigation loop
- [Plan-regression runbook](../../observability/runbooks/postgresql/plan-regression-investigation.md)
- [Buffer manager and I/O](03-buffer-manager-and-io.md) — where plan execution
  pays its I/O bill

## References

- [The path of a query](https://www.postgresql.org/docs/18/query-path.html)
- [Planner/optimizer](https://www.postgresql.org/docs/18/planner-optimizer.html)
- [Planner cost constants and GEQO](https://www.postgresql.org/docs/18/runtime-config-query.html)
- [Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html)
- [EXPLAIN reference](https://www.postgresql.org/docs/18/sql-explain.html)
- [pg_stat_statements](https://www.postgresql.org/docs/18/pgstatstatements.html)
- [auto_explain](https://www.postgresql.org/docs/18/auto-explain.html)
