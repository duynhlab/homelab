# ADR-001: Adopt Temporal for order fulfillment

| Status | Date |
|--------|------|
| Accepted | 2026-06-15 |

## Context

Checkout in `order-service` committed the `orders` row and then ran its side effects
(notification, cart-clear) **synchronously and fire-and-forget** on detached contexts. This had
real correctness problems:

- **Lost work on failure.** A failed downstream call (or a pod restart mid-flight) silently dropped
  the side effect — logged, then forgotten. Nothing recorded that it still needed doing.
- **No inventory decrement.** Stock was a `// TODO`; checkout never reserved it.
- **No shipment** was created proactively.
- **No compensation.** A partial failure (stock taken, shipment fails) left the system inconsistent
  with no rollback.

We need order fulfillment to be a **durable, multi-step, all-or-nothing** process across
product / shipping / order / notification / cart: every checkout must reach a terminal state —
fully fulfilled or cleanly rolled back — and survive process restarts. The work is inherently a
**distributed saga** (forward steps + compensations), not a single transaction (the data lives in
separate service databases).

## Decision

Adopt **[Temporal](https://temporal.io/)** (Go SDK) as the workflow engine and implement order
fulfillment as a Temporal **saga**: a durable `OrderFulfillmentWorkflow` started after the order
commits, with one activity per step, per-activity `RetryPolicy`, and compensations run in reverse on
failure. The HTTP request stays async (`201 pending`); the workflow drives the order to
`confirmed`/`failed`. See the [implementation guide](../api/temporal-order-fulfillment.md).

## Alternatives considered

### Transactional outbox + relay
- **Pros:** No new infra engine; uses the existing Postgres; at-least-once delivery of events.
- **Cons:** Solves *reliable event emission*, not *orchestration*. We'd still hand-build the saga
  state machine, compensation ordering, retries, timeouts, and visibility on top of it. An outbox
  per service + a relay + a coordinator is a lot of bespoke machinery.
- **Rejected:** Reinvents most of what a workflow engine provides, with worse visibility.

### Message queue + choreography (e.g. each service reacts to events)
- **Pros:** Loose coupling; scalable; well-understood.
- **Cons:** Choreographed sagas spread the business flow across N services with no single place that
  describes "what a checkout does." Compensation ordering and stuck-flow debugging become emergent
  and hard to reason about; there's no first-class execution history.
- **Rejected:** The flow is short, ordered, and benefits from a single **orchestrator** that owns
  the sequence and compensations explicitly.

### Hand-rolled orchestration in application code
- **Pros:** No new dependency.
- **Cons:** Durability across restarts is the hard part — you end up persisting step state, building
  a retry/backoff engine, and a resume-after-crash mechanism. That *is* a workflow engine, built
  badly.
- **Rejected:** High effort to get right; exactly the wheel Temporal already turns.

### Temporal (chosen)
- **Pros:** Durable execution (state persisted per step; resumes after crash), built-in retries +
  timeouts, the saga pattern as ordinary testable Go (`testsuite`), and a Web UI with full execution
  history. Operator-based GitOps install fits the platform.
- **Cons:** A new stateful infra dependency (server + DB) and a programming model to learn;
  determinism constraints in workflow code.
- **Accepted:** The durability/visibility/compensation guarantees directly solve the problem, and
  the costs are bounded for a single-cluster homelab.

## Consequences

- A new platform capability + dependency: a Temporal cluster (server + `temporal-db`) and a
  **worker** per owning service (`worker` subcommand). Deployment choice is **[ADR-002](ADR-002-deploy-temporal-via-operator.md)**.
- Activities must be **idempotent** (retries) and workflow code **deterministic** — enforced by
  design + `testsuite` tests.
- New idempotent gRPC contracts (`pkg` `v0.7.0`): product `ReserveStock`/`ReleaseStock`, shipping
  `CreateShipment`/`CancelShipment`.
- Checkout becomes **async** (`201 pending`); the SPA polls for the terminal status.
- When to reach for Temporal again (and when not) is documented in the
  [guide §2](../api/temporal-order-fulfillment.md#2-when-to-use-temporal-and-when-not) — it is for
  durable multi-step orchestration, not for ordinary request/response.
