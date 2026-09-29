# ClickHouse internals learning path

Learn ClickHouse from the deployment that already stores this platform's logs
and traces: begin with a small mental model, follow the mechanism inside the
engine, and then prove the model against read-only evidence from the Kind
cluster.

| Quick facts | |
|---|---|
| **Status** | Curriculum contract approved for issue [#1127](https://github.com/duynhlab/homelab/issues/1127); chapters are planned until linked below |
| **Primary audience** | Platform engineers learning ClickHouse, from first principles through failure and scale reasoning |
| **Page type** | Explanation-first chapters with one embedded, read-only observation lab |
| **Case study** | `otel.otel_logs`, `otel.otel_traces`, and `otel.otel_traces_trace_id_ts` on the local Kind deployment |
| **Safety boundary** | Observe only: `SHOW`, `SELECT`, `EXPLAIN`, Kubernetes reads, and existing telemetry |
| **Canonical platform guide** | [ClickHouse — OTel logs+traces OLAP](../README.md) |
| **Authoring contract** | [Chapter template and review gate](_template.md) |

## Purpose

This path teaches the engine by connecting four layers in order:

1. a plain-language mental model;
2. the internal data structures and state transitions;
3. the configuration and data deployed in this repository; and
4. evidence that you can inspect without changing the running cluster.

The goal is not to memorize SQL or copy an operations runbook. You should be
able to predict what ClickHouse does next, explain why it does that, and read
the system-table evidence that confirms or disproves your model.

## Audience and prerequisites

Start here if you can use `kubectl` and basic SQL but do not yet feel confident
explaining parts, sparse indexes, replication queues, or Keeper. The chapters
progress from junior mental models to senior failure and scaling trade-offs;
they do not require prior ClickHouse operations experience.

Before the live observation blocks, know how to:

- select the Ubuntu Kind kubeconfig without changing another cluster context;
- identify the ClickHouse replica that answered a query;
- use the secure client pattern in [ClickHouse operations](../operations.md#secure-client-pattern);
- distinguish repository intent from a timestamped live observation; and
- stop when a command would write data or alter cluster state.

## How to use this path

Read the chapters in order on the first pass. Within a chapter, use the depth
that matches your goal:

| Depth | Read through | You should be able to |
|---|---|---|
| **Foundation** | Mental model | Define the essential terms and describe the mechanism without implementation detail |
| **Practitioner** | Internal mechanism + homelab case study | Map the model to the deployed DDL, topology, and data path |
| **Operator** | Live observation + failure modes | Interpret real evidence and identify the failing layer |
| **Mastery** | Challenges + teach-back | Predict behavior under a new scenario and defend the trade-off |

Do not skip directly to a command and treat its output as self-explanatory.
Read the mechanism first, then use the observation to test it.

## Curriculum

Files remain plain text until their chapter is written and reviewed. A linked
title is part of the published learning path; an unlinked title is planned.

| # | Planned chapter | Owning question | Depends on |
|---:|---|---|---|
| 1 | `01-architecture.md` | Where does ClickHouse sit, and how does telemetry reach and leave it? | Platform hub |
| 2 | `02-query-pipeline.md` | What happens between SQL submission and returned rows? | 01 |
| 3 | `03-mergetree.md` | How does MergeTree organize data so analytical reads are fast? | 01–02 |
| 4 | `04-parts-and-merges.md` | How does an insert become immutable parts, and how do those parts evolve? | 03 |
| 5 | `05-replication.md` | What is replicated, and how do replicas converge? | 04 |
| 6 | `06-keeper.md` | Why does replication need Keeper, and what changes without quorum? | 05 |
| 7 | `07-sharding.md` | How do replication, sharding, distributed reads, and distributed inserts differ? | 05–06 |
| 8 | `08-ingestion-pipeline.md` | What delivery guarantees exist from a telemetry producer to a durable part? | 04–06 |
| 9 | `09-materialized-views.md` | When does an incremental materialized view run, and what data does it see? | 03–04, 08 |
| 10 | `10-storage-s3.md` | Where do bytes live across hot, cold, cache, and retention boundaries? | 04, 06 |
| 11 | `11-failure-recovery.md` | Given a symptom, which layer failed and what evidence proves it? | 01–10 |
| 12 | `12-scaling.md` | Which bottleneck should be scaled, and what cost follows? | 01–11 |

The sequence is deliberate: topology → read path → storage engine → write
lifecycle → coordination → distribution → ingestion → derived data → storage
lifecycle → failure reasoning → scaling.

## Content ownership

Each chapter answers one question. It links to, rather than copies, content
owned elsewhere.

| Content | Canonical owner |
|---|---|
| Deployed topology, schema summary, Grafana, and platform role | [ClickHouse platform hub](../README.md) |
| OLAP and MergeTree introduction | [ClickHouse fundamentals](../fundamentals.md) |
| Sorting keys, pruning, `EXPLAIN`, and codecs | [Schema and queries](../schema-and-queries.md) |
| Part lifecycle, merge pressure, partitions, and TTL | [Parts, merges, partitions, and TTL](../parts-merges-and-ttl.md) |
| Deployed trace-ID materialized view | [Materialized views](../materialized-views.md) |
| Symptom-first day-2 procedures | [ClickHouse operations](../operations.md) and [alert runbooks](../../runbooks/clickhouse/README.md) |
| Timestamped runtime proof | [ClickHouse runtime audits](../audits/README.md) |

Chapter 11 explains failure propagation and diagnosis order. It does not copy
the recovery procedures from operations or per-alert runbooks. Chapter 8 owns
the deployed OpenTelemetry ingestion path; Kafka appears only as a reference,
not-deployed comparison unless the repository and live cluster later prove
otherwise.

## Evidence vocabulary

Every non-trivial claim uses one of these evidence classes. The label may be in
the sentence, a callout, or an evidence table; it must be unambiguous.

| Class | Meaning | Required proof |
|---|---|---|
| **Upstream invariant** | Product behavior intended to hold across deployments | Current official documentation, source, or specification |
| **Repository fact** | Behavior declared by this Git revision | Link to the smallest owning manifest, DDL, or canonical document |
| **Live observation** | Behavior seen on one running environment at one time | Timestamp, timezone, version, context, database/table, replica, command, and abbreviated output |
| **Inference** | A conclusion derived from evidence but not directly observed | Name the evidence and the limit of the inference |
| **Reference — not deployed** | A useful ClickHouse pattern absent from this platform | Official source plus an explicit not-deployed label |
| **Planned** | Accepted direction that has not been applied | Owning accepted RFC/ADR and an explicit planned label |

Dynamic evidence is never a platform constant. A part name, row count, level,
byte count, queue length, or elapsed time captured from the cluster must say
**observed example** and include its observation context.

## Shared glossary

Chapters define a term inline on first use and link back here when readers need
the short cross-chapter meaning. They do not create separate glossaries.

| Term | Meaning in this learning path |
|---|---|
| **Block** | A batch of columns processed together in memory; an insert may contain or produce more than one block |
| **Granule** | The smallest range addressed by the sparse primary index, represented by a mark |
| **Mark** | An index entry and file offset used to find a granule without indexing every row |
| **Part** | An immutable, sorted on-disk unit created by an insert or merge and owned by one partition |
| **Partition** | A lifecycle boundary grouping parts; it is not a row-level index |
| **Merge** | Background work that reads compatible parts and writes a replacement part |
| **Replica** | A server maintaining its own local copy of a replicated table's parts |
| **Shard** | A horizontal subset of a table's data; the current deployment has one shard |
| **Keeper** | The quorum-based coordination service used for replicated table metadata and logs, not for storing table rows |
| **Materialized view** | An insert trigger that transforms incoming blocks into a target table; not a stored query result refreshed on demand |

## Observation safety

Allowed evidence collection:

- `kubectl get`, `describe`, and bounded log reads;
- `SHOW CREATE`, `SELECT` from `system.*`, and bounded queries against existing tables;
- `EXPLAIN` without executing mutations; and
- existing metrics, dashboards, logs, and dated audits.

Forbidden in the shared Kind cluster:

- `INSERT`, DDL, mutations, `OPTIMIZE`, or commands that move/fetch/drop parts;
- stopping ClickHouse or Keeper members;
- changing merge, replication, or queue settings;
- injecting disk, network, quorum, or object-storage failures; and
- running recovery commands merely to create documentation evidence.

Use an isolated disposable lab for write-path or failure-injection exercises.

## Authoring and review

Start every chapter from the [chapter template](_template.md). The template is
the contributor contract; do not paste its review checklist into published
chapters. A chapter is complete only when its evidence, diagram, links, and
teach-back gate pass the template's review checklist.

## References

- [Diátaxis documentation framework](https://diataxis.fr/)
- [Google developer documentation style guide](https://developers.google.com/style)
- [Kubernetes page content types](https://kubernetes.io/docs/contribute/style/page-content-types/)
- [ClickHouse documentation style guide (historical repository)](https://github.com/ClickHouse/clickhouse-docs/blob/main/contribute/style-guide.md)

---
_Last updated: 2026-09-29 — established the curriculum, evidence vocabulary,
shared glossary, and authoring boundary before the first internals chapter._
