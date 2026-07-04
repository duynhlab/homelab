# Payments

The payment subsystem: a Stripe-style payment service (auth/capture state
machine, idempotency, double-entry ledger, mock provider) wired into the order
fulfillment saga. The *design* lives in [RFC-0010](../proposals/rfc/RFC-0010/)
and its ADRs; this area holds the operational docs.

| Doc | What it covers |
|-----|----------------|
| [Reconciliation](../api/reconciliation.md) | Detecting payment↔provider drift: classes, equivalence rules, the internal API, e2e evidence, v1 limits (lives in the API docs area) |

## Design record

- [RFC-0010: Payment service](../proposals/rfc/RFC-0010/) — the full design
- [ADR-007](../proposals/adr/ADR-007-double-entry-payment-ledger/) — append-only double-entry ledger
- [ADR-008](../proposals/adr/ADR-008-mockpay-standalone-provider/) — mockpay as a standalone process
- [ADR-009](../proposals/adr/ADR-009-saga-authorize-early-capture-late/) — authorize-early / capture-late in the order saga
- [ADR-010](../proposals/adr/ADR-010-shared-idempotency-library/) — shared `pkg/idempotency`
- [ADR-011](../proposals/adr/ADR-011-detect-only-reconciliation/) — detect-only reconciliation

---

_Last updated: 2026-07-04_
