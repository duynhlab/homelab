# Query pipeline — what happens between SQL and returned rows

When a Grafana panel over `otel_logs` takes four seconds, the SQL text alone
cannot tell you whether the time went to reading too many granules, to a full
column scan the index could not help, or to aggregation — this chapter gives
you the stages where each of those costs is paid, and the `EXPLAIN` commands
that expose them.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Foundation / practitioner |
| **Prerequisites** | [ClickHouse in this platform](01-architecture.md); basic SQL |
| **Deployment status** | Deployed |
| **Platform scope** | Any single replica of cluster `otel`; worked examples use `otel.otel_logs` |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | What happens between SQL submission and returned rows |
| **Not this page** | Schema tuning and pruning practice — [Schema and queries](../schema-and-queries.md); how data got into sorted parts — chapters [03](03-mergetree.md)–[04](04-parts-and-merges.md) |
| **Previous / next** | [ClickHouse in this platform](01-architecture.md) / [MergeTree layout](03-mergetree.md) |

## Questions this chapter answers

- Which stages does a SELECT pass through before the first row leaves the server?
- Where does index pruning happen, and which `EXPLAIN` variant shows it?
- How does one query use many CPU cores, and what limits that parallelism?
- Which replica executed my query, and where is its record kept afterwards?

## Mental model

A SELECT is processed in two phases: **planning** (cheap, single-threaded,
milliseconds) and **execution** (where all the data cost is paid, parallel).

Planning turns text into a checked, optimized recipe:

1. **Parser** — the query text becomes an abstract syntax tree (AST): pure
   structure, no knowledge of tables or types.
2. **Analyzer** — the AST becomes a *query tree*: names are resolved against
   real tables, aliases expanded, types fixed. This is where
   `Unknown identifier` errors appear.
3. **Planner** — the query tree becomes a *query plan*: an ordered set of
   logical steps (read, filter, aggregate, sort), with optimizations applied —
   including deciding which parts and granules **not** to read.
4. **Pipeline building** — the plan becomes a physical *pipeline* of
   processors, replicated across CPU lanes.

Execution then pulls data through that pipeline as a stream of **blocks** —
batches of columns, typically thousands of rows each — so a billion-row scan
never needs a billion rows in memory at once.

The recipe analogy: planning writes the recipe, execution cooks. The analogy
breaks in one place — the ClickHouse "recipe" already names the exact shelf
positions (granules) to take ingredients from, because the planner consults
the index during planning, not during cooking.

### Essential terms

| Term | Meaning here |
|---|---|
| `AST` | Abstract syntax tree — the parsed shape of the query, before names mean anything |
| `query plan` | The optimized logical steps; visible with `EXPLAIN PLAN` |
| `pipeline` | The physical graph of processors executing the plan; visible with `EXPLAIN PIPELINE` |
| `processor` | One operator instance (read, transform, aggregate) connected to others by ports |
| `block` | A batch of columns streamed between processors (see the [shared glossary](README.md#shared-glossary)) |

## How it works internally

### Invariants

- Planning is per-query and single-pass; nothing is cached between the parser
  and the pipeline that would let a "prepared" plan skip analysis. *(Upstream
  invariant — [architecture overview](https://clickhouse.com/docs/resources/develop-contribute/introduction/architecture).)*
- Index pruning is decided at plan time: `ReadFromMergeTree` is created already
  knowing which parts and granule ranges to read. *(Upstream invariant —
  [EXPLAIN reference](https://clickhouse.com/docs/reference/statements/explain).)*
- Execution streams blocks; a query's memory is bounded by what its operators
  hold (aggregation states, sort buffers), not by the size of the data
  scanned. The engine does **not** guarantee bounded memory for unbounded
  `GROUP BY` cardinality. *(Upstream invariant.)*
- On this platform, the whole pipeline runs on the one replica that accepted
  the connection — with one shard there is no distributed step. *(Inference
  from the deployed topology, [chapter 01](01-architecture.md).)*

### Lifecycle or sequence

Walking `SELECT count() FROM otel.otel_logs WHERE ServiceName = 'cart-service'
AND Timestamp >= now() - INTERVAL 1 HOUR` through the stages:

1. **Parse.** Text → AST. Syntax errors stop here. Inspect with `EXPLAIN AST`.
2. **Analyze.** `otel.otel_logs` is bound to the real table; `ServiceName` and
   `Timestamp` get their types; the query tree is formed
   ([analyzer guide](https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/understanding-query-execution-with-the-analyzer)).
   Inspect with `EXPLAIN QUERY TREE`, or `EXPLAIN SYNTAX` for the rewritten SQL.
3. **Plan and prune.** The planner builds the step list and consults table
   metadata: the partition key (`toDate(Timestamp)`) excludes whole daily
   partitions outside the hour; the sparse primary index over
   `(toStartOfFiveMinutes(Timestamp), ServiceName, Timestamp)` excludes granule
   ranges within surviving parts ([chapter 03](03-mergetree.md) owns *why* that
   works). `EXPLAIN indexes = 1` prints the result as `Parts: x/y` and
   `Granules: x/y`.
4. **PREWHERE split.** Filter conditions are automatically moved to PREWHERE:
   the engine reads *only the filter columns* first, evaluates the condition
   per granule, and reads the remaining requested columns only for surviving
   row ranges — enabled by default via `optimize_move_to_prewhere`
   ([PREWHERE reference](https://clickhouse.com/docs/reference/statements/select/prewhere)).
   For wide events like `otel_logs` rows (Maps, `Body`) this is a major saving:
   `ServiceName` is a few bytes per row; `LogAttributes` is not.
5. **Build the pipeline.** The plan becomes processors: a `MergeTreeSelect`
   source per read stream, `ExpressionTransform`s, `AggregatingTransform`s, a
   final merge. The engine replicates the lanes up to the core budget —
   `EXPLAIN PIPELINE` shows the multiplier (e.g. `AggregatingTransform × 4`)
   ([query parallelism](https://clickhouse.com/docs/concepts/core-concepts/query-parallelism)).
6. **Execute.** Sources read granules from the selected parts — different
   parts, and different granule ranges of one part, in parallel — and blocks
   flow through the transforms. `count()` accumulates partial states per lane;
   a final processor merges them into one row.
7. **Record.** After the query finishes, its metrics (duration, `read_rows`,
   `read_bytes`, memory) land in that replica's `system.query_log`
   ([query_log reference](https://clickhouse.com/docs/reference/system-tables/query_log)).

No diagram: the pipeline is a straight staged flow, and the `EXPLAIN` outputs
in the lab show the real structure better than a drawn approximation.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Which server plans and executes | The one replica behind `clickhouse-clickhouse:9000` that accepted the connection; no distributed step (1 shard) | [Chapter 01](01-architecture.md); [ADR-065](../../../proposals/adr/ADR-065-clickhouse-replicated-topology/README.md) | Repository fact |
| Partition pruning input | `PARTITION BY toDate(Timestamp)` on both tables | [otel_logs DDL](../../../../images/clickhouse-ddl/sql/10-otel_logs.sql), [otel_traces DDL](../../../../images/clickhouse-ddl/sql/20-otel_traces.sql) | Repository fact |
| Primary-index pruning input | `ORDER BY (toStartOfFiveMinutes(Timestamp), ServiceName, Timestamp)` (logs); `(ServiceName, SpanName, toDateTime(Timestamp))` (traces) | Same DDL | Repository fact |
| Pruning quality in practice | A bare `ServiceName` filter on `otel_logs` prunes poorly because the 5-minute bucket precedes it; measured walk-through | [Schema and queries](../schema-and-queries.md), [platform hub query examples](../README.md#query-examples) | Repository fact (measured there) |
| Main query producers | Grafana panels (ClickHouse datasource, native protocol) and ad-hoc `clickhouse-client` | [Platform hub](../README.md#how-it-works-in-this-platform) | Repository fact |
| Query history | `system.query_log` is engine-managed; on this deployment the operator declares daily partitions and a 30-day TTL for it | [CHI system-log settings](../../../../kubernetes/infra/configs/clickhouse/clickhouseinstallation.yaml) | Repository fact |

The practical tuning discipline — write the filter to match the `ORDER BY`
prefix, then re-check with `EXPLAIN indexes = 1` — is owned by
[Schema and queries](../schema-and-queries.md); this chapter explains the
machinery those checks are reading. The short platform summary of the query
layer sits in [fundamentals](../fundamentals.md#query-layer-short).

## Observe it on the live cluster

### Prerequisites and safety

- Use the [secure ClickHouse client pattern](../operations.md#secure-client-pattern).
- Confirm the current context and the replica you will query — record
  `hostName()`; `system.query_log` is per replica.
- Run only the read-only commands shown below (`EXPLAIN` does not execute the
  query).

### Query

Plan-time pruning for a bounded logs query:

```sql
EXPLAIN indexes = 1
SELECT count()
FROM otel.otel_logs
WHERE Timestamp >= now() - INTERVAL 1 HOUR
  AND ServiceName = 'cart-service';
```

The physical pipeline and its parallelism for the same query:

```sql
EXPLAIN PIPELINE
SELECT count()
FROM otel.otel_logs
WHERE Timestamp >= now() - INTERVAL 1 HOUR
  AND ServiceName = 'cart-service';
```

Then run the query itself, and read its record back from this replica's log:

```sql
SELECT
    hostName() AS replica,
    count() AS matching_rows
FROM otel.otel_logs
WHERE Timestamp >= now() - INTERVAL 1 HOUR
  AND ServiceName = 'cart-service';
```

```sql
SELECT
    event_time,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    result_rows
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query LIKE '%matching_rows%'
  AND event_time >= now() - INTERVAL 10 MINUTE
ORDER BY event_time DESC
LIMIT 3;
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
| **ClickHouse** | _pending_ |
| **Database/table** | _pending_ |
| **Replica** | _pending_ |

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `Parts: x/y`, `Granules: x/y` under `PrimaryKey` | y existed after partition pruning; x survived index analysis — the read set was fixed at plan time | Good pruning does not guarantee a fast query: surviving granules can still be large, and PREWHERE/aggregation cost comes after |
| `MinMax`/`Partition` index lines | Whole daily partitions excluded by `toDate(Timestamp)` before the primary index ran | Partition counts are an observed example — they track data age and TTL state, not a constant |
| `MergeTreeSelect ... × N`, `AggregatingTransform × N` | N parallel lanes were built for this replica's core budget | N is per-server and per-load; it is not "the platform's parallelism" and can differ on another replica or another day |
| `read_rows` vs `result_rows` in `query_log` | The funnel actually paid at execution: rows read from granules vs rows returned | `read_rows` alone cannot separate primary-index misses from PREWHERE savings — compare `read_bytes` against a run with `optimize_move_to_prewhere = 0` only in a disposable lab |
| Empty `query_log` result | This replica did not run your query (it landed elsewhere), or the entry has not flushed yet | Absence here is not absence on the cluster — check `hostName()` from the query itself |

### What to notice

- The pruning numbers appear in `EXPLAIN` output *without executing the
  query* — proof that granule selection is a planning decision.
- The `× N` multipliers make the "one replica does all the work, in parallel"
  model concrete: parallelism here means lanes inside one server, not other
  replicas helping.
- If your `query_log` lookup returns nothing, you have just observed the
  round-robin Service from [chapter 01](01-architecture.md) doing its job.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Filter cannot use the `ORDER BY` prefix | Planner keeps most granules; execution scans them | Query is slow but correct; high `read_rows` | `EXPLAIN indexes = 1` shows `Granules: ~y/y` | Rewrite the query to lead with the sort-key prefix — [Schema and queries](../schema-and-queries.md) *(Repository fact — measured there)* |
| Unbounded `GROUP BY` cardinality | Aggregation states grow with distinct keys | Slow query or `MEMORY_LIMIT_EXCEEDED` for that query | `system.query_log` `memory_usage`; exception text | The per-query limit protects the server at the cost of the query *(Upstream invariant)* |
| Concurrent heavy panels on one replica | Queries compete for the same core budget | All panels on that replica slow together, other replicas idle | `query_log` per replica; `hostName()` | Cost of connection-level balancing with no coordinator; scaling angles in [chapter 12](12-scaling.md) *(Inference)* |
| Reading cold-tier data | Granule reads become S3 GETs behind the same pipeline | Same plan, much slower execution | Disk/tier evidence in [chapter 10](10-storage-s3.md) | Plan shape does not change — only I/O latency does *(Upstream invariant)* |

During all of these the invariant "pruning happened at plan time" still holds
— a slow query re-reads its plan-selected granules slowly; it does not
re-plan. What is not guaranteed is latency: the pipeline is a cost machine,
not a deadline machine.

## Misconceptions and challenge questions

### "ClickHouse scans everything anyway — indexes barely matter for logs"

`EXPLAIN indexes = 1` on the bounded query above disproves this on the
deployed tables: daily partitions fall to the partition key and granule ranges
fall to the primary index before execution starts. What *is* true on this
schema: a filter that skips the leading 5-minute bucket (bare `ServiceName`)
prunes poorly — the measured walk-through is in
[Schema and queries](../schema-and-queries.md). The lesson is "match the
prefix", not "indexes don't work".

### "PREWHERE is a syntax trick you must write yourself"

It is an automatic plan transformation (`optimize_move_to_prewhere`, on by
default): filter columns are read first, other columns only for surviving
ranges ([PREWHERE](https://clickhouse.com/docs/reference/statements/select/prewhere)).
Manual `PREWHERE` exists for overrides, not as the normal path. *(Upstream
invariant.)*

### Challenge: the same dashboard panel is fast at 09:00 and slow at 09:05. `EXPLAIN indexes = 1` output is identical both times. Name two mechanisms from this chapter that can explain it — and one that cannot.

**Model answer:** Can: (a) the two connections landed on different replicas
(`hostName()`), one of them busy with concurrent queries competing for lanes;
(b) the same replica had a different concurrent load or its target granules
now required cold-tier reads ([chapter 10](10-storage-s3.md)). Cannot: a
different pruning decision — identical `EXPLAIN indexes = 1` output means the
planned read set was the same, so the difference was paid at execution, not at
planning.

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The four planning stages and what each one can reject or optimize.
- [ ] Where pruning decisions live (plan vs execution) and which `EXPLAIN`
      variant proves it.
- [ ] What PREWHERE saves on a wide row like `otel_logs`, in terms of columns
      read.
- [ ] One real `Parts/Granules` line and what it cannot tell you about final
      latency.
- [ ] Why `system.query_log` on one replica can be silent about a query you
      definitely ran.

## Related documentation

- [Schema and queries](../schema-and-queries.md) — the hands-on pruning skill on these tables
- [ClickHouse fundamentals — query layer](../fundamentals.md#query-layer-short)
- [ClickHouse in this platform](01-architecture.md) — why exactly one replica runs your query
- Next: [MergeTree layout](03-mergetree.md) — why sorted granules make this pruning possible

## References

- [Understanding query execution with the analyzer](https://clickhouse.com/docs/guides/clickhouse/performance-and-monitoring/understanding-query-execution-with-the-analyzer)
- [Query parallelism](https://clickhouse.com/docs/concepts/core-concepts/query-parallelism)
- [EXPLAIN statement](https://clickhouse.com/docs/reference/statements/explain)
- [PREWHERE clause](https://clickhouse.com/docs/reference/statements/select/prewhere)
- [system.query_log](https://clickhouse.com/docs/reference/system-tables/query_log)
- [Architecture overview](https://clickhouse.com/docs/resources/develop-contribute/introduction/architecture)

---
_Last updated: 2026-09-29 — first published version of the query-pipeline chapter; live lab pending verification._
