# Spec: Temporal Order-Fulfillment Saga

> **Status:** approved design / not yet implemented. This is the spec-driven source of truth for
> the platform's first Temporal workflow + the Temporal infrastructure. Implementation lands
> phase-by-phase (see [Phases](#phases)).

## 1. Objective

Make order fulfillment **durable, observable, and self-healing**. Today checkout is
synchronous + fire-and-forget: after the `orders` row commits, order-service calls notification
(gRPC) and cart-clear (REST) on detached contexts with **no retry/durability** (failures are
logged and lost), inventory decrement is a **TODO**, a shipment is never created proactively, and
there is **no compensation** on partial failure (`order-service internal/web/v1/handler.go`
`CreateOrder` + `logic/v1/service.go`).

Temporal replaces that with a **saga**: a durable workflow that orchestrates the fulfillment
steps with automatic retries and **compensating actions** on failure. Success = every checkout
either fully completes (stock reserved, shipment created, customer notified, cart cleared, order
`confirmed`) **or** is cleanly rolled back (stock released, shipment cancelled, order `failed`) —
and the process survives worker/pod restarts.

## 2. Decisions

- **Feature:** order-fulfillment saga (flagship — exercises orchestration + retry + durable
  execution + compensation).
- **Deploy:** the official **[`temporalio/helm-charts`](https://github.com/temporalio/helm-charts)**
  `temporal` chart (Flux `HelmRelease`), **server v1.27.x**. It installs no DB sub-chart — point it
  at our external Postgres via `server.config.persistence.datastores` (`postgres12` plugin), use
  **`existingSecret`** (ESO/OpenBAO) for credentials, run **schema setup as Jobs with
  `useHelmHooks: false`** (Flux doesn't run Helm hooks the way the chart's defaults assume), and
  **disable the bundled Cassandra / Elasticsearch / Prometheus / Grafana** (we have our own).
  Chosen over the third-party operator: canonical, no extra CRDs/controller to run.
- **Persistence:** a dedicated **CloudNativePG** `temporal-db` (default + `temporal_visibility`
  SQL stores). Advanced visibility stays **SQL** for now (Elasticsearch is a future option).
- **Worker:** embedded in the owning service via a `worker` subcommand (mirrors the existing
  `migrate` subcommand), not a separate repo.
- **Checkout contract:** the order is still committed synchronously and the HTTP **201 returns a
  `pending` order**; the workflow drives fulfillment asynchronously and moves the order to
  `confirmed`/`failed`.

## 3. The workflow

`OrderFulfillmentWorkflow(orderID)` — started from `CreateOrder` right after the order row
commits. Workflow ID `order-fulfillment-<orderID>` (dedup; reuse the existing idempotency key).
Task queue `order-fulfillment`. Each activity gets a `RetryPolicy` (exp backoff); compensations
are appended as steps succeed and run **in reverse** if a later step fails.

| # | Activity → service | Compensation | Notes |
|---|--------------------|--------------|-------|
| 1 | `ReserveStock(items)` → product-service (**new**) | `ReleaseStock(items)` | atomic per-item `stock -= qty WHERE stock >= qty` |
| 2 | `CreateShipment(orderID, addr)` → shipping-service (**new**) | `CancelShipment(id)` | idempotent by `orderID` |
| 3 | `ConfirmOrder(orderID)` → order core | `FailOrder(orderID)` | status `pending → confirmed` |
| 4 | `SendOrderNotification(userID, orderID)` → notification (gRPC) | — | idempotent, no compensation |
| 5 | `ClearCart(userID)` → cart (REST) | — | idempotent, no compensation |

```mermaid
sequenceDiagram
    participant API as order-service (CreateOrder)
    participant T as Temporal
    participant W as Worker (order-fulfillment)
    participant P as product
    participant S as shipping
    participant N as notification
    participant C as cart

    API->>API: persist order (status=pending)
    API->>T: StartWorkflow(order-fulfillment-<id>)
    API-->>API: HTTP 201 (pending)
    T->>W: OrderFulfillmentWorkflow(orderID)
    W->>P: ReserveStock (retry)
    W->>S: CreateShipment (retry)
    W->>W: ConfirmOrder (pending→confirmed)
    W->>N: SendOrderNotification
    W->>C: ClearCart
    Note over W: on any failure → run compensations in reverse,<br/>then FailOrder (pending→failed)
```

### Order-status state machine

```mermaid
stateDiagram-v2
    [*] --> pending: CreateOrder commits
    pending --> confirmed: saga success
    pending --> failed: saga compensated
    confirmed --> [*]
    failed --> [*]
```

### Retry & timeouts
Activities: `StartToCloseTimeout` (e.g. 10s) + `RetryPolicy{InitialInterval: 1s, Backoff: 2.0,
MaxInterval: 100s, MaxAttempts: 5}`. Non-retryable business errors (e.g. insufficient stock →
`codes.FailedPrecondition`) are marked non-retryable so the saga compensates immediately instead
of hammering. Workflow has a sane `WorkflowExecutionTimeout`.

## 4. Infrastructure topology

```mermaid
flowchart LR
    subgraph ns_temporal[ns temporal]
        TC["Temporal server (Helm)<br/>frontend/history/matching/worker"]
        UI[Web UI]
        TDB[(CNPG temporal-db<br/>temporal + temporal_visibility)]
        TC --> TDB
        TC --> UI
    end
    subgraph ns_order[ns order]
        OW[order worker<br/>task queue: order-fulfillment]
    end
    OW -- gRPC :7233 --> TC
    Kong[Kong] -- temporal-ui.duynh.me --> UI
    TC -- /metrics --> VM[VictoriaMetrics]
    OW -- OTLP --> Tempo
```

- **Temporal server** in `kubernetes/infra/configs/temporal/` — Flux `HelmRelease` of the official
  `temporalio/temporal` chart (v1.27.x): datastores → `temporal-db` (default + `temporal_visibility`,
  `postgres12` plugin), `existingSecret` (ESO), schema setup as Jobs (`useHelmHooks: false`),
  `numHistoryShards: 512`, Web UI enabled, the `mop` namespace auto-created (retention 168h),
  bundled cassandra/elasticsearch/prometheus/grafana **disabled**, resources/probes set for Kyverno.
- **temporal-db** in `kubernetes/infra/configs/databases/clusters/temporal-db/` mirroring
  `cnpg-db` (HA, PgDog pooler, Barman backup, PodMonitor, ESO/OpenBAO secret).
- **Kong** ingress `temporal-ui.duynh.me`; a `ServiceMonitor` for the Temporal metrics endpoint;
  **Grafana dashboard + PrometheusRule** (cluster-down, persistence errors, task-queue backlog,
  workflow-failure rate).
- **Flux**: `databases → temporal-db`; new `temporal` Kustomization (`dependsOn` databases) before
  `apps`; the order worker `dependsOn` temporal. (No separate operator/CRDs.)
- **Kyverno**: chart pods must satisfy image-pin/probes/resources/PSS (set via HelmRelease values;
  a scoped+expiring PolicyException only if unavoidable).

## 5. New contracts (`pkg/proto`, buf, backward-compatible)
- **product**: `ReserveStock(items) → {ok}` · `ReleaseStock(items)`.
- **shipping**: `CreateShipment(orderID, addr) → {shipmentID}` · `CancelShipment(shipmentID)`.
- **`pkg/temporalx`**: shared client + worker bootstrap (mirrors `grpcx`/`obsx`) with the Temporal
  **OpenTelemetry interceptor** so workflows/activities emit traces/metrics into the existing stack.

## 6. Boundaries
- **Always:** activities idempotent + retry-safe; compensations idempotent; SHA-pin new actions/
  images; `go test -race`; verify on docker-local before each PR; CI green before merge.
- **Ask first:** changing the checkout 201 semantics further; adding Elasticsearch visibility;
  schema-affecting changes to shared DBs.
- **Never:** block the HTTP request on the full saga; put secrets in YAML; self-merge.

## 7. Success criteria
- Checkout → Temporal UI shows `OrderFulfillmentWorkflow` complete; stock decremented; shipment
  created; notification sent; cart cleared; order `confirmed`.
- **Durability:** kill the worker mid-run → it resumes and completes.
- **Compensation:** force `CreateShipment` to fail → retries exhaust → stock released, order
  `failed`.
- Infra: Temporal server pods Ready on Kind, schema set up, UI via Kong, metrics in Grafana,
  Kyverno admits pods.

## 8. Resolved decisions
- **Server version:** Temporal **1.27.x** (pinned in the HelmRelease).
- **Deploy:** the official `temporalio/temporal` Helm chart against the external CNPG `temporal-db`
  (see §2) — not a third-party operator.
- **Checkout contract:** **async** — `CreateOrder` returns **201 `pending`** immediately and the
  saga finishes it (`confirmed`/`failed`); the SPA shows "Processing…" and polls
  `GET /order/v1/private/orders/:id`. The request does **not** block on the saga: retries can take
  seconds–minutes, blocking would couple user latency to downstream health and risk gateway/client
  timeouts, and an API-pod restart would lose the response while the durable workflow keeps running.
  *Future nicety (deferred):* Temporal **Update-With-Start** can return an early "accepted / stock
  reserved" ack in the initial call while the rest continues async.

## Phases
0 spec (this doc) → 1 infra → 2 `pkg` temporalx+proto (tag) → 3 product inventory →
4 shipping create/cancel → 5 order saga+worker → 6 `mop` worker mode → 7 local-stack e2e →
8 docs/observability. Sequencing + verification: see the plan.
