# Storage, pages, and tuples — where a row physically lives

`UPDATE products SET price = 9.99` does not change a row — it writes a new
tuple into an 8 KiB page inside a numbered file under `base/`, and everything
from vacuum to index-only scans follows from that fact.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Foundation — physical layout before any engine dynamics |
| **Prerequisites** | [Processes and memory](01-processes-and-memory.md); glossary terms page, tuple, TOAST |
| **Deployment status** | Deployed — the layout of every database on `platform-db` and `product-db` |
| **Platform scope** | On-disk anatomy; examples use the `product` database |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | The data directory, page, and tuple-header anatomy, and what `ctid`/`xmin`/`xmax` expose |
| **Not this page** | Which tuple versions a snapshot may *see* — [MVCC and snapshots](05-mvcc-and-snapshots.md); how pages reach RAM — [Buffer manager and I/O](03-buffer-manager-and-io.md) |
| **Previous / next** | [Processes and memory](01-processes-and-memory.md) / [Buffer manager and I/O](03-buffer-manager-and-io.md) |

## Questions this chapter answers

- Which file holds a given table, and when does that file split or multiply?
- What does an 8 KiB page contain besides rows, and why do line pointers exist?
- Which visibility metadata rides inside every tuple header?
- Where do oversized values go, and what triggers TOAST?
- Which parts of this anatomy can be inspected read-only on the shared
  cluster, and which need a disposable lab?

## Mental model

A database is a directory tree of plain files. Each table or index is one or
more files named by number, cut into fixed 8 KiB **pages**. A page is a small
self-describing container: a header, an array of **line pointers** growing
from the front, and the **tuples** themselves packed from the back. A row you
can `SELECT` is one tuple slot addressed as `(page number, line pointer)` —
that pair is the `ctid` you can read on any row.

Think of a page as a paper form: an index card of entries at the top (line
pointers), content written upward from the bottom (tuples), and free space in
the middle where the two fronts have not yet met. The analogy stops at
updates: on paper you would erase; PostgreSQL instead writes a *new* entry and
leaves the old one for [vacuum](07-vacuum-and-freezing.md) — the old version
stays physically present, invisible only by rules that
[MVCC](05-mvcc-and-snapshots.md) owns.

### Essential terms

| Term | Meaning here |
|---|---|
| `relfilenode` | The number naming a relation's files on disk; `pg_relation_filepath()` resolves it |
| `fork` | A parallel file for one relation: main data, free space map (`_fsm`), visibility map (`_vm`), init (`_init`) |
| `line pointer` | A 4-byte slot in the page's front array pointing at a tuple; `ctid` = (page, line pointer) |
| `pd_lower` / `pd_upper` | Page-header offsets marking the two edges of the free-space gap |
| `TOAST` | Compression and out-of-line storage engaged when a row exceeds roughly 2 kB |

## How it works internally

### Invariants

- A tuple never spans pages: a row wider than a page must shrink through
  TOAST before it can be stored. (Upstream invariant —
  [TOAST](https://www.postgresql.org/docs/18/storage-toast.html).)
- A line pointer, once allocated, keeps its index while the tuple it points to
  may move within the page — which is why a `ctid` stays usable across page
  compaction but not across an UPDATE. (Upstream invariant —
  [page layout](https://www.postgresql.org/docs/18/storage-page-layout.html).)
- Every page carries the LSN of the last WAL record that touched it
  (`pd_lsn`), tying physical storage to [WAL ordering](04-wal-and-checkpoints.md).
  (Upstream invariant.)
- No guarantee: file size does not track live data. Deleted tuples occupy
  space until vacuum, and files shrink only in limited cases.

### Lifecycle or sequence

From cluster to byte, top down:

1. **Data directory.** Each database is `base/<database OID>/`; a relation's
   files live there named by `relfilenode` (Upstream invariant —
   [file layout](https://www.postgresql.org/docs/18/storage-file-layout.html)).
   `SELECT pg_relation_filepath('products')` resolves the path.
2. **Segments.** Past 1 GB a relation continues in `<relfilenode>.1`, `.2`, …
   — a naming detail, not a structural boundary.
3. **Forks.** Beside the main fork sit `_fsm` (which pages have free space,
   consulted on INSERT) and `_vm` (which pages are all-visible/all-frozen —
   the bitmap that makes index-only scans and eager vacuum skipping possible;
   consumers in [07](07-vacuum-and-freezing.md) and
   [09](09-indexes-and-access-methods.md)).
4. **Page.** 24-byte header (`pd_lsn`, checksum — enabled here via
   `dataChecksums: true`, flags, `pd_lower`, `pd_upper`, `pd_special`,
   version, `pd_prune_xid`), then line pointers growing forward, free space,
   tuples growing backward, and an access-method "special" area that heaps
   leave empty (Upstream invariant —
   [page layout](https://www.postgresql.org/docs/18/storage-page-layout.html)).
5. **Tuple.** Each heap tuple starts with a header carrying `t_xmin` (the
   transaction that created it), `t_xmax` (the one that deleted or locked it,
   or 0), `t_ctid` (its own address — or, after an UPDATE, the address of its
   successor version), and infomask hint bits that cache commit knowledge.
   The user columns follow.
6. **TOAST.** When a candidate row exceeds `TOAST_TUPLE_THRESHOLD` (normally
   2 kB), wide values are compressed and, if needed, sliced into a side table
   (`pg_toast.pg_toast_<oid>`) until the row fits the target (~2 kB by
   default; Upstream invariant —
   [TOAST](https://www.postgresql.org/docs/18/storage-toast.html)). Unchanged
   TOASTed values are not rewritten on UPDATE.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Page checksums against silent corruption | `dataChecksums: true` at initdb on both operational clusters | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| One directory tree per instance | Each of the three instances holds its own full copy under a 10Gi PVC | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) (`storage`) · [architecture](../architecture.md) | Repository fact |
| Databases as `base/<oid>` subdirectories | Six service databases inside `product-db`, four inside `platform-db` | [architecture — database inventory](../architecture.md) | Repository fact |
| Table-size statistics feeding dashboards | The `pg_table_size` custom query exports per-table bytes | [`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |
| Byte-level page inspection | `pageinspect` is **not installed**; installing it would be DDL on the shared cluster | [Extensions](../extensions.md) · [safety boundary](README.md#observation-safety) | Repository fact |

The checksum choice is the quiet star: with `dataChecksums` on, every page
read can detect torn or bit-rotted storage instead of silently returning
garbage — the failure table below builds on it.

## Observe it on the live cluster

This lab resolves a real table to its file path, reads its page/tuple
statistics from the catalog, and exposes the tuple header columns every row
carries — all without `pageinspect`.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; never through PgDog
  or PgBouncer.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Confirm the kubeconfig context, the instance pod, and its role.
- Run only the read-only queries below.

### Query

```sql
SELECT
    c.relname,
    pg_relation_filepath(c.oid) AS file_path,
    c.relpages,
    c.reltuples,
    pg_relation_size(c.oid, 'main')  AS main_bytes,
    pg_relation_size(c.oid, 'fsm')   AS fsm_bytes,
    pg_relation_size(c.oid, 'vm')    AS vm_bytes,
    c.reltoastrelid <> 0             AS has_toast
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY pg_relation_size(c.oid, 'main') DESC
LIMIT 5;
```

```sql
SELECT
    ctid,
    xmin,
    xmax
FROM pg_class
ORDER BY ctid
LIMIT 5;
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
| `file_path` like `base/16384/16806` | Database OID directory + relfilenode — the literal file under `PGDATA` | Not stable identity: `TRUNCATE`, `VACUUM FULL`, and some ALTERs assign a new relfilenode |
| `relpages` × 8 KiB vs `main_bytes` | `relpages` is the planner's page count from the last VACUUM/ANALYZE; `main_bytes` is live file size | `relpages` freshness — it lags until maintenance runs (Upstream invariant — [disk usage](https://www.postgresql.org/docs/18/diskusage.html)) |
| `fsm_bytes`, `vm_bytes` > 0 | The relation has earned its side forks; tiny tables may show 0 | How *accurate* the maps are — only vacuum refreshes them |
| `ctid = (0,1)` | Page 0, line pointer 1 — the physical address of that row version | Anything after the next UPDATE: the row's next version gets a new `ctid` |
| `xmin`, `xmax` on a live row | The creating XID, and 0 (or a locker/deleter XID) — visibility raw material | Whether *your* snapshot sees it — that rule set is [chapter 05](05-mvcc-and-snapshots.md) |
| `has_toast` | A `pg_toast` side table exists for wide values | That any value is actually toasted today |

### What to notice

- Every number is an **observed example**: `relpages`, sizes, and `ctid`s move
  with workload and maintenance.
- Nothing here required superuser byte access. The gap between this lab and
  seeing actual page bytes (`page_header()`, `heap_page_items()`) is exactly
  the uninstalled `pageinspect` extension — run that part only in a
  **disposable lab**: a throwaway PostgreSQL 18 container where
  `CREATE EXTENSION pageinspect` harms nothing.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Torn page write (power cut mid-8 KiB) | On next read, checksum verification fails (`dataChecksums: true`) | I/O error naming a block; query aborts | Server log checksum failure; `pg_stat_database.checksum_failures` | Full-page images in WAL repair it on recovery ([04](04-wal-and-checkpoints.md)); a detected error beats silent corruption |
| Update-heavy table without vacuum keeping up | Dead tuples accumulate; pages fill with invisible versions | Table and index files grow though row count is flat | `pg_stat_user_tables` dead-tuple counters; [`CNPGAutovacuumFallingBehind`](../../observability/runbooks/postgresql/CNPGAutovacuumFallingBehind.md) | Space returns only via [vacuum](07-vacuum-and-freezing.md); file shrink needs the heavier paths described there |
| Rows near the 8 KiB boundary | TOAST compresses/off-loads on every write | Write amplification; slower wide-row churn | `has_toast`, TOAST relation sizes | Schema design decision — [10](10-schema-and-integrity.md) owns column-type trade-offs |
| 10Gi PVC filling (all forks + WAL share it) | Writes fail when the volume is full | `No space left on device`; instance crash-loops | PVC usage; [`CNPGClusterLowDiskSpaceWarning`](../../observability/runbooks/postgresql/CNPGClusterLowDiskSpaceWarning.md) | WAL and data compete on one volume here (no separate `walStorage`) — a storage-layout Repository fact worth remembering |

The durability invariant survives all four rows: committed data is
reconstructable from WAL and backups. What each failure costs is space,
latency, or one aborted query — not correctness.

## Misconceptions and challenge questions

### “An UPDATE modifies the row in place”

It writes a new tuple (new `ctid`), sets the old tuple's `t_xmax`, and points
the old header's `t_ctid` at the successor. Both versions coexist on disk
until vacuum. This single fact explains bloat, the visibility map, and why
[HOT updates](09-indexes-and-access-methods.md) matter for index cost.

### “`relpages` tells me the table's current size”

`relpages` is a planner statistic updated by VACUUM/ANALYZE and some DDL, not
live truth (Upstream invariant —
[disk usage](https://www.postgresql.org/docs/18/diskusage.html)).
`pg_relation_size()` reads the file system now. A big gap between them is
itself evidence: maintenance has not looked at that table recently.

### Challenge: same row count, file three times larger

Two weeks after launch, `orders` holds the same ~100k rows as day one, but its
main fork tripled. Name the mechanism and the two catalog signals that confirm
it.

**Model answer:** dead tuple accumulation from UPDATE/DELETE churn outpacing
autovacuum. Confirm with `pg_stat_user_tables.n_dead_tup` high relative to
`n_live_tup`, and `last_autovacuum` old or NULL — then continue in
[Vacuum and freezing](07-vacuum-and-freezing.md).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The path from database name to on-disk file, including forks and
  segments.
- [ ] What a page stores in its header, front array, and back region, and who
  owns the gap between.
- [ ] What `xmin`, `xmax`, and `ctid` on a real row mean, and which question
  they cannot answer alone.
- [ ] One observed lab row and the limit of what it proves.
- [ ] Why TOAST exists and when it activates.

## Related documentation

- [Databases architecture](../architecture.md) — clusters, PVCs, database
  inventory
- [Extensions](../extensions.md) — why `pageinspect` is absent here
- Previous: [Processes and memory](01-processes-and-memory.md) · Next:
  [Buffer manager and I/O](03-buffer-manager-and-io.md)

## References

- [PostgreSQL 18 — database file layout](https://www.postgresql.org/docs/18/storage-file-layout.html)
- [PostgreSQL 18 — database page layout](https://www.postgresql.org/docs/18/storage-page-layout.html)
- [PostgreSQL 18 — TOAST](https://www.postgresql.org/docs/18/storage-toast.html)
- [PostgreSQL 18 — determining disk usage](https://www.postgresql.org/docs/18/diskusage.html)
- [PostgreSQL 18 — `pageinspect`](https://www.postgresql.org/docs/18/pageinspect.html) (disposable lab only)

---
_Last updated: 2026-09-29 — chapter authored for issue #1137, absorbing the
storage half of the former storage-and-wal page; live lab pending
verification._
