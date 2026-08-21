# Temporal Workflow Registry

The index of every Temporal workflow on the platform: what each one is for, who
owns it, and where the detail lives. This file is the **canonical owner of the
index**; per-service roles live in each service doc's `## Temporal participation`
section, and the behaviour of each workflow is in
[temporal.md](./temporal.md).

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Status** | Implemented — three workflows, two workers, all running in local-stack and in-cluster | — |
| **Scope** | The index and the naming rules. Behaviour, steps and diagrams belong to [temporal.md](./temporal.md) | — |
| **Namespace** | `mop` | — |
| **Design records** | — | [ADR-030](../proposals/adr/ADR-030-temporal-workflow-versioning/) (worker versioning) · [ADR-031](../proposals/adr/ADR-031-fulfillment-start-outbox/) (start outbox) · [RFC-0021](../proposals/rfc/RFC-0021/) |

## Registry

| Workflow | Purpose | Owner | Worker | Task queue | Detail |
|----------|---------|-------|--------|------------|--------|
| <a id="order-fulfillment"></a>`OrderFulfillmentWorkflow` | Turn a committed order into money taken, stock committed and a shipment created — or undo all of it | order | `order-worker-2-4-0` — **versioned**, `Pinned` (ADR-030) | `order-fulfillment` | [temporal.md § OrderFulfillmentWorkflow](./temporal.md#orderfulfillmentworkflow) |
| <a id="order-cancellation"></a>`CancellationWorkflow` | Give back what a cancelled order took, and park loudly when it cannot | order | `order-worker-2-4-0` (same worker) | `order-fulfillment` | [temporal.md § CancellationWorkflow](./temporal.md#cancellationworkflow) |
| <a id="abandoned-checkout"></a>`AbandonedCheckoutWorkflow` | Expire a checkout session the shopper walked away from | checkout | `checkout-worker` | `checkout` | [temporal.md § AbandonedCheckoutWorkflow](./temporal.md#abandonedcheckoutworkflow) |

### What each one is for

**`OrderFulfillmentWorkflow`** starts when an order row commits and the shopper
has been told the order is being processed. It authorises payment, reserves
stock, creates the shipment, captures the money and confirms the order. Failure
before the pivot undoes every completed step; failure after it does not roll
back. Participants: inventory, shipping, payment, notification, cart.

**`CancellationWorkflow`** starts when a cancel request is accepted. It reads
what the order actually took — shipment, payment state, reservation state — and
returns each of them, then completes the cancellation. It always finishes; the
order's state carries the outcome, and anything that will not converge parks in
`manual_review` with a reason an operator can act on. Participants: shipping,
payment, inventory, notification.

**`AbandonedCheckoutWorkflow`** is signalled by every session mutation and
started by the first one. When its timer fires it asks the database whether the
session's deadline has really passed and expires the row only if it has. It
touches no other service and holds nothing: the deadline on the row is the only
clock, so a lost signal delays an expiry rather than causing a wrong one.

Both workers run in local-stack (`local-stack/compose.yaml`) and in-cluster on
namespace `mop`. Order ships **one manifest per Worker Deployment Version**, side
by side (ADR-030): `1-13-2` is Current, and earlier builds keep polling only
until their pinned histories drain — a pre-phase-4 saga left with no poller would
stall holding stock and an authorization, because 1.13.x **refuses** a
product-participant history rather than re-routing it. Checkout is deliberately
**not** versioned, so its worker is a single manifest and a tag move is safe. See
[order-worker-2-4-0.yaml](../../kubernetes/apps/order-worker-2-4-0.yaml) and
[checkout-worker.yaml](../../kubernetes/apps/checkout-worker.yaml).

## Standard roles

| Role | Meaning | In service doc |
|------|---------|----------------|
| **None** | No Temporal | Table 1 row `Temporal: None` + 3-line section |
| **Orchestrator** | Owns workflow + worker | Table 1 Worker + Temporal rows; full `## Temporal participation` |
| **Client** | StartWorkflow / SignalWithStart only | Table 1 Temporal row; section explains detached context |
| **Participant (gRPC)** | RPC called by an activity | Table 1 `Temporal: Participant`; gRPC table **Saga** column |
| **Participant (side-effect)** | REST/internal call from an activity | Table 1 `Temporal: Participant`; HTTP route + best-effort note |

## Per-service snapshot

| Service | Temporal role |
|---------|---------------|
| auth, user, review | **None** |
| shipping, payment, notification, inventory | **Participant (gRPC)** — order saga |
| product | **None** — former participant; `ReserveStock`/`ReleaseStock` left the contract in pkg v0.33.0 / product 1.7.0. It serves `BatchGetCurrentPrices` to checkout, which is not a saga step |
| cart | **Participant (REST)** — ClearCart activity |
| order | **Orchestrator** — `OrderFulfillmentWorkflow` + `CancellationWorkflow` |
| checkout | **Orchestrator** — `AbandonedCheckoutWorkflow` |

## Naming rules (new workflows)

| Concept | Pattern | Current examples |
|---------|---------|------------------|
| Workflow type | `{Domain}{Process}Workflow` | `OrderFulfillmentWorkflow`, `AbandonedCheckoutWorkflow` |
| Task queue | kebab-case, one queue per worker pool | `order-fulfillment`, `checkout` |
| Workflow ID | `{process-kebab}-{business-key}` | `order-fulfillment-<orderID>`, `order-cancellation-<orderID>-v<epoch>` |
| Worker deployment | `{owner-service}-worker` (same image, `args: ["worker"]`) | `order-worker`, `checkout-worker` |
| Activity | `{Verb}{Noun}` in orchestrator repo | `ReserveInventory`, `ExpireIfDue`, `ClearCart` |
| Participant contract | gRPC/HTTP doc in **owning service** | `PaymentService.Authorize` → [payments.md](./payments.md) |

A workflow ID carries a version suffix only when the same business key may
legitimately run the process more than once — `order-cancellation-…-v<epoch>` is
the one case today, because an order can re-enter cancellation after an operator
resolves it.

## Adding a workflow

1. Add a row to this registry **before** shipping code, with a Purpose that says
   what it is for rather than what it is called.
2. Add a section to [temporal.md](./temporal.md) using the same shape as the
   existing three: what it is for, what starts it, what it guarantees, its steps,
   and how it ends — with at least one diagram.
3. Orchestrator service doc: full `## Temporal participation` section.
4. Each participant doc: update the gRPC/HTTP table and the **Saga** column on
   the relevant RPC or route.
5. Do **not** paste step tables into the participant service docs — they link the
   deep dive instead.

## References

- [temporal.md](./temporal.md) — the three workflows as built, plus saga theory and operations
- [Service contracts](README.md#service-contracts) — platform deployment rollup

_Last updated: 2026-08-11 — the saga role table moves product to None and names inventory as the stock participant._
