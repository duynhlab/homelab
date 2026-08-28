# RFC-0028 Replicate the ClickHouse observability store

| Status | Scope | Research | Created | Last updated |
|--------|-------|----------|---------|--------------|
| Accepted | infra | [./research.md](./research.md) — gate passed 2026-08-28 | 2026-08-28 | 2026-08-28 |

> **Don't forget: every decision is a tradeoff.** The two costs of the chosen
> schema path are named below as revisit triggers, not hidden.

## Prerequisites

- [x] [./research.md](./research.md) merged (#947, amendments #948/#949); [research review gate](./research.md#research-review-gate) ticked 2026-08-28
- [x] Context7 audit complete (see research § Context7 audit log)
- [x] Owner approved **ready for RFC** (2026-08-28, in-session)
- Mechanism deep-dive lives in [./research.md](./research.md) — this file only decides
- Status → **`Accepted`** 2026-08-28. ADR: [`ADR-065`](../../adr/ADR-065-clickhouse-replicated-topology/) — created at `Accepted` with this review (one decision: 1×3 + CHK with exporter-owned replicated schema). `docs/api/`: N/A — no service contract touches ClickHouse. **Platform docs that MUST move at implementation** (infra-only ≠ docs-free):
  - `docs/observability/clickhouse/README.md` — quick-facts row ("MergeTree, single shard × single replica"), deployment inventory, and the DDL section (engine becomes `ReplicatedMergeTree`)
  - `docs/observability/tracing/architecture.md` — the accepted-gap line "ClickHouse is a single shard … lost volume is lost traces" is retired for the ClickHouse half (VictoriaTraces stays single-node by design)
  - `docs/platform/setup.md` — the `clickhouse-local` wave description gains the CHK
  - `docs/observability/alerting/alert-catalog.md` — `ClickHouseZooKeeperExceptions` re-enabled + per-replica reachability
  - CHANGELOG, as always

## Summary

The ClickHouse observability store moves from 1×1 (one replica, one PVC, the
recorded *lost volume = lost traces* gap) to **1 shard × 3 replicas
coordinated by a 3-node ClickHouse Keeper quorum**, with the schema recreated
from scratch as `ReplicatedMergeTree` **by the otel-collector exporter
itself** (`create_schema: true` + `cluster_name` + `table_engine`) — zero new
components beyond the Keeper. Sharding/Distributed stays a documented
reference (research § trigger signals), and the least-privilege user model
stays an optional side-rung. Owner decisions binding this RFC: recreate from
scratch · straight to 3+3 · default `{uuid}` replica path · keep default
access · exporter-owned schema (Option B).

## Motivation

One bad disk currently erases 90 days of edge access logs (ClickHouse-only
per ADR-061) and all long-retention traces. Replication converts that from
unrecoverable data loss into a failover. Everything this needs is already
deployed except the topology itself: operator 0.27.3 (CHK CR, macros,
generated `remote_servers` with `internal_replication: true`) and a collector
whose exporter templates carry `ON CLUSTER` + `ENGINE` slots on every table.

### Goals

- Survive the loss of any single ClickHouse pod/PVC with no data loss and no
  read/write outage (Grafana keeps answering; the collector keeps inserting).
- Keep the delta small: no new schema owner, no new waves, no new repos —
  one CHK resource, three numbers, one exporter config block.
- Leave a written trail for the two futures deliberately not built: sharding
  (trigger table in research) and the user model (optional rung).

### Non-Goals

- **Sharding / Distributed tables** — researched to know the trigger signals;
  explicitly not built (owner: "docs để biết, nếu tương lai hệ thống thật bự").
- **Least-privilege user model** — optional side-rung; `default` user stays.
- Preserving the current 90-day dataset — **fresh tables by owner decision**
  (nothing here is a real deployment yet).
- Backups (clickhouse-backup → RustFS) — complementary, separate follow-up.

## Proposal

1. **Keeper**: a `ClickHouseKeeperInstallation` (`keeper`, 3 replicas, small
   PVCs) lands in `kubernetes/infra/configs/clickhouse/` — same directory,
   same `clickhouse-local` wave; the operator already handles both CRs.
2. **CHI**: `replicasCount: 1 → 3`, plus `zookeeper.keeper.name: keeper`
   (the by-name reference; the operator docs date it to 0.27.1, not 0.27.0 —
   either way 0.27.3 is deployed) and pod anti-affinity on
   `kubernetes.io/hostname` (Kind has no zones). The operator keeps
   auto-creating the PDB; macros and `remote_servers` regenerate themselves.
3. **Schema — REVISED AT IMPLEMENTATION (see History).** The RFC proposed
   Option B: the exporter gains `cluster_name` + `table_engine` and keeps
   creating the schema. That was measured and does not work at three replicas.
   As built: a **bootstrap Job owns the DDL** (`configs/clickhouse-schema`), the
   `otel` database uses **`ENGINE = Replicated`**, tables are created without
   `ON CLUSTER`, and the collector runs **`create_schema: false`**. Old plain
   -MergeTree tables are still **dropped deliberately** (fresh start).
4. **Alerts**: re-enable the commented `ClickHouseZooKeeperExceptions` alert
   (it exists for exactly this topology) and extend the unreachable-server
   alert to per-replica.
5. **local-stack**: compose stays 1×1 single-node (no keeper in compose —
   the twin divergence is recorded, same as it already is for scrape ports
   pre-quick-win); the exporter options are cluster-only values.

### Alternatives

Decision-level tradeoffs live in [research § Integration paths](./research.md#integration-paths)
and [§ Alternatives](./research.md#alternatives); the schema-ownership analysis
(the RFC's central choice) is the Option A/B table there.

## Other solutions considered

| Option | Shape | Why not chosen |
|--------|-------|----------------|
| Migration Job owns DDL (Option A) | Job + SQL in git, `create_schema: false` | **Chosen at implementation, reversing the gate.** The gate preferred B for zero new parts; implementation measured B producing a schema on 1 of 3 then 2 of 3 replicas, and found the exporter's README recommends `create_schema: false` for production precisely to "prevent race conditions during startup". See History |
| Frugal 2+1 first | 2 replicas + 1 keeper (+2 pods) | Owner chose straight 3+3; the RAM ceiling (~7.5Gi limits) is accepted and will be observed after landing |
| Convert existing tables | `ATTACH ... AS REPLICATED` | Nothing is a real deployment yet — fresh tables skip the ceremony; the technique stays documented in research for the day a real deployment needs it |
| Stay 1×1 + backups | clickhouse-backup to RustFS | Restores lose the tail and take hours; doesn't teach replication; backups remain a complementary follow-up |

## Decision outcome

**Chosen option at the research gate:** Option B — exporter-owned replicated
schema, on a 1×3 + CHK topology. **Superseded at implementation by Option A**
(bootstrap Job owns the DDL, `otel` database `ENGINE = Replicated`) — the
reasoning below is preserved as the gate recorded it, and what overturned it is
in [Implementation History](#implementation-history).

**Rationale:** satisfies the Goals with the smallest possible delta — no new
schema owner, no new wave, no data migration — because the other gate
decisions (fresh tables, `{uuid}` default path) remove exactly the risks that
made a Job attractive. Runner-up was Option A (migration Job); the deciding
factor was zero-new-parts vs a Job whose two benefits (ALTER lifecycle,
startup decoupling) are not yet needed and are now standing revisit triggers.

**Decided:** 2026-08-28, owner, at the research review gate (in-session).

## Architecture & Diagrams

Target state (mechanism diagrams live in research — this is the as-proposed
topology):

```mermaid
flowchart TD
  subgraph WRITE["Write"]
    OC["otel-collector<br/>create_schema: true<br/>cluster_name + table_engine:<br/>ReplicatedMergeTree"]
  end
  subgraph READ["Read"]
    GF["Grafana datasource<br/>user: default (unchanged)"]
  end
  subgraph CH["CHI clickhouse — 1 shard × 3 replicas"]
    R0[("replica 0")]
    R1[("replica 1")]
    R2[("replica 2")]
  end
  subgraph KEEP["CHK keeper ×3 (quorum)"]
    K0["keeper-0"] --- K1["keeper-1"] --- K2["keeper-2"]
  end
  OC -->|"INSERT (Service round-robin)"| CH
  GF -->|"SELECT"| CH
  R0 <-->|replicate| R1
  R1 <-->|replicate| R2
  R0 <-->|replicate| R2
  CH -.->|"coordination<br/>zookeeper.keeper.name"| KEEP
  classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
  classDef collector fill:#a5d8ff,color:#111,stroke:#1971c2;
  classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
  classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
  class OC collector; class GF service;
  class R0,R1,R2 data; class K0,K1,K2 platform;
```

## Design Details

- **Enable/disable**: entirely declarative — the CHK resource, three CHI
  fields (`replicasCount`, `zookeeper.keeper.name`, anti-affinity), one
  exporter config block. Disabling = reverting those (see Rollout & rollback).
- **Ordering**: the CHK must be Ready before the CHI reconciles replicas
  (the CHI references it by name). Both live in one wave; the operator
  retries the CHI until Keeper answers, and the wave's `wait: true` plus the
  existing StatefulSet healthCheck gate downstream (`tracing-local` already
  dependsOn `clickhouse-local`).
- **Default replica path**: one implementation check —
  `SELECT * FROM system.server_settings WHERE name LIKE 'default_replica%'`
  — to confirm `/clickhouse/tables/{uuid}/{shard}` + `{replica}` on our build.
- **TTL**: unchanged (`ttl: 2160h` in the exporter). System-table TTLs arrive
  via the independent quick-win PR.
- **Operator determines in-use**: `kubectl get chk,chi -n monitoring`;
  `SELECT * FROM system.replicas` shows three entries per table;
  `system.zookeeper_connection` names the keeper.
- **Drawbacks (recorded, accepted)**: (1) DDL still runs in collector
  `start()` — a collector restart during a ClickHouse outage stalls all its
  sinks until ClickHouse returns (revisit trigger → Option A); (2) the
  exporter never ALTERs — the first real schema change re-opens the Job
  question; (3) memory limits triple (~7.5Gi ceiling in `monitoring`).

## Security considerations

None new: same namespace, same single `default` user (owner-declared
acceptable; hardening documented as the optional rung in research), operator
-created PDB, PSS-baseline pod specs unchanged. `networks/ip` fencing arrives
only if the optional rung is ever taken.

## Observability & SLO impact

- Re-enable `ClickHouseZooKeeperExceptions` (currently commented out) — it
  was written for this day.
- Keeper metrics: chart value `keeperMetrics.enabled` currently `false` —
  flip with this rollout so the quorum is visible.
- Watch during rollout: `system.replication_queue` depth,
  `ClickHouseMetrics_ReadonlyReplica` (a replica stuck read-only means it
  lost Keeper), the DiskAlmostFull pair (data ×3).
- The per-pod native `:9363` scrape ships in the quick-win PR and is what
  makes per-replica dashboards meaningful.

## Rollout & rollback

**Rollout** (one homelab PR): CHK + CHI changes + collector exporter block +
alert re-enable, then either a fresh `make up` or, on the live cluster:
reconcile, **deliberately drop the old plain-MergeTree tables** (owner
decision — this discards current demo data), restart the collector so the
exporter recreates the schema replicated.

**Blast radius**: `monitoring` namespace; Grafana ClickHouse panels are blank
between the drop and the first new inserts; VictoriaMetrics-side dashboards
unaffected.

**Rollback**: `replicasCount: 3 → 1`, remove the exporter's two options,
optionally remove the CHK. Replicated tables remain readable single-replica
(a lone replica without Keeper goes read-only for writes — so a full rollback
also recreates plain tables, which is the same fresh-start move in reverse).

## Testing / verification

1. Fresh `make up`: 26/26 Kustomizations (the schema wave is the 26th), `chk` +
   6 ClickHouse-family pods Ready, the `clickhouse-schema` Job Complete, and
   `system.replicas` listing 3 replicas per `otel` table **on all three pods**.
2. Drive gate traffic (`make e2e GATE=kind` — existing SG/K rows); confirm
   inserts land and `system.replication_queue` drains to 0 on all replicas.
3. **Kill drill**: delete one replica pod mid-traffic — Grafana keeps
   answering, the collector keeps inserting (Service routes around), the pod
   returns and catches up (`replication_queue` drains again).
4. Keeper drill: delete one keeper pod — quorum holds (2/3), writes continue.
5. `make validate` + the standard Kind gate as the release gate.

## Resulting decisions

| Decision | ADR | Status |
|----------|-----|--------|
| 1×3 replicated ClickHouse with CHK quorum, exporter-owned replicated schema (fresh start, default replica path) | [ADR-065](../../adr/ADR-065-clickhouse-replicated-topology/) | Accepted 2026-08-28 |

## Implementation History

- 2026-08-28 — **Status → `Accepted`.** [ADR-065](../../adr/ADR-065-clickhouse-replicated-topology/)
  created at `Accepted` with this review, carrying the one decision this RFC
  frames. Implementation runs in the same pull request, so the gate that proves
  it is also the gate that closes the ADR's adoption.

  Three repo facts found while planning it, none of them in this RFC's own text,
  each of which would have produced green-but-false evidence:
  `clickhouse-local` health-checked **one** StatefulSet, so `wait: true` would
  have reported Ready on one replica of three and released `tracing-local`
  early; the CHK **CRD was not health-checked** at all, so the wave could race
  the CRD it needs; and `make validate` **never built** the ClickHouse overlay
  (absent from `flux-validate.sh`), so a malformed CHK would have passed
  validation and failed on the cluster. All three are fixed here.

  Two scope calls made at implementation. The **`:9363` per-pod scrape is folded
  in** — this RFC deferred it to a "quick-win PR" that turned out never to have
  been created, which left `ClickHouseMetrics_ReadonlyReplica`, named in this
  RFC's own rollout watch list, with no series at all. And
  `ClickHouseServerUnreachable` is **re-graded**: at 1×1 one unreachable host was
  the store being down, so it paged; with three replicas it is a degraded member,
  and a new `ClickHouseAllReplicasUnreachable` carries the page instead.

- 2026-08-28 — **The first Kind bring-up produced a half-created schema, and
  finding out why invalidated this RFC's ordering assumption.** Every check
  passed except one: six pods `Running`, all three tables `ReplicatedMergeTree`
  on replica 0 — and `system.replicas` reporting `total_replicas=1`. The `otel`
  database existed on replica 0 alone. `system.distributed_ddl_queue` showed the
  exporter's six `CREATE` statements with a status row for host `0` only: the
  collector had run its DDL before replicas 1 and 2 joined the distributed-DDL
  queue, and **a host that joins later skips earlier entries** while
  `IF NOT EXISTS` makes every retry a no-op. Only inserting on one replica and
  reading from another exposed it.

  The cause was upstream of ClickHouse. `clickhouse-local` carried both
  `wait: true` and `healthChecks`, which are **mutually exclusive in Flux with
  `wait` winning** — so `wait` waited for the health of what the overlay applies,
  two custom resources whose status kstatus cannot assess and therefore calls
  Current immediately. Measured: the wave reconciled in **371 ms** and reported
  success while zero StatefulSets existed; the operator created the first one a
  minute later, and `tracing-local` applied on that green light. The single
  health check this wave carried before this RFC was inert for the same reason —
  it had never gated on anything. Dropping `wait` is what makes health checks on
  operator-created StatefulSets evaluate at all.

  Recorded in [ADR-065](../../adr/ADR-065-clickhouse-replicated-topology/) as a
  negative consequence and a revisit trigger, because the sharp edge belongs to
  exporter-owned schema (Option B), not to the wave: a migration Job owns its DDL
  explicitly and can be re-run against replicas that arrived in any order.

- 2026-08-28 — **The second bring-up settled it: schema ownership moves to a Job,
  reversing this RFC's central decision before it shipped.** With the ordering
  fixed the wave reconciled in 3m25s and the collector was created after all
  three StatefulSets — correct by every measure this RFC named — and the schema
  still landed on only **2 of 3** replicas. `system.distributed_ddl_queue` again
  showed the exporter's six `CREATE` statements with status rows for hosts `0`
  and `1` only. "Pod Ready" is not "joined the DDL queue", so ordering cannot
  close this gap; `IF NOT EXISTS` guarantees no retry closes it either.

  Then the exporter's own README, which the research never quoted:

  > **Schema management** — "While the exporter can automatically create
  > databases and tables, it is recommended for production environments to
  > manage schemas manually by setting `create_schema` to false. This approach
  > prevents race conditions during startup and simplifies future upgrades.
  > When manual schema management is enabled, the exporter only executes INSERT
  > statements, allowing users to customize indexes, TTL, and partitioning as
  > needed."

  Upstream names our exact failure and recommends against Option B for
  production. The gate chose B on parts-count and schema-evolution; it was never
  shown that sentence.

  **As built instead:** a bootstrap Job (`configs/clickhouse-schema`, its own
  `clickhouse-schema-local` wave with `wait: true`) creates the `otel` database
  with **`ENGINE = Replicated`** on **each replica individually** — no
  `ON CLUSTER`, so the cluster-wide DDL queue is never touched — then creates the
  tables **once** and lets the database's own Keeper log propagate them. The
  collector runs `create_schema: false` and only INSERTs; `cluster_name`,
  `table_engine`, `ttl` and the `distributed_ddl_task_timeout` DSN parameter are
  gone, because all four only ever fed the DDL path.

  Measured before committing, on the live cluster: `0` DDL-queue entries for the
  bootstrap; database `Replicated` on all three replicas; tables applied once
  reaching **`total_replicas=3 active_replicas=3 is_readonly=0`** everywhere; the
  exporter's exact INSERT column lists accepted; the materialized view firing and
  its target replicating; and the `__otel_materialized_*` columns computing.

  This also closes both revisit triggers this RFC recorded — `ALTER` ownership
  and startup decoupling — so the "Option A is ready if either fires" line came
  due in the same week it was written.

## Related

- [./research.md](./research.md) — plain-language research and Context7 audit trail (gate passed 2026-08-28)
- [ADR-023](../../adr/ADR-023-clickhouse-observability-olap/) — why ClickHouse exists here; [ADR-061](../../adr/ADR-061-edge-log-routing/) — edge logs are ClickHouse-only
- [RFC-0019](../RFC-0019/) — the observability OLAP program this extends
- Quick-win train (system-table TTLs, image pin, PVC Retain) — independent of this RFC's gate; the `:9363` scrape was pulled out of it and shipped here instead

---
_Last updated: 2026-08-28 — schema ownership **reversed to Option A** at implementation: a bootstrap Job owns the DDL and the `otel` database is `ENGINE = Replicated`, after exporter-owned `ON CLUSTER` DDL was measured reaching 1 of 3 then 2 of 3 replicas and the exporter's README was found to recommend `create_schema: false` for production. Earlier: Status → `Accepted`; ADR-065 created at `Accepted`, implementation opened in the same PR, `:9363` scrape folded in. Earlier still: owner review — the bare “docs/api: N/A” hid the real docs impact._
