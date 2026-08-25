# ADR-033: Make Order Status a Guarded State Machine with Customer Cancellation

> **Decision summary:** We will replace order's unconditional status UPDATE
> with a closed FSM written only through a CAS-guarded, history-recording
> command path, and deliver customer cancellation as a separate Temporal
> workflow driven by that same path. We accept committed-stock shrinkage on
> cancellation (no inventory Return RPC yet) and a best-effort UX projection
> in exchange for status writes that can no longer race, lie, or lose audit.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-07-31 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | `orders.status` lifecycle, cancellation, manual review, processing projection |
| **Affected components** | order-service (API + worker), payment/shipping/inventory (called), frontend |
| **Related RFC** | [RFC-0021](../../rfc/RFC-0021/) (Phase 5) |
| **Related research** | [research.md](../../rfc/RFC-0021/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | order-service #157–#167, homelab #639/#640, frontend #79 |
| **Adoption** | Complete |

## Context

Until v1.9.x, `orders.status` had three values (`pending/confirmed/failed`)
written by `UpdateStatus` — an unconditional `UPDATE` with no guard, no
version, and no history. A lost-ack `ConfirmOrder` could be overwritten by a
racing `FailOrder` (and vice versa), replays were indistinguishable from
conflicts, and nothing recorded who moved an order or why. There was no
customer cancellation: once confirmed, an order could only be refunded by
hand. RFC-0021 P5's exit criteria — *no generic status writes; cancellation
and manual-review semantics clear* — forced the decision.

## Scope

### In scope

- The order status vocabulary, its transition table, and who may drive each edge.
- The single write path (CAS + idempotent command ids + append-only history).
- Customer cancellation end-to-end, including its stock/refund disposition.
- Manual review as a parked state with an operator-only exit.
- The processing projection's consistency class (UX, not correctness).

### Out of scope

- Inventory restock (`Return` RPC) — inventory.v1 has no such RPC; see the
  accepted trade-off below.
- Reconciler settlement semantics (ADR-031 territory); only its terminal set
  changes here.
- Payment idempotency-cache behavior (cross-repo follow-up below).

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Correctness under races | Status is money-bearing: confirm/fail/cancel outcomes must not overwrite each other |
| 2 | Auditability | Every transition needs an actor, a command id, and a reason an operator can trust |
| 3 | Operability | Stuck states must be worklist items (gauges + alerts), not silent data |
| 4 | Learning value | The platform mirrors production practice: FSM + CAS + outbox is the canonical shape |

## Decision

We will make `orders.status` a closed seven-state FSM — `pending`,
`confirmed`, `failed`, `completed`, `cancelling`, `cancelled`,
`manual_review` (lowercase on disk, CHECK-constrained since migration
000014) — whose only writer is `ApplyStatusCommand`: one transaction under
`SELECT … FOR UPDATE` that validates the transition **and** the actor,
replays idempotently by `(order_id, command_id)`, appends to
`order_status_history`, and applies a version-guarded UPDATE. Domain methods
(`Confirm`, `Fail(reason)`, `Complete`, `MarkManualReview`,
`RequestCancellation`, `CompleteCancellation`, `ResolveManualReview`) are the
whole API; there is no generic setter.

Cancellation is a **separate** `CancellationWorkflow` (not a signal into the
fulfillment saga): the cancel API CASes the order to `cancelling` and arms a
lean outbox row in one transaction, then the workflow unwinds by *current*
server-side state — cancel shipment, void or refund the remainder by payment
state, release a RESERVED reservation — and always completes; the order state
carries the outcome. Compensation exhaustion anywhere parks the order in
`manual_review` (`COMPENSATION_INCOMPLETE`), which only an OPERATOR command
can leave.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | order-service owns `orders.status`; no other service writes it |
| **Write path** | `ApplyStatusCommand` only — FSM edge + actor matrix + `KnownReason` under the row lock |
| **Actors** | USER only reaches `cancelling`; only OPERATOR leaves `manual_review`; WORKFLOW drives saga edges; SYSTEM only `pending→failed` |
| **Command ids** | Workflow commands are version-free (`confirm:<id>` — reasons ride the payload so a reset that fails differently still replays); USER/OPERATOR and cancellation-episode commands carry the observed `orders.version` as an epoch (`cancel:<id>:v<n>`) |
| **Terminal semantics** | `failed` only when ALL compensations converged; any exhaustion → `manual_review` |
| **Cancellation edges** | `confirmed→cancelling` and `completed→cancelling` (see consequence below); policy gate = shipment not dispatched |
| **Failure behavior** | Cancellation activities read current state server-side, so a late or duplicate workflow start is harmless |
| **Compatibility** | History begins at the v1.10.0 cutover — pre-FSM rows got vocabulary normalization (000014), never backfilled history |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — FSM + CAS command path + separate cancellation workflow** | Races impossible by construction; audit for free; cancellation isolated from fulfillment history | More moving parts (history table, outbox, second workflow type) | Selected |
| **B — Keep UpdateStatus, add WHERE-status guards ad hoc** | Small diff | No audit, no actor control, replay vs conflict still ambiguous; every new edge re-litigates the guard | Rejected |
| **C — Cancellation as a signal into the fulfillment saga** | One workflow type | Couples cancel to fulfillment history and ADR-030 pinning; a completed saga cannot be signalled, so `completed→cancelling` would need a new workflow anyway | Rejected |

### Why the selected option won

Only A satisfies driver 1 structurally: the FSM table plus the row lock makes
an illegal write unrepresentable rather than merely unlikely, and the
command-id grammar turns retries into replays instead of conflicts. C failed
on its own terms the moment the `completed→cancelling` edge was accepted.

## Consequences

### Positive consequences

- Lost-ack overwrites are gone; every transition is attributable
  (`order_status_history` carries actor, command id, reason, workflow identity).
- Cancellation is durable: CAS + outbox arm commit together, the inline start
  is a fast path, the dispatcher sweeps the rest.
- Parked work is visible: `order_manual_review_backlog` and
  `order_cancelling_backlog` gauges feed the phase-5 alerts and runbooks.

### Negative consequences and accepted trade-offs

- **Committed stock is not restocked on cancellation.** inventory.v1 has no
  `Return` RPC; a COMMITTED reservation is recorded as `RESTOCK_SKIPPED`
  (accepted shrinkage). The branch is isolated in
  `resolveInventoryDisposition`, so adding a `Return` RPC later changes one
  arm. Named follow-up, not silent debt.
- **`completed → cancelling` widens the cancel window.** `Complete()` runs at
  the saga tail seconds after confirm, so without this edge full cancellation
  would be a few-seconds feature. The unified policy gate (shipment not
  dispatched) is as-built accurate — shipping has no carrier integration.
- **The processing projection is deliberately non-transactional.** Stage
  writes are best-effort (tiny retry budget, counted by
  `order_projection_write_failures_total`); `orders.status` never depends on
  them. A dark projection degrades the SPA's progress rendering, nothing else.
- **The reconciler does not settle `cancelled`.** Its terminal set grew to
  `{confirmed, failed, completed}` only; the cancellation workflow settles its
  own stock, and the backstop for a wedged episode is `OrderStuckCancelling`,
  not the reconciler. Gap accepted and documented here.
- **Cross-repo follow-up owed:** payment-service answers a provider-declined
  refund with gRPC OK + `status:"failed"` and seals that into its idempotency
  cache as a 201. The order side defends itself (verifies
  `refund.status=="succeeded"`, parks otherwise), but payment must stop
  caching failed refunds as success.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| FSM + CAS + history + saga rewrite + cancellation + projection | order-service | #157–#164 (v1.10.0) | Replay gate green on gen-2 corpus; live e2e table in #164 |
| Delete generic writes; CHECK the vocabulary; remove legacy REST create | order-service | #165–#167 (v1.10.1–v1.11.0) | grep gate: no `UpdateStatus`; 000014 constraint live |
| Worker build pin + activation (ADR-030) | homelab | #640 | `order-worker` build 1.10.0 Current on the cluster |
| Alerts + runbooks + gauges | homelab | #639 | Phase-5 alerts fire on test data; runbooks linked |
| Cancel UI + FSM states | frontend | #79 | agent-browser e2e: cancel → cancelling → cancelled |
| docs/api sync | homelab | this PR | order.md / workflows.md / temporal doc match as-built |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Single write path | grep gate (no `UpdateStatus`); repository integration tests drive every edge |
| Race safety | Integration race test: competing history insert serializes via FK KEY SHARE → FOR UPDATE queue → replay convergence |
| Actor matrix | FSM matrix unit tests (mutation-killed) + `ActorAllowed` under-lock checks |
| Determinism | `ORDER_RELEASE_GATE=1` replay gate over the gen-2 corpus (both workflow types) |
| Vocabulary | Migration 000014 CHECK; seed normalized; `INSERT 'shipped'` rejected (proof in #166) |
| Operability | Phase-5 PrometheusRules + 4 runbooks; operator resolve drill executed on a real parked order |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- inventory.v1 grows a `Return`/`Restock` RPC (flip `RESTOCK_SKIPPED` to a
  real return in `resolveInventoryDisposition`).
- Shipping gains carrier dispatch, making the "shipment not dispatched" cancel
  gate meaningfully time-bound — the policy needs a real window.
- The reconciler-cancelled gap produces a real incident (a wedged cancellation
  the alert did not surface).
- Manual-review volume makes the operator SQL discipline untenable — build an
  operator API/UI instead.

## References

- [RFC-0021](../../rfc/RFC-0021/) — platform overhaul umbrella (Phase 5)
- [Order contract](../../../api/order.md)
- [Temporal order fulfillment](../../../api/temporal.md)
- [Workflows registry](../../../api/workflows.md)
- [ADR-030](../ADR-030-temporal-workflow-versioning/) — worker versioning the cutover rides on
- [ADR-031](../ADR-031-fulfillment-start-outbox/) — the outbox pattern the cancellation start mirrors
- Runbooks: [OrderStuckCancelling](../../../observability/runbooks/microservices/OrderStuckCancelling.md), [OrderManualReviewBacklog](../../../observability/runbooks/microservices/OrderManualReviewBacklog.md)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-07-31 | Proposed / Not started | Drafted during RFC-0021 P5 planning (owner scope decisions recorded) |
| 2026-08-01 | Accepted / Complete | P5 shipped: v1.10.0–v1.11.0, homelab #639/#640, frontend #79 |

---
_Last updated: 2026-08-10_
