# {Service} Service API

<!--
Template for every service contract in docs/api/. Copy, fill, delete the
comments. Keep the section order exactly as below (15 parts). Depth bar:
checkout.md — target 250–350 lines. English only, Mermaid only (AGENTS.md
palette). Status vocabulary: Implemented / Partial / Technical debt /
No caller / Planned / None — defined in README.md § Service Contracts.
CI badges live in hub rollup + docs/README.md § Repositories, not here.
-->

{One-line hook: what this service turns into what.}

<!-- Part 2 — Table 1: At a glance (deployment & transport). Same rows on
     every service doc, short cells; details belong in body sections. -->

| Dimension | Value | Status |
|-----------|-------|--------|
| **Deployment** | local-stack + cluster | Implemented |
| **HTTP** | {audiences} · `:8080` · Kong `/{service}/v1/{audience}/` | Implemented |
| **gRPC server** | None <!-- or `Svc/RPC` · `:9090` --> | None |
| **gRPC client** | None <!-- or list of callees --> | None |
| **Worker** | None <!-- or `{service}-worker` · queue `{queue}` --> | None |
| **Temporal** | None · [workflows.md](./workflows.md) <!-- or Orchestrator/Participant + link --> | None |
| **Technical debt** | None <!-- or short item · [Known gaps](#known-gaps) --> | None |

<!-- Part 3 — Table 2: Identity (stable metadata, does not change per phase). -->

| | |
|---|---|
| **Repository** | [`duynhlab/{service}-service`](https://github.com/duynhlab/{service}-service) |
| **Owns** | {data this service is the source of truth for} |
| **Database** | `{db}` on `platform-db` |
| **Design record** | [RFC-NNNN](../proposals/rfc/RFC-NNNN/) <!-- omit row if none --> |

## Temporal participation

<!-- Part 4 — pick ONE of the three shapes:
None (max 3 lines):
    None — this service does not start or participate in Temporal workflows.
    See [workflows.md](./workflows.md).
Participant / Orchestrator: field table like below. -->

| Field | Value |
|-------|-------|
| **Role** | Participant (gRPC) |
| **Workflow** | `OrderFulfillmentWorkflow` (owned by order) |
| **This service's steps** | `{Activity}`, `{Compensation}` (compensation) |
| **Idempotency** | {key} |
| **Deep dive** | [workflows.md](./workflows.md#order-fulfillment) · [temporal-order-fulfillment.md](./temporal-order-fulfillment.md) |

## Why it exists

<!-- Part 5 — problem → solution, a few short paragraphs. -->

## Architecture

<!-- Part 6 — one Mermaid diagram, AGENTS.md palette, answer ONE question. -->

## Data model

<!-- Part 7 — tables, constraints, money units. -->

## HTTP API

<!-- Part 8 — full canonical paths (/{service}/v1/{audience}/...), JSON
     request/response examples, error matrix. -->

## gRPC API

<!-- Part 9 — RPC table with a Saga column: — | step | compensation.
     If no gRPC server: one line "None — HTTP only." -->

| RPC | Request → Response | Saga | Notes |
|-----|--------------------|------|-------|

## Business rules & techniques

<!-- Part 10 — invariants, FSMs, idempotency, caching strategy. -->

## Callers & dependencies

<!-- Part 11 — who calls this service, what this service calls (moved out of
     the old header's Callers prose). -->

## Known gaps

<!-- Part 12 — technical debt, no-caller routes, planned removals. "None." if
     empty. -->

## Operations

<!-- Part 13 — env vars, probes, key metrics, curl/grpcurl examples via Kong. -->

## Code map

<!-- Part 14 — verify paths against the actual service repo. -->

Paths in [`duynhlab/{service}-service`](https://github.com/duynhlab/{service}-service).
Transport peers call `logic/v1`; logic calls `core` only
([api.md § Inside Each Service](./api.md#inside-each-service)).

| Layer | Path | Notes |
|-------|------|-------|
| **Transport** | `internal/web/v1/` | HTTP handlers |
| | `internal/grpc/v1/` | gRPC server (if any) |
| **logic** | `internal/logic/v1/` | Business rules |
| **core** | `internal/core/` | Domain, repositories, ports |
| **Platform** | `cmd/main.go`, `config/`, `db/migrations/`, `pkg/proto/` | Bootstrap, schema, contract |

## References

<!-- Part 15 — api.md, workflows.md, RFC/ADRs, runbooks. -->

_Last updated: YYYY-MM-DD_
