# Scaling decisions — which bottleneck to scale and what it costs

When ClickHouse feels slow, "add resources" is five different actions with five
different price tags — and on this platform, one of them (sharding) is a
deliberate non-decision. This chapter turns a measured bottleneck into the one
scaling action that addresses it, and names what each action costs.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Mastery entry point |
| **Prerequisites** | All previous chapters; especially [parts and merges](04-parts-and-merges.md), [replication](05-replication.md), [sharding](07-sharding.md), [tiered storage](10-storage-s3.md) |
| **Deployment status** | Deployed limits (1 shard × 3 replicas, 2Gi memory limit, 10Gi PVC); scale-out options are Reference — not deployed |
| **Platform scope** | Cluster `otel`; the `otel.*` tables; Keeper and RustFS as scaling dependencies |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | The bottleneck → scaling-action decision model and its cost accounting |
| **Not this page** | Merge-debt response procedure — [capacity and merge debt](../operations.md#capacity-and-merge-debt); the sharding trigger analysis — [RFC-0028 research](../../../proposals/rfc/RFC-0028/research.md) |
| **Previous / next** | [Failure reasoning](11-failure-recovery.md) / [Learning path hub](README.md) |

## Questions this chapter answers

- Which evidence distinguishes a memory bottleneck from merge debt, and from
  ingest pressure?
- Why is adding a replica a *read* scaling action here, and what does it cost
  in Keeper sessions and bucket bytes?
- Which bottlenecks does vertical resizing actually address, and where is its
  measured history on this platform?
- What would have to be true before sharding is worth its cost — and who owns
  that analysis?
- Why do disk numbers on this Kind cluster not isolate anything?

## Mental model

A scaling decision is a diagnosis followed by a purchase. The diagnosis names
the saturated resource — CPU, memory, disk I/O and space, merge throughput,
query concurrency, or ingest rate — using the same evidence discipline as
[chapter 11](11-failure-recovery.md). The purchase picks the cheapest action
whose mechanism actually touches that resource. Buying the wrong axis is worse
than doing nothing: a second shard does not fix a memory-starved merge, and a
bigger memory limit does not fix a partition with three thousand parts.

Think of a kitchen: a slow restaurant might need a bigger stove (vertical), a
second identical kitchen serving the same menu to more tables (replica — more
diners served, food cooked no faster), or splitting the menu across two
kitchens (shard — each cooks half, but now every order must be assembled from
both). The analogy stops at the assembly step: a Distributed query does its
"assembly" on every read forever, which is why the platform refuses that cost
until a measured limit forces it.

### Essential terms

| Term | Meaning here |
|---|---|
| `vertical scaling` | Raising a replica's CPU/memory/disk within the same topology |
| `read scaling` | Adding replicas: more copies answering SELECTs; every replica still ingests and stores everything |
| `merge debt` | Parts accumulating faster than merges retire them; the write-side backpressure axis |
| `server memory budget` | ClickHouse self-caps at `max_server_memory_usage_to_ram_ratio` (default 0.9) × the cgroup limit ([server settings](https://clickhouse.com/docs/reference/settings/server-settings/settings/max-server-memory-usage)) |

Shared meanings of *part*, *merge*, *replica*, and *shard* are in the
[learning-path glossary](README.md#shared-glossary).

## How it works internally

### Invariants

- Every replica does all the work: with one shard, adding a replica divides
  read traffic but multiplies ingest, merge, and storage work by the replica
  count — it never reduces per-replica write load
  ([chapter 5](05-replication.md)).
- The engine budgets its own memory from the cgroup: the container limit is not
  merely a ceiling the kernel enforces but the number ClickHouse multiplies by
  0.9 to size everything it will attempt (upstream invariant —
  [max_server_memory_usage_to_ram_ratio](https://clickhouse.com/docs/reference/settings/server-settings/settings/max-server-memory-usage)).
- Backpressure is per partition, not per table: inserts are delayed at 1000
  active parts in one partition and refused at 3000 (upstream defaults —
  [parts_to_delay_insert, parts_to_throw_insert](https://clickhouse.com/docs/reference/settings/merge-tree-settings/parts-to)).
- A single query's parallelism is bounded by `max_threads` (default 10 —
  [knowledge base](https://clickhouse.com/docs/resources/support-center/knowledge-base/performance-optimization/async-vs-optimize-read-in-order));
  concurrency across queries by `max_concurrent_queries`. Scaling reads means
  scaling one of those two dimensions or adding replicas.
- Sharding is the only action that reduces per-server *data volume*, and it
  permanently adds distributed-query cost to every read
  ([chapter 7](07-sharding.md)).

### The decision model

Diagnose first (left columns), then buy the matching action (right column).
Costs are accounted below the table.

| Bottleneck | Fingerprint (read-only evidence) | Primary action | Secondary action |
|---|---|---|---|
| Memory | `MEMORY_LIMIT_EXCEEDED` in `system.errors`; failed merges; refused INSERTs | Vertical: raise the container memory limit (the budget follows it) | Reduce demand: widen engine-log collection intervals, trim heavy queries |
| Merge debt / parts | `ClickHouseTooManyParts*` alerts; parts-per-partition query rising; `DelayedInserts` metric | Fix ingest batching upstream (Collector batch and async insert — [chapter 8](08-ingestion-pipeline.md)) | Vertical CPU/memory so merges keep up; never raise the thresholds first ([response order](../parts-merges-and-ttl.md#part-pressure-and-the-two-guard-dimensions)) |
| Disk space (hot) | `ClickHouseDiskAlmostFull`; `system.parts` bytes by disk | Cold-tier offload is already maximal at 7d; shorten retention or grow the PVC | Verify TTL moves are not lagging (`ClickHouseOtelTTLLagging`) |
| Disk space (cold) | Move failures; bucket exhaustion ([chapter 10](10-storage-s3.md)) | Grow RustFS `dataStorageSize` | Shorten the 90d delete TTL |
| Query concurrency / read latency | `system.processes` depth; query_log durations; CPU saturation during dashboards | Add a replica (read scaling) | Per-query tuning: `max_threads`, pruning — owned by [schema and queries](../schema-and-queries.md) |
| Ingest rate | Exporter queue growth with healthy ClickHouse ([chapter 8](08-ingestion-pipeline.md)) | Batching first: fewer, larger inserts | Vertical; sharding only at the researched triggers |
| Data volume per server | Everything above degrading together at a size no single node carries | Shard — **Reference — not deployed**; the trigger analysis and no-rebalance rule are owned by [RFC-0028 research](../../../proposals/rfc/RFC-0028/research.md) | — |

Cost accounting for the three purchases:

- **Vertical** — cheapest and reversible. The one measured scaling event on
  this platform was vertical: the memory limit was raised from 1280Mi to 2Gi on
  2026-09-06 after the 0.9 self-cap (~1152Mi) refused work — 15,678
  `MEMORY_LIMIT_EXCEEDED`, 2,222 failed merges on `system.metric_log`, and 6
  rejected INSERTs into `otel.otel_traces` in a two-hour window; the companion
  fix reduced demand by widening `metric_log`'s collection interval to 15s
  (repository fact — the measured rationale recorded in the
  [CHI manifest](../../../../kubernetes/infra/configs/clickhouse/clickhouseinstallation.yaml)).
  Ceiling: the node's real capacity, which on Kind is the shared VM.
- **Add a replica** — buys read throughput and one more failure domain.
  Costs: a full copy of all data (hot PVC and, with zero-copy off, another
  complete set of cold objects in the bucket — [chapter 10](10-storage-s3.md));
  one more Keeper session and more coordination traffic
  ([chapter 6](06-keeper.md)); anti-affinity demands a fourth node
  (repository fact — the CHI requires one replica per node). It does nothing
  for ingest or merge load — every replica still does all writes.
- **Shard** — buys smaller per-server data and parallel write capacity.
  Costs: Distributed-table fan-out on every read, a sharding-key commitment,
  no automatic rebalancing of existing data, and doubled operational surface
  ([chapter 7](07-sharding.md)). ADR-065 scopes it out and RFC-0028 records
  the measured triggers that would reopen it; nothing is accepted, so the
  correct label is **Reference — not deployed**, not planned
  ([ADR-065 § revisit triggers](../../../proposals/adr/ADR-065-clickhouse-replicated-topology/README.md#revisit-triggers)).

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| cgroup-derived memory budget | Requests 1Gi, limit 2Gi → self-cap ≈ 1843Mi; measured working set 887–899Mi at the time of the resize | [CHI resources and rationale](../../../../kubernetes/infra/configs/clickhouse/clickhouseinstallation.yaml) | Repository fact (the working-set figures are the manifest's dated measurements, not today's values) |
| Hot capacity | 10Gi PVC per replica, storage class `standard` | Same CHI file | Repository fact |
| Parts-pressure early warning | Alerts at 300 active parts — 30% of the delay threshold, 10% of the throw threshold | [Alert rules](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/observability/clickhouse-alerts.yaml); [upstream defaults](https://clickhouse.com/docs/reference/settings/merge-tree-settings/parts-to) | Repository fact + upstream invariant |
| Ingest shaping | Collector batch 512/1024/5s with async insert — the batching lever the model reaches for first | [Chapter 8](08-ingestion-pipeline.md) | Repository fact |
| Read scaling ceiling | 3 replicas on 3 nodes with required anti-affinity; a fourth replica requires a fourth node | Same CHI file | Repository fact |
| Scale-out boundary | 1 shard by decision; triggers documented, none accepted | [ADR-065](../../../proposals/adr/ADR-065-clickhouse-replicated-topology/README.md); [RFC-0028 research](../../../proposals/rfc/RFC-0028/research.md) | Repository fact (the decision); Reference — not deployed (the shard design) |

**The Kind caveat, load-bearing for every disk number:** the hot PVCs of all
three replicas, the `s3_cache` paths, and RustFS's own volume are directories
on the same node filesystem; `local-path` does not enforce PVC sizes, and disk
metrics reflect the shared VM (repository fact — the CHI's cold-tier rationale,
operationalized in [Cold tier on RustFS](../README.md#cold-tier-on-rustfs)).
Inference, and its limit: on this cluster a "disk pressure" fingerprint
implicates the whole node, and per-replica disk isolation cannot be measured at
all — capacity conclusions transfer to a real multi-node deployment only in
shape, never in numbers.

What separates **measured current limits** from **hypothetical design** on this
platform: measured are the 2026-09-06 memory incident, the alert thresholds
firing history, and whatever the lab below captures; hypothetical are all
multi-shard numbers, which exist only as reasoning in RFC-0028. A scaling
proposal that cites the second kind as if it were the first should be sent back
for evidence.

## Observe it on the live cluster

This lab is the capacity sweep: the same few numbers the decision model's
fingerprint column keys on, captured as a dated baseline.

### Prerequisites and safety

- Use the [secure ClickHouse client pattern](../operations.md#secure-client-pattern).
- Confirm the current context and the replica you will query; parts and
  asynchronous metrics are per-replica views.
- Run only the read-only commands shown below.

### Query

```sql
SELECT
    table,
    disk_name,
    count()                                  AS active_parts,
    sum(rows)                                AS rows,
    formatReadableSize(sum(bytes_on_disk))   AS on_disk
FROM system.parts
WHERE database = 'otel' AND active
GROUP BY table, disk_name
ORDER BY table, disk_name
LIMIT 20;
```

```sql
SELECT
    metric,
    value
FROM system.asynchronous_metrics
WHERE metric IN (
    'MaxPartCountForPartition',
    'ReplicasMaxAbsoluteDelay',
    'CGroupMemoryTotal',
    'CGroupMaxCPU'
)
ORDER BY metric
LIMIT 10;
```

```sql
SELECT
    metric,
    value
FROM system.metrics
WHERE metric IN ('MemoryTracking', 'DelayedInserts', 'PartsActive', 'Merge')
ORDER BY metric
LIMIT 10;
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
| `on_disk` per table/disk | Today's byte footprint per tier; the hot sum against 10Gi is the headroom that matters | Growth rate — one snapshot has no slope; compare against the [audit baselines](../audits/README.md) for that |
| `MaxPartCountForPartition` vs 300 / 1000 / 3000 | Distance to the alert, the delay, and the refusal thresholds, in that order | Which partition or table it is — this metric is a server-wide maximum; the parts query localizes it |
| `CGroupMemoryTotal` | The cgroup limit the 0.9 budget multiplies | The budget's *use*: `MemoryTracking` shows demand against it |
| `MemoryTracking` vs 0.9 × `CGroupMemoryTotal` | Headroom before the server refuses allocations | Peak demand — merges and heavy queries spike far above a quiet snapshot; the manifest's incident history shows exactly this gap |
| `ReplicasMaxAbsoluteDelay` ≈ 0 | Replication is not the bottleneck at this instant | Anything under sustained load |
| `DelayedInserts` = 0 | No backpressure active now | That thresholds were never hit — `system.errors` and alert history hold the past |

### What to notice

- Whether the memory headroom (`MemoryTracking` against the self-cap) is wide
  at idle — the 2026-09-06 incident teaches that the gap that matters is at
  merge peaks, which a quiet snapshot structurally understates.
- Every value is an observed example bound to the context above. Capacity
  numbers are the least constant data in this learning path; a baseline without
  its date is noise.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Scaling the wrong axis | The saturated resource stays saturated; the purchase adds its own load (a new replica adds ingest+merge work to a write-bound cluster) | Money and complexity spent, symptom unchanged | The fingerprint that named the bottleneck persists after the change | Re-diagnose; the decision-model table is the contract |
| Raising part thresholds instead of fixing merges | Delay/refusal fire later, parts grow further | Reads slow across the board; eventual harder failure | [Part pressure](../parts-merges-and-ttl.md#part-pressure-and-the-two-guard-dimensions) response order | Upstream warns this trades early detection for deeper trouble ([parts_to_throw_insert](https://clickhouse.com/docs/reference/settings/merge-tree-settings/parts-to)) |
| Vertical limit above node reality | On Kind, the scheduler sees phantom capacity; the node itself starves | OOM kills or VM-wide pressure, not graceful refusal | Node metrics vs pod limits | The CHI comment's core warning: the limit is the *budget*, keep it honest against real capacity |
| Sharding before its triggers | Permanent distributed-read cost, key commitment, no rebalance of existing data | Every query pays fan-out forever | [RFC-0028 research](../../../proposals/rfc/RFC-0028/research.md) trigger table unmet | The boundary is procedural: reopening needs the RFC's measured triggers, not a hunch |

The invariant that holds through every scaling action here: data already in
parts on three replicas stays consistent and queryable — topology changes of
this kind (resources, replica count) never put stored data at risk. What is
temporarily unavailable during a vertical resize is one replica at a time as
pods roll; the guarantee that is *never* available on this cluster is
capacity isolation between components sharing the one node filesystem.

## Misconceptions and challenge questions

### "Ingest is struggling, so add a replica"

Backwards on a one-shard cluster. Every replica performs every insert and
every merge ([chapter 5](05-replication.md)); a fourth replica adds a fourth
full copy of the write load and one more Keeper session, while dividing only
*read* traffic. Ingest pressure is addressed upstream (batching —
[chapter 8](08-ingestion-pipeline.md)), vertically (merge headroom), or — at
researched triggers only — by sharding, which is the single action that splits
write volume ([chapter 7](07-sharding.md)).

### "The container limit is 2Gi, so ClickHouse can use 2Gi"

The server budgets 0.9 × the cgroup limit — about 1843Mi — and refuses its own
allocations beyond that, well before the kernel would OOM-kill it (upstream
invariant —
[max_server_memory_usage_to_ram_ratio](https://clickhouse.com/docs/reference/settings/server-settings/settings/max-server-memory-usage)).
This platform's history makes it concrete: at a 1280Mi limit the ~1152Mi budget
was refusing merges and INSERTs while the working set looked comfortable
(repository fact — CHI rationale). Size the limit for peak *budget demand*,
not steady-state use.

### Challenge: dashboards are slow every morning at 09:00; ingest is healthy, parts are low, memory headroom is wide, but `system.processes` shows twenty concurrent dashboard queries. Which purchase, and what does it cost?

**Model answer:** The fingerprint is query concurrency — the one bottleneck
whose primary action is read scaling. Options in cost order: tune the
dashboards (fewer/cheaper queries — free), then add a replica, which costs a
fourth node (anti-affinity), a full extra copy of hot data on a new PVC and of
cold data in the bucket (zero-copy is off), and one more Keeper session — and
buys a third more read capacity. Sharding is not on the table: no per-server
data-volume trigger fired, and it would tax these same dashboards with
fan-out. Vertical CPU is the middle option if profiling shows the three
replicas saturating cores rather than queueing.

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] The decision model in your own words: the six bottleneck axes and the
      primary action for each.
- [ ] Where the memory budget comes from (what is persisted in the manifest,
      what the server derives from the cgroup, and who enforces refusal).
- [ ] The prediction for adding a fourth replica to a write-bound cluster —
      what improves, what worsens, and why.
- [ ] One row of your capacity sweep and what a quiet-hour snapshot cannot
      prove about peak demand.
- [ ] The full cost of sharding, and the procedural boundary that keeps it a
      reference design here.

## Related documentation

- [Capacity and merge debt](../operations.md#capacity-and-merge-debt) — the
  operational response when the write-side fingerprints fire
- [RFC-0028 research](../../../proposals/rfc/RFC-0028/research.md) — the
  sharding trigger table and scouted integration path
- [ADR-065 — replicated topology](../../../proposals/adr/ADR-065-clickhouse-replicated-topology/README.md) —
  the accepted decision and its revisit triggers
- [ClickHouse runtime audits](../audits/README.md) — dated capacity baselines
  to compare your sweep against
- [Learning path hub](README.md) — you have reached the end of the path

## References

- [ClickHouse: `max_server_memory_usage_to_ram_ratio`](https://clickhouse.com/docs/reference/settings/server-settings/settings/max-server-memory-usage)
- [ClickHouse: MergeTree settings — `parts_to_delay_insert`, `parts_to_throw_insert`](https://clickhouse.com/docs/reference/settings/merge-tree-settings/parts-to)
- [ClickHouse: `max_concurrent_queries`](https://clickhouse.com/docs/reference/settings/server-settings/settings/max-concurrent)
- [ClickHouse knowledge base: `max_threads` and pipeline parallelism](https://clickhouse.com/docs/resources/support-center/knowledge-base/performance-optimization/async-vs-optimize-read-in-order)

---
_Last updated: 2026-09-29 — first draft of the scaling-decisions chapter; live
observation pending verification on the Ubuntu Kind cluster._
