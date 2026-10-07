# Database Platform Documentation Review

Review findings connect documentation corrections to evidence and keep infrastructure follow-ups separate from implemented changes.

| Item | Review boundary |
|---|---|
| **Date / baseline** | 2026-10-06, main `d421daf3` |
| **Scope** | Database platform guides, references and runbooks; fundamentals preserved |
| **Sources** | Repository manifests, existing drill records, official CNPG 1.30 and PostgreSQL 18 documentation |
| **Verification** | Static documentation review; no new cluster drill or live sizing measurement |

## Findings and disposition

Priority means documentation or operational impact, not a measured incident severity.

| Priority | Finding and evidence | Documentation disposition | Infrastructure follow-up |
|---|---|---|---|
| High | Add-database and password-rotation runbooks reused the bootstrap Job/root token; the bootstrap manifest explicitly revokes root and exits on subsequent runs | Route day-2 writes to the existing secrets runbook, remove password-bearing diagnostic DSNs, cover all six product services and worker consumers | Execute rotations only through the authorized credential workflow; no rotation performed by this review |
| High | Hub/control-plane/extension pages said CNPG 1.30.0 and PostgreSQL 18.1; operator and all three operand manifests pin 1.30.1 / 18.6 | Correct current inventory; preserve dated historical observations | None: the upgrade already landed |
| High | `reliability-targets.md` described ≤5 min DR RPO as as-built, although archive/replay delay and failures are not bounded by `archive_timeout` | Separate objectives, configuration and August drill evidence | Measure loss and full client recovery in representative DR and unplanned-failover drills |
| High | `ANY 1` commit acknowledgment was treated as a blanket failover guarantee; manifests do not enable `failoverQuorum` | Explain surviving-WAL/candidate conditions and distinguish Lease from fencing | Evaluate promotion-safety policy and partition scenarios in a separate design/change |
| High | Operational `instance.yaml` files combine 10Gi PVCs and 8GB `max_wal_size`, plus 1Gi memory limits, 32MB `work_mem` and 200 connections | Add capacity model and diagnostic checks; do not call settings production sizing | Measure disk/WAL growth, active query concurrency and maintenance overlap; then propose budgets |
| Medium | Operator comparison denied in-place major upgrades | Correct CNPG capability; add outage, extension and rollback boundaries | No major upgrade selected or scheduled |
| Medium | Maintenance coverage was spread across DR/pooler drills without a lifecycle entry point | Add maintenance/upgrades runbook and task index | Rehearse chosen operations before relying on their timings |
| Medium | Transport and SQL authorization could be conflated; HBA `host` is not TLS enforcement, and payment's `require` is unverified TLS | Add security/access guide linked to RFC-0020 and the planned RFC-0029 authorization guide | Continue the existing transport and authorization workstreams; neither is implemented by this review |
| Medium | Declarative role guide implied file ordering made reconciliation deterministic and said never to edit the cluster file despite required HBA changes | Clarify asynchronous reconciliation and the HBA exception; identify the four-role example as historical | Use the current Kind isolation gate for the full service inventory |

## How to use the review

The [database hub](../README.md) owns navigation; the linked topic guides own
current explanations. This is a dated review record, not a second inventory.
Before implementing any infrastructure follow-up, inspect then-current manifests
and collect the missing runtime evidence. Update the owning guide with the
result and link the new change/drill record rather than rewriting historical
measurements as though they ran on today's versions.

## Validation evidence

- `make validate`: passed (464 YAML files, app manifests, Kustomize overlays,
  Kyverno suites and repository invariant checks).
- All 45 Mermaid blocks in the database area, including unchanged fundamentals
  and historical reference diagrams: rendered successfully; reviewed as a
  contact sheet, with new diagrams inspected individually.
- Local Markdown links, heading anchors and code fences: checked across the
  database area and the main docs index; no failures.
- The 13 distinct official documentation URLs introduced by the new guides:
  HTTP 200 at review time.
- `git diff --check`: passed. Fundamentals, manifests and live cluster state
  were not changed; no new upgrade, failover, restore or rotation was executed.

## References

- [Architecture and manifest inventory](../architecture.md)
- [Capacity and manifest evidence](../storage-and-capacity.md)
- [Reliability targets and measured evidence](../reliability-targets.md)
- [CloudNativePG 1.30 release notes](https://cloudnative-pg.io/docs/1.30/release_notes/v1.30/)
- [CloudNativePG 1.30 PostgreSQL upgrades](https://cloudnative-pg.io/docs/1.30/postgres_upgrades/)
