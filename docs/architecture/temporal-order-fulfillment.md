# Spec: Temporal Order-Fulfillment Saga

> **Status:** **implemented** ✅ — shipped phase-by-phase and verified end-to-end on `local-stack`
> (a checkout drives the full saga; an over-quantity checkout fails fast and rolls back). This doc
> is the as-built source of truth for the platform's first Temporal workflow + its infrastructure.
> See [§9 As-built notes](#9-as-built-notes) for what differs from the original design and the
> tracked follow-ups.

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
- **Deploy:** **[`alexandrevilain/temporal-operator`](https://github.com/alexandrevilain/temporal-operator)**
  (`TemporalCluster` + `TemporalNamespace` CRDs) via a Flux `HelmRepository` + `HelmRelease` —
  fits the platform's operator-heavy GitOps, reconciles the cluster declaratively, handles schema
  create/upgrade on version bumps, and emits a `ServiceMonitor`.
  - **Server version — pinned to `1.24.2` for now (target `1.27.x`):** the operator's *published
    Helm chart* tops out at `0.6.0` (operator **v0.20.0**, which supports Temporal server
    `>=1.14.0 <1.25.0`). Operator **v0.22.0** supports `<1.29.0` (i.e. 1.27.x) but ships **only raw
    release manifests — no published chart**. To keep a clean Helm/Renovate install we run the
    chart and pin the server to **1.24.2** today; bump to **1.27.x** once the operator re-publishes
    its chart for v0.22.0 (Renovate tracks the `HelmRepository`). Vendoring the v0.22.0 manifests
    was considered and rejected (≈5k lines of vendored CRDs, no Renovate, manual re-vendor + Kyverno
    patch on every upgrade).
  - **Known limitations (accepted for this homelab scope):** the operator does **not** provide
    native **auto-scaling** of the Temporal services, nor **multi-cluster replication** setup. Fine
    for a single-cluster homelab; revisit if those become requirements.
  - **Alternative (documented for awareness, not chosen):** the official
    [`temporalio/helm-charts`](https://github.com/temporalio/helm-charts) `temporal` chart — the
    canonical install. It uses no DB sub-chart (point it at an external Postgres via
    `server.config.persistence.datastores` + `existingSecret`, `useHelmHooks: false` for Flux).
    Reach for it if you later need the chart's broader knobs over the operator's CRD model.
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
        OP[temporal-operator]
        TC[TemporalCluster<br/>frontend/history/matching/worker]
        UI[Web UI]
        TDB[(CNPG temporal-db<br/>temporal + temporal_visibility)]
        OP --> TC
        TC --> TDB
        TC --> UI
    end
    subgraph ns_order[ns order]
        OW[order worker<br/>task queue: order-fulfillment]
    end
    OW -- gRPC :7233 --> TC
    Kong[Kong] -- temporal.duynh.me --> UI
    TC -- /metrics --> VM[VictoriaMetrics]
    OW -- OTLP --> Tempo
```

- **Operator** in `kubernetes/infra/controllers/temporal/` — `temporal-operator` `HelmRepository`
  + `HelmRelease` (chart `0.6.0`); installs the `TemporalCluster`/`TemporalNamespace` CRDs. Webhook
  certs via cert-manager.
- **TemporalCluster + `mop` TemporalNamespace** (retention 168h) in
  `kubernetes/infra/configs/temporal/`: server **`1.24.2`** (target 1.27.x — see §2),
  `numHistoryShards: 512`, persistence → `temporal-db` (default + `temporal_visibility` via
  `passwordSecretRef` from the **CNPG-generated `temporal-db-app` secret**), `ui.enabled`,
  `admintools.enabled`, `metrics.prometheus.serviceMonitor.enabled`, resources set on every
  operator-created pod for Kyverno (probes are operator-managed).
- **temporal-db** in `kubernetes/infra/configs/databases/clusters/temporal-db/` — CloudNativePG
  cluster with the two stores (`temporal` + `temporal_visibility`). Single instance for now
  (Temporal HA is at the service layer); scaling + Barman backups are a follow-up.
- **Kong** ingress `temporal.duynh.me`; **`TemporalServerDown`** PrometheusRule. A Grafana
  dashboard + richer alerts (persistence errors, task-queue backlog, workflow-failure rate) land in
  Phase 8 once metric names are confirmed from a live scrape.
- **Flux**: `controllers → temporal-operator`; `databases → temporal-db`; new `temporal`
  Kustomization (`dependsOn` databases) before `apps`; the order worker `dependsOn` temporal.
- **Kyverno**: temporal pods must satisfy image-pin/probes/resources/PSS (set via CR/HelmRelease
  values; a scoped+expiring PolicyException only if unavoidable).

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
- ✅ **Happy path** — verified on `local-stack`: checkout → `201 pending`; Temporal UI shows
  `OrderFulfillmentWorkflow` **Completed**; stock decremented (DB 50→48 + `stock_reservations`
  ledger row); shipment created (`MOP0000000006`); cart cleared; order `confirmed`.
- ✅ **Fail-fast / no side effects** — verified: an over-quantity checkout → `ReserveStock`
  `FAILED_PRECONDITION` (non-retryable) → workflow **Failed**, order `failed`, stock untouched, zero
  reservations.
- **Compensation (ReleaseStock/CancelShipment)** — covered by the order-service workflow
  `testsuite` tests (failure injected at CreateShipment / ConfirmOrder asserts reverse-order
  compensation + order `failed`); a live mid-saga failure drill is a future GameDay.
- **Durability** — Temporal's guarantee (worker restart resumes in-flight workflows); covered by
  design, a live kill-the-worker drill is a future GameDay.
- **Infra (Kind)** — `TemporalCluster` Ready, schema set up, UI via Kong, ServiceMonitor scraped,
  Kyverno admits the pods: verify on `make up` (the manifests pass `make validate`).

## 8. Resolved decisions
- **Server version:** Temporal **`1.24.2`** today, **target `1.27.x`**. The published operator
  chart (`0.6.0` / operator v0.20.0) only supports server `<1.25.0`; the v0.22.0 operator that
  supports 1.27.x has no published chart. We keep the clean Helm/Renovate install and bump the
  server to 1.27.x once the chart is re-published (§2).
- **Deploy:** `alexandrevilain/temporal-operator` via `HelmRepository` + `HelmRelease` (chart
  `0.6.0`), `TemporalCluster`/`TemporalNamespace` CRDs, against the external CNPG `temporal-db` (§2)
  using the **CNPG-generated `temporal-db-app`** secret. Accepted gaps: no native auto-scaling, no
  multi-cluster replication. The official `temporalio/helm-charts` is documented as the
  alternative (§2), not chosen.
- **Checkout contract:** **async** — `CreateOrder` returns **201 `pending`** immediately and the
  saga finishes it (`confirmed`/`failed`); the SPA shows "Processing…" and polls
  `GET /order/v1/private/orders/:id`. The request does **not** block on the saga: retries can take
  seconds–minutes, blocking would couple user latency to downstream health and risk gateway/client
  timeouts, and an API-pod restart would lose the response while the durable workflow keeps running.
  *Future nicety (deferred):* Temporal **Update-With-Start** can return an early "accepted / stock
  reserved" ack in the initial call while the rest continues async.

## 9. As-built notes

What shipped differs from the original design in a few deliberate ways:

- **Saga shape — ConfirmOrder is the pivot.** `ReserveStock → CreateShipment` compensate in reverse
  on failure (`ReleaseStock` / `CancelShipment`) and the order is marked `failed`. After
  `ConfirmOrder` succeeds the order is `confirmed`; `SendNotification` + `ClearCart` are
  **best-effort** (a failed notification/cart-clear never rolls a confirmed order back).
- **Workflow start lives in the web handler** (where the old fire-and-forget calls were), so the
  logic layer stays Temporal-free. If Temporal is unavailable at request time the order is still
  created (`pending`) and the start is logged — checkout never fails on Temporal.
- **`ClearCart` carries the caller's bearer token** in the workflow input (cart's private REST
  validates it; the saga runs within seconds). Homelab simplification — production should expose an
  internal, NetworkPolicy-fenced cart-clear (by user id) and drop the token from workflow history.
- **Idempotency is DB-enforced.** product `stock_reservations` (PK `reservation_id,product_id`) and
  shipping `UNIQUE(order_id)` make `ReserveStock`/`CreateShipment` safe to retry. `ReserveStock`
  insufficient stock is a **non-retryable** activity error (fail fast → compensate).
- **Server pinned 1.24.2**, target 1.27.x (operator chart cap — see §2/§8).
- **Cache staleness (known follow-up):** the product read API serves Cache-Aside (Valkey) views, so
  stock can read stale right after a reserve until the TTL (~10 min); the DB is authoritative.
  Fix: bust the product cache on `ReserveStock`/`ReleaseStock`.
- **Observability:** the operator scrapes Temporal server metrics via a `ServiceMonitor`; alerts are
  `TemporalServerDown` + service/persistence error-rate (official metric names). The worker exposes
  `/health`, `/ready`, `/metrics` (gRPC RED + Go runtime). **Follow-ups:** (a) a Grafana dashboard
  adapted from the official [`temporalio/dashboards`](https://github.com/temporalio/dashboards)
  `server/server-general.json`; (b) workflow/activity-level RED metrics + burn alerts via a Temporal
  SDK `MetricsHandler` wired into `pkg/temporalx`.

## Phases — all delivered ✅
0 spec (this doc) · 1 infra (operator + `temporal-db` + cluster + UI) · 2 `pkg` `temporalx`+proto
(`v0.7.0`) · 3 product inventory · 4 shipping create/cancel · 5 order saga+worker · 6 `mop` worker
mode (chart `0.10.0`) · 7 local-stack e2e · 8 docs/observability (this update).
