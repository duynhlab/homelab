# Schema and integrity — which constraint is enforced where

A constraint is the only validator that covers every writer, every retry, and
every admin session that reaches the database. This chapter explains what each
constraint costs to enforce, which lock every `ALTER TABLE` takes, and why
"add a constraint to a big table" is a locking problem before it is a data
problem.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Practitioner — enforcement internals and migration safety |
| **Prerequisites** | [Locking and wait events](06-locking-and-wait-events.md); [Indexes and access methods](09-indexes-and-access-methods.md) |
| **Deployment status** | Deployed — service schemas on both operational clusters are constraint-enforced; migrations run against `-rw` |
| **Platform scope** | All CNPG clusters; schema DDL is owned by service repositories |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | Constraint enforcement internals, ALTER TABLE lock levels, the NOT VALID pattern, PG 18 generated columns and temporal constraints |
| **Not this page** | Partition DDL and retention — [Partitioning and retention](11-partitioning-and-retention.md); lock diagnosis — [Locking and wait events](06-locking-and-wait-events.md) |
| **Previous / next** | [Indexes and access methods](09-indexes-and-access-methods.md) / [Partitioning and retention](11-partitioning-and-retention.md) |

## Questions this chapter answers

- Which mechanism enforces each constraint type — index, per-row check, or
  internal trigger?
- Which lock does each common `ALTER TABLE` form take, and who does it block?
- How does `NOT VALID` + `VALIDATE CONSTRAINT` change the locking story for
  large tables?
- What changed in PostgreSQL 18 for generated columns and range-key
  constraints?
- Why can application-side validation never replace a database constraint?

## Mental model

PostgreSQL checks constraints inside the same transaction that changes the
data, under the same locks and the same MVCC rules
([chapter 05](05-mvcc-and-snapshots.md)). That placement is the whole value:
several services, workers, retries, and admin tools can write the same
relation, and the constraint is the one gate all of them pass through.
Application validation is a UX layer; the constraint is the storage boundary.

Each constraint type is enforced by a different machine: uniqueness by an
index, row shape by an expression check, references by hidden triggers. Their
costs differ accordingly.

### Essential terms

| Term | Meaning here |
|---|---|
| `contype` | The constraint-type code in `pg_constraint`: `p` primary key, `u` unique, `c` check, `f` foreign key, `x` exclusion, `n` not-null |
| `NOT VALID` | A constraint that enforces new writes immediately but has not yet been proven against existing rows |
| `lock level` | The table-level lock an operation takes; it decides who is blocked ([chapter 06](06-locking-and-wait-events.md)) |
| `generated column` | A column computed from an expression — PG 18 computes it on read (`VIRTUAL`) by default, or on write with `STORED` |
| `temporal constraint` | A PG 18 PK/UNIQUE with `WITHOUT OVERLAPS` on a range column, enforced through a GiST exclusion index |

## How it works internally

### Invariants

- A committed row satisfies every **validated** constraint on its table; a
  `NOT VALID` constraint guarantees this only for rows written after it was
  added. (Upstream invariant —
  [ALTER TABLE notes](https://www.postgresql.org/docs/18/sql-altertable.html).)
- Constraint checks see concurrent writers through the lock system, not
  through snapshots alone — uniqueness holds even between transactions that
  cannot see each other's rows. (Upstream invariant —
  [constraints](https://www.postgresql.org/docs/18/ddl-constraints.html).)
- DDL is transactional: an aborted migration leaves neither the constraint nor
  its index behind.
- A constraint never repairs data; it only refuses new violations.

### Lifecycle or sequence

**Enforcement machinery per type:**

| Constraint | Enforced by | Write-path cost |
|---|---|---|
| `PRIMARY KEY` / `UNIQUE` | A unique B-tree index created with the constraint (GiST when `WITHOUT OVERLAPS`) | One index maintenance per non-HOT write ([chapter 09](09-indexes-and-access-methods.md)) plus conflict arbitration under concurrency |
| `CHECK` / `NOT NULL` | Expression evaluated against the candidate row | Cheap and local; no cross-row work |
| `FOREIGN KEY` | System-generated internal triggers on **both** tables (visible in `pg_trigger` as `RI_ConstraintTrigger_*`) | Referencing writes probe the referenced key; referenced deletes/updates fire the action (`CASCADE`, `SET NULL`, `RESTRICT`) row by row |
| `EXCLUSION` | A GiST index probed with the constraint's operators | Range-overlap arbitration; heavier than B-tree equality |

**Adding a constraint to a live table**, in causal order:

1. `ALTER TABLE ... ADD CONSTRAINT` acquires its table lock. A plain FK add
   takes `SHARE ROW EXCLUSIVE` on both tables; most heavyweight forms (type
   changes, `DROP COLUMN`) take `ACCESS EXCLUSIVE`. (Upstream invariant —
   [explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html).)
2. Without `NOT VALID`, the command scans the whole table to prove existing
   rows — holding its lock for the duration.
3. With `NOT VALID`, the command commits immediately: only the catalog row is
   written, and new writes are enforced from now on.
4. A later `VALIDATE CONSTRAINT` scans existing rows under only
   `SHARE UPDATE EXCLUSIVE` (plus `ROW SHARE` on the referenced table for
   FKs) — concurrent reads and writes continue. (Upstream invariant —
   [ALTER TABLE notes](https://www.postgresql.org/docs/18/sql-altertable.html).)

**PostgreSQL 18 additions** (upstream invariants —
[release 18](https://www.postgresql.org/docs/18/release-18.html),
[CREATE TABLE](https://www.postgresql.org/docs/18/sql-createtable.html)):

- **Generated columns default to `VIRTUAL`**: computed on read, occupying no
  storage. A virtual column cannot use user-defined types or functions;
  `STORED` keeps the old compute-on-write behavior. A migration that assumed
  `STORED`-by-default now gets different storage and read-cost behavior.
- **Temporal keys**: `PRIMARY KEY`/`UNIQUE (..., valid_at WITHOUT OVERLAPS)`
  enforce "no overlapping ranges per key" through a GiST index — semantically
  an `EXCLUDE USING GIST (id WITH =, valid_at WITH &&)`.

The absorbed page's judgment survives intact: choose the narrowest correct
type, avoid sentinel values, never implement uniqueness as SELECT-then-INSERT
(two transactions interleave; the unique index arbitrates), and pick FK
actions by ownership semantics — `CASCADE` only when the child is meaningless
without the parent and the delete size is bounded.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Schema ownership | Service repositories own business DDL; migration Jobs run against the `-rw` service, never through poolers | [databases hub](../README.md); [application delivery](../../platform/application-delivery.md) | Repository fact |
| DDL audit trail | `pgaudit.log: ddl, write` records every migration statement | [`instance.yaml` pgaudit block](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| Lock-wait visibility during migrations | `log_lock_waits on` plus the blocked-queries metric and alert | same GUC block; [`deep-signals-alerts.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml) | Repository fact |
| Declarative roles and databases | CNPG `Database`/role objects own who may write which schema | [declarative role management](../declarative-role-management.md) | Repository fact |
| PG 18 virtual generated columns / temporal keys | Available on 18.1; no service schema is declared to use them yet | [Release 18](https://www.postgresql.org/docs/18/release-18.html) | Reference — not deployed |

## Observe it on the live cluster

This lab takes a constraint census for one application database and reads one
FK's hidden enforcement triggers.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; never through PgDog.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Connect to one application database (for example `product`); confirm pod and
  role first.
- Run only the read-only commands shown below — **no DDL of any kind**.

### Query

Constraint census by type, with validation state:

```sql
SELECT
    contype,
    count(*) AS constraints,
    count(*) FILTER (WHERE NOT convalidated) AS not_validated
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
GROUP BY contype
ORDER BY contype;
```

The enforcement triggers behind one foreign key:

```sql
SELECT
    con.conname,
    con.conrelid::regclass AS referencing_table,
    con.confrelid::regclass AS referenced_table,
    tg.tgname,
    tg.tgrelid::regclass AS trigger_on
FROM pg_constraint AS con
JOIN pg_trigger AS tg ON tg.tgconstraint = con.oid
WHERE con.contype = 'f'
ORDER BY con.conname, tg.tgname
LIMIT 12;
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
| `contype` distribution | Which invariants this schema trusts the database with | Nothing about coverage — absent constraints are invisible here |
| `not_validated > 0` | A migration used `NOT VALID` and has not finished `VALIDATE CONSTRAINT` | Not that existing rows violate it — only that they are unproven |
| Two `RI_ConstraintTrigger_*` rows per FK per side | References are enforced by triggers on both tables, firing row-by-row | Not the cost of a specific delete — that depends on child fan-out and indexes on the FK column |
| `referenced_table` of many FKs | The blast radius of deleting from that table | Not that `CASCADE` is configured — read `pg_get_constraintdef` for the action |

### What to notice

- Counts are **observed examples** per database; each service database has its
  own census, and migrations change it release by release.
- An FK is enforcement on *both* tables: a "read-mostly" parent table still
  pays trigger probes for every child write.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| `ADD CONSTRAINT` without `NOT VALID` on a large table | Full-table validation scan under the DDL lock | Writers (and often readers) queue behind the migration | Lock waits ([chapter 06](06-locking-and-wait-events.md)); `log_lock_waits` lines | Use `NOT VALID` then `VALIDATE` (only `SHARE UPDATE EXCLUSIVE`); backfill in bounded batches |
| Unbounded `ON DELETE CASCADE` | Row-by-row child deletes inside one transaction | Long transaction, WAL burst, replication lag | Long-running-transaction alert; WAL rate ([chapter 04](04-wal-and-checkpoints.md)) | Count children first; prefer an explicit deletion workflow |
| FK column without an index on the referencing side | Every referenced-key delete/update seq-scans the child table | "Small" parent delete becomes minutes | Plan of the internal probe; blocked sessions | Service-repo index migration ([chapter 09](09-indexes-and-access-methods.md) — with its write tax) |
| SELECT-then-INSERT uniqueness | Race window between statements | Duplicate-key errors under retry storms, or silent duplicates without a constraint | `pg_stat_database` conflict/error counters; application logs | Let the unique index arbitrate; handle the conflict in the application |
| Constraint dropped "temporarily" for a load | Enforcement gap for every writer | Invalid rows commit; re-adding the constraint now fails validation | `not_validated` census; failed `VALIDATE` | Data repair through the owning service's reconciliation — never interactive fixes |

The invariant that survives every row above: validated constraints never let a
new violation commit. What becomes unavailable is migration speed — integrity
work is lock work.

## Misconceptions and challenge questions

### “The application already validates this, so the constraint is redundant”

The application validates one code path. The constraint validates the table —
including the second service, the backfill script, the retry that raced, and
the admin session. Concurrency is the sharp edge: two transactions can each
"check then write" and both pass application validation; only the unique
index's arbitration under locks stops them (upstream invariant —
[constraints](https://www.postgresql.org/docs/18/ddl-constraints.html)).

### “`NOT VALID` means the constraint is off”

It is fully enforced for every new write from the moment it commits. What is
deferred is only the proof over pre-existing rows — which is exactly why it
can commit without scanning the table. `VALIDATE CONSTRAINT` later needs only
`SHARE UPDATE EXCLUSIVE`, so the heavyweight lock window shrinks to the
catalog change (upstream invariant —
[ALTER TABLE notes](https://www.postgresql.org/docs/18/sql-altertable.html)).

### Challenge: a migration adds a generated column on PG 18 and a nightly export that reads the whole table gets slower, though writes did not

**Model answer:** PG 18 defaults generated columns to `VIRTUAL` — computed on
every read, stored never. The export now evaluates the expression per row per
scan, while the write path is untouched. If the column is read-hot and
write-cold, the migration should say `STORED` explicitly, paying storage and
write-time compute instead (upstream invariant —
[CREATE TABLE generated columns](https://www.postgresql.org/docs/18/sql-createtable.html)).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] Which machine enforces each constraint type, in your own words.
- [ ] The lock story of `ADD CONSTRAINT` with and without `NOT VALID`.
- [ ] Why uniqueness cannot be implemented above the database under
      concurrency.
- [ ] One `pg_constraint` census row and what it cannot tell you.
- [ ] The PG 18 `VIRTUAL` default and the workload it can surprise.

## Related documentation

- [Locking and wait events](06-locking-and-wait-events.md) — the lock modes
  every DDL decision trades in
- [Indexes and access methods](09-indexes-and-access-methods.md) — the indexes
  constraints create and their write tax
- [Partitioning and retention](11-partitioning-and-retention.md) — constraint
  rules on partitioned tables
- [Declarative role management](../declarative-role-management.md) — who may
  write which schema

## References

- [Constraints](https://www.postgresql.org/docs/18/ddl-constraints.html)
- [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html)
- [CREATE TABLE](https://www.postgresql.org/docs/18/sql-createtable.html)
- [Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

---
_Last updated: 2026-09-29 — first published chapter; absorbs the former
schema-and-integrity page and adds enforcement internals, the ALTER TABLE lock
model, and the PG 18 generated-column and temporal-constraint changes._
