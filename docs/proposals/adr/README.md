# Architecture Decision Records (ADRs)

An **ADR** records a significant technical decision: the *context* that forced it, the *decision*
itself, the *alternatives* we rejected (and why), and the *consequences* we accepted. They capture
the **why** that code and manifests can't — so future engineers (and agents) don't re-litigate
settled decisions.

> **ADR vs RFC vs research:** an [RFC](../rfc/) *proposes* a substantial change after
> [`research.md`](../rfc/RFC-0000/research.md) exploration; an ADR *records* the decision
> it produced. Link **Related research** for mechanism background — do not re-copy the
> deep dive in **Context**. An accepted RFC typically spawns one or more ADRs.

## Conventions

- One folder per decision: `ADR-NNN-short-slug/README.md` (mirrors the RFC layout —
  keep any per-ADR diagrams/assets inside the folder), numbered sequentially. Start
  from [`ADR-0000-template/`](ADR-0000-template/).
- Format (Nygard style): `| Status | Date | Related RFC | Related research |` metadata
  table at the top, then **Context · Decision · Alternatives considered · Consequences**.
  Related research = `RFC-NNNN/research.md` when the RFC had a research phase, or `—`.
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
| [ADR-011](ADR-011-detect-only-reconciliation/) | Ship reconciliation detect-only; defer auto-heal | Accepted (heal for one class added by [ADR-012](ADR-012-reconciliation-auto-heal/)) | [RFC-0010](../rfc/RFC-0010/) |
| [ADR-012](ADR-012-reconciliation-auto-heal/) | Auto-heal one reconciliation class — the lost-capture-response window | Accepted | [RFC-0010](../rfc/RFC-0010/) |
| [ADR-013](ADR-013-per-service-db-triplet/) | Per-service database triplet (ExternalSecret + DatabaseRole + Database) on cnpg-db | Accepted | [RFC-0012](../rfc/RFC-0012/) |
| [ADR-014](ADR-014-pooler-credentials-valuesfrom/) | PgDog pooler credentials via Flux valuesFrom targetPath | Accepted | [RFC-0012](../rfc/RFC-0012/) |
| [ADR-015](ADR-015-pg-hba-connection-isolation/) | Database connection isolation via declarative pg_hba | Accepted | [RFC-0012](../rfc/RFC-0012/) |
| [ADR-016](ADR-016-otel-metrics-cutover/) | Metrics cutover to the OTLP push pipeline | Accepted | [RFC-0014](../rfc/RFC-0014/) |
| [ADR-017](ADR-017-api-path-collection-noun/) | Collection-noun segment after the audience in every API path | Accepted | — |
| [ADR-018](ADR-018-checkout-order-boundary/) | Order stays the only orders-writer; checkout hands off via CreateOrder gRPC | Accepted | [RFC-0015](../rfc/RFC-0015/) |
| [ADR-019](ADR-019-session-expiry-model/) | Session expiry = durable timer (wake-up) + lazy backstop (authority) | Accepted | [RFC-0015](../rfc/RFC-0015/) |
| [ADR-020](ADR-020-checkout-revalidation-policy/) | Product is the checkout price authority; stock checked, never reserved | Accepted | [RFC-0015](../rfc/RFC-0015/) |
| [ADR-021](ADR-021-cart-grpc-read-surface/) | Cart gains a read-only gRPC surface; writes stay on REST | Accepted | [RFC-0015](../rfc/RFC-0015/) |
| [ADR-022](ADR-022-atomic-promo-redemption/) | Promo redemptions count atomically at confirm, before the attempt marker | Accepted | [RFC-0015](../rfc/RFC-0015/) |
| [ADR-023](ADR-023-clickhouse-observability-olap/) | Adopt ClickHouse as supplementary OLAP for OTel logs+traces SQL (Altinity, PVC, 90d, alongside) | Accepted | [RFC-0019](../rfc/RFC-0019/) |

---
_Last updated: 2026-07-19_
