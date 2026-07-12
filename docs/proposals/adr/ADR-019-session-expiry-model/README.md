# ADR-019: Expire checkout sessions with a durable timer plus a lazy backstop

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-13 | [RFC-0015](../../rfc/RFC-0015/) |

## Context

A checkout session is a short-lived quote whose TTL models user presence
(RFC-0015: nothing is reserved, the clock just keeps quotes honest). Expiry
therefore needs two properties that pull in different directions: it must be
**correct** (an expired session must never be usable, even if every
background component is down) and **timely** (abandoned sessions should
actually flip to `expired` so the one-active-session-per-user index frees up
and metrics reflect reality — not only when someone happens to read them).

The platform already runs Temporal for the order saga; P1 shipped the lazy
half (`lazyExpire` checks `expires_at` on every read and mutation and records
`expired(lazy)` best-effort). Reset-on-activity means every successful
mutation pushes the deadline to `now+TTL`.

## Decision

We expire sessions with **two cooperating mechanisms, with the lazy backstop
as the correctness authority**:

1. **Lazy backstop (authoritative):** every read/mutation treats
   `now > expires_at` as expired regardless of anything else. This is the
   only mechanism correctness depends on.
2. **Durable timer (timeliness):** one `AbandonedCheckoutWorkflow` per
   session (`checkout-abandon-<session_id>`, task queue `checkout`), started
   idempotently with Signal-With-Start. Every successful mutation both
   **bumps the DB deadline** (`Touch`: `expires_at = now+TTL`) and signals
   `activity` (timer resets). Confirm and cancel signal `finalize`. The
   timer firing is a **wake-up, never a verdict**: the `ExpireIfDue`
   activity re-reads the row and expires it only when
   `expires_at <= now()` (conditional, idempotent, skips `confirming` and
   terminal rows, records `expired(timer)`); if the DB deadline moved — a
   lost or racing signal — the workflow re-arms the timer to the DB's
   remaining time. The DB clock is the single source of truth; signals are
   only a latency optimization, so losing any of them can delay expiry but
   never mis-expire.

All signal sends are best-effort with a detached 2-second budget: a Temporal
outage degrades expiry to lazy-only and nothing else. The
`expired_reason` column (`timer` | `lazy`) is the operational signal — a
lazy-majority in `checkout_sessions_expired_total{reason}` means the worker
is down.

## Alternatives considered

**Lazy-only (P1 status quo).**
Pros: zero moving parts. Cons: abandoned sessions linger as `open` rows
forever unless read; the active-session index stays occupied; "how many
sessions expire" is unanswerable. Rejected as the permanent state — it
remains the fallback mode.

**A cron sweeper (`UPDATE … WHERE expires_at < now()`).**
Pros: trivial. Cons: cluster-cron plumbing, one more schedule to operate,
resolution limited by sweep interval, and it teaches nothing about the
platform's chosen durable-timer primitive. Rejected; Temporal already runs
here and gives per-session precision plus visibility (Query `session_state`).

**One long-lived janitor workflow for all sessions.**
Pros: one workflow. Cons: unbounded signal fan-in and history growth on a
single execution, a hot spot the per-session design avoids; Continue-As-New
churn scales with global activity instead of per-session activity. Rejected.

**Timer as authority (no lazy check).**
Pros: single mechanism. Cons: worker or Temporal downtime would let expired
sessions keep transacting — a correctness dependency on availability.
Rejected outright; this ADR's core is that the timer is never load-bearing.

## Consequences

- Expiry works with Temporal completely absent; the workflow only makes it
  timely. A late or duplicate timer is harmless by construction (conditional
  SQL, first `expired_reason` wins).
- `confirming` is never expired by either mechanism — the confirm flow owns
  that state's fate (ADR-018 handoff); its parked-session tradeoff is
  documented in RFC-0015 P2.
- Each mutation now performs one extra DB write (`Touch`) and one Temporal
  signal; both are cheap and best-effort.
- Workflow history is bounded by Continue-As-New after 500 activity resets.
- The checkout deployment gains a second process (`worker` subcommand) to
  run and monitor — Temporal SDK metrics surface on its `/metrics` like the
  order worker.
- Revisit trigger: reservations at checkout time (stock/price holds) would
  make expiry a money-adjacent event and reopen the authority question.

---
_Last updated: 2026-07-13_
