# Replication and slots — how standbys converge

When `COMMIT` returns on `product-db`, exactly one standby has flushed that
commit record — not both, and not necessarily the one you will read from next.
This chapter explains what the WAL stream transports, what the acknowledgement
under `ANY 1` actually promises, and why a replication slot is a durability
promise that can fill your disk.

| Quick facts | |
|---|---|
| **Page type** | Explanation-first learning chapter |
| **Audience** | Operator — replication transport, acknowledgement, and lag evidence |
| **Prerequisites** | [WAL and checkpoints](04-wal-and-checkpoints.md); the [shared glossary](README.md#shared-glossary) terms WAL, LSN, replication slot, instance |
| **Deployment status** | Deployed — `product-db` and `platform-db` (3 instances, quorum sync), `product-db-replica` (archive-fed replica cluster) |
| **Platform scope** | Clusters `product-db`, `platform-db`, `product-db-replica`; WAL transport between their instances and the RustFS archive |
| **Evidence context** | Live Kind cluster `kind-homelab`, 2026-10-01 02:43–02:58 UTC, PostgreSQL 18.1 — read-only lab below; other rows are labelled by evidence class |
| **This page owns** | Steps 2 and 4 of the representative-commit case study: the `ANY 1` acknowledgement and the archive-fed DR replay ([chapter 04](04-wal-and-checkpoints.md) owns steps 1 and 3: WAL position and archiving) |
| **Not this page** | Backup, PITR, and timelines — [Backup and PITR](13-backup-and-pitr.md); promotion procedure — [DR replica bootstrap runbook](../runbooks/cnpg-dr-replica-bootstrap.md); DR policy — [Disaster recovery](../disaster-recovery.md) |
| **Previous / next** | [Partitioning and retention](11-partitioning-and-retention.md) / [Backup and PITR](13-backup-and-pitr.md) |

## Questions this chapter answers

- What has been guaranteed, and on how many instances, when `COMMIT` returns
  under the deployed `ANY 1` synchronous configuration?
- Which of the four LSN columns in `pg_stat_replication` corresponds to the
  guarantee a given `synchronous_commit` level buys?
- How does the archive-fed `product-db-replica` receive changes without a
  streaming connection, and which stages contribute to its replay lag?
- What does a replication slot persist, and what happens to `pg_wal` when a
  slot's consumer disappears?
- After a failover, why can logical consumers resume at all — what did
  `sync_replication_slots` copy to the standby beforehand?

## Mental model

Physical replication ships the [WAL](README.md#shared-glossary) stream — the
same bytes [chapter 04](04-wal-and-checkpoints.md) shows being flushed at commit —
to another instance, which replays it page change by page change. Nothing else
travels: no SQL text, no rows, no schema. A standby is therefore always a byte
replay of the primary's storage history, positioned at some
[LSN](README.md#shared-glossary).

Think of the primary as writing a diary and each standby as a reader with a
bookmark. The bookmark position is everything: how far the reader has *received*,
*written*, *flushed*, and *applied* are four different bookmarks, and each
answers a different durability question. The analogy stops at the archive: a
diary has one copy, while this platform also photocopies every finished 64 MB
page into an object store, and one reader (`product-db-replica`) reads only the
photocopies, never the original.

A replication slot is the primary's promise to keep diary pages until a
specific reader confirms them. The promise holds even while the reader is
absent — which is exactly when it becomes expensive.

### Essential terms

| Term | Meaning here |
|---|---|
| `walsender` / `walreceiver` | The primary-side and standby-side processes of one streaming connection |
| `sync_state` | Whether a standby's acknowledgement can satisfy the synchronous commit wait: `sync`, `quorum`, `potential`, or `async` |
| `quorum commit` | `ANY N (...)`: any N of the listed standbys acknowledging releases the commit |
| `restart_lsn` | The oldest WAL position a slot still pins on the primary |
| `designated primary` | The one instance of a replica cluster that performs recovery from the source; promotable in DR |

## How it works internally

### Invariants

- WAL is the only replication payload; a standby can never contain a change
  the primary's WAL does not describe. (Upstream invariant —
  [log-shipping standby servers](https://www.postgresql.org/docs/18/warm-standby.html).)
- Replay order equals WAL order. A standby has one position per moment; it
  cannot apply commit B before commit A that precedes it in the stream.
  (Upstream invariant.)
- A synchronous commit wait releases only when the configured number of
  eligible standbys report the commit record at the level
  `synchronous_commit` demands — flush (`on`, the default), write
  (`remote_write`), or replay (`remote_apply`). (Upstream invariant —
  [`synchronous_commit`](https://www.postgresql.org/docs/18/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT).)
- Synchronous replication does **not** guarantee the standby you read from has
  applied the commit: with `synchronous_commit = on`, replay lag is invisible
  to the committing session. (Upstream invariant; the deployed level is the
  default `on` — Repository fact, no override in
  [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml).)
- A synchronous acknowledgement proves that enough standbys processed the
  commit; it does not prove that an arbitrary remaining failover candidate has
  it. CloudNativePG's separate failover-quorum mechanism provides that stronger
  promotion gate, and it is not enabled here. (Upstream invariant + Repository
  fact — [CloudNativePG failover quorum](https://cloudnative-pg.io/docs/1.30/failover/).)
- A slot pins WAL from its `restart_lsn` forward until the consumer advances
  it; only `max_slot_wal_keep_size` bounds that retention, and it is not set
  here, so retention is unbounded. (Upstream invariant + Repository fact.)

### Lifecycle or sequence

The standby's supply loop, in causal order
([standby server operation](https://www.postgresql.org/docs/18/warm-standby.html#STANDBY-SERVER-OPERATION)):

1. **Restore from archive.** In standby mode the server first calls
   `restore_command` for the next segment. Success feeds the startup process;
   failure moves to step 2.
2. **Local `pg_wal`.** Any segments already present locally are replayed.
3. **Streaming.** If `primary_conninfo` is configured, a `walreceiver`
   connects; the primary forks a `walsender`, which reads WAL and streams from
   the last valid record. The sender's `state` passes through `catchup` before
   reaching `streaming`.
4. **Loop.** On disconnect or end of stream, the standby returns to step 1.
   The loop ends only at shutdown or promotion.

Inside `product-db`, all three instances participate in one quorum:
CloudNativePG renders `synchronous_standby_names = 'ANY 1 (pod-2, pod-3, ...)'`
from `synchronous: {method: any, number: 1}` — the operator forbids setting
the GUC directly (Repository fact —
[`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml)
`synchronous` block; upstream rendering per the
[CloudNativePG replication documentation](https://cloudnative-pg.io/docs/1.30/replication)).
`dataDurability: required` means the commit wait is never silently relaxed:
if no eligible standby is available, writes pause rather than degrade to
asynchronous (Upstream invariant — CloudNativePG replication documentation).

`product-db-replica` never appears in that quorum. It is a separate Cluster
resource whose single instance runs as a **designated primary** in continuous
recovery: its `externalClusters` entry names the Barman object store, so the
operator configures the restore path instead of `primary_conninfo` — step 1
of the loop, forever, with no step 3 (Repository fact —
[`product-db-replica/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db-replica/instance.yaml);
mechanism per the
[CloudNativePG replica cluster documentation](https://cloudnative-pg.io/docs/1.30/replica_cluster)).

```mermaid
sequenceDiagram
    participant C as Client
    participant P as product-db primary
    participant S as One standby of two<br/>(quorum ANY 1)
    participant A as RustFS WAL archive
    participant R as product-db-replica<br/>(designated primary)

    C->>P: COMMIT
    P->>P: flush commit record to local WAL (ch. 04)
    P->>S: walsender streams WAL
    S->>S: write + flush commit record
    S-->>P: flush_lsn acknowledgement
    P-->>C: COMMIT returns (primary + at least 1 standby durable)
    Note over P,S: other standby may already be durable or may lag
    P->>A: archiver on segment switch<br/>or archive_timeout 5min (ch. 04)
    R->>A: restore_command polls next segment
    A-->>R: gzip WAL object<br/>(restores to 64 MB segment)
    R->>R: startup process replays — pg_last_wal_replay_lsn advances
```

### What to notice

- The client's `COMMIT` returns after the **first required** standby flush
  acknowledgement — the diagram's reply arrow — so the primary and at least
  one standby hold the commit durably. The other standby may already have
  flushed it; `ANY 1` defines a minimum, not an exact copy count.
- `product-db-replica` appears **after** the archive, not after the primary:
  its recency includes segment completion, Barman upload, object-store
  availability, restore polling, download, and replay. `archive_timeout` bounds
  only the low-traffic wait for a forced segment switch.

## How homelab uses it

| Upstream mechanism | Homelab setting or behavior | Evidence | Class/status |
|---|---|---|---|
| Quorum synchronous commit `ANY N` | `method: any, number: 1, dataDurability: required` on `product-db` and `platform-db` | [`product-db/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db/instance.yaml) `synchronous` block | Repository fact |
| `synchronous_commit` level | Default `on` (flush on the quorum standby), not `remote_apply` | Same manifest — no override in `parameters` | Repository fact |
| Failover safety gate | `failoverQuorum` is not enabled; synchronous commit and safe promotion are distinct guarantees | Same manifest · [CloudNativePG failover quorum](https://cloudnative-pg.io/docs/1.30/failover/) | Repository fact + Upstream invariant |
| HA replication slots per standby | Operator-managed slots, plus `synchronizeLogicalDecoding: true` | Same manifest, `replicationSlots.highAvailability` | Repository fact |
| Failover slot synchronization | `sync_replication_slots: "on"`, `hot_standby_feedback: "on"` | Same manifest, parameters block | Repository fact |
| Standalone replica cluster in continuous recovery | `product-db-replica`: 1 instance, `replica.enabled`, source `product-db-primary` via Barman object store; three instances until 2026-09-29, reduced because each standby's restore polling cost more CPU than the serving cluster ([#1134](https://github.com/duynhlab/homelab/pull/1134)) | [`product-db-replica/instance.yaml`](../../../kubernetes/infra/configs/databases/clusters/product-db-replica/instance.yaml) header + `replica`/`externalClusters` | Repository fact |
| Slot-retained WAL as a failure signal | `CNPGInactiveSlotRetainingWAL` alert; per-alert runbook | [`deep-signals-alerts.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/deep-signals-alerts.yaml) · [runbook](../../observability/runbooks/postgresql/CNPGInactiveSlotRetainingWAL.md) | Repository fact |
| Lag alerting | `CNPGClusterStandbyNotStreaming`, physical-replication-lag warning/critical, `CNPGDRClusterOffline` | [`replication-health.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/replication-health.yaml) · [`dr-cluster-offline.yaml`](../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/dr-cluster-offline.yaml) | Repository fact |
| Measured failover cost | Switchover 11.4 s in the recorded drill | [Reliability targets](../reliability-targets.md) | Repository fact (their evidence) |

Why it matters here: the deployed quorum means a single standby restart does
not block writes (the other can acknowledge), but losing **both** standbys
freezes commits by design — `dataDurability: required` chooses durability over
availability. It does not by itself prove that whichever replica remains
promotable contains every acknowledged commit; that is the separate guarantee
the undeployed `failoverQuorum` feature would gate. The slot-sync pair
(`sync_replication_slots` +
`synchronizeLogicalDecoding`) exists so that logical consumers (the platform's
CDC-style consumers, when present) survive a failover: the standby maintains
copies of failover-enabled logical slots and can serve them after promotion
(Upstream invariant —
[replication slot synchronization](https://www.postgresql.org/docs/18/logicaldecoding-explanation.html#LOGICALDECODING-REPLICATION-SLOTS-SYNCHRONIZATION)).

## Observe it on the live cluster

This lab reads the acknowledgement ladder on the `product-db` primary, the
slot inventory, and the DR replica's replay position — case-study steps 2
and 4. Step 1 (current WAL position) and step 3 (archiver state) are the
[chapter 04 lab](04-wal-and-checkpoints.md); run them in the same session for
one coherent trace.

### Prerequisites and safety

- Connect with `kubectl cnpg psql product-db -n product`; the third query uses
  `kubectl cnpg psql product-db-replica -n product` (its single instance is
  the designated primary of that cluster).
- Open with the [safe session header](../observability-and-troubleshooting.md#safe-session-header)
  and `SET default_transaction_read_only = on;`.
- Confirm the kubeconfig context, the pod that answered, and its role before
  reading.
- Run only the read-only queries below.

### Query

On the `product-db` primary — the acknowledgement ladder and slot inventory:

```sql
SELECT
    application_name,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_state
FROM pg_stat_replication
ORDER BY application_name
LIMIT 10;
```

```sql
SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn,
    wal_status,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
ORDER BY slot_name
LIMIT 20;
```

On `product-db-replica` — recovery state and replay position:

```sql
SELECT
    pg_is_in_recovery() AS in_recovery,
    pg_last_wal_replay_lsn() AS replay_lsn,
    now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_commit
LIMIT 1;
```

### Observed example

```text
-- product-db-1 (primary): the acknowledgement ladder, 02:43 UTC
application_name  state      sent/write/flush/replay  write_lag  flush_lag  replay_lag  sync_state
product-db-2      streaming  2/840083F0 (all four)    0.9 ms     3.0 ms     3.2 ms      quorum
product-db-3      streaming  2/840083F0 (all four)    0.7 ms     2.6 ms     2.7 ms      quorum

slot_name           slot_type  active  restart_lsn  wal_status  retained_wal
_cnpg_product_db_2  physical   t       2/840083F0   reserved    0 bytes
_cnpg_product_db_3  physical   t       2/840083F0   reserved    0 bytes

-- product-db-replica-1 (DR, designated primary), case study steps 2 and 4
              replay_lsn  receive_lsn  last_replayed_commit  time_since
02:47:00 UTC  2/88000000  (null)       02:44:51              00:02:08
02:58:15 UTC  2/90000000  (null)       02:54:07              00:04:07
backend types: archiver, background writer, checkpointer, io worker ×3, startup
               (no walreceiver)
```

Observation context:

| Field | Value |
|---|---|
| **Observed at** | 2026-10-01 02:43–02:58 UTC |
| **Repository** | `main` at `b884a26c` (what Flux served); chapters on `docs/pg-internals-chapters` |
| **Cluster/context** | `kind-homelab`; both clusters created 2026-09-30 ≈13:45 UTC (the `stats_reset` epoch below) |
| **PostgreSQL** | `PostgreSQL 18.1 (Debian 18.1-1.pgdg13+2)`, image `ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie` |
| **Cluster/instance** | `product-db` / `product-db-1`; DR replay on `product-db-replica` / `product-db-replica-1` |
| **CNPG role** | `primary` on `product-db-1`; `product-db-replica-1` is the designated primary of the replica cluster (pod labels `cnpg.io/instanceRole`) |
| **PostgreSQL recovery state** | primary `f`; `product-db-replica-1` `t` (timeline 1) |
| **Synchronous state** | `ANY 1 ("product-db-2","product-db-3","product-db-1")`; both standbys `streaming`, `sync_state = quorum` |
| **Database** | `postgres` |

What this run showed:

- Both standbys were `quorum` candidates with identical LSNs. Flush lag was about 3 ms, the latency an `on` commit pays to the faster of the two. The same ladder on `platform-db` showed about 1.2 ms.
- The two HA slots were active, with no retained WAL beyond the standbys' position. `max_slot_wal_keep_size = -1`, so nothing caps retention if a slot goes inactive. The alert, not the engine, is the guard.
- The DR replica is archive-fed: `pg_last_wal_receive_lsn()` is NULL, and it runs a `startup` process but no `walreceiver`. It also runs an `archiver`, because as the designated primary of its own cluster it archives to its own store.
- Both replica snapshots had replayed exactly up to the primary's current LSN, which was the start of the segment not yet archived. The last replayed commit was 2–4 minutes old. At 02:58 the commits after 02:56:04 were still in an unarchived segment, so DR freshness is bounded by the `archive_timeout` switch plus restore polling, as [04](04-wal-and-checkpoints.md) explains.
- The DR replica ran one instance, matching the manifest. It was enabled only for this run, because a local patch keeps it off on Kind to save CPU.

### How to read the result

| Field or relationship | Interpretation | What it cannot prove |
|---|---|---|
| Two rows in `pg_stat_replication`, `sync_state` = `quorum` | Both standbys are candidates; any one flush acknowledgement releases a commit | Not which standby acknowledged any past commit — the quorum winner varies per transaction |
| `flush_lsn` vs `replay_lsn` gap on a standby | Commits durable there but not yet visible to its read queries (`synchronous_commit = on` waits only for flush) | Not data loss — replay is behind, durability is not |
| `write_lag` / `flush_lag` / `replay_lag` | The extra commit latency `remote_write` / `on` / `remote_apply` **would** cost against this standby | Nothing about past lag; these are current-sample estimates |
| Slot with `active = f` and growing `retained_wal` | A consumer is gone and the primary is pinning WAL for it — the failure mode behind [`CNPGInactiveSlotRetainingWAL`](../../observability/runbooks/postgresql/CNPGInactiveSlotRetainingWAL.md) | Not who the consumer was or whether it returns; the slot has no health opinion |
| Replica: `in_recovery = t`, recent `time_since_last_replayed_commit` | The archive-fed loop has replayed a recent commit | End-to-end lag or archive health by itself: compare primary WAL/archive positions with DR replay, because no new commits, upload delay, restore polling, and replay delay can produce similar timestamps |
| LSN arithmetic via `pg_wal_lsn_diff` | Byte distance between positions | Not a transaction count and not elapsed time |

### What to notice

- Every LSN, lag interval, and retained-WAL size above is an **observed
  example** — they change with every commit and every archive cycle.
- The DR replica can be simultaneously *healthy* (the loop runs and replay
  advances) and *minutes behind*. No single number proves both health and
  freshness; correlate the primary's current/archive positions with the DR
  replay position and timestamp.

## Failure modes and trade-offs

| Trigger | Internal reaction | User-visible symptom | Evidence | Recovery boundary or cost |
|---|---|---|---|---|
| One `product-db` standby down | Quorum still satisfiable by the other; sender row disappears | None for writers | `pg_stat_replication` row count; `CNPGClusterStandbyNotStreaming` | Redundancy reduced from 2 spare copies to 1 (Inference — not induced here) |
| Both standbys down | `dataDurability: required` keeps the commit wait; sessions block in `SyncRep` wait | Writes hang, reads fine | `pg_stat_activity.wait_event = SyncRep`; HA alerts | Deliberate: durability over availability; recovery = restore a standby, not weaken the setting (Upstream invariant) |
| Primary and the standby that acknowledged a commit become unavailable | The remaining standby may be behind that commit; `dataDurability: required` does not validate promotion candidates | A failover to the remaining standby can lose an acknowledged commit | Available-instance LSNs and CNPG failover state; `failoverQuorum` is absent | Wait for an up-to-date instance or accept the recovery trade-off; enabling failover quorum is a separate architecture decision (Upstream invariant + Repository fact) |
| Standby restarts and reconnects | Sender passes `startup` → `catchup` → `streaming`; slot guarantees no segment gap | Temporary lag spike | `state` column; lag intervals | Catch-up competes with foreground WAL for I/O (Inference) |
| Slot consumer disappears | `restart_lsn` frozen; WAL accumulates without bound (`max_slot_wal_keep_size` unset) | `pg_wal` growth → disk pressure | `pg_replication_slots.wal_status`, retained bytes; `CNPGInactiveSlotRetainingWAL` | Dropping the slot frees disk but abandons the consumer's resume point permanently (Upstream invariant) |
| Archive stalls (RustFS down or credentials broken) | Primary keeps segments pending archive; DR replica starves | DR replay timestamp ages; later disk pressure on primary | `pg_stat_archiver.failed_count`; `CNPGWALArchiveFailing`, `CNPGDRClusterOffline` | DR RPO degrades silently first — the primary is healthy while the replica falls behind (Inference) |
| DR replica promoted | Recovery exits, timeline increments ([chapter 13](13-backup-and-pitr.md)); cluster is a 1-instance primary | Write service from a single point of failure | `pg_is_in_recovery() = f` | Promotion procedure — including raising `instances` back to 3 — is owned by the [DR replica bootstrap runbook](../runbooks/cnpg-dr-replica-bootstrap.md); never promote from a chapter |

During every failure above, the invariant that survives is WAL ordering: no
replica ever holds a change out of order or ahead of the primary's history.
What becomes temporarily unavailable is either commit progress (quorum loss)
or recency (archive stall) — never consistency.

## Misconceptions and challenge questions

### “Synchronous replication means my next read sees the write”

No. The deployed level is `synchronous_commit = on`: the quorum standby has
**flushed** the commit record, not applied it. Its `replay_lsn` may still be
behind, so a read routed to that standby can miss the row you committed —
that is precisely the gap [PgDog's LSN check](../poolers.md) papers over for
read routing. Visibility-on-standby requires `remote_apply`, which is not
deployed (Repository fact + Upstream invariant —
[`synchronous_commit` modes table](https://www.postgresql.org/docs/18/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT)).

### “The DR replica is lagging, so replication is broken”

The DR replica has no replication connection to break. It replays photocopies:
finished segments from the archive. A quiet primary can spend up to roughly
`archive_timeout` waiting for a forced switch, then upload, polling, download,
and replay add their own delay. A recent replay timestamp is encouraging but
does not prove a fixed lag bound; diagnose freshness by comparing both ends of
the pipeline.

### Challenge: the primary and acknowledging standby disappear

The primary returned `COMMIT` after one standby flushed the record. A partition
then makes both of those instances unavailable while the other standby remains.
Can `dataDurability: required` prove that the remaining promotion candidate has
the commit?

**Model answer:** No. `dataDurability: required` prevented the commit wait from
degrading while the transaction ran, but `ANY 1` proves only that *some*
standby acknowledged. The remaining standby may be behind. This cluster does
not enable CloudNativePG's separate `failoverQuorum`, so promotion is not gated
on proving that the candidate contains every synchronously acknowledged commit
([CloudNativePG failover quorum](https://cloudnative-pg.io/docs/1.30/failover/)).

## Teach-back checklist

Before continuing, explain these without rereading the chapter:

- [ ] What travels over a physical replication connection, in your own words.
- [ ] What exactly is durable, and on how many instances, when `COMMIT`
      returns under the deployed `ANY 1` + `dataDurability: required`.
- [ ] The predicted behavior of writes when both `product-db` standbys are
      down, and why that is a choice rather than a bug.
- [ ] One row of the slot query and what a frozen `restart_lsn` with growing
      retained WAL does — and does not — tell you.
- [ ] Which stages contribute to archive-fed DR replay lag, and why
      `archive_timeout` alone is not an end-to-end bound.
- [ ] Why synchronous acknowledgement and safe failover are different
      guarantees when `failoverQuorum` is not enabled.

## Related documentation

- [WAL and checkpoints](04-wal-and-checkpoints.md) — case-study steps 1 and 3
- [Backup and PITR](13-backup-and-pitr.md) — timelines and what promotion rewrites
- [Disaster recovery](../disaster-recovery.md) — standby taxonomy and DR policy
- [DR replica bootstrap runbook](../runbooks/cnpg-dr-replica-bootstrap.md) — the promotion procedure
- [Reliability targets](../reliability-targets.md) — measured switchover and PITR drills

## References

- [Log-shipping standby servers](https://www.postgresql.org/docs/18/warm-standby.html)
- [`synchronous_commit` and WAL settings](https://www.postgresql.org/docs/18/runtime-config-wal.html)
- [Replication configuration, `sync_replication_slots`](https://www.postgresql.org/docs/18/runtime-config-replication.html)
- [`pg_stat_replication`](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [Replication slot synchronization](https://www.postgresql.org/docs/18/logicaldecoding-explanation.html)
- [CloudNativePG replication](https://cloudnative-pg.io/docs/1.30/replication) and [replica clusters](https://cloudnative-pg.io/docs/1.30/replica_cluster)
