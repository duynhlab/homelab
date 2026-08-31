# Database Documentation Refactor Tasks

Execution checklist for [the database documentation refactor plan](./refactor-plan.md).
The plan owns scope, taxonomy, document contracts, and migration decisions. This
file owns task order and completion evidence; it must not redefine the target
structure.

| Item | Value |
|---|---|
| **Status** | Complete |
| **Plan** | `docs/databases/refactor-plan.md` |
| **Delivery model** | Sequential checkpoints in the current workspace; no commit or PR created |
| **Task size** | S: 1–2 files; M: 3–5 files |
| **Runtime testing** | No Kind/application E2E; documentation validation only |
| **Last updated** | 2026-08-31 |

Completion evidence is recorded in
[the refactor plan](./refactor-plan.md#completion-evidence). The work was
executed sequentially in the current workspace; no commit, push, or pull
request was created.

## Execution rules

- Complete phases in order. Do not start a later checkpoint until the previous
  checkpoint passes.
- Re-read the relevant manifests in every task that carries forward an as-built
  claim; Phase 0 evidence is not a permanent substitute.
- A moved source may temporarily become a short `Moved` stub, but two full
  pages must never claim canonical ownership.
- Preserve heading intent when migrating inbound links with fragments.
- Use official PostgreSQL, CloudNativePG, PgDog, or extension documentation for
  non-obvious technical claims.
- Render every changed Mermaid block with `mmdc` and inspect the output.
- Run `git diff --check` after every task and the Markdown link checker plus
  `make validate` at each PR checkpoint.
- Do not modify Kubernetes manifests, RFC/ADR decisions, or operational policy
  as part of this refactor. Record newly discovered factual drift instead of
  silently changing the underlying decision.

## Phase 0 — Baseline and ownership

### DBDOC-001: Capture the source inventory

**Description:** Record the pre-refactor file list, line counts, document class,
target path, and action for all database Markdown files.

**Acceptance criteria:**

- [x] All 27 source documents are represented exactly once.
- [x] Every source has one of `move`, `split`, `merge`, `rename`, or `keep`.
- [x] The recorded total matches a fresh filesystem scan.

**Verification:**

- [x] Run `find docs/databases -type f -name '*.md' | sort` and compare it with
  the migration inventory.
- [x] Run `git diff --check`.

**Dependencies:** None
**Files likely touched:** `docs/databases/refactor-plan.md`,
`docs/databases/refactor-tasks.md`
**Estimated scope:** S

### DBDOC-002: Capture inbound-link counts

**Description:** Count every Markdown page that links to each numbered database
document and renamed runbook, grouped by database, proposals, observability,
platform, security, and root indexes.

**Acceptance criteria:**

- [x] Every source path scheduled for deletion has an inbound-link count.
- [x] Fragment links are called out separately from file-only links.
- [x] Link groups are small enough to assign to DBDOC-033 through DBDOC-036.

**Verification:**

- [x] Run `rg -n 'docs/databases|databases/' docs --glob '*.md'` and reconcile
  the ledger.
- [x] Spot-check the four most-linked documents against individual `rg -l`
  searches.

**Dependencies:** DBDOC-001
**Files likely touched:** `docs/databases/refactor-plan.md`,
`docs/databases/refactor-tasks.md`
**Estimated scope:** S

### DBDOC-003: Verify manifest truth and ownership

**Description:** Verify current cluster, operator, PostgreSQL, pooler, backup,
DR, role, and extension facts and record contradictions plus their canonical
future owners.

**Acceptance criteria:**

- [x] The evidence ledger cites the exact manifest path for every current fact.
- [x] Known cluster-count and retired-Zalando contradictions are recorded.
- [x] No repeated fact lacks a canonical owner from `refactor-plan.md`.

**Verification:**

- [x] Compare the ledger with manifests under
  `kubernetes/infra/configs/databases/` and the database controller manifests.
- [x] Confirm the task introduces no manifest changes.

**Dependencies:** DBDOC-002
**Files likely touched:** `docs/databases/refactor-plan.md`,
`docs/databases/refactor-tasks.md`
**Estimated scope:** S

### Phase 0 checkpoint

- [x] DBDOC-001 through DBDOC-003 are complete.
- [x] The migration inventory and inbound-link ledger are reviewable evidence.
- [x] No naming, ownership, or destination decision remains open.
- [x] Markdown links, `git diff --check`, and `make validate` pass.

## Phase 1 — Area hub

### DBDOC-004: Create the database area hub

**Description:** Create the first `docs/databases/README.md` with a concise
purpose statement and four paths: Learn, Understand the Homelab, Operate, and
Reference.

**Acceptance criteria:**

- [x] Each path links to existing filenames at this phase.
- [x] Current, planned, and historical documents are visibly distinguished.
- [x] The hub follows the repository documentation house style.

**Verification:**

- [x] Open every local link from the new hub.
- [x] Render any Mermaid block with `mmdc`.

**Dependencies:** Phase 0 checkpoint
**Files likely touched:** `docs/databases/README.md`
**Estimated scope:** S

### DBDOC-005: Add quick facts and document ownership

**Description:** Add an as-built quick-facts table and the canonical ownership
matrix from the plan without duplicating full topology or policy content.

**Acceptance criteria:**

- [x] Quick facts match the Phase 0 manifest evidence.
- [x] Every recurring fact has exactly one canonical owner.
- [x] The hub links to RFC/ADR history rather than restating it.

**Verification:**

- [x] Compare quick facts with the evidence ledger.
- [x] Search the hub for conflicting cluster counts or retired components.

**Dependencies:** DBDOC-004
**Files likely touched:** `docs/databases/README.md`
**Estimated scope:** S

### DBDOC-006: Simplify the root documentation index

**Description:** Replace the duplicated database file catalog and stale cluster
summary in `docs/README.md` with a concise area entry and learning-path link.

**Acceptance criteria:**

- [x] `docs/README.md` points readers to the database hub.
- [x] It no longer maintains a second detailed database catalog.
- [x] Non-database sections remain unchanged.

**Verification:**

- [x] Review the diff for database-only scope.
- [x] Check all modified links.

**Dependencies:** DBDOC-005
**Files likely touched:** `docs/README.md`
**Estimated scope:** S

### DBDOC-007: Validate hub navigation

**Description:** Audit the four hub paths from the perspective of a learner, a
platform reviewer, and an on-call responder, then correct navigation defects.

**Acceptance criteria:**

- [x] Every source document is reachable from the hub or a child index.
- [x] Emergency recovery is reachable in at most two clicks.
- [x] Historical pages cannot be mistaken for current operations.

**Verification:**

- [x] Run the repository Markdown link check on the two modified indexes.
- [x] Run `git diff --check` and `make validate`.

**Dependencies:** DBDOC-006
**Files likely touched:** `docs/databases/README.md`, `docs/README.md`
**Estimated scope:** S

### Phase 1 checkpoint

- [x] DBDOC-004 through DBDOC-007 are complete.
- [x] The hub works while all legacy paths still exist.
- [x] Link check, Mermaid rendering where applicable, and `make validate` pass.

## Phase 2 — Fundamentals

### DBDOC-008: Extract PostgreSQL internals

**Description:** Rewrite the stable process, memory, WAL, MVCC, storage,
vacuum, and query-flow material from `001` as a project-neutral fundamentals
page.

**Acceptance criteria:**

- [x] The main tutorial does not depend on `product-db` or Kubernetes.
- [x] Current topology is replaced by one final `Applied in this homelab`
  section.
- [x] `001` becomes a short moved stub after inbound links are redirected.

**Verification:**

- [x] Search the fundamentals body for current cluster/version claims.
- [x] Render all migrated Mermaid blocks.

**Dependencies:** Phase 1 checkpoint
**Files likely touched:** `docs/databases/001-postgresql-internals.md`,
`docs/databases/fundamentals/postgresql-internals.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-009: Extract replication and HA fundamentals

**Description:** Consolidate physical/logical replication, WAL streaming,
synchronous commit, quorum, failover, and HA-vs-DR concepts from `004` and
`005`.

**Acceptance criteria:**

- [x] Concepts are operator-neutral and do not duplicate current topology.
- [x] RPO/RTO targets and executable recovery commands remain outside the page.
- [x] The applied section links to architecture and DR platform owners.

**Verification:**

- [x] Compare destination headings with the conceptual headings in both sources.
- [x] Render all Mermaid diagrams and inspect arrow/state semantics.

**Dependencies:** DBDOC-008
**Files likely touched:** `docs/databases/004-replication-strategy.md`,
`docs/databases/005-ha-dr-deep-dive.md`,
`docs/databases/fundamentals/replication-and-ha.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-010: Extract backup and recovery fundamentals

**Description:** Move backup types, WAL archiving, PITR, RPO/RTO mechanics, and
tool-selection concepts out of `006` into a stable learning page.

**Acceptance criteria:**

- [x] The page distinguishes replication, backup, restore, PITR, RPO, and RTO.
- [x] RustFS paths, schedules, and platform targets remain in platform docs.
- [x] The applied section links to backup policy and disaster recovery.

**Verification:**

- [x] Search for current bucket paths, schedules, namespaces, and cluster names.
- [x] Verify retained claims against official PostgreSQL/CNPG documentation.

**Dependencies:** DBDOC-009
**Files likely touched:** `docs/databases/006-backup-strategy.md`,
`docs/databases/fundamentals/backup-and-recovery.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-011: Extract connection-pooling fundamentals

**Description:** Move pooling purposes, session/transaction/statement modes,
prepared-statement behavior, and failure trade-offs from `008` into a generic
learning page.

**Acceptance criteria:**

- [x] The tutorial is not organized around PgDog or the deployed PgBouncer.
- [x] Product-specific endpoints and credentials remain outside fundamentals.
- [x] The applied section links to the current pooler page.

**Verification:**

- [x] Search for deployed release names, namespaces, and ports in the main body.
- [x] Render any moved comparison diagrams.

**Dependencies:** DBDOC-010
**Files likely touched:** `docs/databases/008-pooler.md`,
`docs/databases/fundamentals/connection-pooling.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-012: Extract extension fundamentals

**Description:** Move extension lifecycle, trust, preload, compatibility,
packaging, and upgrade-risk concepts from `009` into a generic learning page.

**Acceptance criteria:**

- [x] The page explains extension mechanics without claiming an installed set.
- [x] Current allowlists and deployment methods remain in platform docs.
- [x] The applied section links to the future current extension page.

**Verification:**

- [x] Search for current manifest names and installed-version claims.
- [x] Verify technical claims against PostgreSQL and extension documentation.

**Dependencies:** DBDOC-011
**Files likely touched:** `docs/databases/009-extensions.md`,
`docs/databases/fundamentals/extensions.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-013: Finalize the fundamentals learning path

**Description:** Order the five fundamentals pages, replace extracted sections
in mixed legacy pages with contextual links, and confirm no competing tutorial
copy remains.

**Acceptance criteria:**

- [x] Learning order is internals, replication/HA, pooling, backup/recovery,
  extensions.
- [x] Mixed sources retain only content needed by later platform/runbook phases.
- [x] No fundamentals page contains duplicated as-built tables.

**Verification:**

- [x] Run the project-specific-term search defined in `refactor-plan.md`.
- [x] Run link check, render all changed Mermaid blocks, and run
  `make validate`.

**Dependencies:** DBDOC-012
**Files likely touched:** `docs/databases/README.md`,
`docs/databases/004-replication-strategy.md`,
`docs/databases/005-ha-dr-deep-dive.md`,
`docs/databases/006-backup-strategy.md`,
`docs/databases/refactor-tasks.md`
**Estimated scope:** M

### Phase 2 checkpoint

- [x] DBDOC-008 through DBDOC-013 are complete.
- [x] Five fundamentals pages satisfy the fundamentals contract.
- [x] Official references, link check, Mermaid rendering, and `make validate`
  pass.

## Phase 3 — Current platform documentation

### DBDOC-014: Consolidate current database architecture

**Description:** Merge the as-built inventory and unique read/write flow from
`002`, `007`, and the current-topology section of `004` into `architecture.md`.

**Acceptance criteria:**

- [x] `architecture.md` is the only full cluster inventory.
- [x] Every topology fact matches current manifests.
- [x] Repeated learning, DR, pooler, and role details are replaced by links.

**Verification:**

- [x] Compare the quick facts and diagram with cluster manifests.
- [x] Render every architecture diagram.

**Dependencies:** Phase 2 checkpoint
**Files likely touched:** `docs/databases/002-database-integration.md`,
`docs/databases/007-architecture.md`,
`docs/databases/004-replication-strategy.md`,
`docs/databases/architecture.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-015: Establish the current CloudNativePG page

**Description:** Rename and update `003.1` as the canonical CNPG control-plane,
operand, security, backup-plugin, and deployed-usage page.

**Acceptance criteria:**

- [x] All deployed clusters are represented and Zalando is not presented as current.
- [x] Version and feature claims match controller and cluster manifests.
- [x] Generic PostgreSQL teaching links to fundamentals instead of repeating it.

**Verification:**

- [x] Compare claims with the CNPG HelmRelease and cluster CRs.
- [x] Render the CNPG architecture diagram.

**Dependencies:** DBDOC-014
**Files likely touched:** `docs/databases/003.1-operator-cnpg.md`,
`docs/databases/cloudnativepg.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-016: Establish the deployed backup policy

**Description:** Move current Barman plugin, RustFS, schedules, retention,
bucket layout, and alert ownership from `006` into `backup-policy.md`.

**Acceptance criteria:**

- [x] Schedules, retention, and object-store paths match manifests.
- [x] Tool comparison and PITR teaching remain in fundamentals/reference.
- [x] Procedures link to the backup runbook instead of being duplicated.

**Verification:**

- [x] Compare the page with ObjectStore, Backup, and ScheduledBackup resources.
- [x] Check links to alerts, DR, and fundamentals.

**Dependencies:** DBDOC-015
**Files likely touched:** `docs/databases/006-backup-strategy.md`,
`docs/databases/backup-policy.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-017: Consolidate disaster-recovery policy

**Description:** Merge the recovery decision model and current DR topology from
`005` and `010` into `disaster-recovery.md`, excluding targets and procedures.

**Acceptance criteria:**

- [x] The page owns recovery paths and DR topology, not RPO/RTO tables.
- [x] Commands route to runbooks and concepts route to fundamentals.
- [x] Current and planned failure domains are explicitly labelled.

**Verification:**

- [x] Compare recovery paths with CNPG replica and backup manifests.
- [x] Render decision-flow and topology diagrams.

**Dependencies:** DBDOC-016
**Files likely touched:** `docs/databases/005-ha-dr-deep-dive.md`,
`docs/databases/010-drp.md`, `docs/databases/disaster-recovery.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-018: Establish reliability targets

**Description:** Rename and narrow `010.1` so it exclusively owns target versus
measured RPO/RTO, evidence links, and known gaps.

**Acceptance criteria:**

- [x] Every target is distinguishable from measured evidence.
- [x] General RPO/RTO explanation links to fundamentals.
- [x] DR and backup pages contain no competing target matrix.

**Verification:**

- [x] Trace measured values to existing drill evidence.
- [x] Search database docs for duplicate target tables.

**Dependencies:** DBDOC-017
**Files likely touched:** `docs/databases/010.1-rpo-rto-planning.md`,
`docs/databases/reliability-targets.md`, `docs/databases/disaster-recovery.md`,
`docs/databases/backup-policy.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-019: Establish the cross-region roadmap

**Description:** Rename `010.3` and align every undeployed node and edge with
the repository's `planned` diagram/status convention.

**Acceptance criteria:**

- [x] Current co-location and future failure domains are separated.
- [x] Every undeployed topology element contains the word `planned`.
- [x] The page links to the canonical current DR and target pages.

**Verification:**

- [x] Render and inspect every roadmap diagram.
- [x] Search for unqualified future-tense deployment claims.

**Dependencies:** DBDOC-018
**Files likely touched:** `docs/databases/010.3-cross-region-dr.md`,
`docs/databases/cross-region-dr.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-020: Establish current pooler ownership

**Description:** Move the deployed PgDog and CNPG PgBouncer topology,
connection ownership, and platform trade-offs from `008` into `poolers.md`.

**Acceptance criteria:**

- [x] Current clients, endpoints, ports, and pooler roles match manifests.
- [x] Generic pooling semantics link to fundamentals.
- [x] Operational commands link to the pooler runbook.

**Verification:**

- [x] Compare claims with PgDog HelmRelease and CNPG Pooler resources.
- [x] Render the deployed connection diagram.

**Dependencies:** DBDOC-019
**Files likely touched:** `docs/databases/008-pooler.md`,
`docs/databases/poolers.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-021: Establish the current extension model

**Description:** Move installed/allowed extensions, preload requirements,
packaging, ownership, and upgrade constraints from `009` into `extensions.md`.

**Acceptance criteria:**

- [x] Installed and planned extensions are separately labelled.
- [x] Current claims match images, cluster parameters, and service migrations.
- [x] Generic mechanics link to fundamentals.

**Verification:**

- [x] Search manifests and canonical API docs for each claimed current extension.
- [x] Check that no external service-repo README overrides `docs/api/` truth.

**Dependencies:** DBDOC-020
**Files likely touched:** `docs/databases/009-extensions.md`,
`docs/databases/extensions.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-022: Rename declarative role management

**Description:** Move `012` to its semantic filename while preserving the
RFC-0012 as-built role/database/credential contract.

**Acceptance criteria:**

- [x] DatabaseRole, Database, ExternalSecret, and reclaim semantics remain intact.
- [x] Current cluster/service claims match manifests.
- [x] Lifecycle procedures remain links to runbooks.

**Verification:**

- [x] Compare examples with current per-service triplet manifests.
- [x] Check all local RFC/ADR/runbook links.

**Dependencies:** DBDOC-021
**Files likely touched:** `docs/databases/012-declarative-role-management.md`,
`docs/databases/declarative-role-management.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-023: Audit canonical platform ownership

**Description:** Search all database pages for repeated inventories, versions,
RPO/RTO targets, schedules, endpoints, and installed-extension lists and replace
non-canonical copies with contextual links.

**Acceptance criteria:**

- [x] Each ownership row from the hub has exactly one full canonical treatment.
- [x] Retained summaries do not become independently maintainable inventories.
- [x] Legacy mixed pages contain only material still awaiting Phase 4 migration.

**Verification:**

- [x] Run focused `rg` searches for counts, versions, retention, endpoints, and
  RPO/RTO values.
- [x] Run link check, render changed Mermaid blocks, and run `make validate`.

**Dependencies:** DBDOC-022
**Files likely touched:** `docs/databases/README.md`,
`docs/databases/architecture.md`, `docs/databases/backup-policy.md`,
`docs/databases/disaster-recovery.md`,
`docs/databases/reliability-targets.md`
**Estimated scope:** M

### Phase 3 checkpoint

- [x] DBDOC-014 through DBDOC-023 are complete.
- [x] Current platform pages satisfy their ownership contracts.
- [x] Manifest comparison, link check, Mermaid rendering, and `make validate`
  pass.

## Phase 4 — Runbooks and historical reference

### DBDOC-024: Move emergency recovery into runbooks

**Description:** Move `010.4` to the current runbook area and retain its role as
the first-response recovery router.

**Acceptance criteria:**

- [x] Triage, decision flow, destructive warnings, verification, and escalation remain.
- [x] Theory and topology link to canonical pages.
- [x] The database hub and runbook index expose the new path.

**Verification:**

- [x] Render the decision tree.
- [x] Check all links from the moved page and its two indexes.

**Dependencies:** Phase 3 checkpoint
**Files likely touched:** `docs/databases/010.4-emergency-recovery.md`,
`docs/databases/runbooks/emergency-recovery.md`,
`docs/databases/runbooks/README.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-025: Move restore and failover drills

**Description:** Move `010.2` into runbooks while preserving cadence, roles,
procedures, evidence templates, and historical drill links.

**Acceptance criteria:**

- [x] Drill evidence and acceptance gates remain reachable by their new anchors.
- [x] RPO/RTO values link to `reliability-targets.md`.
- [x] Recovery theory and topology are not duplicated.

**Verification:**

- [x] Compare every existing evidence heading before and after the move.
- [x] Check links from the page and indexes.

**Dependencies:** DBDOC-024
**Files likely touched:** `docs/databases/010.2-restore-and-failover-drills.md`,
`docs/databases/runbooks/restore-and-failover-drills.md`,
`docs/databases/runbooks/README.md`, `docs/databases/README.md`
**Estimated scope:** M

### DBDOC-026: Rename the backup runbook

**Description:** Rename `postgres-backup-restore.md` to `backup-restore.md` and
align its references with the new backup, DR, target, and fundamentals pages.

**Acceptance criteria:**

- [x] All current Barman backup, restore, and PITR procedures remain intact.
- [x] Expected output, verification, rollback, and escalation are explicit.
- [x] The old file becomes a short compatibility stub until Phase 5.

**Verification:**

- [x] Compare all command blocks before and after the rename.
- [x] Check local links and anchors.

**Dependencies:** DBDOC-025
**Files likely touched:** `docs/databases/runbooks/postgres-backup-restore.md`,
`docs/databases/runbooks/backup-restore.md`,
`docs/databases/runbooks/README.md`
**Estimated scope:** M

### DBDOC-027: Rename the pooler operations runbook

**Description:** Rename `pgdog-operations.md` to `pooler-operations.md` because
the page operates both PgDog and CNPG PgBouncer.

**Acceptance criteria:**

- [x] Both deployed poolers retain status, rotation, backend, and failure procedures.
- [x] Generic pooling teaching links to fundamentals.
- [x] The old path becomes a compatibility stub until Phase 5.

**Verification:**

- [x] Compare command and failure-mode coverage before and after the rename.
- [x] Check local links and anchors.

**Dependencies:** DBDOC-026
**Files likely touched:** `docs/databases/runbooks/pgdog-operations.md`,
`docs/databases/runbooks/pooler-operations.md`,
`docs/databases/runbooks/README.md`
**Estimated scope:** M

### DBDOC-028: Narrow retained current runbooks

**Description:** Relink and remove duplicated theory from the add-database,
CNPG DR bootstrap, and password-rotation runbooks without changing procedures.

**Acceptance criteria:**

- [x] Each page starts from a task/trigger and contains current commands only.
- [x] Concepts and topology link to their canonical pages.
- [x] No command behavior or safety gate changes.

**Verification:**

- [x] Review command diffs to confirm procedural equivalence.
- [x] Check every modified relative link.

**Dependencies:** DBDOC-027
**Files likely touched:** `docs/databases/runbooks/add-service-database.md`,
`docs/databases/runbooks/cnpg-dr-replica-bootstrap.md`,
`docs/databases/runbooks/rotate-cnpg-service-password.md`
**Estimated scope:** M

### DBDOC-029: Move operator comparison and further reading

**Description:** Move `003` and `011` into the reference area and remove current
cluster inventory from the operator comparison.

**Acceptance criteria:**

- [x] The comparison states CNPG is current and Zalando is historical.
- [x] The reading list follows the new learning categories.
- [x] Neither page appears in the current operations path.

**Verification:**

- [x] Search both pages for stale current cluster claims.
- [x] Check external and internal links.

**Dependencies:** DBDOC-028
**Files likely touched:** `docs/databases/003-operator-comparison.md`,
`docs/databases/011-documents.md`,
`docs/databases/reference/operator-comparison.md`,
`docs/databases/reference/further-reading.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-030: Move Zalando operator and prepared-database history

**Description:** Move the Zalando operator deep dive and preparedDatabases
failure analysis under `reference/zalando/`.

**Acceptance criteria:**

- [x] Both pages carry a visible historical/not-deployed notice.
- [x] `Current Homelab Usage` and similar headings are rewritten historically.
- [x] Replacement CNPG pages are linked.

**Verification:**

- [x] Run the historical-current-language search from `refactor-plan.md`.
- [x] Check all moved links and diagrams.

**Dependencies:** DBDOC-029
**Files likely touched:** `docs/databases/003.2-operator-zalando.md`,
`docs/databases/runbooks/prepared-databases.md`,
`docs/databases/reference/zalando/operator.md`,
`docs/databases/reference/zalando/prepared-databases.md`,
`docs/databases/README.md`
**Estimated scope:** M

### DBDOC-031: Move remaining Zalando procedures

**Description:** Move Endpoints-to-ConfigMaps and Zalando HA scaling procedures
out of the current runbook directory.

**Acceptance criteria:**

- [x] Both documents are available under `reference/zalando/`.
- [x] Historical commands cannot be reached from the current runbook index.
- [x] CNPG replacement and retirement context are explicit.

**Verification:**

- [x] Search the current runbook directory for Zalando/Spilo/Patroni procedures.
- [x] Check all moved links and diagrams.

**Dependencies:** DBDOC-030
**Files likely touched:** `docs/databases/runbooks/endpoints-to-configmaps.md`,
`docs/databases/runbooks/zalando-ha-scaling.md`,
`docs/databases/reference/zalando/endpoints-to-configmaps.md`,
`docs/databases/reference/zalando/ha-scaling.md`
**Estimated scope:** M

### DBDOC-032: Finalize the current runbook index

**Description:** Rewrite `runbooks/README.md` as a current-only task index and
connect the hub's Operate path to emergency and task-specific entry points.

**Acceptance criteria:**

- [x] Every listed runbook applies to the deployed CNPG platform.
- [x] Emergency recovery is the first incident entry point.
- [x] Historical procedures are reachable only through Reference.

**Verification:**

- [x] Open every runbook index link.
- [x] Run link check, render changed Mermaid blocks, and run `make validate`.

**Dependencies:** DBDOC-031
**Files likely touched:** `docs/databases/runbooks/README.md`,
`docs/databases/README.md`, `docs/databases/refactor-tasks.md`
**Estimated scope:** M

### Phase 4 checkpoint

- [x] DBDOC-024 through DBDOC-032 are complete.
- [x] Current runbooks and historical reference material are fully separated.
- [x] Link check, Mermaid rendering, and `make validate` pass.

## Phase 5 — Link migration and legacy retirement

### DBDOC-033: Migrate database-area and root-index links

**Description:** Update stale paths and fragment links within
`docs/databases/` plus `docs/README.md`, preserving section-level intent.

**Acceptance criteria:**

- [x] No final database page links to a numeric path or renamed runbook.
- [x] Every old fragment link resolves to the equivalent destination heading.

**Verification:**

- [x] Run stale-path searches limited to `docs/databases/` and `docs/README.md`.
- [x] Run the Markdown link checker on modified files.

**Dependencies:** Phase 4 checkpoint
**Files likely touched:** Mechanical link updates, split into commits/groups of
no more than five files
**Estimated scope:** M per group

### DBDOC-034: Migrate proposal links

**Description:** Update RFC and ADR links in groups of no more than five files,
preserving drill-evidence and decision-record anchors.

**Acceptance criteria:**

- [x] No proposal links to legacy database paths.
- [x] RFC-0007 and GameDay evidence links still land on exact records.

**Verification:**

- [x] Run stale-path searches under `docs/proposals/`.
- [x] Check all modified fragment links.

**Dependencies:** DBDOC-033
**Files likely touched:** `docs/proposals/` Markdown files, maximum five per
execution group
**Estimated scope:** M per group

### DBDOC-035: Migrate observability indexes and metrics links

**Description:** Update database paths in the alert catalog, PostgreSQL metrics
hub, PostgreSQL runbook index, and other observability index pages.

**Acceptance criteria:**

- [x] Index/catalog links point to final current runbooks and platform pages.
- [x] Link labels describe the renamed destinations accurately.

**Verification:**

- [x] Run stale-path searches on the modified observability indexes.
- [x] Run the Markdown link checker.

**Dependencies:** DBDOC-034
**Files likely touched:** Up to five observability index/catalog files per group
**Estimated scope:** M per group

### DBDOC-036: Migrate per-alert and remaining domain links

**Description:** Update individual PostgreSQL alert runbooks and any remaining
platform, security, or secrets references in groups of no more than five files.

**Acceptance criteria:**

- [x] Every per-alert operational link lands on a current runbook.
- [x] No non-database document references a legacy database path.

**Verification:**

- [x] Run repository-wide stale-path searches after each group.
- [x] Check modified links and fragments.

**Dependencies:** DBDOC-035
**Files likely touched:** Up to five non-database Markdown files per group
**Estimated scope:** M per group

### DBDOC-037: Remove legacy files 001 through 005

**Description:** Delete compatibility stubs for `001`, `002`, `003`, `003.1`,
`003.2`, `004`, and `005` only after their inbound-link counts reach zero.

**Acceptance criteria:**

- [x] Every target page exists and is indexed.
- [x] Repository search finds no inbound reference to the removed paths.

**Verification:**

- [x] Run exact `rg` searches for each removed filename before deletion.
- [x] Run link check after deletion.

**Dependencies:** DBDOC-036
**Files likely touched:** Delete in groups of no more than five legacy stubs
**Estimated scope:** S per group

### DBDOC-038: Remove legacy files 006 through 009

**Description:** Delete `006`, `007`, `008`, and `009` compatibility stubs after
confirming their split destinations and inbound-link migrations.

**Acceptance criteria:**

- [x] All conceptual and current sections have canonical destinations.
- [x] Repository search finds no inbound reference to the removed paths.

**Verification:**

- [x] Compare original heading inventories with destination coverage.
- [x] Run exact stale-path searches and link check.

**Dependencies:** DBDOC-037
**Files likely touched:** Four legacy stubs
**Estimated scope:** M

### DBDOC-039: Remove the 010–012 and old-runbook paths

**Description:** Delete remaining numbered stubs and renamed/moved runbook
stubs in groups of no more than five files.

**Acceptance criteria:**

- [x] All recovery evidence and section anchors have final destinations.
- [x] No old numbered or renamed-runbook path remains.

**Verification:**

- [x] Run exact searches for `010*`, `011`, `012`, `pgdog-operations.md`, and
  `postgres-backup-restore.md` references.
- [x] Run link check after each deletion group.

**Dependencies:** DBDOC-038
**Files likely touched:** Legacy stubs, maximum five per group
**Estimated scope:** M per group

### DBDOC-040: Run the stale-path and orphan audit

**Description:** Execute the complete retirement searches from the plan, find
unindexed Markdown files, and close every remaining path/ownership gap.

**Acceptance criteria:**

- [x] No numeric database filename exists.
- [x] No Markdown link references a legacy path.
- [x] Every final page is reachable from the area hub or runbook index.

**Verification:**

- [x] Run all Phase 5 commands from `refactor-plan.md` with empty results.
- [x] Run link check and `make validate`.

**Dependencies:** DBDOC-039
**Files likely touched:** `docs/databases/README.md`,
`docs/databases/runbooks/README.md`, `docs/databases/refactor-plan.md`,
`docs/databases/refactor-tasks.md`
**Estimated scope:** M

### Phase 5 checkpoint

- [x] DBDOC-033 through DBDOC-040 are complete.
- [x] Numeric filenames, compatibility stubs, and stale paths are gone.
- [x] Link check and `make validate` pass.

## Phase 6 — Final quality gate

### DBDOC-041: Run the complete Markdown link audit

**Description:** Run the CI-equivalent Markdown link checker over every file
changed by the refactor and resolve all internal or checked external failures.

**Acceptance criteria:**

- [x] Every internal link and fragment resolves.
- [x] External-link failures are fixed or handled only through existing CI policy.

**Verification:**

- [x] Record the successful link-check command/output in the PR evidence.
- [x] Run a final repository-wide stale-path search.

**Dependencies:** Phase 5 checkpoint
**Files likely touched:** Only files with verified link defects, maximum five per
fix group
**Estimated scope:** M

### DBDOC-042: Render and inspect all Mermaid diagrams

**Description:** Enumerate every changed Mermaid block, render it with `mmdc`,
and inspect state labels, clipping, crossings, and palette compliance.

**Acceptance criteria:**

- [x] Every changed Mermaid block renders successfully.
- [x] Planned/reference state is conveyed in text, not color alone.
- [x] No diagram claims topology that differs from its owning page.

**Verification:**

- [x] Record the diagram inventory and render result.
- [x] Manually inspect generated SVG/PNG output.

**Dependencies:** DBDOC-041
**Files likely touched:** Only pages with diagram defects, maximum five per fix
group
**Estimated scope:** M

### DBDOC-043: Run the final repository and contract audit

**Description:** Run repository validation and review every final page against
its Fundamentals, Current, Runbook, or Reference contract.

**Acceptance criteria:**

- [x] `make validate` passes.
- [x] Every database page belongs to exactly one document class.
- [x] Current facts, targets, procedures, and history have no competing owner.

**Verification:**

- [x] Record successful `make validate` output.
- [x] Complete the plan's final ownership and completion checklist.

**Dependencies:** DBDOC-042
**Files likely touched:** `docs/databases/README.md`,
`docs/databases/refactor-plan.md`, `docs/databases/refactor-tasks.md`
**Estimated scope:** M

### DBDOC-044: Close the refactor

**Description:** Mark the plan and task checklist complete only after every PR
checkpoint and final validation has recorded evidence.

**Acceptance criteria:**

- [x] All DBDOC task and phase checkboxes are complete.
- [x] Both files show `Complete` and the final verification date.
- [x] The final delivery summary links the hub and validation evidence.

**Verification:**

- [x] Search for unchecked task/checkpoint boxes and resolve every result.
- [x] Run `git diff --check`, link check, and `make validate` one final time.

**Dependencies:** DBDOC-043
**Files likely touched:** `docs/databases/refactor-plan.md`,
`docs/databases/refactor-tasks.md`
**Estimated scope:** S

### Phase 6 checkpoint

- [x] DBDOC-041 through DBDOC-044 are complete.
- [x] The final information architecture is link-complete, rendered, validated,
  and marked complete.

## Checkpoint order summary

| PR | Tasks | Deliverable |
|---|---|---|
| 0 | DBDOC-001–003 | Auditable inventory, inbound links, manifest truth, ownership |
| 1 | DBDOC-004–007 | Database hub and simplified root index |
| 2 | DBDOC-008–013 | Five project-neutral fundamentals pages |
| 3 | DBDOC-014–023 | Canonical as-built platform pages |
| 4 | DBDOC-024–032 | Current runbooks and quarantined historical references |
| 5 | DBDOC-033–040 | Link migration and removal of every legacy path |
| 6 | DBDOC-041–044 | Link, Mermaid, repository, and contract quality gates |

## Completion summary

- [x] 44 of 44 DBDOC tasks complete.
- [x] 7 of 7 phase checkpoints complete.
- [x] No numbered database documentation files remain.
- [x] Learn, Understand, Operate, and Reference paths work from the area hub.
- [x] Markdown links, Mermaid rendering, and `make validate` pass.
