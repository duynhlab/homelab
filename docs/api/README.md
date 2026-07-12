# API Documentation

The platform's API surface, in four layers: **where routes live** (naming
convention), **what they accept and return** (API reference), **who owns what**
(microservices catalog), and **how the subsystems behind them work**
(payments, gRPC east-west, the Temporal saga).

## Start here — the three core docs and how they differ

| Question | Doc | Status |
|---|---|---|
| *What is the URL?* — shape, audiences, the complete route inventory | [**api-naming-convention.md**](api-naming-convention.md) | v2.0.0 **Adopted** — the sole URL surface |
| *What does the endpoint take/return?* — payloads, validation, error codes | [**api.md**](api.md) | Living reference |
| *Which service builds what, with which technique?* — per-service feature matrix (feature → API → technique), data ownership, call graph | [**microservices.md**](microservices.md) | Living reference |

One rule keeps them from overlapping: **routes are documented once** (in the
naming convention), payloads once (in the API reference), ownership once (in
the catalog). If a doc needs one of the others, it links — it does not restate.

## Subsystem deep-dives

| Doc | Covers | Status |
|---|---|---|
| [grpc-internal-comms.md](grpc-internal-comms.md) | East-west transport: gRPC-only on `:9090`, dual-port, HTTP/2 LB pitfall, observability, security | **Implemented** |
| [payments.md](payments.md) | Payment subsystem: design record (RFC-0010 + ADRs), checkout read path, reconciliation | **Implemented** |
| [checkout.md](checkout.md) | Checkout subsystem: session FSM, price re-validation, order handoff (RFC-0015 + ADR-020/021) | **P1 implemented** |
| [temporal-order-fulfillment.md](temporal-order-fulfillment.md) | The durable order-fulfillment saga on Temporal: design, contracts, infra, ops | **Implemented** |
| [saga-vs-2pc.md](saga-vs-2pc.md) | Theory: why 2PC doesn't fit microservices and how the saga gets consistency | Learning |

## Related, but lives elsewhere

| Topic | Where | Why there |
|---|---|---|
| App-side logging conventions | [observability → logging-standards.md](../observability/logging/logging-standards.md) | Logging is an observability concern |
| Graceful shutdown pattern | [platform → graceful-shutdown.md](../platform/graceful-shutdown.md) | Cross-cutting service-lifecycle pattern |
| GKE / Cloud DNS internals | [platform → gke-internal-dns.md](../platform/gke-internal-dns.md) | Cluster networking, not API surface |
| Seed data & demo accounts | [platform → setup.md](../platform/setup.md#seed-data--demo-accounts) | Local-dev fixture, not an API contract |
| RED metrics & instrumentation | [observability → metrics-apps.md](../observability/metrics/metrics-apps.md) | Metrics pillar owns it |

## Conventions for this area

- **Adding/changing a route?** Update the
  [route inventory](api-naming-convention.md#complete-route-inventory) first
  (it is the contract), then the payload spec in [api.md](api.md).
- **New subsystem doc?** One `docs/api/<subsystem>.md` with design-record
  links at the top — [payments.md](payments.md) is the shape to copy. No new
  subdirectories for a single doc.
- Every doc carries a status table (or status line) up top and an italic
  `_Last updated:_` footer.

---

_Last updated: 2026-07-10 — microservices.md rebuilt as a per-service feature matrix (+ technique index)._
