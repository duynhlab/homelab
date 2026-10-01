# ADR-081: Serialize Agent Work with Leases and Reconciliation

> **Decision summary:** We will run agent work as bounded, serialized jobs whose
> leases and recovery state live in the GitHub ledger. We accept hourly,
> best-effort reconciliation instead of continuous availability so a trigger
> can never become the system of record.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-01 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Dispatch, leasing, retries, reconciliation, heartbeat, and dead-letter behavior for RFC-0033 |
| **Affected components** | Planned dispatcher, bounded jobs, GitHub ledger, later routine triggers, heartbeat checker |
| **Related RFC** | [RFC-0033](../../rfc/RFC-0033/) |
| **Related research** | [research.md](../../rfc/RFC-0033/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0033 Phases 0–3 |
| **Adoption** | Not started |

## Context

Claude routines, GitHub events, and manual invocations can wake work, but they
do not guarantee unique, durable delivery. Events may be duplicated, delayed,
dropped, or rejected at account and usage limits. A successful trigger run also
does not prove the engineering task reached its semantic outcome.

Multiple workers acting on one mutable task can collide or repeat external
effects. Recovery must use durable task state and immutable revisions rather
than relying on the process that received the event.

## Scope

### In scope

- Single-writer task transitions, leases, idempotency, retry, and recovery.
- The qualification boundary between bounded jobs and later Claude routines.
- Heartbeat and dead-letter visibility for the best-effort pilot.

### Out of scope

- Task and authorization record contents, owned by [ADR-079](../ADR-079-version-agent-task-contracts/).
- Publishing credentials, owned by [ADR-080](../ADR-080-tokenless-agent-workers/).
- A continuously available Agent SDK controller or external on-call service.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Correctness under duplicate delivery | Two triggers must not create two owners or effects for one revision |
| 2 | Recoverability | A fresh job must resume from durable state after interruption |
| 3 | Bounded cost and failure | Retries, turns, time, concurrency, and spend must stop predictably |
| 4 | Small operating surface | The pilot must not start with a new 24/7 service |

## Decision

Phases 0–2 will use human-started Claude sessions or bounded GitHub Actions jobs.
A single trusted dispatcher serializes transitions for each task revision. In
GitHub Actions, its external serialization boundary is a task-and-revision-keyed
concurrency group; comments remain audit records, not locks.

Only the dispatcher may acquire or renew a lease. A lease binds the authorized
revision and checksum, immutable base SHA, holder/run ID, acquisition time,
expiry, and renewal time. A newer task revision invalidates the old revision's
eligibility; an active old lease stops at its next boundary and never adopts new
scope in place.

Every action uses a stable idempotency key derived from task ID, revision, and
action. Retries obey the task's explicit attempt, turn, wall-time, and cost
budgets. Exhaustion or an ambiguous external result moves the task to
`dead-letter` or `blocked`; the system never retries until green.

Phase 3 may add qualified Claude routine schedules or supported GitHub events
as trigger surfaces. A scheduled reconciliation scan reads all ledger events
after the previous monotonic watermark and backfills eligible work. A heartbeat
is written only after that semantic scan completes, with its watermark and
completion timestamp. The minimum expected cadence is one hour.

A separate scheduled GitHub Action checks heartbeat age and opens or updates a
single incident issue when stale. This is outside Claude's failure domain but
still shares GitHub's failure domain. The pilot is best-effort and has no
availability SLO; failure defaults to pause and record.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Serialization** | One dispatcher transition per task revision at a time |
| **Lease ownership** | Only the dispatcher acquires or renews a lease; workers cannot alter it |
| **Revision change** | New scope requires a new authorization and lease; active work never adopts it |
| **Retry** | Only declared retryable failures retry, within attempt/time/turn/cost budgets |
| **Trigger boundary** | A trigger wakes reconciliation; it never owns task state or proves success |
| **Heartbeat** | Advance only after a complete semantic scan and include the ledger watermark |
| **Failure behavior** | Stale, ambiguous, over-budget, or contradictory work becomes visible and stops |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Bounded jobs + ledger leases + reconciliation** | Small surface, durable recovery, measurable gaps | Hourly latency and GitHub-shaped coordination | Selected |
| **B — Claude routines as queue and state** | Native scheduled/event execution | Preview limits, dropped events, personal identity, fresh sessions | Rejected |
| **C — Agent SDK controller immediately** | Explicit queue, state, and scheduling | New production service and on-call burden before evidence | Deferred to Phase 4 |
| **D — One long-lived agent-team session** | Fast interactive collaboration | Session-bound, experimental, weak resume semantics | Rejected |

### Why the selected option won

It proves the task, lease, retry, and recovery model using systems Homelab
already operates. If it cannot satisfy measured needs, the same ledger contract
can feed a later controller.

### Why the closest alternative lost

A thin Agent SDK controller provides stronger scheduling, but choosing it now
would turn an unmeasured limitation into a permanent service, secret, datastore,
telemetry stream, and operating responsibility.

## Consequences

### Positive consequences

- Duplicate and missed triggers can converge on one durable task revision.
- Interrupted jobs do not require hidden session memory to resume.
- Retry and spend exhaustion are explicit outcomes rather than silent loops.

### Negative consequences and accepted trade-offs

- GitHub is not a transactional queue; the dispatcher must supply serialization.
- Expected reconciliation latency is up to one hourly cycle in Phase 3.
- A total GitHub outage or disabled checker cannot be detected inside this pilot.

### Neutral consequences

- Interactive agent teams may still support bounded research, but never act as scheduler.
- A later controller must preserve the same task and evidence contracts.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Implement lifecycle and lease fixtures | `duynhne` | RFC-0033 Phase 0 | Invalid transitions, holders, revisions, and renewals fail closed |
| Prove bounded duplicate dispatch behavior | `duynhne` | RFC-0033 Phase 0 | Concurrent duplicate triggers yield one lease holder |
| Add parent/child dependency sequencing | `duynhne` | RFC-0033 Phase 2 | A child cannot advance before recorded prerequisites |
| Qualify reconciliation, heartbeat, and routine failures | `duynhne` | RFC-0033 Phase 3 | Duplicate, drop, cap, false-green, stale-heartbeat, and outage drills pass |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Single holder | Race duplicate triggers against the same revision |
| Lease recovery | Expire, renew, and recover a lease without changing authorized scope |
| Revision isolation | Publish a new revision while an old lease is active |
| Bounded retry | Inject flaky CI and verify stop at the declared threshold |
| Reconciliation | Drop an event and verify backfill from the last watermark |
| Semantic heartbeat | A green trigger with failed task semantics cannot advance the heartbeat |

## Revisit triggers

Re-open this decision when bounded jobs cannot meet measured identity, queue
durability, latency, or concurrency requirements, or when Phase 4 evidence names
a guarantee that requires an Agent SDK controller.

## References

- [RFC-0033](../../rfc/RFC-0033/)
- [RFC-0033 research](../../rfc/RFC-0033/research.md)
- [ADR-079](../ADR-079-version-agent-task-contracts/)
- [ADR-080](../ADR-080-tokenless-agent-workers/)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-10-01 | Accepted / Not started | Architecture review accepted bounded dispatch, leases, and best-effort reconciliation |

---
_Last updated: 2026-10-01 — Accepted, Adoption Not started_
