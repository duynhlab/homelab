# Partitioning and retention — what partitioning buys and costs

Deleting a million expired rows writes a million tombstones; dropping a
partition writes almost nothing. This chapter explains when PostgreSQL's
declarative partitioning earns that shortcut, how pruning works at plan and
execution time, and why this platform deliberately runs zero partitioned
application tables today.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Practitioner — partition mechanics and the retention trade |
| **Prerequisites** | [Indexes and access methods](09-indexes-and-access-methods.md); [Schema and integrity](10-schema-and-integrity.md) |
| **Deployment status** | Reference — not deployed: no service migration declares a partitioned table |
| **Platform scope** | All CNPG clusters; retention on this platform lives in ClickHouse TTLs, not PostgreSQL partitions |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | Declarative partitioning, plan-time vs execution-time pruning, attach/detach locking, the retention workflow |
| **Not this page** | Constraint rules in general — [Schema and integrity](10-schema-and-integrity.md); ClickHouse partition lifecycle — [Parts, merges, partitions, and TTL](../../observability/clickhouse/parts-merges-and-ttl.md) |
| **Previous / next** | [Schema and integrity](10-schema-and-integrity.md) / [Replication and slots](12-replication-and-slots.md) |

## Questions this chapter answers

- What does the planner have to prove before it can skip a partition, and when
  can that proof only happen at execution time?
- Which locks do `CREATE ... PARTITION OF`, `ATTACH`, `DETACH`, and
  `DETACH CONCURRENTLY` take on the parent?
- Why must a unique constraint on a partitioned table include the partition
  key?
- When is partition-drop retention cheaper than `DELETE`, and what does it
  still require operationally?
- Why does this platform have no partitioned application table, and what
  evidence would justify one?

## Mental model

A partitioned table is a router with no storage of its own: rows land in child
tables by key ranges, lists, or hashes, and a query against the parent fans
out to children — unless the planner can *prove* from the predicate and the
partition bounds that a child cannot contain matching rows, in which case that
child is pruned from the plan entirely.

Think of an archive room with one drawer per month: a request for "March
receipts" opens one drawer, and "shred everything older than two years" removes
whole drawers unopened. The analogy stops at uniqueness — drawers cannot
prove that a receipt number is unique across the room, and neither can
PostgreSQL without the partition key inside the unique index.

### Essential terms

| Term | Meaning here |
|---|---|
| `partition bound` | The range/list/hash slice a child owns, stored in the catalog and readable via `pg_get_expr(relpartbound, oid)` |
| `pruning` | Removing children from a plan (or skipping them at runtime) because their bounds cannot satisfy the predicate |
| `partition-wise` | Planning joins or aggregates child-by-child when both sides share compatible partitioning (`enable_partitionwise_join`/`_aggregate`) |
| `DETACH CONCURRENTLY` | The two-transaction detach that avoids blocking the parent, at the cost of restrictions and a possible `FINALIZE` step |
| `default partition` | The catch-all child for unmatched keys; it weakens pruning and complicates attach proofs |

## How it works internally

### Invariants

- A row lives in exactly one leaf partition, chosen by the partition key at
  write time; the parent stores nothing. (Upstream invariant —
  [table partitioning](https://www.postgresql.org/docs/18/ddl-partitioning.html).)
- Pruning is a proof over declared bounds, never a guess: a pruned partition
  cannot have contained a matching row. Wrapping the key in an expression the
  planner cannot analyze forfeits the proof and scans every child.
- Uniqueness is enforced per child index; a global guarantee exists only when
  the partition key is part of the constraint, so equal keys cannot land in
  different children. (Upstream invariant —
  [CREATE TABLE](https://www.postgresql.org/docs/18/sql-createtable.html).)
- Detaching or dropping a partition removes its rows from the parent's view
  atomically — but it is DDL with lock and dependency consequences, never a
  routine data operation.

### Lifecycle or sequence

**Pruning happens at up to three moments** (upstream invariant —
[partition pruning](https://www.postgresql.org/docs/18/ddl-partitioning.html)):

1. **Plan time.** Constant predicates on the key are compared against bounds;
   pruned children never appear in `EXPLAIN` output.
2. **Executor initialization.** Parameter values known at startup (for
   example a `PREPARE` parameter) prune subplans — visible as
   `Subplans Removed` in `EXPLAIN`; note those children are still locked.
3. **Execution.** Values produced mid-query (subquery results, parameterized
   nested-loop inner sides) prune per iteration — visible as
   `(never executed)` subplans in `EXPLAIN ANALYZE`.

`enable_partition_pruning` (default on) governs all of it; partition-wise
join and aggregate are separate opt-in settings because their planning cost
grows with child count.

**Lifecycle DDL and its locks** (upstream invariant —
[partitioning maintenance](https://www.postgresql.org/docs/18/ddl-partitioning.html)):

| Operation | Lock on parent | Notes |
|---|---|---|
| `CREATE TABLE ... PARTITION OF` | `ACCESS EXCLUSIVE` | Blocks everything; prefer create-then-attach |
| `ATTACH PARTITION` | `SHARE UPDATE EXCLUSIVE` | A matching `CHECK` constraint on the incoming table lets PostgreSQL skip the validation scan |
| `DETACH PARTITION` | `ACCESS EXCLUSIVE` | The blocking form |
| `DETACH PARTITION CONCURRENTLY` | `SHARE UPDATE EXCLUSIVE` | Two transactions; cannot run inside a transaction block; an interrupted run leaves a detach to `FINALIZE` |
| `DROP TABLE child` | `ACCESS EXCLUSIVE` | The cheapest possible retention delete |

**The retention trade.** `DELETE` writes a dead-tuple version per row
([chapter 05](05-mvcc-and-snapshots.md)), WAL per row
([chapter 04](04-wal-and-checkpoints.md)), and hands vacuum the cleanup
([chapter 07](07-vacuum-and-freezing.md)). Dropping a child skips all three —
which is only possible when expired rows occupy *complete* children, i.e. the
partition grain was chosen from the retention interval in the first place. The
absorbed page's workflow still governs: prove the bounds, check legal and
downstream dependencies, verify backups, detach first when an archive window
is needed.

### What to notice

- Pruning quality is a schema property (bounds + honest predicates), not a
  tuning knob.
- The grain decision couples three rhythms — ingest volume, query windows, and
  the retention drop interval; thousands of tiny children buy planning cost,
  lock lists, and monitoring noise for pruning you may never need.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Declarative partitioning | No service migration declares `PARTITION BY`; no partitioned application table exists in any of the ten service repositories | service-repo SQL migrations (checked 2026-09-29); schema ownership per the [databases hub](../README.md) | Repository fact |
| Partition-drop retention | Not used in PostgreSQL here; bulk time-based retention on this platform is ClickHouse's job (`ttl_only_drop_parts` dropping whole daily parts) | [ClickHouse parts, merges, partitions, and TTL](../../observability/clickhouse/parts-merges-and-ttl.md) | Repository fact |
| Pruning settings | `enable_partition_pruning` left at default on; partition-wise join/aggregate not configured | [`instance.yaml` GUC block](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) has no partition settings | Repository fact |
| Per-table size visibility | `pg_table_size` exporter rows would surface a partition census automatically if one appeared | [`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |

The contrast is deliberate and worth internalizing: the platform's
high-volume, time-expiring data (logs, traces) lives in ClickHouse where
partition-drop is the native TTL mechanism; the PostgreSQL side holds
transactional service data with row-level lifecycles. A future partitioned
table here would need the evidence in the failure table below, not a habit
imported from the OLAP side.

## Observe it on the live cluster

This lab takes a partition census. On this platform the expected result is
**empty** — that emptiness is the observation, proving the repository fact
above against the live catalog.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; never through PgDog.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Connect to one application database (for example `product`); confirm pod and
  role first.
- Run only the read-only commands shown below.

### Query

Partitioned-table census:

```sql
SELECT
    c.oid::regclass AS partitioned_table,
    p.partstrat,
    p.partnatts
FROM pg_partitioned_table AS p
JOIN pg_class AS c ON c.oid = p.partrelid
ORDER BY c.oid::regclass::text
LIMIT 20;
```

Inheritance edges (partitions and any legacy inheritance), with bounds:

```sql
SELECT
    parent.relname AS parent,
    child.relname AS child,
    pg_get_expr(child.relpartbound, child.oid) AS bounds
FROM pg_inherits
JOIN pg_class AS parent ON parent.oid = inhparent
JOIN pg_class AS child ON child.oid = inhrelid
JOIN pg_namespace AS nsp ON nsp.oid = parent.relnamespace
WHERE nsp.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY parent.relname, child.relname
LIMIT 50;
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
| Zero rows from `pg_partitioned_table` | No declarative partitioning in this database at observation time — the live catalog agrees with the repository fact | Nothing about other databases on the cluster; each needs its own census |
| `partstrat` (`r`/`l`/`h`) | Range, list, or hash routing, should a row appear | Not whether the grain fits the workload |
| `relpartbound` expression | The exact slice a child owns — the input to every pruning proof | Not that queries actually prune; only `EXPLAIN` shows that |
| Rows in `pg_inherits` without `relpartbound` | Legacy inheritance, not declarative partitioning — pruned only by constraint exclusion at plan time | — |

### What to notice

- An empty census is a real, citable observation — record its context like any
  other evidence.
- If a partitioned table ever appears here, this chapter's plan-vs-execution
  pruning section becomes testable with `EXPLAIN` on a key-bounded predicate;
  the census query is deliberately reusable for that day.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Predicate wraps the partition key in an unanalyzable expression | No pruning proof; all children planned and scanned | A "partitioned for speed" table performs like one big table plus overhead | `EXPLAIN` listing every child | Rewrite predicates against the raw key; pruning is contract, not magic |
| Grain too fine (for example daily for years) | Thousands of relations: planning time, locks at executor init, catalog and autovacuum load | Slow planning, noisy monitoring, long lock lists | Child count from the census query; planning time in `EXPLAIN` | Re-grain via attach/detach migrations — expensive after the fact |
| Default partition accumulating unmatched keys | Catch-all grows without bounds and blocks attach proofs | Retention cannot drop cleanly; attaches validate against the default | Default-partition size vs siblings | Backfill proper children; avoid a default unless ingest truly needs it |
| `DETACH` without `CONCURRENTLY` in peak hours | `ACCESS EXCLUSIVE` on the parent | Every query on the table queues | Lock waits ([chapter 06](06-locking-and-wait-events.md)) | `DETACH CONCURRENTLY` — respecting its no-transaction-block rule and `FINALIZE` on interruption |
| Retention by `DELETE` on a table that could have been partitioned | Per-row dead tuples, WAL, vacuum debt | Bloat and lag spikes every retention run | Dead-tuple counters ([chapter 07](07-vacuum-and-freezing.md)); WAL rate | The cheap path required choosing the grain when the table was born — retro-partitioning a live table is a full migration |

Throughout these, correctness holds — pruning never drops a child that could
match, and detach is atomic. What is lost is the performance promise the
partitioning was bought for.

## Misconceptions and challenge questions

### “Partitioning makes queries faster”

Partitioning makes *pruned* queries faster and *lifecycle operations* cheap.
A query that does not constrain the partition key now pays fan-out over N
children plus per-child index descents — often slower than one well-indexed
table ([chapter 09](09-indexes-and-access-methods.md)). The honest statement:
partitioning trades general performance for key-bounded performance and
drawer-drop retention (upstream invariant —
[table partitioning](https://www.postgresql.org/docs/18/ddl-partitioning.html)).

### “We partition in ClickHouse, so the PostgreSQL tables should be partitioned too”

Different engines, different jobs. ClickHouse partitions immutable parts and
drops whole expired parts as its native TTL mechanism; this platform's
PostgreSQL tables hold mutable transactional state with row-level lifecycles,
where constraints, HOT updates, and vacuum do the work. Importing the OLAP
habit buys the costs in the failure table with none of the drop-retention
benefit until a real complete-range lifecycle exists (repository fact — see
[How homelab uses it](#how-homelab-uses-it)).

### Challenge: an audit-events table is projected to grow 5 GB/month with a hard 12-month retention and every query bounded to a time window — partition it?

**Model answer:** this is the textbook yes: monthly range partitions on the
event timestamp, matching grain to the retention interval, 13 children online,
retention = `DETACH CONCURRENTLY` then `DROP` after the archive window, every
query pruning to 1–2 children. The unique key must include the partition
column ([chapter 10](10-schema-and-integrity.md)). It remains a service-repo
migration with the operational checklist above — and the census lab is how you
verify it landed.

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The three moments pruning can happen and where each is visible in
      `EXPLAIN`.
- [ ] The lock difference between `DETACH` and `DETACH CONCURRENTLY`, and the
      `FINALIZE` caveat.
- [ ] Why a partitioned unique constraint must include the partition key.
- [ ] Why an empty `pg_partitioned_table` census on this platform is evidence,
      not a failed lab.
- [ ] The full cost side of the partition trade, in your own words.

## Related documentation

- [Schema and integrity](10-schema-and-integrity.md) — constraint and lock
  groundwork
- [Vacuum and freezing](07-vacuum-and-freezing.md) — what DELETE-based
  retention costs instead
- [ClickHouse parts, merges, partitions, and TTL](../../observability/clickhouse/parts-merges-and-ttl.md)
  — the platform's actual partition-drop retention, in its native engine
- [Replication and slots](12-replication-and-slots.md) — next chapter

## References

- [Table partitioning](https://www.postgresql.org/docs/18/ddl-partitioning.html)
- [CREATE TABLE — partitioning and unique constraints](https://www.postgresql.org/docs/18/sql-createtable.html)
- [Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html)

---
_Last updated: 2026-09-29 — first published chapter; absorbs the former
partitioning-and-retention page, adds the three-phase pruning model and
attach/detach lock mechanics, and records the deliberate zero-partitioned-table
state of this platform._
