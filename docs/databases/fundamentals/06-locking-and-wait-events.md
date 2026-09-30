# Locking and wait events — who is blocking whom

When checkout latency spikes and CPU is idle, the time is usually being spent
*waiting* — and PostgreSQL names every wait. This chapter turns `pg_locks`,
`pg_blocking_pids()`, and the wait-event taxonomy into an evidence chain that
identifies the one session everyone else is queued behind.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Operator — contention diagnosis on live evidence |
| **Prerequisites** | [MVCC and snapshots](05-mvcc-and-snapshots.md); glossary terms [tuple, XID](README.md#shared-glossary) |
| **Deployment status** | Deployed — lock telemetry and alerts active on `platform-db` and `product-db` |
| **Platform scope** | Engine-wide mechanism; metrics exported per cluster, per database |
| **Evidence context** | Repository facts only — live lab pending verification on the Ubuntu Kind cluster |
| **This page owns** | The blocking-evidence chain: lock modes → waiters → root blocker → wait-event class |
| **Not this page** | Why versions coexist — [MVCC and snapshots](05-mvcc-and-snapshots.md); per-alert procedures — [PostgreSQL alert runbooks](../../observability/runbooks/postgresql/README.md) |
| **Previous / next** | [MVCC and snapshots](05-mvcc-and-snapshots.md) / [Vacuum and freezing](07-vacuum-and-freezing.md) |

## Questions this chapter answers

- Which lock does an ordinary `UPDATE` take, and what does it actually block?
- What happens between two `UPDATE`s targeting the same row, step by step?
- Where does the evidence live for "session A waits on session B", and which
  query walks the chain to the root?
- Which wait-event class distinguishes a lock queue from an I/O stall or a
  saturated lightweight lock?
- When does the deadlock detector run, and who pays for it?

## Mental model

MVCC removed reader-vs-writer conflicts, so what remains is coordination among
*changers*: two sessions changing the same row, a migration changing a table's
shape while traffic changes its rows. PostgreSQL coordinates with locks at two
grains — table-level modes that mostly coexist, and row-level locks that queue
writers on the same row.

A lock conflict is not an error; it is a queue. The waiting session sits in
`pg_stat_activity` with `wait_event_type = 'Lock'`, fully idle, until the
holder commits or aborts. Trouble is therefore rarely "locks exist" and almost
always "someone holds one longer than the workload can absorb" — and the
telemetry names that someone.

The queue analogy stops at ordering: lock queues are not strictly first-come
for incompatible modes, and a transaction never conflicts with itself, so
reasoning must always go through the conflict matrix, not intuition.

### Essential terms

| Term | Meaning here |
|---|---|
| `lock mode` | One of eight table-level modes; only the conflict matrix defines their meaning ([explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html)) |
| `row lock` | Tuple-scope lock (`FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE`, `FOR KEY SHARE`) written into the tuple itself, not into memory tables |
| `fast path` | A shortcut recording weak, unconflicted relation locks per backend, bypassing the shared lock table |
| `LWLock` | Lightweight lock protecting shared memory structures (buffer mappings, WAL insert positions); held for microseconds, never across user waits |
| `wait event` | The labelled reason a backend is not on CPU: class (`Lock`, `LWLock`, `IO`, `Client`, ...) plus a specific name |
| `deadlock` | A cycle in the waits-for graph; detected after `deadlock_timeout` and broken by aborting one participant |

## How it works internally

### Invariants

- Two transactions never hold conflicting locks on the same object at the same
  time; everything else — queues, timeouts, deadlock aborts — exists to
  preserve this. (Upstream invariant —
  [explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html).)
- All locks are released at transaction end, never mid-transaction; long
  transactions therefore hold their worst lock for their whole life. (Upstream
  invariant.)
- Row locks live in tuple headers on disk, so locking a million rows cannot
  exhaust a lock table — but `SELECT FOR UPDATE` writes those tuples, doing
  real I/O. (Upstream invariant — [row-level locks](https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-ROWS).)
- Lock waits are invisible to the CPU: a blocked backend consumes no cycles,
  which is exactly why latency without load points here.

### Lifecycle or sequence

Two `UPDATE`s collide on the same order row:

1. Session A's `UPDATE` takes `ROW EXCLUSIVE` on the table (compatible with
   other readers and writers) and marks the target tuple locked by writing its
   own XID into the tuple's `xmax` — the row lock *is* tuple metadata
   ([chapter 05](05-mvcc-and-snapshots.md) explained those stamps).
2. Session B's `UPDATE` reaches the same tuple, sees a live locker, and takes a
   short `tuple`-scope lock plus a wait on A's `transactionid` lock — B now
   shows `wait_event_type = 'Lock'`, `wait_event = 'transactionid'`.
3. Every transaction holds an exclusive lock on its own XID for its lifetime;
   "wait until A ends" is implemented as "queue on A's XID lock". This is the
   edge `pg_blocking_pids(B)` reports.
4. If A commits, B re-fetches the row's newest version and applies its update
   (under `READ COMMITTED`) or fails with a serialization error (under
   `REPEATABLE READ`). If A aborts, B proceeds against the original version.
5. If instead A later waits on something B holds, both sit in `Lock` waits
   until one backend's wait exceeds `deadlock_timeout` (1 s default); that
   backend runs the waits-for cycle search and one participant is aborted with
   a deadlock error, with the whole cycle logged when `log_lock_waits` is on.
   (Upstream invariant — [deadlocks](https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-DEADLOCKS);
   the detector cost is why the timeout exists.)

Below the user-visible layer, shared structures are protected by **LWLocks**
and, for relation locks that cannot conflict, the **fast path** keeps
bookkeeping per backend instead of in the shared lock table. Sustained
`LWLock` waits are a saturation signal (buffer mapping, WAL insert), not an
application bug — that boundary matters when reading the census below.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Lock waits are silent by default | `log_lock_waits: "on"` logs any wait crossing `deadlock_timeout`, so every >1 s queue leaves a log line | [product-db GUC block](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) | Repository fact |
| Waiters are countable from `pg_locks` / `pg_blocking_pids` | Exported per cluster as `cnpg_pg_blocking_queries_blocked_queries` and `cnpg_pg_locks_count` | [`pg_blocking_queries`, `pg_locks_count` custom queries](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |
| Blocking becomes an incident only when sustained | `CNPGBlockedQueries` fires at `> 0` held for 10 m; `CNPGDeadlocksIncreasing` on any deadlock increase over 10 m | [deep-signals alerts](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml) | Repository fact |
| Wait-event classes locate the stalled layer | Active backends are exported grouped by class (`Lock`, `IO`, `LWLock`, ... or `CPU`) | [`pg_wait_events` custom query](../../../kubernetes/infra/configs/databases/clusters/product-db/configmaps/monitoring-queries.yaml) | Repository fact |
| Transaction mode pooling multiplexes sessions | Through PgDog/PgBouncer, one client's lock can be held by a backend another client observes — a reason labs and lock forensics connect directly | [Poolers](../poolers.md) | Repository fact |

The alert thresholds encode a diagnosis order: a 10-minute-old `Lock` wait has
a root blocker worth naming, while deadlocks — already auto-resolved by the
engine — alert because *recurrence* means a lock-ordering bug in application
code, not a database failure.

## Observe it on the live cluster

This lab takes a wait-event census and walks any blocking chain to its root.
On a healthy idle cluster the chain query returns zero rows — that is the
baseline being verified, not a failed lab.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; never through PgDog
  or PgBouncer.
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Confirm the kubeconfig context, the instance pod, and its role before
  reading.
- Run only the read-only commands shown below.

### Query

Wait-event census with upstream descriptions (the deployed metric's query,
joined to `pg_wait_events` for meaning):

```sql
SELECT
    coalesce(a.wait_event_type, 'CPU') AS wait_class,
    a.wait_event,
    count(*) AS backends,
    max(w.description) AS description
FROM pg_stat_activity AS a
LEFT JOIN pg_wait_events AS w
    ON w.type = a.wait_event_type AND w.name = a.wait_event
WHERE a.state = 'active'
  AND a.pid <> pg_backend_pid()
GROUP BY 1, 2
ORDER BY backends DESC
LIMIT 20;
```

Blocking chain to the root (absorbed from the retired monitoring page):

```sql
SELECT
    blocked.pid AS blocked_pid,
    pg_blocking_pids(blocked.pid) AS blocker_pids,
    age(clock_timestamp(), blocked.query_start) AS blocked_for,
    left(blocked.query, 160) AS blocked_query
FROM pg_stat_activity AS blocked
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0
ORDER BY blocked.query_start
LIMIT 50;
```

Lock inventory for one suspicious backend (replace the pid from the chain):

```sql
SELECT
    locktype,
    mode,
    granted,
    fastpath,
    relation::regclass AS relation,
    transactionid
FROM pg_locks
WHERE pid = 12345
ORDER BY granted, locktype
LIMIT 30;
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
| `wait_class = 'CPU'` rows | Backends actually executing at sample time (the census labels non-waiting as CPU) | Not sustained CPU saturation — this is one instant, not a rate |
| `wait_class = 'Lock'` | Queued behind another transaction; the chain query names the blocker | Not *which* statement of the blocker conflicts — locks are held since whichever earlier statement took them |
| `wait_class = 'LWLock'` sustained across samples | Shared-structure contention (buffers, WAL insert) — capacity, not application ordering | A single sample proves nothing; LWLocks are normally sub-millisecond |
| `blocker_pids` array | Direct plus indirect blockers of that waiter | Not the business owner of the transaction — join back to `pg_stat_activity` for user/app fields |
| `granted = f` rows in `pg_locks` | Exactly what that backend is queued for (mode + object) | — |
| `fastpath = t` | The lock never touched the shared lock table (weak, unconflicted) | Not that it is harmless to DDL — a fast-path `ACCESS SHARE` still blocks `ACCESS EXCLUSIVE` |
| Empty chain result | No blocking at sample time | Not that the 10-minute alert was wrong earlier — blocking is bursty; compare with the metric's history |

### What to notice

- Every row is an **observed example** of one instant; contention evidence
  should always be paired with the exported metrics' time series.
- The blocked session's `query` shows the *waiter*, not the conflict: the
  blocker may be `idle in transaction` with an innocent-looking last query —
  which is why [chapter 05](05-mvcc-and-snapshots.md)'s idle-transaction alert
  and this chapter's chain query point at the same villain.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| Writer holds a row lock through a long transaction | Waiters queue on its XID lock, each idle | Latency spike with idle CPU | `CNPGBlockedQueries`, chain query, `log_lock_waits` lines | End the blocker via its owning application; cancelling waiters only multiplies retries |
| Migration takes `ACCESS EXCLUSIVE` under traffic | Every later query on that table queues behind the DDL, which itself queues behind older readers | Full stop on one table, cascading pool exhaustion | Chain query rooted at the DDL pid | Bounded `lock_timeout` in migrations; scheduling — the conflict matrix, not the data volume, is the cost |
| Lock-ordering bug between two code paths | Waits-for cycle; detector aborts one transaction after `deadlock_timeout` | Sporadic deadlock errors | `CNPGDeadlocksIncreasing`, logged cycle | Fix ordering in the application; the abort is the engine succeeding, and only recurrence is actionable |
| Shared-structure saturation | Backends pile up in `LWLock` waits nothing in `pg_locks` explains | Throughput ceiling under high concurrency | Wait census over time | Capacity/tuning territory — [chapter 14](14-monitoring-and-capacity.md); no session is at fault |

Through all of these, the invariant holds: no two conflicting locks coexist —
the engine is never confused about ownership. What is sacrificed is time; the
diagnosis discipline exists because *whose* time is the only real question.

## Misconceptions and challenge questions

### “Readers get blocked by our big writes”

Plain readers take `ACCESS SHARE`, which conflicts only with
`ACCESS EXCLUSIVE` — schema changes, not writes. A read that appears stuck
behind writes is queued behind DDL, or is itself a locking read
(`SELECT ... FOR UPDATE`). Check `pg_locks.mode` before blaming MVCC.

### “The deadlock alert means PostgreSQL is broken”

The detector *resolving* a cycle is the designed behavior; the alert exists
because recurring cycles indicate an application acquiring the same locks in
different orders. The fix is ordering (or lock scope), and the evidence is the
logged cycle pair.

### Challenge: the invisible blocker

The chain query shows six sessions blocked by pid 4711. In `pg_stat_activity`,
pid 4711 is `idle in transaction`, its last query a fast one-row `SELECT`.
Reconstruct what happened and name the safe resolution.

**Model answer:** An earlier statement of that transaction took the contested
lock (locks persist to transaction end, regardless of the last statement
shown); the session then went idle without committing. Resolution goes through
the owning application path — commit, roll back, or cancel that transaction —
per the [safe mitigation order](../observability-and-troubleshooting.md);
killing the six waiters resolves nothing. See
[Lifecycle or sequence](#lifecycle-or-sequence).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] Which locks an `UPDATE` takes at table and row grain, and where the row
  lock physically lives.
- [ ] How "waiting for a row" becomes "queued on a transaction's XID lock".
- [ ] The predicted sequence when two sessions deadlock, including who detects
  it and when.
- [ ] One census or chain row and the limit of what a single sample proves.
- [ ] The trade-off behind `deadlock_timeout` — detection latency versus
  detector cost.

## Related documentation

- [MVCC and snapshots](05-mvcc-and-snapshots.md) — why readers are absent from
  every queue here
- [Vacuum and freezing](07-vacuum-and-freezing.md) — the other victim of long
  transactions
- [Observability and troubleshooting](../observability-and-troubleshooting.md)
  — safe mitigation hierarchy
- [CNPGBlockedQueries runbook](../../observability/runbooks/postgresql/CNPGBlockedQueries.md)
  and [CNPGDeadlocksIncreasing runbook](../../observability/runbooks/postgresql/CNPGDeadlocksIncreasing.md)

## References

- [Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html)
- [Wait events and `pg_wait_events`](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [Lock management configuration](https://www.postgresql.org/docs/18/runtime-config-locks.html)
- [`pg_locks` view](https://www.postgresql.org/docs/18/view-pg-locks.html)

---
_Last updated: 2026-09-29 — first published chapter version for issue #1137;
absorbs the locking sections of the retired mvcc-locking-and-vacuum page and
the blocking-chain queries of the retired monitoring page._
