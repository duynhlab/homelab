# MergeTree layout — why analytical reads stay fast

`Granules: 39/7578` in an `EXPLAIN` is the payoff of a physical layout decided
long before the query existed; this chapter opens a data part on disk and shows
the files that make skipping 7,539 granules possible — and why the same layout
makes some filters on `otel_logs` unable to skip much at all.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Practitioner |
| **Prerequisites** | [Query pipeline](02-query-pipeline.md) — where pruning numbers come from |
| **Deployment status** | Deployed |
| **Platform scope** | `otel.otel_logs` and `otel.otel_traces` on cluster `otel` |
| **Evidence context** | Live Kind cluster `kind-homelab`, 2026-09-30 11:20 UTC, ClickHouse 26.7.17.7 — read-only lab below; other rows are labelled by evidence class |
| **This page owns** | How MergeTree organizes data on disk so analytical reads are fast |
| **Not this page** | How parts are born and merged over time — [Parts and merges](04-parts-and-merges.md); choosing/tuning keys — [Schema and queries](../schema-and-queries.md) |
| **Previous / next** | [Query pipeline](02-query-pipeline.md) / [Parts and merges](04-parts-and-merges.md) |

## Questions this chapter answers

- Which files exist inside one data part, and what does each contribute to a read?
- How does a mark turn "granule 644" into a byte offset inside a compressed column file?
- When can the engine binary-search the primary index, and when must it fall back to generic exclusion?
- What does a skip index's `GRANULARITY` mean, and why do the deployed text indexes use 100,000,000?

## Mental model

A MergeTree table is not one big file. It is a set of immutable **parts**;
each part is a directory holding the same rows in three synchronized views:

1. **Column data** — every column's values, in sort order, compressed.
2. **A sparse primary index** — one entry per **granule** (8,192 rows here),
   recording the sort-key values at the granule's first row.
3. **Marks** — per column, the file offset where each granule starts.

Think of a part as a phone book sorted by (city, surname): the index page at
the front lists the first entry of every 8,192-entry range. To find "LONDON,
SMITH" you scan the *index page* (tiny), pick the ranges that could contain it,
and open the book only there. The analogy breaks on one point: the phone book
is one volume, but each column lives in its own compressed file, so "opening
the book" happens per column — this is why reading two columns of a 25-column
log row costs a fraction of the row width.

Sorting is what makes the sparse index sufficient: within a part, rows are
physically ordered by the table's sorting key, so each index entry bounds an
entire range. Unsorted data would need an entry per row — a dense index — and
that is exactly what MergeTree avoids.

### Essential terms

| Term | Meaning here |
|---|---|
| `granule` | The smallest range the index addresses, 8,192 rows on these tables (see the [shared glossary](README.md#shared-glossary)) |
| `mark` | A per-column entry mapping granule *n* → byte offsets in that column's files |
| `sorting key` | The `ORDER BY` tuple that fixes physical row order inside every part |
| `part_type` | `Wide` (file per column) or `Compact` (all columns in one file) |
| `skip index` | A secondary index that can only *exclude* granule blocks, never locate rows |

## How it works internally

### Invariants

- Rows inside a part are always physically sorted by the sorting key; a part
  is never partially sorted. *(Upstream invariant —
  [MergeTree engine](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree).)*
- The primary index is sparse: one entry per granule, loaded in memory;
  it selects granule *ranges*, never rows
  ([architecture overview](https://clickhouse.com/docs/resources/develop-contribute/introduction/architecture)).
  *(Upstream invariant.)*
- Marks are the only bridge between "granule number" and "byte offset";
  column files are unreadable positionally without them. *(Upstream invariant.)*
- The layout guarantees reads can *skip*; it does not guarantee any particular
  filter *will* skip — that depends on how the filter relates to the sort
  order (below).

### Inside one part directory

For a `Wide` part of `otel_logs`, the directory (named as
[chapter 04](04-parts-and-merges.md) explains) contains:

| File | Role in a read |
|---|---|
| `primary.idx` | The sparse index: sort-key values at each granule boundary, kept in memory |
| `{Column}.bin` | One compressed file per column, values in sort order |
| `{Column}.cmrk3` / `.mrk3` | That column's marks: per granule, the offset of its compressed block and the offset inside the decompressed block |
| `checksums.txt` | Integrity manifest of every file (what `CHECK TABLE` verifies) |
| `columns.txt` | The column list and types this part was written with |
| `count.txt` | Row count — how `count()` with no filter answers without touching data |
| `partition.dat`, `minmax_{col}.idx` | The partition value and min/max of the partition column, used to skip whole parts |
| `skp_idx_{name}.*` | Skip-index data and marks, one set per declared `INDEX` |

*(Upstream invariants — [MergeTree data storage](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree);
the primary-index file location is visible via `system.parts.path`
([sparse primary indexes guide](https://clickhouse.com/docs/guides/clickhouse/data-modelling/sparse-primary-indexes)).)*

A **Compact** part stores all columns in one `data.bin` with one shared marks
file instead — chosen automatically for small parts (below
`min_bytes_for_wide_part`, default 10,485,760 bytes) because a fresh insert of
a few hundred rows does not deserve 60+ files. Fresh telemetry inserts
therefore usually begin life Compact and become Wide through merges
([chapter 04](04-parts-and-merges.md)). *(Upstream invariant — same source.)*

### From granule number to bytes: the mark dance

A read that survived pruning ("granules 644–682 of part X, columns
`ServiceName`, `Body`") proceeds per column:

1. Open that column's marks file at entry 644.
2. The mark gives two numbers: the offset of the compressed block in `.bin`
   that contains the granule's first row, and the row's offset inside the
   decompressed block (granules and compression blocks do not align 1:1).
3. Seek, decompress that block, skip to the in-block offset, stream 8,192 rows,
   continue sequentially to granule 682.

This two-level addressing is why compression does not break random access:
compression works on blocks, marks remember both coordinates. It is also why
each extra column in a SELECT has a real, linear cost — its own seeks, its own
decompression — and why PREWHERE ([chapter 02](02-query-pipeline.md)) reads
filter columns first.

### Binary search vs generic exclusion — the deployed keys as the worked example

The sorting keys in the deployed DDL *(Repository facts —
[otel_logs](https://github.com/duynhlab/images/blob/main/images/clickhouse-ddl/sql/10-otel_logs.sql),
[otel_traces](https://github.com/duynhlab/images/blob/main/images/clickhouse-ddl/sql/20-otel_traces.sql))*:

```sql
-- otel_logs
ORDER BY (toStartOfFiveMinutes(Timestamp), ServiceName, Timestamp)
-- otel_traces
ORDER BY (ServiceName, SpanName, toDateTime(Timestamp))
```

How the index is searched depends on whether the filter constrains a **prefix**
of that tuple
([sparse primary indexes guide](https://clickhouse.com/docs/guides/clickhouse/data-modelling/sparse-primary-indexes)):

- **Prefix constrained → binary search.** A traces filter
  `ServiceName = 'cart-service'` binary-searches `primary.idx` — the first key
  column is globally sorted within the part, so the matching granules form one
  contiguous range found in ~log₂(marks) steps.
- **Prefix skipped → generic exclusion.** A logs filter on bare `ServiceName`
  cannot binary-search: `ServiceName` order restarts inside every 5-minute
  bucket. The engine walks index entries and asks, per granule range, "could
  this value occur here?" — excluding a range only when the *bucket* value
  proves it. With many 5-minute buckets per day, most ranges survive. This is
  the mechanism behind the measured poor pruning documented in
  [Schema and queries](../schema-and-queries.md) and the
  [platform hub](../README.md#query-examples); it works well only when the
  preceding key column is low-cardinality.

Neither search reads column data — both consume only the in-memory
`primary.idx`. The price of generic exclusion is paid twice: more index steps
now, more surviving granules to read next.

### Skip indexes: exclusion at a coarser grain

A skip index summarizes **blocks of `GRANULARITY` × 8,192 rows** and can only
say "this block cannot match — skip it"
([skip indexes](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree)).
The deployed choices *(Repository facts — DDL above)*:

- `otel_traces`: `bloom_filter(0.001)` on `TraceId`, `bloom_filter(0.01)` on
  attribute map keys/values, `minmax` on `Duration` — all `GRANULARITY 1`,
  i.e. one summary per granule: fine-grained exclusion for point lookups
  (trace ID) and range filters (duration).
- `otel_logs`: eight `text(...)` indexes with `GRANULARITY 100000000`. That
  number is the text index's documented "infinite" granularity — one inverted
  index over the *whole part*
  ([text indexes](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/textindexes)).
  A token query consults the part-level token index instead of scanning
  `Body` bytes; it is part-level token lookup, not per-granule exclusion.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Granule size | `index_granularity = 8192` on both tables | [DDL](https://github.com/duynhlab/images/blob/main/images/clickhouse-ddl/sql/10-otel_logs.sql) `SETTINGS` | Repository fact |
| Sorting keys | Logs: 5-minute bucket → service → time; traces: service → span → time | DDL `ORDER BY` | Repository fact |
| Why these keys | Time-window dashboards prune logs by prefix; per-service trace search prunes traces by prefix; trade-offs analyzed | [Schema and queries](../schema-and-queries.md) | Repository fact |
| Part-level skipping before the index | `PARTITION BY toDate(Timestamp)` — daily parts, min/max checked first | DDL; lifecycle owned by [chapter 04](04-parts-and-merges.md) | Repository fact |
| Compression in `.bin` files | `ZSTD(1)` everywhere; `Delta(8), ZSTD(1)` on `Timestamp` | DDL codecs; sizing discussion in [platform hub](../README.md#retention--compression) | Repository fact |
| Skip indexes | Traces: bloom + minmax, `GRANULARITY 1`; logs: 8 × `text`, part-level | DDL `INDEX` clauses | Repository fact |
| Wide vs compact threshold | Not set in DDL — server default (`min_bytes_for_wide_part` = 10,485,760) applies | Absence in [DDL](https://github.com/duynhlab/images/blob/main/images/clickhouse-ddl/sql/10-otel_logs.sql); [MergeTree reference](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree) | Inference — the default is upstream-documented; confirm live via `system.parts.part_type` |

Note what is *absent*: no projections, no sampling key, no explicit
`min_bytes_for_wide_part`. The schema leans on the two mechanisms this page
explains — sort order and skip summaries — and nothing else.

## Observe it on the live cluster

### Prerequisites and safety

- Use the [secure ClickHouse client pattern](../operations.md#secure-client-pattern).
- Confirm the current context and the replica you will query — `system.parts`
  is replica-local.
- Run only the read-only commands shown below.

### Query

The physical anatomy of the largest active logs parts — rows, granules
(≈ marks), format, and index size actually held in memory:

```sql
SELECT
    name,
    part_type,
    rows,
    marks,
    round(rows / marks) AS avg_rows_per_granule,
    formatReadableSize(bytes_on_disk) AS on_disk,
    formatReadableSize(primary_key_bytes_in_memory) AS pk_in_memory,
    disk_name
FROM system.parts
WHERE database = 'otel'
  AND table = 'otel_logs'
  AND active
ORDER BY rows DESC
LIMIT 5;
```

The declared skip indexes as the engine sees them, with their granularity:

```sql
SELECT
    table,
    name,
    type_full,
    expr,
    granularity
FROM system.data_skipping_indices
WHERE database = 'otel'
ORDER BY table, name
LIMIT 20;
```

### Observed example

```text
name                   part_type  rows     marks  avg_rows_per_granule  on_disk     pk_in_memory
20260930_0_2977_18     Wide       1374649  180    7637                  103.21 MiB  2.46 KiB
20260930_2978_5708_18  Wide       1201717  158    7606                  91.19 MiB   2.19 KiB
20260930_6181_6861_16  Wide       304614   41     7430                  23.49 MiB   698.00 B
20260930_5709_6180_16  Wide       214208   30     7140                  16.51 MiB   540.00 B
20260930_6862_7053_14  Wide       87716    12     7310                  6.94 MiB    236.00 B
(all on disk `default`)

table                    name                type_full                            granularity
otel_logs                idx_log_attr_key    text(tokenizer = 'array')            100000000
otel_logs                idx_lower_body      text(tokenizer = 'splitByNonAlpha')  100000000
… 8 text indexes on otel_logs, all 100000000
otel_traces              idx_duration        minmax                               1
otel_traces              idx_trace_id        bloom_filter(0.001)                  1
… 5 bloom_filter(0.01) indexes on otel_traces / otel_traces_trace_id_ts, all 1
```

Observation context:

| Field | Value |
|---|---|
| **Observed at** | 2026-09-30 11:20 UTC |
| **Repository** | `docs/clickhouse-internals-chapters` at `423a1c04` (main merged at `f326a367`) |
| **Cluster/context** | `kind-homelab` — Kind 1.35.8, cluster rebuilt 2026-09-30 ≈02:10 UTC |
| **ClickHouse** | `26.7.17.7` (image tag `clickhouse/clickhouse-server:26.7`); Keeper `v26.7.17.7-stable` |
| **Database/table** | `otel.otel_logs` (parts); `otel.*` (skip indexes) |
| **Replica** | `chi-clickhouse-otel-0-0-0` |

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `marks` ≈ `rows / 8192` (+1 boundary mark) | The sparse index really is ~1/8192 the density of the data | Mark count says nothing about how many marks a given query will *select* |
| `part_type` | `Wide` = file per column; `Compact` = single data file — expect Wide for large merged parts, Compact possible for fresh small ones | One snapshot cannot show the Compact→Wide transition; that is merge history ([chapter 04](04-parts-and-merges.md)) |
| `pk_in_memory` vs `on_disk` | The memory cost of pruning: kilobytes of index guarding gigabytes of data | In-memory index size does not bound query memory — that is execution ([chapter 02](02-query-pipeline.md)) |
| `granularity` in `data_skipping_indices` | 1 on the traces indexes (per-granule summaries); 100000000 on the logs text indexes (whole-part token index) | Presence of an index proves nothing about use — only `EXPLAIN indexes = 1` shows whether a query consulted it |
| `disk_name` | Which tier holds the part now (`default` hot, or the cold tier) | Placement is TTL lifecycle, owned by [chapter 10](10-storage-s3.md) |

### What to notice

- Every number here (part names, rows, sizes) is an observed example from one
  replica at one moment; merges may replace the parts minutes later.
- `avg_rows_per_granule` ≈ 8192 confirms the DDL setting made it to disk —
  the one stable relationship in an otherwise churning listing.
- The same query against `otel_traces` shows the same anatomy under a
  different sort key: the mechanism is table-independent, the pruning behavior
  is not.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Filter skips the sort-key prefix | Generic exclusion keeps most granules | Slow query, high `read_rows`, correct results | `EXPLAIN indexes = 1` granule ratio | Query rewrite, not recovery — [Schema and queries](../schema-and-queries.md) *(Repository fact — measured)* |
| Needle-in-haystack on an unindexed column (e.g. a `LogAttributes` value without token match) | No structure can exclude anything; full column scan of surviving partitions | Seconds-to-minutes latency | Same `EXPLAIN`; `read_bytes` | The layout's honest limit: sorted ≠ indexed on everything *(Upstream invariant)* |
| Corrupted file inside a part | Checksums mismatch on read; the broken part is detected | Query error naming the part | `CHECK TABLE` result; `system.parts` | Re-fetch from a healthy replica — replication ([chapter 05](05-replication.md)) is the repair path here *(Upstream invariant)* |
| Skip-index bloat (high-cardinality tokens) | Index files grow; each insert/merge pays index build cost | Larger parts, slower merges — not faster queries | `secondary_indices_*` columns in `system.parts` | Indexes are paid on write and only *sometimes* redeemed on read *(Upstream invariant)* |

The invariant that survives every row above: reads are never *wrong* because
pruning failed — exclusion errs only toward reading more. What is not
guaranteed is that the layout helps your particular filter; MergeTree
optimizes for filters that respect its sort order.

## Misconceptions and challenge questions

### "The primary index locates rows"

It locates *granule ranges* — 8,192-row neighborhoods. After index analysis,
the engine still reads and filters whole granules; a one-row lookup reads at
least one granule per surviving range. This is the sparse/dense trade:
row-precision indexes (OLTP B-trees) cost memory and write amplification that
a telemetry firehose cannot afford. *(Upstream invariant —
[sparse primary indexes](https://clickhouse.com/docs/guides/clickhouse/data-modelling/sparse-primary-indexes).)*

### "Adding a skip index on `ServiceName` would fix the logs pruning problem"

The poor pruning comes from `ServiceName` sitting *behind* the 5-minute bucket
in the sort order — a positional fact. A per-granule skip summary on a value
that appears in nearly every granule (every active service logs in most
5-minute windows) excludes almost nothing; the deployed schema instead treats
service-first querying as the *traces* table's job, whose sort key leads with
`ServiceName`. *(Inference from the DDL and the measured behavior in
[Schema and queries](../schema-and-queries.md).)*

### Challenge: `otel_traces` has `bloom_filter(0.001)` on `TraceId` at `GRANULARITY 1`. A trace-ID lookup still reports reading ~30 granules across 6 parts, not 1–2. Why is that expected, and which two files answered the query before any `.bin` was touched?

**Model answer:** Expected because (a) spans of one trace spread across time
and arrive in different inserts, so several parts hold matches, and (b) a
bloom filter only *excludes* granules — false positives at 0.001 plus genuine
multi-granule spread leave a handful of survivors per part; it cannot point at
rows. Before any `.bin`: `primary.idx` (sort-key range analysis) and
`skp_idx_idx_trace_id.*` (bloom exclusion) — both index structures, per part.
The trace-ID *fast path* actually deployed for Grafana is different again: the
materialized-view lookup table, owned by [chapter 09](09-materialized-views.md).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The three synchronized views inside a part (data, sparse index, marks)
      and the file that carries each.
- [ ] How a mark bridges granule number → bytes, and why compression doesn't
      break seeking.
- [ ] When index analysis binary-searches vs generic-excludes, using both
      deployed `ORDER BY` tuples as examples.
- [ ] One real `system.parts` row: what `marks`, `part_type`, and
      `pk_in_memory` each prove — and one thing each cannot prove.
- [ ] The write-side price of the eight text indexes on `otel_logs`.

## Related documentation

- [Schema and queries](../schema-and-queries.md) — applying this to real query tuning
- [ClickHouse fundamentals — MergeTree section](../fundamentals.md#mergetree-parts-partitions-merges-sparse-index)
- [Parts, merges, partitions, and TTL](../parts-merges-and-ttl.md) — the platform lifecycle page
- Next: [Parts and merges](04-parts-and-merges.md) — how these directories are born, named, and replaced

## References

- [MergeTree table engine](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree)
- [A practical introduction to sparse primary indexes](https://clickhouse.com/docs/guides/clickhouse/data-modelling/sparse-primary-indexes)
- [Full-text search with text indexes](https://clickhouse.com/docs/reference/engines/table-engines/mergetree-family/textindexes)
- [mergeTreeIndex table function](https://clickhouse.com/docs/reference/functions/table-functions/mergeTreeIndex)
- [Architecture overview — MergeTree](https://clickhouse.com/docs/resources/develop-contribute/introduction/architecture)

---
_Last updated: 2026-10-01 — DDL links point at the duynhlab/images repository. Earlier: 2026-09-30 — live lab verified: part anatomy (~7,600 rows per granule) and skip-index granularities. Earlier: 2026-09-29 — first published version of the MergeTree layout chapter; live lab pending verification._
