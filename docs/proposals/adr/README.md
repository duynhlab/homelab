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
- **Lifecycle:** `Proposed → Accepted → (Superseded by ADR-XXX | Deprecated)`.
- **Append-only:** don't rewrite history. When a decision changes, write a new ADR that supersedes
  the old one and update the old one's Status.

## Index

| ADR | Title | Status | Related RFC |
|-----|-------|--------|-------------|
| [ADR-001](ADR-001-adopt-temporal-for-order-fulfillment/) | Adopt Temporal for order fulfillment | Accepted | [RFC-0001](../rfc/RFC-0001/) |
| [ADR-002](ADR-002-deploy-temporal-via-operator/) | Deploy Temporal via the alexandrevilain operator | Accepted | [RFC-0001](../rfc/RFC-0001/) |
| [ADR-003](ADR-003-jwt-validation-in-services-not-kong/) | Keep JWT validation in services, not the Kong gateway | Accepted | — |
