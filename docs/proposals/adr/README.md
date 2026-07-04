# Architecture Decision Records (ADRs)

An **ADR** records a significant technical decision: the *context* that forced it, the *decision*
itself, the *alternatives* we rejected (and why), and the *consequences* we accepted. They capture
the **why** that code and manifests can't — so future engineers (and agents) don't re-litigate
settled decisions.

> **ADR vs RFC:** an [RFC](../rfc/) *proposes* a substantial change (discussed before
> building); an ADR *records* the decision it produced. An accepted RFC typically spawns
> one or more ADRs.

## Conventions

- One folder per decision: `ADR-NNN-short-slug/README.md` (mirrors the RFC layout —
  keep any per-ADR diagrams/assets inside the folder), numbered sequentially. Start
  from [`ADR-0000-template/`](ADR-0000-template/).
- Format (Nygard style): a `| Status | Date | Related RFC |` metadata table at the top
  (Related RFC = the RFC that spawned it, or `—`), then **Context · Decision ·
  Alternatives considered · Consequences**.
- **Every decision is a tradeoff** — always record the rejected *Alternatives* (and why) and the *Consequences* you accept (the bad as well as the good). A decision with no downside listed hasn't been examined hard enough.
- **Lifecycle:** `Proposed → Accepted → (Superseded by ADR-XXX | Deprecated)`.
- **Append-only:** don't rewrite history. When a decision changes, write a new ADR that supersedes
  the old one and update the old one's Status.

## Index

| ADR | Title | Status | Related RFC |
|-----|-------|--------|-------------|
| [ADR-001](ADR-001-adopt-temporal-for-order-fulfillment/) | Adopt Temporal for order fulfillment | Accepted | [RFC-0001](../rfc/RFC-0001/) |
| [ADR-002](ADR-002-deploy-temporal-via-operator/) | Deploy Temporal via the alexandrevilain operator | Accepted | [RFC-0001](../rfc/RFC-0001/) |
| [ADR-003](ADR-003-jwt-validation-in-services-not-kong/) | Keep JWT validation in services, not the Kong gateway | Superseded by [ADR-006](ADR-006-rs256-jwt-kong-edge-auth/) | — |
| [ADR-004](ADR-004-enable-openbao-audit-logging/) | Enable OpenBAO audit logging | Accepted | — |
| [ADR-005](ADR-005-openbao-ha-raft/) | Run OpenBAO HA (Raft) instead of Vault dev mode | Accepted | — |
| [ADR-006](ADR-006-rs256-jwt-kong-edge-auth/) | Adopt RS256 signed JWTs + Kong edge authentication | Accepted | [RFC-0009](../rfc/RFC-0009/) |
| [ADR-007](ADR-007-double-entry-payment-ledger/) | Record money movement in an append-only double-entry ledger | Accepted | [RFC-0010](../rfc/RFC-0010/) |
| [ADR-008](ADR-008-mockpay-standalone-provider/) | Run the mock payment provider as a standalone process | Accepted | [RFC-0010](../rfc/RFC-0010/) |
| [ADR-009](ADR-009-saga-authorize-early-capture-late/) | Authorize payment early, capture late in the order saga | Accepted | [RFC-0010](../rfc/RFC-0010/) |
| [ADR-010](ADR-010-shared-idempotency-library/) | Extract idempotency into a shared pkg/idempotency library | Accepted | [RFC-0010](../rfc/RFC-0010/) |
