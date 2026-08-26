# API Documentation

Start here to learn the platform's shared API rules and then drill into one API
service or the Backoffice application service at a time.

| Attribute | Value | RFC / ADR |
|-----------|-------|-----------|
| **Status** | Living documentation checked against 11 API service repositories and the Backoffice application repository | — |
| **Canonical shared guide** | [api.md](./api.md) | — |
| **Service map** | [microservices.md](./microservices.md) | — |
| **Workflow guide** | [temporal.md](./temporal.md) | — |
| **Design record** | — | None |

## Documentation Map

```mermaid
flowchart TD
    Hub["API documentation hub"] --> Shared["api.md<br/>shared HTTP + gRPC rules"]
    Hub --> Rollup["Service contracts rollup<br/>deployment + CI"]
    Hub --> Catalog["microservices.md<br/>ownership + feature matrix"]
    Hub --> Contracts["11 API contract files"]
    Hub --> Workflows["workflows.md<br/>Temporal workflow registry"]
    Hub --> Saga["temporal.md<br/>3 workflows + saga theory"]
    Hub --> Pkg["pkg.md<br/>shared Go modules + layering"]
    Hub --> Consumer["admin.md<br/>Backoffice app service<br/>+ consumer index"]
    Shared --> Journeys["api.md § End-to-end user journeys"]
    Contracts --> Basic["Auth · User · Product · Inventory · Cart<br/>Order · Review · Notification · Shipping"]
    Contracts --> Deep["Checkout · Payment<br/>state-machine deep dives"]
    Consumer -.->|"links, never restates"| Contracts
    Shared --> Contracts
    Catalog --> Contracts
    Journeys --> Contracts
    Workflows --> Saga
    Template["_template-service.md<br/>authoring template"] -.->|"shapes"| Contracts
    Saga --> Order["order.md"]
    Saga --> Payment["payments.md"]
    Pkg -.->|"contracts ship as the proto module"| Contracts

    classDef hub fill:#2563eb,color:#fff,stroke:#1e3a8a;
    classDef guide fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef contract fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef workflow fill:#f59e0b,color:#451a03,stroke:#b45309;
    class Hub hub;
    class Shared,Catalog,Rollup,Journeys,Template,Pkg,Consumer guide;
    class Contracts,Basic,Deep,Order,Payment contract;
    class Saga,Workflows workflow;
```

The arrows show documentation ownership, not runtime traffic. Runtime traffic is
shown in [api.md](./api.md#current-east-west-call-graph).

## Recommended Learning Path

| Step | Read | What it answers |
|------|------|-----------------|
| 1 | [api.md](./api.md) | How URLs, audiences, auth, errors, pagination, HTTP, and gRPC work |
| 2 | [api.md § End-to-end user journeys](./api.md#end-to-end-user-journeys) | How one user journey (login, browse, checkout, fulfillment) travels through the services |
| 3 | [microservices.md](./microservices.md) | Which service owns each feature and how services call one another |
| 4 | One service file below | Exact HTTP routes, gRPC methods, payload examples, and service rules |
| 5 | [workflows.md](./workflows.md) | Which Temporal workflows exist, who orchestrates them, and who participates |
| 6 | [temporal.md](./temporal.md) | What each of the three workflows does, why Saga instead of 2PC, and how compensation works |
| 7 | [payments.md](./payments.md) or [checkout.md](./checkout.md) | Deeper state-machine, idempotency, and operational examples |
| 8 | [_template-service.md](./_template-service.md) then diff against [checkout.md](./checkout.md) | Authoring shape for new or migrated service contracts (v2) |

## Document Ownership

Three layers — not three copies of the same fact:

1. **Normative contract** (routes, RPCs, payloads, deployment status, ownership boundaries)
   lives here in `docs/api/`. Agents and service authors implement against these files.
2. **Design rationale** (alternatives, tradeoffs, rollout history) lives in
   [RFC](../proposals/rfc/) and [ADR](../proposals/adr/) — link via **Design records**,
   do not paste the full decision essay into a service contract.
3. **Allowed duplication:** Mermaid diagrams and explanatory prose may repeat across RFC/ADR
   and `docs/api/` when cross-linked and labelled (*Target state* vs *As-built contract*).
   **Drift is forbidden** on deployed behaviour (paths, status badges, ownership) — not on
   teaching diagrams that answer different questions.

### Where a fact belongs: here, the service README, or the service AGENTS.md

Three documents describe every service, and they answer different questions. A
fact written in the wrong one is a fact that will drift, because only one of the
three is read when the behaviour changes.

| Document | Answers | Must not contain |
|----------|---------|------------------|
| **`docs/api/{service}.md`** (here) | What the service promises: routes, RPCs, payloads, errors, ownership, deployment status | Repo build commands, directory tours, decision essays |
| Service **`README.md`** | How a human starts and verifies it locally, and where the contract lives | A second endpoint table, payload or error inventory, env-var catalogue, call graph, or deployment claim |
| Service **`AGENTS.md`** | How to implement in that repo: workflow, verification commands, architecture boundaries, service-specific invariants | Any API inventory — routes, RPCs, payloads, or the cross-service call graph |

The rule that makes this stick: **a service repo links the canonical contract,
it never reproduces it.** When the two disagree, `docs/api/` wins and the service
doc is corrected — not the other way round.

Invariants are the deliberate exception. Money units, idempotency keys,
anti-IDOR scoping, fail-closed behaviour, FSM ownership, pooler-safe database
settings, shutdown order — these belong in the service `AGENTS.md` because they
are rules an implementer can violate at the keyboard, and they stay there even
though the contract also implies them.

### Resolving a mismatch

When this documentation and the evidence disagree, classify before editing.
Choosing whichever side is cheaper to change is how a contract quietly becomes a
description of whatever the code happens to do.

| Class | Signal | Resolution |
|-------|--------|------------|
| **Stale service doc** | The service `README`/`AGENTS` contradicts the canonical contract | Correct the service doc; do not copy canonical tables into the repo |
| **Canonical doc missed a shipped change** | Code, tests, local-stack and manifests agree with each other, and this page is behind | Update the owning `{service}.md` with that evidence; touch rollups or the call graph only if their owned facts changed |
| **Implementation violates the contract** | The behaviour is not what the contract intends, and the contract is right | **Blocks the release tag.** Record it, open a separate implementation task — never rewrite the contract to legitimise the defect |
| **Designed but not deployed** | Manifests and local-stack do not run it yet | Tag it `Planned`; never present it as current |

The third class is the one worth being strict about. It is also the one that
looks most like a documentation bug, because the fastest way to make the
mismatch disappear is to edit this page — which converts a known defect into an
accepted behaviour without anyone deciding to accept it.

Service **At a glance** tables use four columns: **Capability | Current shape |
Availability | Evidence**. Evidence links to the smallest stable proof: a
detailed contract section, homelab manifest, workflow registry, or code-map
path. Service **Identity** tables use **Attribute | Value**; normative design
links belong in the **Design records** value. Cross-cutting guides may use a
different quick-facts shape when per-attribute provenance is useful.

| Information | Canonical owner |
|-------------|-----------------|
| Shared URL, auth, error, pagination, idempotency, and gRPC rules | [api.md](./api.md) |
| Realms, token claims, `user_id`, and the `OIDC_*` verification contract | [identity.md](./identity.md) |
| Cross-cutting observability policy, env, middleware, layer responsibilities | [observability.md](./observability.md) |
| Application logging JSON contract, levels, otelzap tee | [logs.md](./logs.md) |
| Metric instruments, cardinality, business metric authoring | [metrics.md](./metrics.md) |
| Tracing spans, sampling, span helpers | [tracing.md](./tracing.md) |
| Profiling client (`obsx.SetupProfiling`, env) | [profiling.md](./profiling.md) |
| Cache-Aside pattern, keys, stampede lock, env, invalidation boundaries | [caching.md](./caching.md) |
| Graceful-shutdown contract: readiness drain, `SHUTDOWN_TIMEOUT`, cleanup order | [graceful-shutdown.md](./graceful-shutdown.md) |
| East-west call graph and edge exposure rules | [api.md](./api.md) |
| One service's routes, RPCs, payloads, and business constraints | That service's file (At a glance **Deployment** row for local/cluster) |
| Platform deployment rollup and availability vocabulary | This page § [Service contracts](#service-contracts) |
| Cross-service feature ownership | [microservices.md](./microservices.md) |
| Saga, 2PC theory, Temporal workflow, compensation, and operations | [temporal.md](./temporal.md) |
| Which `pkg` modules exist, how they are tagged, the import layering | [pkg.md](./pkg.md) |
| Which `pkg` modules a service imports and at which version | That service's own `go.mod` — never a document |
| Design rationale and alternatives | RFC or ADR |
| Deployed gateway, network, database, or observability backends/ops | The matching platform area under `docs/observability/` |
| Repository URLs, images, and CI badges | [docs/README.md § Repositories](../README.md#repositories) |

## Service Contracts

Per-service **At a glance** tables hold deployment detail; this rollup is the platform-wide view.

### Availability vocabulary

| Badge | Meaning |
|-------|---------|
| **Implemented** | Runs in local-stack + cluster; e2e or manifest evidence |
| **Partial** | Partly shipped (e.g. HTTP live, edge prefix divergence) |
| **Planned** | Designed, not deployed |
| **None** | The capability does not exist for this service — e.g. no gRPC client, no worker. A live but unused capability remains **Implemented**; record its missing caller under **Known gaps** |
| **Archived** | The former surface has been deliberately removed and is retained only as historical contract material |

`Technical debt`, `No caller`, and `Deprecated` describe a shipped capability,
not its availability. Record them under the service's **Known gaps** section.

### Platform rollup

| Component | Local | Cluster | Status | CI |
|-----------|:-----:|:-------:|--------|-----|
| [auth API](./auth.md) | — | — | **Archived** — RFC-0024 P5 executed: the whole surface is deleted; the realm is the only issuer. Contract kept as history | — (repo archived) |
| [user API](./user.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/user-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/user-service/actions) |
| [product API + gRPC](./product.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/product-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/product-service/actions) |
| [inventory gRPC](./inventory.md) | ✓ | ✓ | Implemented — the sole stock authority; callers: order saga, checkout, product /details | [![CI](https://github.com/duynhlab/inventory-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/inventory-service/actions) |
| [cart API + gRPC](./cart.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/cart-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/cart-service/actions) |
| [order API + gRPC](./order.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/order-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/order-service/actions) |
| [review API + gRPC](./review.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/review-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/review-service/actions) |
| [shipping API + gRPC](./shipping.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/shipping-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/shipping-service/actions) |
| [notification API + gRPC](./notification.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/notification-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/notification-service/actions) |
| [payment API + gRPC](./payments.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/payment-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/payment-service/actions) |
| [checkout API](./checkout.md) | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/checkout-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/checkout-service/actions) |
| order-worker | ✓ | ✓ | Implemented | — |
| checkout-worker | ✓ | ✓ | Implemented | — |
| mockpay provider | ✓ | ✓ | Implemented | — |
| frontend SPA | ✓ | ✓ | Implemented | [![CI](https://github.com/duynhlab/frontend/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/frontend/actions) |
| [Backoffice app service](./admin.md) | ✓ | ✓ | Implemented — React SPA served by Nginx; consumes six owning services and serves no business API | [![CI](https://github.com/duynhlab/admin-service/actions/workflows/build.yml/badge.svg)](https://github.com/duynhlab/admin-service/actions) |
| gRPC mTLS east-west | — | — | Planned | — |

| Service | One-line responsibility | Contract |
|---------|-------------------------|----------|
| Auth (**Archived** — Keycloak realm is the issuer) | Credentials, JWTs, refresh rotation, and JWKS — retired contract kept for learning | [auth.md](./auth.md) |
| User | Public and owner-scoped profiles | [user.md](./user.md) |
| Product | Catalog, price, and review aggregation (**no stock** since RFC-0021 phase 4) | [product.md](./product.md) |
| Inventory | Warehouse balances, reservations, and movement ledger — the **sole** stock authority, called by checkout, product `/details`, and the order saga | [inventory.md](./inventory.md) |
| Cart | Active cart and checkout snapshot | [cart.md](./cart.md) |
| Order | Orders and fulfillment workflow handoff | [order.md](./order.md) |
| Review | Product ratings and comments | [review.md](./review.md) |
| Notification | Inbox records and delivery requests | [notification.md](./notification.md) |
| Shipping | Quotes, tracking, and shipment lifecycle | [shipping.md](./shipping.md) |
| Checkout | Purchase sessions, totals, promo, and confirm | [checkout.md](./checkout.md) |
| Payment | Payment state, ledger, refunds, and reconciliation | [payments.md](./payments.md) |
| Backoffice | Operator SPA and client-side orchestration across six owning services; owns no business API or data | [admin.md](./admin.md) |

## Architecture and Workflow Guides

| Document | Covers | Current status |
|----------|--------|----------------|
| [api.md](./api.md) | HTTP and gRPC architecture, call graph, user journeys, HTTP/2 load balancing, security, observability | Implemented |
| [identity.md](./identity.md) | Two realms, edge vs in-service verification, `sub` as `user_id`, the `OIDC_*` env contract, browser flow | Implemented |
| [admin.md](./admin.md) | Backoffice application-service contract plus the 26 `/protected/` operations it consumes; no BFF or business API | Implemented |
| [microservices.md](./microservices.md) | Service feature matrix, ownership, dependencies, and known gaps | Living reference |
| [temporal.md](./temporal.md) | Saga vs 2PC learning plus the live order workflow and Temporal operations | Implemented |
| [checkout.md](./checkout.md) | Checkout FSM, price re-validation, totals, promo, confirm, and abandonment | Implemented — P1-P5 shipped; the legacy order path was removed in RFC-0021 P5 |
| [payments.md](./payments.md) | Money state machine, idempotency, ledger, provider, and reconciliation | Implemented |

## Related Areas

| Topic | Document |
|-------|----------|
| Edge routing and policy | [Envoy Gateway](../platform/envoy-gateway.md) |
| Identity provider deployment and ops | [Keycloak (platform)](../platform/keycloak.md) |
| NetworkPolicy caller matrix | [Network policies](../security/network-policies.md) |
| Application observability (normative contract) | [observability.md](./observability.md) · [logs](./logs.md) · [metrics](./metrics.md) · [tracing](./tracing.md) · [profiling](./profiling.md) |
| Metrics platform ops (alerts, dashboards) | [Application metrics (platform)](../observability/metrics/metrics-apps.md) |
| Valkey cache-aside behavior | [Application caching](./caching.md) · [Caching (platform)](../caching/README.md) |
| Shared Go library (packages, consumers, bump ledger) | [pkg.md](./pkg.md) |
| Local environment | [local-stack README](../../local-stack/README.md) |
| Repository index (images + CI) | [docs/README.md § Repositories](../README.md#repositories) |

## Updating This Area

| Change | Required documentation |
|--------|------------------------|
| Shared convention changes | Update [api.md](./api.md) |
| Realm, client, token-claim, or `OIDC_*` env changes | Update [identity.md](./identity.md); platform-side deployment changes go to [Keycloak (platform)](../platform/keycloak.md) |
| Shared observability / instrumentation changes | Update [observability.md](./observability.md) and the relevant pillar file |
| Cache-Aside contract, keys, stampede, or invalidation rules | Update [caching.md](./caching.md) |
| Service route, RPC, payload, or state changes | Update only the owning service file |
| Deployment or CI status changes | Update this rollup + the service At a glance table |
| East-west call graph or edge exposure changes | Update [api.md](./api.md) |
| Cross-service feature ownership changes | Update [microservices.md](./microservices.md) and the relevant service files |
| Saga step or compensation changes | Update [temporal.md](./temporal.md) |
| RFC `implemented` or ADR `Accepted` (API-touching) | Sync per [Document Ownership](#document-ownership); set **Design records** links; same PR or immediate follow-up — see [proposals lifecycle](../proposals/README.md) |
| At a glance or code map format | v2 template: `Capability \| Current shape \| Availability \| Evidence` rows include **Deployment**, **Runtime modes**, **HTTP server**, **Edge exposure**, **gRPC server/clients**, **Worker**, **Temporal**, and **Events** — see [_template-service.md](./_template-service.md) |
| New service contract file | Start from [_template-service.md](./_template-service.md) v2 — At a glance + Identity + 15-part outline |
| New file | Link it here and from [docs/README.md](../README.md) |
| A service `README.md` or `AGENTS.md` disagrees with a contract | Correct the service doc — see [Where a fact belongs](#where-a-fact-belongs-here-the-service-readme-or-the-service-agentsmd) |

Every substantive claim must match the service code, local-stack wiring, and
GitOps manifests — that evidence is how a claim is verified, not a competing
source to prefer. Mark designed but undeployed behavior as **planned**, and when
the two disagree, classify it first: [Resolving a mismatch](#resolving-a-mismatch).

_Last updated: 2026-08-26 — separates capability availability from known-gap lifecycle, adds per-capability evidence, and recognizes `admin-service` as the deployed Backoffice application service._
