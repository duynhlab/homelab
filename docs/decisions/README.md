# Architecture Decision Records (ADRs)

An **ADR** records a significant technical decision: the *context* that forced it, the *decision*
itself, the *alternatives* we rejected (and why), and the *consequences* we accepted. They capture
the **why** that code and manifests can't — so future engineers (and agents) don't re-litigate
settled decisions.

## Conventions

- One file per decision: `ADR-NNN-short-slug.md`, numbered sequentially.
- Format: **Status · Date · Context · Decision · Alternatives considered · Consequences** (Nygard style).
- **Lifecycle:** `Proposed → Accepted → (Superseded by ADR-XXX | Deprecated)`.
- **Append-only:** don't rewrite history. When a decision changes, write a new ADR that supersedes
  the old one and update the old one's Status.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-adopt-temporal-for-order-fulfillment.md) | Adopt Temporal for order fulfillment | Accepted |
| [ADR-002](ADR-002-deploy-temporal-via-operator.md) | Deploy Temporal via the alexandrevilain operator | Accepted |
| [ADR-003](ADR-003-jwt-validation-in-services-not-kong.md) | Keep JWT validation in services, not the Kong gateway | Accepted |
