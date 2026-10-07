# PostgreSQL internals learning path

Learn PostgreSQL from the clusters that already run this platform's data: begin
with a small mental model, follow the mechanism inside the engine, and then
prove the model against read-only evidence from the CNPG clusters on the Kind
cluster.

| Quick facts | |
|---|---|
| **Status** | All 14 chapters authored and live-verified for issue [#1137](https://github.com/duynhlab/homelab/issues/1137): every lab ran read-only on `kind-homelab` on 2026-10-01 (PostgreSQL 18.1), including the case study on the DR replica |
| **Primary audience** | Platform engineers learning PostgreSQL, from first principles through failure and capacity reasoning |
| **Page type** | Explanation-first chapters with one embedded, read-only observation lab |
| **Version baseline** | PostgreSQL 18 (deployed 18.1; record the live minor per observation) |
| **Case study** | A representative commit's durability path on `product-db`: local WAL flush → `ANY 1` acknowledgement → archive → replay on the archive-fed `product-db-replica`; shared-cluster evidence demonstrates boundaries, not row-level WAL attribution |
| **Safety boundary** | Observe only: `SELECT` on `pg_catalog`/`pg_stat_*`, `SHOW`, `EXPLAIN`, `kubectl cnpg status`, Kubernetes reads, and existing telemetry |
| **Canonical platform guide** | [Databases hub](../README.md) |
| **Authoring contract** | [Chapter template and review gate](_template.md) |

## Purpose

This path teaches the engine by connecting four layers in order:

1. a plain-language mental model;
2. the internal data structures and state transitions;
3. the configuration and clusters deployed in this repository; and
4. evidence that you can inspect without changing the running clusters.

The goal is not to memorize SQL or copy an operations runbook. You should be
able to predict what PostgreSQL does next, explain why it does that, and read
the catalog and statistics evidence that confirms or disproves your model.

This directory previously held nine vendor-neutral concept pages under a rule
that forbade naming the deployment. Issue
[#1137](https://github.com/duynhlab/homelab/issues/1137) retired that rule: the
chapters below absorbed those pages and ground the same concepts in the
deployed CNPG clusters, their manifests, and live evidence.

## Audience and prerequisites

Start here if you can use `kubectl` and basic SQL but do not yet feel confident
explaining pages, tuples, WAL, snapshots, vacuum, or replication slots. The
chapters progress from junior mental models to senior failure and capacity
trade-offs; they do not require prior PostgreSQL operations experience.

Before the live observation blocks, know how to:

- select the Ubuntu Kind kubeconfig without changing another cluster context;
- reach an instance with `kubectl cnpg psql <cluster>` (never through the
  poolers) and identify the pod and its role;
- open every session with the
  [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  plus `SET default_transaction_read_only = on;`
- distinguish repository intent from a timestamped live observation; and
- stop when a command would write data or alter cluster state.

## How to use this path

Read the chapters in order on the first pass. Within a chapter, use the depth
that matches your goal:

| Depth | Read through | You should be able to |
|---|---|---|
| **Foundation** | Mental model | Define the essential terms and describe the mechanism without implementation detail |
| **Practitioner** | Internal mechanism + homelab case study | Map the model to the deployed manifests, GUCs, and data path |
| **Operator** | Live observation + failure modes | Interpret real evidence and identify the failing layer |
| **Mastery** | Challenges + teach-back | Predict behavior under a new scenario and defend the trade-off |

Do not skip directly to a command and treat its output as self-explanatory.
Read the mechanism first, then use the observation to test it.

## Curriculum

A linked title is part of the published learning path; an unlinked title is
planned. The Absorbed column records which retired page each chapter replaced.

| # | Chapter | Owning question | Absorbed | Depends on |
|---:|---|---|---|---|
| 1 | [Processes and memory](01-processes-and-memory.md) | Which processes run inside a CNPG instance, and how is memory divided? | `process-and-memory.md` | Databases hub |
| 2 | [Storage, pages, and tuples](02-storage-pages-and-tuples.md) | Where does a row physically live on disk? | storage half of `storage-and-wal.md` | 01 |
| 3 | [Buffer manager and I/O](03-buffer-manager-and-io.md) | How does an 8 KiB page travel between disk and RAM? | (new) | 01–02 |
| 4 | [WAL and checkpoints](04-wal-and-checkpoints.md) | What makes a commit durable? | WAL half of `storage-and-wal.md` | 02–03 |
| 5 | [MVCC and snapshots](05-mvcc-and-snapshots.md) | How do two transactions see different data at once? | MVCC part of `mvcc-locking-and-vacuum.md` | 02 |
| 6 | [Locking and wait events](06-locking-and-wait-events.md) | Who is blocking whom, and which evidence proves it? | locking part of `mvcc-locking-and-vacuum.md`; blocking chains from `monitoring-and-performance-investigation.md` | 05 |
| 7 | [Vacuum and freezing](07-vacuum-and-freezing.md) | Why does vacuum exist, and when does it lose? | vacuum part of `mvcc-locking-and-vacuum.md`; vacuum pressure from `monitoring-and-performance-investigation.md` | 05 |
| 8 | [Query processing](08-query-processing.md) | How does SQL become a plan and then rows? | `query-planning-and-execution.md`; plan investigation from `monitoring-and-performance-investigation.md` | 03, 05 |
| 9 | [Indexes and access methods](09-indexes-and-access-methods.md) | How does a B-tree find — and punish — you? | `indexes-and-access-paths.md` | 02, 08 |
| 10 | [Schema and integrity](10-schema-and-integrity.md) | Which constraint is enforced where, and which migration is safe? | `schema-and-integrity.md` | 06, 09 |
| 11 | [Partitioning and retention](11-partitioning-and-retention.md) | What does partitioning buy, and at what price? | `partitioning-and-retention.md` | 09–10 |
| 12 | [Replication and slots](12-replication-and-slots.md) | How do standbys converge, and how do slots hold WAL hostage? | `replication.md` | 04 |
| 13 | [Backup and PITR](13-backup-and-pitr.md) | How does the engine restore to a point in time? | (new; recovery notes from `storage-and-wal.md`) | 04, 12 |
| 14 | [Monitoring and capacity](14-monitoring-and-capacity.md) | What do you measure to name the failing layer? | `monitoring-and-performance-investigation.md` | 01–13 |

The sequence is deliberate: processes → storage → buffers → WAL → MVCC →
locks → vacuum → queries → indexes → schema → partitioning → replication →
backup → monitoring.

## Content ownership

Each chapter answers one question. It links to, rather than copies, content
owned elsewhere.

| Content | Canonical owner |
|---|---|
| Cluster inventory, topology, services, connection paths | [Databases architecture](../architecture.md) |
| Operator behavior, resource model, reconciliation | [CloudNativePG](../cloudnativepg.md) |
| Backup schedules, retention, recovery model | [Backup policy](../backup-policy.md) |
| DR plan, standby taxonomy, PITR procedures, RPO/RTO | [Disaster recovery](../disaster-recovery.md) and [reliability targets](../reliability-targets.md) |
| Pooler inventory and modes | [Poolers](../poolers.md) |
| Extension inventory per database | [Extensions](../extensions.md) |
| Symptom-first triage and safe session header | [Observability and troubleshooting](../observability-and-troubleshooting.md) |
| Task procedures (restore, failover drills, role rotation) | [Databases runbooks](../runbooks/README.md) |
| Per-alert diagnosis | [PostgreSQL alert runbooks](../../observability/runbooks/postgresql/README.md) |

Chapter 13 explains restore mechanics inside the engine; it does not copy the
DR plan or the restore runbooks. Chapter 14 owns investigation method, not
per-alert procedures.

## Evidence vocabulary

Every non-trivial claim uses one of these evidence classes. The label may be in
the sentence, a callout, or an evidence table; it must be unambiguous.

| Class | Meaning | Required proof |
|---|---|---|
| **Upstream invariant** | Product behavior intended to hold across deployments | Current official documentation, source, or specification |
| **Repository fact** | Behavior declared by this Git revision | Link to the smallest owning manifest, GUC block, or canonical document |
| **Live observation** | Behavior seen on one running environment at one time | Timestamp, timezone, `SELECT version()`, context, cluster, instance pod and role, database, command, and abbreviated output |
| **Inference** | A conclusion derived from evidence but not directly observed | Name the evidence and the limit of the inference |
| **Reference — not deployed** | A useful PostgreSQL pattern absent from this platform | Official source plus an explicit not-deployed label |
| **Planned** | Accepted direction that has not been applied | Owning accepted RFC/ADR and an explicit planned label |

Dynamic evidence is never a platform constant. An LSN, XID age, WAL segment
name, buffer count, lag value, or `pg_stat_*` counter captured from the
cluster must say **observed example** and include its observation context.
Cumulative `pg_stat_*` counters also name their last reset time.

## Shared glossary

Chapters define a term inline on first use and link back here when readers need
the short cross-chapter meaning. They do not create separate glossaries.

| Term | Meaning in this learning path |
|---|---|
| **Page** | The 8 KiB block PostgreSQL reads and writes as one unit, in memory and on disk |
| **Tuple** | One physical row version inside a page, carrying `xmin`/`xmax` visibility metadata |
| **TOAST** | The side storage for values too large to fit a page inline |
| **XID** | A 32-bit transaction identifier whose finite space makes freezing mandatory |
| **Snapshot** | The set of transaction visibility decisions a statement or transaction reads through |
| **WAL** | The append-only log whose flush, not the data-file write, makes a commit durable |
| **LSN** | A byte position in the WAL stream; ordering and lag are measured as LSN distances |
| **Checkpoint** | The act of forcing dirty pages to disk so recovery can start from a known REDO point |
| **Vacuum** | Background reclamation of dead tuples and the freezing that keeps XIDs usable |
| **Replication slot** | Server-side state that pins WAL until a consumer confirms it, deliberately trading disk for safety |
| **Timeline** | The recovery lineage identifier that diverges whenever a restore or promotion rewrites history |
| **Instance** | One PostgreSQL process tree in one pod; a CNPG cluster is one primary plus its standbys |

## Observation safety

Labs connect with `kubectl cnpg psql <cluster>` (add `--replica` for a
standby), never through PgDog or PgBouncer: transaction pooling breaks session
state, and read routing hides which instance answered. The connection is a
superuser, so every lab opens with the
[safe session header](../observability-and-troubleshooting.md#safe-session-header)
and `SET default_transaction_read_only = on;`.

Allowed evidence collection:

- bounded `SELECT` on `pg_catalog`, `pg_stat_*`, `pg_settings`, and existing
  tables; `SHOW`; system functions such as `pg_current_wal_lsn()` and
  `pg_control_checkpoint()`;
- `EXPLAIN` without `ANALYZE` on any writing statement;
- `kubectl get`, `describe`, `cnpg status`, and bounded log reads; and
- existing metrics, dashboards, logs, and dated audits.

Forbidden on the shared Kind cluster:

- any DML or DDL — including `CREATE EXTENSION`; `pageinspect`,
  `pg_buffercache`, `pg_visibility`, and `pg_walinspect` are not installed and
  must stay that way here;
- `CHECKPOINT`, `pg_switch_wal()`, `VACUUM`, `ANALYZE`, or settings changes at
  cluster scope;
- `kubectl cnpg promote`, `fencing`, `restart`, `backup`, or `hibernate`,
  deleting pods, or editing Cluster resources; and
- shelling into the data directory, including `pg_waldump`.

Page-level and WAL-file forensics belong in an isolated disposable lab (a
throwaway PostgreSQL 18 container); a chapter that uses one says so explicitly.

## Authoring and review

Start every chapter from the [chapter template](_template.md). The template is
the contributor contract; do not paste its review checklist into published
chapters. A chapter is complete only when its evidence, diagram, links, and
teach-back gate pass the template's review checklist.

## References

- [PostgreSQL 18 documentation](https://www.postgresql.org/docs/18/index.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)
- [CloudNativePG documentation](https://cloudnative-pg.io/documentation/)
- [Diátaxis documentation framework](https://diataxis.fr/)
