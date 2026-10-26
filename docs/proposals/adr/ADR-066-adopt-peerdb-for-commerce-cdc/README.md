# ADR-066: Adopt PeerDB for Commerce CDC

> **Decision summary:** We will self-host PeerDB as the PostgreSQL-to-ClickHouse
> CDC transport for Backoffice commerce analytics because it owns snapshot,
> checkpoint, update, and delete capture without introducing a broker. We accept
> a new stateful control plane, logical-slot WAL risk, and a version and licence
> qualification gate in exchange for not owning a bespoke transport.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-09-09 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The transport and control-plane boundary from the three commerce PostgreSQL databases to ClickHouse |
| **Affected components** | `product-db`; PeerDB; the `peerdb` Temporal namespace; the `analytics-service-cdc` RustFS bucket; the PeerDB catalog on `platform-db`; ClickHouse commerce raw tables |
| **Related RFC** | [RFC-0030](../../rfc/RFC-0030/) |
| **Related research** | [research.md](../../rfc/RFC-0030/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | [#1313](https://github.com/duynhlab/homelab/issues/1313) — native Task sub-issues and tradeoff log |
| **Adoption** | Complete — three mirrors on Kind with failover slots; phase-7 drills, CDC alerts and a cold bring-up passed (2026-10-23); the dashboard is deferred by the owner |

## Context

The Backoffice needs joined order, checkout, and payment facts for bounded
analytics. Those facts live in three databases on the same CloudNativePG
cluster, and none of the transactional services owns the cross-domain read
model. ClickHouse is already the platform OLAP store, but no commerce tables or
transport exist.

A custom batch would make the platform define initial-copy boundaries,
watermarks, overlap, retries, updates, and deletes. Continuous CDC avoids that
second transport implementation, but creates a consumer slot whose retained WAL
can endanger the source and a stateful runtime that must recover correctly.

## Scope

### In scope

- The CDC product and one-mirror-per-database topology.
- Placement and isolation of PeerDB's catalog, workflow, and staging state.
- Source connection and failure containment rules.

### Out of scope

- Source column authorization, decided by ADR-067.
- Freshness heartbeat scheduling, decided by ADR-068.
- Commerce metric semantics, ClickHouse DDL, and the consumer API.
- A general event backbone for application integration.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Correct update and delete capture | Financial and funnel views cannot silently retain superseded state |
| 2 | Bounded source blast radius | A stalled consumer must not exhaust PostgreSQL storage or block transactions |
| 3 | Avoid owning transport internals | Snapshot, checkpoint, type mapping, and retry are not product differentiators |
| 4 | Operational isolation | Shared platform dependencies must not imply shared credentials or failure domains |
| 5 | Reversibility | A failed prototype must permit a clean return to the batch option |

## Decision

We will self-host PeerDB for PostgreSQL-to-ClickHouse CDC. We will run three
independent mirrors in rollout order `order`, `checkout`, then `payment`; each
mirror owns one source database connection, publication, logical slot, and
destination mapping.

PeerDB will connect through a platform-owned, replication-compatible CDC
pooler profile to the source primary, with verify-full semantics on both hops.
Snapshot SQL and WAL streaming must pass the RFC-0029 compatibility gate; no
replica routing or automatic direct fallback is allowed. The concrete profile
is not qualified yet. PeerDB may reuse the
existing Temporal, RustFS, and `platform-db` capabilities only through a
dedicated `peerdb` namespace, `analytics-service-cdc` bucket and identity, and catalog
database and role. PeerDB control APIs and UI stay cluster-internal.

> **As built (2026-10-23):** the qualified profile is `product-db-pooler-cdc`
> (CNPG PgBouncer, session mode, client TLS required, verify-full to the
> primary); replication through it passed G3.1–G3.6. Operations:
> [Commerce CDC](../../../databases/cdc/README.md).

Resource names follow [RFC-0030](../../rfc/RFC-0030/README.md#resource-naming):
the destination peer is `analytics_service`, the ClickHouse database is
`analytics`, and the ingest identity is `analytics_ingest`. The bucket identity
is separate from the API reader and from the platform backup/cold-tier identities.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Transport ownership** | PeerDB owns snapshot, WAL consumption, checkpoints, staging, retries, and ClickHouse delivery; platform code must not implement a second CDC loop |
| **Mirror isolation** | `order`, `checkout`, and `payment` use separate mirrors, publications, slots, credentials, and source health |
| **Source path** | Snapshot SQL and WAL use a qualified CDC pooler profile to the primary; verify-full on both hops; a failed gate blocks rollout |
| **Dependency isolation** | PeerDB receives dedicated Temporal namespace, RustFS identity/bucket, and catalog database/role |
| **Failure behavior** | Finite retained-WAL limits protect PostgreSQL; invalidated or unsafe slots require an explicit resync decision rather than an improvised retry |
| **Rollback** | Pause mirrors and preserve evidence and slots first; never run batch and PeerDB as parallel production transports |

### Decision view

```mermaid
flowchart LR
    O[("order DB")] -.->|"planned primary-only"| CP["CDC pooler profile<br/>planned — not qualified"]
    C[("checkout DB")] -.->|"planned primary-only"| CP
    M[("payment DB")] -.->|"planned primary-only"| CP
    CP -.->|"planned snapshot + WAL<br/>verify-full both hops"| P["PeerDB<br/>self-hosted — planned"]
    P -->|"staging"| R[("RustFS — Analytics CDC files<br/>analytics-service-cdc")]
    P -->|"raw versions + tombstones"| CH[("ClickHouse<br/>analytics raw tables")]
    P -.->|"isolated workflow/catalog"| D["Temporal + platform-db"]

    classDef planned fill:#fff,color:#475569,stroke:#64748b,stroke-dasharray:5 5;
    class CP planned;
    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
    class O,C,M,R,CH data;
    class P,D platform;
```

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Self-hosted PeerDB** | Purpose-built snapshot and CDC, update/delete capture, no broker | New control plane, logical slots, full snapshots, licence and version qualification | Selected |
| **B — Custom bounded batch** | Smaller infrastructure footprint | Platform owns watermarks, overlap, retries, updates, deletes, and recovery | Rejected fallback unless the prototype fails |
| **C — Debezium plus Kafka/Redpanda** | Mature general-purpose event backbone and replay | Broker, Connect, topics, schemas, ordering, and on-call surface for one consumer | Rejected |
| **D — Custom `pgoutput` consumer** | Maximum control | Permanent decoding, checkpoint, mapping, and support ownership | Rejected |
| **E — ClickHouse `MaterializedPostgreSQL`** | Fewer components | Experimental and DDL limitations below the platform production bar | Rejected |
| **F — Service export APIs** | Preserves service boundaries | Three bulk APIs, repeated serialization, and transactional-service load | Rejected |

### Why the selected option won

PeerDB is the narrowest option that removes transport correctness from
application code while retaining continuous updates and deletes. It also fits
the existing PostgreSQL, Temporal, RustFS, and ClickHouse stack without creating
a general-purpose event platform.

### Why the closest alternative lost

Batch is operationally smaller, but its simplicity ends at the first update,
delete, retry, or interrupted initial copy. Those cases are the transport. A
home-grown batch therefore saves pods by transferring the harder state machine
to platform-owned code.

## Consequences

### Positive consequences

- Transactional services remain independent of analytics availability.
- Snapshot, checkpoint, update, and delete behavior have one explicit owner.
- Each lagging source can be diagnosed or paused independently.

### Negative consequences and accepted trade-offs

- PeerDB, its catalog, workflows, staging, and upgrades become day-2 platform work.
- Consumer lag retains WAL and can force a destructive resync after the safety cap.
- Initial snapshots consume source, network, staging, and ClickHouse capacity.
- AGPL-3.0 core and the ELv2 chart require explicit approval before acceptance
  (granted for internal self-hosting on 2026-10-23, see History).
- Schema evolution remains conservative until the pinned build proves exact behavior.

### Neutral consequences

- Commerce CDC is an analytical integration path, not an application event bus.
- ClickHouse stores independently versioned raw rows and tombstones before serving normalization.

The source-access decision follows the [RFC-0030 contract](../../rfc/RFC-0030/README.md#source-access-contract)
and RFC-0029; the existing direct Compose baseline is not pooled-access evidence.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Pin and review a compatible PeerDB core and deployment artifact | Platform | [#1314](https://github.com/duynhlab/homelab/issues/1314) | Digests and licence decision recorded; clean install passes |
| Declare isolated catalog, workflow, staging, secrets, and network paths | Platform | [#1315](https://github.com/duynhlab/homelab/issues/1315) | No PeerDB identity can access adjacent platform state |
| Size slots, WAL senders, retained WAL, storage, and resource floor | Platform / Database | [#1316](https://github.com/duynhlab/homelab/issues/1316) | Measured thresholds and finite WAL cap are committed |
| Prove three mirrors and recovery | Platform | [#1317](https://github.com/duynhlab/homelab/issues/1317) | Snapshot and CDC tests pass through restart, outage, and resync |
| Add alerts, dashboard, and runbook | Platform / Observability | [#1318](https://github.com/duynhlab/homelab/issues/1318) | Lag, slot, staging, dependency, and resync paths are operable |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Update/delete correctness | Concurrent snapshot plus insert/update/delete/tombstone and duplicate-delivery tests |
| Independent mirrors | Stop each mirror and prove only its source freshness degrades |
| Source safety | Network-partition and dependency-outage drills keep retained WAL within the configured cap |
| Recovery | PeerDB restart, CNPG switchover/failover, WAL invalidation, and explicit resync drills |
| Isolation | Positive and negative credential, HBA, TLS, NetworkPolicy, catalog, and bucket tests |
| Capacity | One-million-fact load measures snapshot duration, WAL, staging, raw storage, CPU, and memory |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- PeerDB fails any RFC-0030 hard prototype gate on the pinned build.
- Licence terms cannot be approved for the selected deployment artifact.
- Retained WAL or source load cannot be bounded without harming transactions.
- More independent consumers require replay and schema governance that justify a broker.
- Schema changes repeatedly require full resync beyond the accepted operational budget.

A changed decision requires a new ADR that supersedes this one.

## References

- [RFC-0030](../../rfc/RFC-0030/)
- [RFC-0030 research](../../rfc/RFC-0030/research.md)
- [ClickHouse platform guide](../../../observability/clickhouse/README.md)
- [Database architecture](../../../databases/architecture.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-09-09 | Proposed / Not started | Initial decision drafted during RFC-0030 architecture review |
| 2026-09-09 | Accepted / Not started | Owner accepted the architecture; qualification remains Phase 0 of implementation |
| 2026-10-18 | Accepted / Not started | Owner aligned source access with RFC-0029: qualified CDC pooler profile, verified TLS on both hops, no silent direct fallback; runtime qualification pending |
| 2026-10-23 | Accepted / Partial | Owner accepted ELv2 and the upstream chart; PeerDB 0.9.17 (core v0.37.5) on Kind with catalog on platform-db, Temporal namespace `peerdb`, RustFS staging (shared key, recorded gap). Three mirrors admitted; replicated target via `replicated: true` + `database_replicated_allow_replicated_engine_arguments = 2`; four checkouts reached the read API as $142.48 captured within 45 s |
| 2026-10-23 | Accepted / Complete | Phase 7 closed: drills G7.1–G7.8 passed (CDC hub); PeerDB exports OTLP metrics and six CDC alerts load (#1373); slots are created as failover slots and survive a promotion with no lost rows (#1376); a cold `make up` brings the whole path up with no manual step (#1378). Follow-up: stale slots on a demoted primary (#1377) |
