# Work reconciliation — 2026-11-01

This historical snapshot reconciles proposal metadata and GitHub work items. Use
[Platform work](https://github.com/orgs/duynhlab/projects/1) for the live queue and
[the tracking procedure](../platform/work-tracking.md) for updates.

| Quick facts | |
|---|---|
| **Page type** | Reference |
| **Repository baseline** | `ca736829` (main, 2026-11-01) |
| **Coverage** | 33 RFC directories, 90 ADR records, all 73 homelab issues returned across open/closed pages, and 16 open homelab PRs |
| **Original open issues** | 12 total: 11 work items and Renovate Dashboard #201 |
| **Evidence boundary** | Metadata, GitHub state, and recorded gate evidence; no new runtime audit |
| **Result** | 17 stale ADR index adoption entries aligned with their existing records |

## Findings and dispositions

| Finding | Evidence | Disposition |
|---|---|---|
| Index adoption lagged the record | ADR-041–045, 048–050, 053, 056, 070–076 | Align index with the existing Complete evidence; no new adoption claim |
| ADR-089 prose listed closed work | #1304 and #1305 closed; native tracker #1283 had 9/11 sub-issues closed | Link live sub-issues; retain #1296 and #1306 |
| Telemetry findings were one flat checklist | #1388 contained F01–F17 with no native children | Create one verifiable acceptance task per finding; preserve original evidence and priority |
| Audit holds were historical | Eight of nine PRs in #1262 held list merged 2026-10-29; #1410 remained open | Preserve audit rounds; separate current queue and three untracked follow-ups |
| Old incomplete records had no actionable tracker | ADR-038 and ADR-055 | Reconcile middleware evidence; retain the KEDA final deletion check as Verification |
| Design acceptance and scheduling were mixed | RFC-0033 accepted, ADR-079–082 not started, ADR-083 partial | Track gated phases without approving broader agent authority |
| Proposed work had no visible queue | RFC-0004/0006/0008/0011/0020 and RFC-0034 research | Capture review/revisit work; do not authorize implementation |
| Historical completion does not cover all deferred work | RFC-0005/0014/0017/0021/0022/0028 contain lifecycle or follow-up questions | [#1505](https://github.com/duynhlab/homelab/issues/1505) owns evidence reconciliation before new implementation commitments |
| Open implementation PRs were outside an issue queue | #1343–1347 VMRule migration, #1244 ADR template, #954 CI/CD guidance | Add existing PRs to the Project; preserve their original review and rollout gates |

## Project migration evidence

The live Project was read back after import on 2026-11-01:

- 8 views; the Doing board uses Status columns.
- 68 items: 47 open issues, 11 previously closed issues, and 10 open PRs.
- 36 issues extracted from recorded obligations; 11 existing open work issues standardized.
- Native children: telemetry #1388 has 17, dependency audit #1262 has 3, and agent initiative #1501 has 5.
- Four native blocked-by relationships enforce the RFC-0033 phase sequence.
- The pre-existing closed `pkg#124` appeared through native sub-issue auto-add beneath #1338; its history was preserved.
- No issue was closed and no design was accepted by this migration.

Status distribution: 25 Needs triage, 18 Waiting, 6 Backlog, 4 Ready,
3 Review, 1 Verification, and 11 Done. This is a dated snapshot, not a live count.

The Project retains private visibility. Built-in automation adds sub-issues and
reflects issue closure. PR merge/link and reverse auto-close workflows are absent;
a merged change cannot silently complete a missing runtime gate.

## Record inventory

Every live RFC/ADR directory appears below; template directories are excluded.
RFC-0016 is a retired reserved number and has no directory. Complete means the
record already reports completion; it is not a fresh verification by this audit.
Legacy ADRs without an Adoption field use the index, as the ADR process permits.
Withdrawn and superseded records do not become new implementation obligations.

### RFC records

| Record | Decision/status | Adoption | Work item / disposition |
|---|---|---|---|
| [RFC-0001](rfc/RFC-0001/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0002](rfc/RFC-0002/README.md) | superseded | — | Historical / replaced |
| [RFC-0003](rfc/RFC-0003/README.md) | superseded | — | Historical / replaced |
| [RFC-0004](rfc/RFC-0004/README.md) | provisional | — | [#1496](https://github.com/duynhlab/homelab/issues/1496) |
| [RFC-0005](rfc/RFC-0005/README.md) | provisional | — | [#1505](https://github.com/duynhlab/homelab/issues/1505) |
| [RFC-0006](rfc/RFC-0006/README.md) | provisional | — | [#1497](https://github.com/duynhlab/homelab/issues/1497) |
| [RFC-0007](rfc/RFC-0007/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0008](rfc/RFC-0008/README.md) | accepted | — | [#1498](https://github.com/duynhlab/homelab/issues/1498) |
| [RFC-0009](rfc/RFC-0009/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0010](rfc/RFC-0010/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0011](rfc/RFC-0011/README.md) | provisional | — | [#1499](https://github.com/duynhlab/homelab/issues/1499) |
| [RFC-0012](rfc/RFC-0012/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0013](rfc/RFC-0013/README.md) | superseded | — | Historical / replaced |
| [RFC-0014](rfc/RFC-0014/README.md) | implemented | — | [#1505](https://github.com/duynhlab/homelab/issues/1505) |
| [RFC-0015](rfc/RFC-0015/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0017](rfc/RFC-0017/README.md) | implemented | — | [#1505](https://github.com/duynhlab/homelab/issues/1505) |
| [RFC-0018](rfc/RFC-0018/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0019](rfc/RFC-0019/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0020](rfc/RFC-0020/README.md) | provisional | — | [#1500](https://github.com/duynhlab/homelab/issues/1500) |
| [RFC-0021](rfc/RFC-0021/README.md) | implemented | — | [#1505](https://github.com/duynhlab/homelab/issues/1505) |
| [RFC-0022](rfc/RFC-0022/README.md) | accepted | — | [#1505](https://github.com/duynhlab/homelab/issues/1505) |
| [RFC-0023](rfc/RFC-0023/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0024](rfc/RFC-0024/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0025](rfc/RFC-0025/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0026](rfc/RFC-0026/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0027](rfc/RFC-0027/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0028](rfc/RFC-0028/README.md) | accepted | — | [#1505](https://github.com/duynhlab/homelab/issues/1505) |
| [RFC-0029](rfc/RFC-0029/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0030](rfc/RFC-0030/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0031](rfc/RFC-0031/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0032](rfc/RFC-0032/README.md) | implemented | — | Recorded delivery; no new task inferred |
| [RFC-0033](rfc/RFC-0033/README.md) | accepted | — | [#1501](https://github.com/duynhlab/homelab/issues/1501) |
| [RFC-0034](rfc/RFC-0034/research.md) | researching | — | [#1502](https://github.com/duynhlab/homelab/issues/1502) |

### ADR records

| Record | Decision/status | Adoption | Work item / disposition |
|---|---|---|---|
| [ADR-001](adr/ADR-001-adopt-temporal-for-order-fulfillment/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-002](adr/ADR-002-deploy-temporal-via-operator/README.md) | superseded | complete | Historical / replaced |
| [ADR-003](adr/ADR-003-jwt-validation-in-services-not-kong/README.md) | superseded | complete | Historical / replaced |
| [ADR-004](adr/ADR-004-enable-openbao-audit-logging/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-005](adr/ADR-005-openbao-ha-raft/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-006](adr/ADR-006-rs256-jwt-kong-edge-auth/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-007](adr/ADR-007-double-entry-payment-ledger/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-008](adr/ADR-008-mockpay-standalone-provider/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-009](adr/ADR-009-saga-authorize-early-capture-late/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-010](adr/ADR-010-shared-idempotency-library/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-011](adr/ADR-011-detect-only-reconciliation/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-012](adr/ADR-012-reconciliation-auto-heal/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-013](adr/ADR-013-per-service-db-triplet/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-014](adr/ADR-014-pooler-credentials-valuesfrom/README.md) | superseded | complete | Historical / replaced |
| [ADR-015](adr/ADR-015-pg-hba-connection-isolation/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-016](adr/ADR-016-otel-metrics-cutover/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-017](adr/ADR-017-api-path-collection-noun/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-018](adr/ADR-018-checkout-order-boundary/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-019](adr/ADR-019-session-expiry-model/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-020](adr/ADR-020-checkout-revalidation-policy/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-021](adr/ADR-021-cart-grpc-read-surface/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-022](adr/ADR-022-atomic-promo-redemption/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-023](adr/ADR-023-clickhouse-observability-olap/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-024](adr/ADR-024-floci-kms-emulator-auto-unseal/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-025](adr/ADR-025-pgdog-passthrough-dynamic-db-creds/README.md) | proposed | partial | [#1498](https://github.com/duynhlab/homelab/issues/1498) |
| [ADR-026](adr/ADR-026-platform-db-pgbouncer-pilot/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-027](adr/ADR-027-inventory-sole-stock-authority/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-028](adr/ADR-028-inventory-reservation-model/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-029](adr/ADR-029-enum-feature-flag-helper/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-030](adr/ADR-030-temporal-workflow-versioning/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-031](adr/ADR-031-fulfillment-start-outbox/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-032](adr/ADR-032-tempo-operator-monolithic/README.md) | withdrawn | not started | Historical / replaced |
| [ADR-033](adr/ADR-033-order-status-cancellation/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-034](adr/ADR-034-provider-outcome-ambiguity/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-035](adr/ADR-035-windowed-reconciliation/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-036](adr/ADR-036-single-writer-lease/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-037](adr/ADR-037-per-request-refund-identity/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-038](adr/ADR-038-shared-http-middleware/README.md) | accepted | partial | [#1503](https://github.com/duynhlab/homelab/issues/1503) |
| [ADR-039](adr/ADR-039-local-stack-temporal-server-postgres/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-040](adr/ADR-040-tempo-community-helm-chart/README.md) | withdrawn | partial | Historical / replaced |
| [ADR-041](adr/ADR-041-keycloak-platform-idp/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-042](adr/ADR-042-oidc-sub-as-user-id/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-043](adr/ADR-043-oidc-browser-workload-trust/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-044](adr/ADR-044-envoy-gateway-platform-edge/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-045](adr/ADR-045-local-first-edge-rate-limiting/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-046](adr/ADR-046-e2e-gate-kind-fallback/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-047](adr/ADR-047-protected-apis-on-owning-services/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-048](adr/ADR-048-admin-portal-no-bff/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-049](adr/ADR-049-admin-portal-tanstack-spa/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-050](adr/ADR-050-separate-staff-identity-realm/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-051](adr/ADR-051-trusted-operator-resolution/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-052](adr/ADR-052-converge-the-customer-spa-on-the-portal-stack/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-053](adr/ADR-053-untracked-sku-operator-data-not-outage/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-054](adr/ADR-054-temporal-worker-controller/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-055](adr/ADR-055-keda-worker-autoscaling/README.md) | accepted | partial | [#1504](https://github.com/duynhlab/homelab/issues/1504) |
| [ADR-056](adr/ADR-056-k6-e2e-assertion-layer/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-057](adr/ADR-057-span-metrics-in-collector/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-058](adr/ADR-058-retire-jaeger/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-059](adr/ADR-059-retire-tempo/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-060](adr/ADR-060-envoy-access-log-transport/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-061](adr/ADR-061-edge-log-routing/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-062](adr/ADR-062-staff-groups-sso/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-063](adr/ADR-063-temporal-otel-v2/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-064](adr/ADR-064-all-workers-under-controller/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-065](adr/ADR-065-clickhouse-replicated-topology/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-066](adr/ADR-066-adopt-peerdb-for-commerce-cdc/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-067](adr/ADR-067-constrain-commerce-cdc-source-allowlist/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-068](adr/ADR-068-schedule-cdc-heartbeats-with-pg-cron/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-069](adr/ADR-069-serve-commerce-analytics-through-read-only-service/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-070](adr/ADR-070-logging-facade-and-event-catalog/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-071](adr/ADR-071-telemetry-event-data-contract/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-072](adr/ADR-072-telemetry-clean-cutover/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-073](adr/ADR-073-application-metrics-contract/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-074](adr/ADR-074-continuous-profiling-contract/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-075](adr/ADR-075-application-tracing-contract/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-076](adr/ADR-076-semantic-convention-registry/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-077](adr/ADR-077-image-volume-schema-delivery/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-078](adr/ADR-078-migrate-kyverno-policies-to-cel-types/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-079](adr/ADR-079-version-agent-task-contracts/README.md) | accepted | not started | [#1501](https://github.com/duynhlab/homelab/issues/1501) |
| [ADR-080](adr/ADR-080-tokenless-agent-workers/README.md) | accepted | not started | [#1501](https://github.com/duynhlab/homelab/issues/1501) |
| [ADR-081](adr/ADR-081-agent-leases-and-reconciliation/README.md) | accepted | not started | [#1501](https://github.com/duynhlab/homelab/issues/1501) |
| [ADR-082](adr/ADR-082-agent-evaluation-gates/README.md) | accepted | not started | [#1501](https://github.com/duynhlab/homelab/issues/1501) |
| [ADR-083](adr/ADR-083-documentation-steward/README.md) | accepted | partial | [#1501](https://github.com/duynhlab/homelab/issues/1501) |
| [ADR-084](adr/ADR-084-split-service-database-roles/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-085](adr/ADR-085-service-migrations-own-authorization/README.md) | superseded | partial | Historical / replaced |
| [ADR-086](adr/ADR-086-guard-membership-options/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-087](adr/ADR-087-homelab-private-and-web-access/README.md) | proposed | not started | [#1499](https://github.com/duynhlab/homelab/issues/1499) |
| [ADR-088](adr/ADR-088-platform-owns-database-authorization/README.md) | accepted | complete | Recorded delivery; no new task inferred |
| [ADR-089](adr/ADR-089-postgresql-access-contract/README.md) | accepted | partial | [#1283](https://github.com/duynhlab/homelab/issues/1283) |
| [ADR-090](adr/ADR-090-homelab-docs-skill/README.md) | accepted | complete | Recorded delivery; no new task inferred |

## Initial issue migration

| Issue | Disposition |
|---|---|
| [#1388](https://github.com/duynhlab/homelab/issues/1388) | Telemetry initiative; native children own F01–F17 progress |
| [#1283](https://github.com/duynhlab/homelab/issues/1283) | Independent ADR-089 tracker; preserve its native children and history |
| [#1262](https://github.com/duynhlab/homelab/issues/1262) | Audit history with a current queue and follow-up children |
| [#1210](https://github.com/duynhlab/homelab/issues/1210) | Waiting for a real trace-query consumer |
| [#1296](https://github.com/duynhlab/homelab/issues/1296) | Waiting; retain the recorded deferred direct-client scope |
| [#1306](https://github.com/duynhlab/homelab/issues/1306), [#1299](https://github.com/duynhlab/homelab/issues/1299), [#1404](https://github.com/duynhlab/homelab/issues/1404), [#1446](https://github.com/duynhlab/homelab/issues/1446) | Ready for the next selected bounded task; no implementation performed here |
| [#1460](https://github.com/duynhlab/homelab/issues/1460) | Retained security work in Backlog |
| [#1209](https://github.com/duynhlab/homelab/issues/1209) | Needs triage against current mockpay and gate behavior |
| [#201](https://github.com/duynhlab/homelab/issues/201) | Renovate owns this dashboard; exclude it from the actionable Project queue |

## Reproduce the metadata inventory

```bash
python3 scripts/proposal-status.py --json
make proposals-check
```

The checker reads local record headers and indexes. GitHub evidence was gathered
with paginated `gh api` issue queries, native sub-issue queries, and PR state queries.
Rerunning the local checker does not refresh this dated GitHub snapshot.

## Remaining uncertainty

- Proposed records require owner design decisions before implementation.
- Audit findings require current source/pin reconciliation; old failures are not assumed to persist.
- Optional RFC alternatives and unchecked historical examples are not automatically new commitments.
- The org-wide open-issue search found two unrelated tasks in `sshresume` and `packages`; neither was imported into this platform queue.
- ADR-038 and the historical RFC closure questions remain explicit tasks; no unverified record was marked Complete.
