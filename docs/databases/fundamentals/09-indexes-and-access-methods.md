# Indexes and access methods — how a B-tree finds and punishes you

An index is an alternative access path with a permanent write tax, not a
universal accelerator. This chapter explains how a B-tree descends, when
PostgreSQL 18 can skip through it, and why every index you add bills every
`INSERT` on `product-db` forever.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Practitioner — access-path mechanics behind the planner's choices |
| **Prerequisites** | [Storage, pages, and tuples](02-storage-pages-and-tuples.md); [Query processing](08-query-processing.md); glossary terms page, tuple |
| **Deployment status** | Deployed — every service schema on both operational clusters relies on B-tree constraint indexes |
| **Platform scope** | All CNPG clusters; index statistics exported by the monitoring ConfigMap |
| **Evidence context** | Live Kind cluster `kind-homelab`, 2026-10-01 02:43 UTC, PostgreSQL 18.1 — read-only lab below; other rows are labelled by evidence class |
| **This page owns** | B-tree descent, PG 18 skip scan, HOT interplay, index-only scans, write amplification, non-B-tree methods |
| **Not this page** | Planner cost pricing — [Query processing](08-query-processing.md); visibility-map maintenance — [Vacuum and freezing](07-vacuum-and-freezing.md) |
| **Previous / next** | [Query processing](08-query-processing.md) / [Schema and integrity](10-schema-and-integrity.md) |

## Questions this chapter answers

- How does a B-tree turn a predicate into a small set of leaf pages, and what
  does "Index Searches" in a plan count?
- Under what conditions can PostgreSQL 18 use a multicolumn index when the
  leading column has no predicate?
- When does an index-only scan still touch the heap, and which bit decides?
- Which UPDATEs skip index maintenance entirely, and why does that matter for
  write-heavy tables?
- When do GIN, BRIN, or hash beat a B-tree, and what do they cost?

## Mental model

A B-tree is a sorted, balanced tree of index tuples: internal pages route by
key ranges, leaf pages hold `(key, ctid)` pairs pointing at heap tuples
([chapter 02](02-storage-pages-and-tuples.md)). A lookup descends from the
root once per *search*, lands on a leaf, and walks sideways along linked leaf
pages for ranges.

The index is a phone book: sorted by name, each entry giving a street address
(the `ctid`). The analogy stops at visibility — a phone book never lists three
addresses for the same person, but a heap holds multiple row versions, and the
index points at all of them until vacuum cleans up
([chapter 07](07-vacuum-and-freezing.md)).

### Essential terms

| Term | Meaning here |
|---|---|
| `index tuple` | A `(key values, ctid)` entry in a leaf page; it carries no visibility information |
| `descent` | One root-to-leaf traversal; `EXPLAIN` reports these as "Index Searches" |
| `skip scan` | A PG 18 B-tree strategy that runs one descent per distinct leading-column value when the leading column has no predicate |
| `HOT update` | An UPDATE whose new tuple version stays on the same heap page and changes no indexed column, so no index entry is written |
| `operator class` | The set of operators an index can serve for a column type; it decides indexability, not the column type alone |

## How it works internally

### Invariants

- Index entries carry **no visibility**: every index hit must be checked
  against the heap tuple's `xmin`/`xmax` — unless the visibility map proves
  the whole heap page all-visible. (Upstream invariant —
  [index-only scans](https://www.postgresql.org/docs/18/indexes-index-only-scans.html).)
- A B-tree serves only the operators of its operator class (equality, range,
  prefix ordering); an expression index matches the indexed expression, not
  equivalent rewrites. (Upstream invariant —
  [index types](https://www.postgresql.org/docs/18/indexes-types.html).)
- Every non-HOT write to an indexed table writes every index. There is no
  partial exemption per statement — only per index via partial-index
  predicates.
- An index never makes a query wrong; it can only make the plan cheaper or
  more expensive than alternatives.

### Lifecycle or sequence

A B-tree equality lookup, in causal order:

1. **Descend.** Compare the key against the root page's separators, follow the
   child pointer, repeat to a leaf. Depth stays small — millions of keys fit
   in 3–4 levels of 8 KiB pages.
2. **Scan the leaf.** Binary-search the leaf, collect matching
   `(key, ctid)` entries; for ranges, follow the leaf sibling links.
3. **Visit the heap** (plain index scan). Fetch each `ctid`'s page via the
   buffer manager ([chapter 03](03-buffer-manager-and-io.md)) and test tuple
   visibility against the snapshot.
4. **Or skip the heap** (index-only scan). If the query needs only indexed
   columns, consult the visibility map first: an all-visible page needs no
   heap fetch; otherwise that tuple falls back to a heap check, counted as
   "Heap Fetches" in the plan. (Upstream invariant —
   [visibility map](https://www.postgresql.org/docs/18/storage-vm.html).)

**PG 18 skip scan.** Given an index on `(four, unique1)` and a predicate only
on `unique1`, PostgreSQL 18 can run one descent per distinct value of `four` —
`EXPLAIN` shows `Index Searches: N` where N tracks the distinct leading
values in range. It pays off when the leading column is low-cardinality
("no more than several hundred distinct values"); high-cardinality leading
columns degrade it toward a full index walk. (Upstream invariant —
[release 18](https://www.postgresql.org/docs/18/release-18.html),
[combining indexes](https://www.postgresql.org/docs/18/indexes-bitmap-scans.html),
[using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html).)

**Bitmap scans** sit between: multiple index scans build bitmaps of candidate
pages, AND/OR them, then visit the heap in physical order — trading precise
ordering for sequential heap access.

**Write side.** An `INSERT` adds one entry to every index. An `UPDATE`
normally deletes-and-inserts in every index too — unless it qualifies as
**HOT**: no indexed column changed and the new version fits on the same heap
page, in which case the heap chains the versions and no index is touched.
This is why fillfactor headroom and narrow indexes make write-heavy tables
cheaper ([chapter 02](02-storage-pages-and-tuples.md) owns page anatomy;
upstream invariant — [HOT](https://www.postgresql.org/docs/18/storage-hot.html)).

Non-B-tree methods, from the absorbed access-method table:

| Method | Good fit | Cost to respect |
|---|---|---|
| Hash | Equality only | Rarely beats B-tree; no ordering, no ranges |
| GIN | Arrays, JSONB containment, full-text tokens | Write amplification and pending-list flushes |
| GiST / SP-GiST | Ranges, geometry, nearest-neighbour; partitionable spaces | Operator-class semantics vary; check the class, not the type |
| BRIN | Very large, naturally ordered tables | Block-range summaries — page-level precision only |

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Index usage counters | `pg_stat_user_indexes` exported per database by the monitoring ConfigMap | [`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |
| Index scans priced vs heap correlation | `random_page_cost 1.1` makes index paths win earlier than upstream defaults | [`instance.yaml` planner block](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| Constraint indexes | Every service schema's PK/unique constraints are B-trees created by service-repo migrations against `-rw` | [application delivery](../../platform/application-delivery.md); service repos own DDL | Repository fact |
| Index build locking | `REINDEX` takes ACCESS EXCLUSIVE; `REINDEX CONCURRENTLY` avoids it at the cost of multiple passes | [Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html) | Upstream invariant |
| Skip scan | Available engine-wide on PG 18.1; no schema here is declared to depend on it | [Release 18](https://www.postgresql.org/docs/18/release-18.html) | Upstream invariant |

Index *design* is owned by service repositories; this platform observes index
cost and usage, it does not prescribe schemas (repository fact — boundary
stated in the [databases hub](../README.md)).

## Observe it on the live cluster

This lab reads index size/usage for one application database and confirms the
visibility-map dependency of index-only scans on a catalog query.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; never through PgDog.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Connect to one application database (for example `product`) for the first
  query; confirm pod and role first.
- Run only the read-only commands shown below.

### Query

Index inventory with usage, size, and definition:

```sql
SELECT
    s.schemaname,
    s.relname AS table_name,
    s.indexrelname AS index_name,
    s.idx_scan,
    pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
    i.indisunique,
    i.indisprimary
FROM pg_stat_user_indexes AS s
JOIN pg_index AS i ON i.indexrelid = s.indexrelid
ORDER BY pg_relation_size(s.indexrelid) DESC
LIMIT 25;
```

Index-only scan evidence on a stable catalog index (plain `EXPLAIN`, no
execution):

```sql
EXPLAIN (FORMAT TEXT)
SELECT relname
FROM pg_class
WHERE relname LIKE 'pg_stat%'
ORDER BY relname
LIMIT 10;
```

### Observed example

```text
-- product-db-1 (primary), database product
table_name          index_name               idx_scan  size   unique  primary
schema_migrations   schema_migrations_pkey   0         16 kB  t       t
categories          categories_pkey          151       16 kB  t       t
categories          categories_name_key      4         16 kB  t       f
categories          idx_categories_name      12        16 kB  f       f
products            products_pkey            65        16 kB  t       t
products            unique_product_name      13        16 kB  t       f
products            idx_products_name        0         16 kB  f       f
products            idx_products_category    0         16 kB  f       f
products            idx_products_price       0         16 kB  f       f
products            idx_products_created_at  2         16 kB  f       f
products            idx_products_status      25        16 kB  f       f
admin_action_audit  admin_action_audit_pkey  0         16 kB  t       t
admin_action_audit  idx_admin_audit_target   2         16 kB  f       f

Limit  (cost=0.27..4.58 rows=10 width=64)
  ->  Index Only Scan using pg_class_relname_nsp_index on pg_class
        Index Cond: ((relname >= 'pg'::text) AND (relname < 'ph'::text))
        Filter: (relname ~~ 'pg_stat%'::text)
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
| **Database** | `product` |

What this run showed:

- Thirteen B-tree indexes, each two pages (16 kB) on one-page tables. The index tax here is larger than the data.
- `categories_name_key` (unique constraint) and `idx_categories_name` index the same column twice. Five indexes show `idx_scan = 0` after 13 h. As the table below warns, zero is not proof they are droppable, and the standbys were not checked.
- The `LIKE 'pg_stat%'` predicate became an index range condition (`>= 'pg'` and `< 'ph'`) and an Index Only Scan. The prefix match is rewritten into B-tree bounds; this works because the catalog uses the `C` collation.

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `idx_scan` | Descents into this index since the stats reset on this instance | Not "safe to drop" at 0 — resets, seasonal queries, and constraint enforcement all hide behind a zero |
| `indisunique` / `indisprimary` | The index exists to enforce a constraint ([chapter 10](10-schema-and-integrity.md)) | Dropping it is a schema change, not an optimization |
| `index_size` vs table size | The permanent storage and cache tax of the access path | Not the write tax — that shows up in WAL and per-statement latency |
| `Index Only Scan` node | Planner expects to answer from the index | Not zero heap access — only `EXPLAIN ANALYZE`'s "Heap Fetches" shows how often the visibility map was insufficient |
| `Index Searches: N` (with ANALYZE) | Number of descents — >1 per loop reveals skip scan or `IN`-list searches | Not efficiency by itself; compare against buffers touched |

### What to notice

- Every number is an **observed example**; `idx_scan` is cumulative per
  instance and resets with the statistics system, so record the reset time
  ([chapter 14](14-monitoring-and-capacity.md)).
- Standbys serve reads too: an index unused on the primary may be earning its
  keep on a replica — check `pg_stat_user_indexes` on each instance before
  judging.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Index added "for safety" on a write-heavy table | Every non-HOT write now maintains one more index | Higher write latency, more WAL, larger backups, slower vacuum | WAL rate, `pg_stat_user_indexes.idx_scan` staying near 0 | Removal is a service-repo migration with the drop checklist from the absorbed page: constraints, replicas, full business cycle |
| Indexed-column update pattern | HOT disqualified — all indexes maintained per update | Write amplification on a "small" update | Heap-only vs regular update counters in `pg_stat_user_tables` | Schema/design change owned by the service repo |
| Visibility map decay under churn | Index-only scans degrade into heap fetches | "Covering" index stops covering; latency creeps | `Heap Fetches` in ANALYZE plans; VM bits are set only by vacuum | Vacuum cadence ([chapter 07](07-vacuum-and-freezing.md)) — not a new index |
| Skip scan on a high-cardinality leading column | One descent per distinct value | Index path chosen but slow — many searches | `Index Searches` far above expectations | Column-order redesign; skip scan is a rescue, not a design pattern |
| `REINDEX` without CONCURRENTLY | ACCESS EXCLUSIVE on the index's table | All reads and writes blocked for the build | Lock waits in `pg_locks` ([chapter 06](06-locking-and-wait-events.md)) | `REINDEX CONCURRENTLY` trades runtime and failure-cleanup complexity for availability |

The correctness invariant holds throughout: a missing, bloated, or ignored
index never changes results — only cost. What becomes unavailable under these
failures is predictable latency.

## Misconceptions and challenge questions

### “The index covers all the query's columns, so the heap is never touched”

Coverage is necessary, not sufficient. Index tuples carry no visibility, so
the executor still needs each heap page proven all-visible in the visibility
map; any page with recent churn forces a heap fetch. Vacuum sets those bits —
an index-only scan's performance is a vacuum outcome as much as an index
design (upstream invariant —
[index-only scans](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)).

### “PG 18 skip scan means column order in composite indexes no longer matters”

Skip scan makes a *low-cardinality* leading column survivable — one descent
per distinct value. With a high-cardinality leading column, "skipping" means
thousands of descents. Order columns for your dominant predicates; treat skip
scan as the engine rescuing the queries you did not design for (upstream
invariant — [combining indexes](https://www.postgresql.org/docs/18/indexes-bitmap-scans.html)).

### Challenge: a table takes 40% more time per UPDATE after a migration that "only added one index on a rarely-queried column"

**Model answer:** the new index disqualifies HOT for every UPDATE that touches
its column — and even untouched-column UPDATEs now pay one more index insert
whenever HOT fails for page-space reasons. Check the heap-only-update ratio in
`pg_stat_user_tables` before/after, and weigh the index's `idx_scan` against
the permanent write tax. The fix is a service-repo decision: drop, make
partial, or accept the cost.

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] A B-tree descent and what "Index Searches" counts in a plan.
- [ ] Where index tuples' visibility comes from, and which bit lets an
      index-only scan skip the heap.
- [ ] The exact two conditions for a HOT update and what they save.
- [ ] One `pg_stat_user_indexes` row and why `idx_scan = 0` cannot prove an
      index is droppable.
- [ ] When skip scan helps and when it quietly multiplies descents.

## Related documentation

- [Storage, pages, and tuples](02-storage-pages-and-tuples.md) — heap pages,
  `ctid`, and fillfactor behind HOT
- [Vacuum and freezing](07-vacuum-and-freezing.md) — who sets the visibility
  map bits
- [Query processing](08-query-processing.md) — how these paths get priced
- [Schema and integrity](10-schema-and-integrity.md) — constraint-backed
  indexes

## References

- [Indexes](https://www.postgresql.org/docs/18/indexes.html)
- [Index types](https://www.postgresql.org/docs/18/indexes-types.html)
- [Combining multiple indexes](https://www.postgresql.org/docs/18/indexes-bitmap-scans.html)
- [Index-only scans and covering indexes](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)
- [Visibility map](https://www.postgresql.org/docs/18/storage-vm.html)
- [Heap-only tuples](https://www.postgresql.org/docs/18/storage-hot.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)
