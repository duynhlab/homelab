# Buffer manager and I/O — how pages travel between disk and RAM

The deployed clusters give PostgreSQL 256MB of shared buffers for databases
several times that size — so almost every performance question here eventually
becomes "was that page in the buffer pool, and if not, who read it and how?"

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Practitioner — the layer between files (02) and durability (04) |
| **Prerequisites** | [Storage, pages, and tuples](02-storage-pages-and-tuples.md); glossary term page |
| **Deployment status** | Deployed — every instance; PostgreSQL 18 AIO active with defaults |
| **Platform scope** | Shared buffers and the I/O paths of `platform-db` and `product-db` |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | Buffer lookup, pinning, eviction, ring buffers, the write-out division of labor, and the PG 18 asynchronous I/O subsystem |
| **Not this page** | WAL flush ordering — [WAL and checkpoints](04-wal-and-checkpoints.md); plan-level read strategies — [Query processing](08-query-processing.md) |
| **Previous / next** | [Storage, pages, and tuples](02-storage-pages-and-tuples.md) / [WAL and checkpoints](04-wal-and-checkpoints.md) |

## Questions this chapter answers

- What happens, step by step, when a backend needs a page that is not in
  shared buffers?
- Who writes dirty pages back — the backend, the background writer, or the
  checkpointer — and why does the answer matter?
- What changed in PostgreSQL 18 with asynchronous I/O, and what do
  `io_method`, `io_workers`, and `pg_aios` expose?
- Why do sequential scans and vacuum not flood the whole buffer pool?
- Which deployed evidence (`pg_stat_io`, the cache-hit alert) maps to which
  internal event?

## Mental model

Shared buffers is a fixed array of 8 KiB slots fronting the data files. Every
page a backend touches must sit in a slot first; a hash table maps
(relation, fork, block) → slot. Finding the page there is a **hit** — the
overwhelmingly common case the deployed
[`CNPGLowCacheHitRatio`](../../observability/runbooks/postgresql/CNPGLowCacheHitRatio.md)
alert watches. A miss means choosing a victim slot, evicting its page (writing
it first if dirty), and reading the wanted page in.

Two refinements make this workable at scale. First, **usage tracking**: a
clock-sweep algorithm gives every buffer a small usage count so hot pages
survive eviction. Second, **containment**: bulk work (large sequential scans,
vacuum) runs inside small **ring buffers**, private working sets that recycle
their own slots instead of evicting the whole pool.

PostgreSQL 18 changed *how* the bytes move: reads that used to be one blocking
`read()` per backend can now be queued as **asynchronous I/O** and executed by
dedicated I/O worker processes — the `io worker` rows you met in
[chapter 01](01-processes-and-memory.md). The kitchen analogy: backends are
cooks; before, each cook walked to the pantry personally; now cooks post
orders and three runners fetch in batches. The analogy stops at writes: the
AIO subsystem in 18 accelerates *reads* (sequential scans, bitmap scans,
vacuum), while write-back keeps its old division of labor.

### Essential terms

| Term | Meaning here |
|---|---|
| `buffer descriptor` | Per-slot metadata: which page, dirty flag, usage count, pin count |
| `pin` | A reference count that forbids evicting a slot while any backend uses it |
| `clock sweep` | Eviction scan that decrements usage counts and takes the first zero-count, unpinned buffer |
| `ring buffer` | A small private slot set for bulk reads/writes and vacuum, isolating them from the main pool |
| `io_method` | PG 18 server setting selecting how asynchronous-eligible I/O executes: `worker` (default), `io_uring`, or `sync` |

## How it works internally

### Invariants

- A pinned buffer is never evicted; a dirty buffer is never dropped without
  being written. (Upstream invariant —
  [resource settings](https://www.postgresql.org/docs/18/runtime-config-resource.html).)
- WAL-before-data: a dirty page cannot be written out before the WAL records
  describing its changes are flushed — the bridge to
  [chapter 04](04-wal-and-checkpoints.md). (Upstream invariant.)
- All table I/O goes through shared buffers; there is no direct-read fast path
  for ordinary heap access. (Upstream invariant.)
- No guarantee: a buffer hit is not "no I/O ever happened" — the OS page cache
  below adds a second, invisible caching layer, which is why `track_io_timing`
  matters more than counts alone.

### Lifecycle or sequence

A read miss on PostgreSQL 18, in causal order:

1. **Lookup.** The backend hashes (relation, fork, block); on a hit it pins
   the slot and proceeds — `pg_stat_io.hits` increments.
2. **Victim search.** On a miss, clock sweep finds an unpinned, zero-usage
   buffer. If the victim is dirty, it is written out first — by this backend,
   right now (`pg_stat_io` `writes` with `backend_type = client backend`, the
   signal the view's own documentation calls a checkpointer/bgwriter
   misconfiguration hint; Upstream invariant —
   [`pg_stat_io`](https://www.postgresql.org/docs/18/monitoring-stats.html)).
3. **Read submission.** The read is defined as an AIO handle. With the
   deployed default `io_method = worker`, the handle is queued and one of the
   `io_workers` (default 3) executes it; with `io_uring` the backend submits
   to the kernel; with `sync` it degenerates to the pre-18 blocking read
   (Upstream invariant —
   [I/O settings](https://www.postgresql.org/docs/18/runtime-config-resource.html)).
   Adjacent requests are combined up to `io_combine_limit`. In-flight handles
   are visible in the [`pg_aios`](https://www.postgresql.org/docs/18/view-pg-aios.html)
   view with states `DEFINED → SUBMITTED → COMPLETED_*`.
4. **Completion.** The page lands in the slot, the backend unpins when done,
   and usage count rises so the clock sweep spares it next round.
5. **Write-back, by someone else, later.** The **background writer** trickles
   dirty buffers out ahead of demand (`bgwriter_lru_maxpages` per round,
   default 100); the **checkpointer** writes every dirty page at checkpoint
   time, throttled by `checkpoint_completion_target` — the schedule
   [chapter 04](04-wal-and-checkpoints.md) owns (Upstream invariant —
   [background writer](https://www.postgresql.org/docs/18/runtime-config-resource.html)).
6. **Bulk containment.** A large sequential scan or vacuum allocates a ring;
   its evictions recycle ring slots (`pg_stat_io.reuses`, contexts `bulkread`
   / `vacuum`), so one reporting query cannot flush the hot working set.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Shared buffer pool size | `shared_buffers 256MB` per instance, `effective_cache_size 1.5GB` telling the planner about the OS cache above it | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| PG 18 AIO configuration | `io_method`/`io_workers` unset in manifests → upstream defaults `worker` / 3 | [I/O settings](https://www.postgresql.org/docs/18/runtime-config-resource.html); absence in the manifest | Inference — confirm with `SHOW io_method` |
| Readahead hinting | `effective_io_concurrency 200` (SSD-tuned); in 18 this feeds the AIO depth rather than only `fadvise` | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) · [release notes](https://www.postgresql.org/docs/18/release-18.html) | Repository fact |
| I/O timing visibility | `track_io_timing on`, so `pg_stat_io` `*_time` columns carry real milliseconds | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| Per-backend-type I/O accounting | The `pg_stat_io` custom query exports reads/writes/hits/evictions/reuses with PG 18 `read_bytes`/`write_bytes` | [`monitoring-queries.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |
| Cache-effectiveness alerting | `CNPGLowCacheHitRatio` fires below 90 % hit rate under real load | [`deep-signals-alerts.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml) | Repository fact |
| Buffer-content inspection | `pg_buffercache` is **not installed** | [Extensions](../extensions.md) | Repository fact — disposable lab only |

256MB of shared buffers under a 1Gi pod limit is a deliberate small-pool
bet: the OS page cache (and Kind's single-node file system) absorbs the rest.
That makes `pg_stat_io.evictions` the number to watch — a small pool under
pressure evicts constantly, and the view names *who* paid for it.

## Observe it on the live cluster

This lab reads the effective AIO configuration and the per-process I/O ledger
— which backend types read, wrote, hit, and evicted, in which contexts.

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
    name,
    setting
FROM pg_settings
WHERE name IN ('io_method', 'io_workers', 'io_combine_limit',
               'effective_io_concurrency', 'shared_buffers',
               'bgwriter_lru_maxpages', 'track_io_timing')
ORDER BY name
LIMIT 10;
```

```sql
SELECT
    backend_type,
    object,
    context,
    hits,
    reads,
    read_bytes,
    writes,
    evictions,
    reuses,
    stats_reset
FROM pg_stat_io
WHERE object = 'relation'
  AND (hits > 0 OR reads > 0 OR writes > 0)
ORDER BY reads DESC
LIMIT 15;
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
| **Cluster/instance** | _pending_ |
| **CNPG role** | _pending_ |
| **PostgreSQL recovery state** | _pending_ |
| **Synchronous state** | _pending_ |
| **Database** | _pending_ |

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| `io_method = worker`, `io_workers = 3` | PG 18 defaults in effect — reads flow through I/O worker processes | That the workers are the bottleneck or the win; latency lives in `read_time` |
| `hits` vs `reads` per row | The buffer pool's effectiveness for that backend type and context | Real disk I/O — a `read` satisfied by the OS page cache still counts as a read here |
| `evictions` on `client backend` | Backends had to make room themselves — small-pool pressure | Which relations were evicted; the view aggregates |
| `reuses` in `bulkread`/`vacuum` contexts | Ring buffers doing their containment job | — |
| `writes` on `client backend` (nonzero, growing) | Backends writing dirty victims — the documented sign that bgwriter/checkpointer lag demand | Cause: could be one bulk load or chronic misconfiguration; correlate with [04](04-wal-and-checkpoints.md)'s checkpoint evidence |
| `stats_reset` | The ledger's epoch — cumulative counters mean nothing without it | — |

### What to notice

- Every counter is an **observed example** since `stats_reset`; quote deltas
  between two timestamps, not lifetime totals.
- Deeper inspection — which pages occupy which slots (`pg_buffercache`), or
  watching a `pg_aios` handle mid-flight — needs the **disposable lab**;
  `pg_aios` is readable here but usually empty at rest, which is itself the
  expected observation on an idle cluster.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Working set outgrows 256MB pool | Constant eviction; every miss pays a victim write when dirty | Rising latency; hit ratio sags | `pg_stat_io.evictions`; [`CNPGLowCacheHitRatio`](../../observability/runbooks/postgresql/CNPGLowCacheHitRatio.md) | Raise `shared_buffers` (restart; memory taken from the pod's 1Gi) or shrink the working set — [14](14-monitoring-and-capacity.md) owns the decision |
| bgwriter/checkpointer behind write demand | Backends write dirty victims inline | Foreground query latency spikes | `pg_stat_io` `writes`/`fsyncs` on `client backend` (Upstream invariant — the view's own tuning guidance) | Checkpoint tuning is [04](04-wal-and-checkpoints.md)'s territory; the evidence starts here |
| One reporting query scans a huge table | Ring buffer contains it; the scan recycles its own slots | The *scan* is slower than a warm cache; the rest of the system stays warm | `reuses` in `bulkread` context | Containment by design — the cost lands on the bulk job, not the OLTP path |
| I/O workers saturated (`io_method = worker`) | Read queue deepens behind 3 workers | Sequential-scan-heavy work slower than raw disk suggests | `pg_aios` backlog during load; `read_time` growth | `io_workers` is a start-time setting; changing it on the shared cluster is out of bounds — measure first, file a change |

The invariant that survives every row: correctness. A thrashing buffer pool is
slow, never wrong — dirty pages still obey WAL-before-data.

## Misconceptions and challenge questions

### “A 99 % hit ratio means the database barely touches disk”

`pg_stat_io` hits count only *shared buffer* hits. Misses served by the OS
page cache are still `reads` and still fast — and real disk reads hide inside
the same counter. Hit ratio measures pool sizing, not storage load; `read_time`
with `track_io_timing on` (deployed) is the honest signal.

### “PostgreSQL 18 made all I/O asynchronous”

The 18 release notes scope AIO to read-side operations — sequential scans,
bitmap heap scans, vacuum
([release notes](https://www.postgresql.org/docs/18/release-18.html)). WAL
flushes and dirty-page write-back keep their existing paths. `io_method = sync`
also remains available and turns the new machinery back into blocking reads.

### Challenge: eviction storm with an idle checkpointer

`pg_stat_io` shows `client backend` evictions and writes climbing fast, while
the checkpointer row barely moves and no checkpoint is running. What is
happening, and what single deployed number most likely explains it?

**Model answer:** backends are taking misses in a pool too small for the
working set and writing dirty victims inline; between checkpoints that work
lands on foreground queries. The deployed `shared_buffers 256MB` against the
databases' size is the first suspect — confirm with the hit ratio under load,
then weigh the [capacity trade-off](14-monitoring-and-capacity.md).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The full path of a read miss on PostgreSQL 18, naming who executes the
  I/O under the deployed `io_method`.
- [ ] Where dirty pages are persisted, by which three writers, and what a
  client-backend write signals.
- [ ] What a ring buffer protects, and from whom.
- [ ] One `pg_stat_io` row and the limit of what it proves.
- [ ] The trade-off inside `shared_buffers 256MB` on a 1Gi pod.

## Related documentation

- [Observability and troubleshooting](../observability-and-troubleshooting.md)
  — the symptom-first view of the same signals
- [Extensions](../extensions.md) — `pg_buffercache` absence
- Previous: [Storage, pages, and tuples](02-storage-pages-and-tuples.md) ·
  Next: [WAL and checkpoints](04-wal-and-checkpoints.md)

## References

- [PostgreSQL 18 — resource consumption and I/O settings](https://www.postgresql.org/docs/18/runtime-config-resource.html)
- [PostgreSQL 18 — `pg_stat_io`](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [PostgreSQL 18 — `pg_aios`](https://www.postgresql.org/docs/18/view-pg-aios.html)
- [PostgreSQL 18 — release notes (AIO subsystem)](https://www.postgresql.org/docs/18/release-18.html)

---
_Last updated: 2026-09-29 — new chapter authored for issue #1137 (no
predecessor page); live lab pending verification._
