# ADR-031: Start the fulfillment saga through a transactional outbox

Write "this order needs a saga" into the order's own database transaction, keep
the inline start for latency, and let a dispatcher in the order worker retry
whatever the inline start could not complete.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-28 | [RFC-0021](../../rfc/RFC-0021/) | [RFC-0021 research.md](../../rfc/RFC-0021/research.md) |

## Context

`CreateOrder` committed the order row and **then** called Temporal:

```
BEGIN; INSERT orders; COMMIT;        ← durable
ExecuteWorkflow(...)                  ← not durable, not in the transaction
```

Anything that interrupts the second line leaves an order `pending` forever with
nothing that remembers to start it: a pod restart between the two, a Temporal
outage, a network partition, an OOM kill. The web transport logged the failure
and still returned 201; the gRPC transport returned `Unavailable` **after** the
order had already committed. Either way the order existed and its saga did not,
and no process would ever notice.

Temporal cannot be enrolled in the PostgreSQL transaction, so the two writes can
never be atomic with each other. What *can* be atomic is the order row and a
record of the intent — which moves the problem from "two systems must commit
together" to "one database must commit two rows together", something the database
already guarantees.

Three constraints shaped the design rather than being discovered afterwards:

- **The payment token is not on the order row.** `CreateOrderRequest.PaymentMethod`
  is the checkout's opaque `tok_*` reference and is deliberately never persisted
  there. A retry that cannot supply it makes `AuthorizePayment` fall back to its
  **demo** token, so anything that re-starts a saga must carry the real one.
- **Starting twice moves money.** The saga authorizes and captures. A duplicate
  start is a second authorization and a second capture, so "at least once" is not
  an acceptable delivery guarantee here — it has to be exactly once.
- **The workflow id is derived from the order id.** That gives Temporal a natural
  dedup key, but only while the previous run still exists in namespace retention.

## Decision

**A transactional outbox, `fulfillment_start_requests`, with the inline start
kept as the fast path.**

1. **One row per order, written in the order's transaction.** The order id is the
   primary key, so the uniqueness guarantee is structural and a retried create
   cannot enqueue a second start. The enqueue is **not** best-effort: if it fails
   the create fails and the order rolls back, because an order whose saga nothing
   remembers is worse than no order — the customer sees a created order that
   never progresses.
2. **The inline start stays**, so the common path keeps its latency and never
   touches the dispatcher. On success it marks the row `DISPATCHED`; on failure it
   leaves it `PENDING` and returns to the caller.
3. **A dispatcher in the order worker sweeps due `PENDING` rows.** It claims with
   a *lease* — one statement that selects `FOR UPDATE SKIP LOCKED`, increments
   `attempts`, and pushes `next_attempt_at` out — so no transaction is held across
   a Temporal call, two dispatchers cannot claim one row, and a dispatcher that
   dies mid-dispatch still burned an attempt.
4. **The row carries the payment token, transiently.** It is the only input the
   dispatcher cannot rebuild. It is cleared on **both** terminal transitions, and
   a `payment_method_cleared` flag records that it once existed so an empty token
   cannot be confused with an order that never had one.
5. **Exactly-once is enforced at three layers**, because no single one is
   sufficient:
   - `REJECT_DUPLICATE` is the **default** in the start seam, not something each
     caller remembers. Omission has to be safe.
   - `WorkflowExecutionErrorWhenAlreadyStarted: true`, because without it the SDK
     **swallows** the rejection: it converts
     `serviceerror.WorkflowExecutionAlreadyStarted` into a handle for the existing
     run and returns a nil error
     (`sdk@v1.45.0/internal/internal_workflow_client.go:2144-2151`, documented at
     `internal/client.go:93`). A refused start would otherwise look like a
     successful one.
   - On a collision the dispatcher **describes the existing run** and only closes
     the row for a live or completed one. A collision says a run *exists*, not
     that it did its job; a run terminated by an operator or timed out leaves
     nothing driving the order, and closing the row there would delete the only
     record that a saga is owed.
6. **Rows past the dedup window are refused, not started.** Once the previous run
   ages out of namespace retention the server has nothing left to reject, so a
   stale `PENDING` row whose saga already ran would start a brand new one. The
   outbox stores no run id, so age is the only evidence available.
7. **Bounded vocabularies.** `last_error_code` holds only tokens mapped from
   Temporal's `serviceerror` types, never a message; metric labels are the four
   dispatch results.
8. **Observability reads the table.** `pending`, `failed` and `oldest_age` are
   OTel *observable* gauges evaluated on each collection cycle, so they cannot
   drift when a process restarts or two instances run. A failing read returns the
   error rather than reporting zeros, because zero is indistinguishable from
   "nothing pending" — the one reading an operator must not be handed during a
   database problem. They are registered in **both** the API and the worker, since
   the worker exits when Temporal is unreachable and that is exactly when a
   backlog builds.

## Alternatives considered

- **Sweep `orders WHERE status = 'pending' AND created_at < now() - 5m`** — no new
  table. Pros: no schema change, no second write. Cons: it cannot carry the
  payment token, so every recovered saga would charge the demo token; and it
  cannot distinguish "never started" from "started and still running", so it would
  re-start healthy in-flight sagas. Rejected on both counts.
- **Temporal first, then commit the order.** Pros: no order without a workflow.
  Cons: the inverse failure — a workflow referencing an order that never
  committed, which then fails every activity and compensates something that does
  not exist. It also does not remove the atomicity problem, it moves it.
- **Store `workflow_id` in the row.** Rejected: it is a pure function of the order
  id, so it would be a second source of truth to keep in sync for no benefit. The
  dispatcher derives it through the same seam the API uses.
- **Persist the payment token on `orders`.** Rejected: a token on the order row
  outlives the order's whole lifetime and reaches every backup, whereas in the
  outbox it is cleared on the terminal transition — usually milliseconds later.
- **Run the dispatcher in the API process.** Pros: the API tolerates Temporal
  being unreachable, so it would sweep during an outage. Cons: the API scales with
  traffic, so N replicas would compete for the same rows; and sweeping during a
  Temporal outage produces nothing but burned attempts (see Consequences).
  Rejected, but the *observability* half of its argument was taken — the gauges
  are registered in the API too.
- **Delete the row on success** instead of marking it `DISPATCHED`. Pros: the
  token disappears sooner and the table stays small. Cons: no audit trail of which
  orders ever needed recovery, and the row is the natural place to record the
  attempt history that explains an incident. Accepted the growth instead, and made
  `Stats` read only the open statuses so its cost tracks open work rather than
  lifetime order volume.

## Consequences

- **The attempt cap is coupled to the worker's fail-fast Temporal dial, and the
  coupling is not obvious.** Attempts burn on claim, and the cap does not
  distinguish "this row is poison" from "the dependency is down" — so a dispatcher
  sweeping through a multi-hour Temporal outage would walk **every** stranded row
  to the cap and mark them `FAILED`: the platform giving up on every order because
  of an outage that then ended. That cannot happen today only because the worker
  exits when Temporal is unreachable, so no sweeps occur while the dependency is
  down. The safety is real but accidental. **Making the worker survive an
  unreachable Temporal requires teaching the cap the difference first** — either
  by not counting `UNAVAILABLE`/`DEADLINE_EXCEEDED` toward it, or by tracking
  consecutive-failure-with-a-live-dependency separately. The dependency is
  recorded at the constant in code as well as here.
- **A Temporal outage delays recovery, it does not lose it.** Rows persist, and
  the dispatcher sweeps immediately on startup rather than waiting a poll
  interval. Sweeping during the outage would fail every attempt anyway.
- **`FAILED` rows have no requeue tooling, deliberately.** The token is cleared, so
  a requeue would start a saga against the demo token. By the attempt cap —
  roughly two hours of retries — the authorization window has almost certainly
  passed, so the supported operator action is to fail the order and let the
  customer retry. The dispatcher refuses a cleared row rather than trusting an
  operator to remember.
- **Drain rate is about 0.2 rows/second** (batch 10, sequential, each start
  bounded at 5s). Ample for recovery; if order intake exceeded that during a long
  outage the backlog would grow. Batch size is the knob.
- **The table has no retention.** One `DISPATCHED` row accumulates per order for
  the platform's lifetime. `Stats` is filtered to the open statuses so metrics
  cost does not grow with it, but a cleanup job is owed.
- **Alerts and the runbook are not part of this decision.** The alert-worthy
  signal is `oldest_age`, not the count — one order pending for twenty minutes is
  an incident, twenty pending for two seconds during a Temporal restart is the
  system working — and it needs `absent()` handling, because a database failure
  blanks all three gauges together and a naive threshold would silently *resolve*
  during the incident. They land with the other RFC-0021 phase-3 write-path
  alerts.
- **Gained:** a committed order is now guaranteed to reach its saga exactly once,
  the guarantee is testable without Temporal, and "how many orders are waiting and
  for how long" became a number instead of a log search.

---

**A note on why the code looks the way it does.** The first implementation trusted
`ErrAlreadyStarted` to surface on a rejected duplicate. It does not, unless the
SDK is explicitly told to — and until that was found, `REJECT_DUPLICATE` was
silently converting a double start into something worse: the dispatcher read the
nil error as success, closed the durable row, and the order sat `pending` forever
with `pending == 0` on the dashboard. The same latent bug sat in the gRPC
idempotent-kickoff branch, which had depended on that error since RFC-0015 P2. The
tests could not catch it, because the fakes returned an error the real client
never produces. Any future change to how a start is issued should re-read that
part of the SDK rather than the SDK's method signature.

---

_Last updated: 2026-07-28_
