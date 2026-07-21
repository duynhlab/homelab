# Temporal Workflow Registry

Every durable workflow on the platform, in one table: who orchestrates, who participates, where the deep dive lives. This file is the **canonical owner** of the workflow index; per-service roles live in each service doc's `## Temporal participation` section.

## Registry

| Workflow | Owner | Worker | Task queue | Participants | Deep dive |
|----------|-------|--------|------------|--------------|-----------|
| <a id="order-fulfillment"></a>`OrderFulfillmentWorkflow` | order | `order-worker` | `order-fulfillment` | product, shipping, payment, notification, cart | [temporal-order-fulfillment.md](./temporal-order-fulfillment.md) |
| <a id="abandoned-checkout"></a>`AbandonedCheckoutWorkflow` | checkout | `checkout-worker` | `checkout` | checkout DB (in-process activities) | [checkout.md § Abandonment](./checkout.md#abandonment-p2-implemented--the-timer-is-a-wake-up-never-a-verdict) |

Both workers run in local-stack (`local-stack/compose.yaml`) and in-cluster ([order-worker.yaml](../../kubernetes/apps/order-worker.yaml), [checkout-worker.yaml](../../kubernetes/apps/checkout-worker.yaml)) on Temporal namespace `mop`.

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
| product, shipping, payment, notification | **Participant (gRPC)** — order saga |
| cart | **Participant (REST)** — ClearCart activity |
| order | **Orchestrator** — `OrderFulfillmentWorkflow` |
| checkout | **Orchestrator** — `AbandonedCheckoutWorkflow` |

## Naming rules (new workflows)

| Concept | Pattern | Current examples |
|---------|---------|------------------|
| Workflow type | `{Domain}{Process}Workflow` | `OrderFulfillmentWorkflow`, `AbandonedCheckoutWorkflow` |
| Task queue | kebab-case, one queue per worker pool | `order-fulfillment`, `checkout` |
| Workflow ID | `{process-kebab}-{business-key}` | `order-fulfillment-<orderID>` |
| Worker deployment | `{owner-service}-worker` (same image, `args: ["worker"]`) | `order-worker`, `checkout-worker` |
| Activity | `{Verb}{Noun}` in orchestrator repo | `ReserveStock`, `ExpireIfDue`, `ClearCart` |
| Participant contract | gRPC/HTTP doc in **owning service** | `PaymentService.Authorize` → [payments.md](./payments.md) |

## Adding a workflow

1. Add a row to this registry **before** shipping code.
2. Orchestrator service doc: full `## Temporal participation` section.
3. Each participant doc: update gRPC/HTTP table + **Saga** column on the relevant RPC/route.
4. Complex multi-step saga: new deep-dive file — do **not** paste step tables into all 10 service files.

## References

- [temporal-order-fulfillment.md](./temporal-order-fulfillment.md) — saga theory + as-built + operations
- [Service contracts](README.md#service-contracts) — platform deployment rollup

_Last updated: 2026-07-21_
