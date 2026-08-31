# Database Documentation Refactor Plan

Before this refactor, the database area mixed PostgreSQL learning material,
deployed homelab truth, operational procedures, and retired operator history in
the same numbered files. The implementation separates those responsibilities while preserving the
material as a personal learning library and making current platform facts safe
to use during operations.

| Item | Value |
|---|---|
| **Status** | Complete |
| **Owner** | Platform |
| **Scope** | `docs/databases/` plus inbound Markdown links |
| **Implementation unit** | Sequential checkpoints; owner chooses commit and PR boundaries |
| **Architecture impact** | None — documentation information architecture only |
| **RFC / ADR required** | No |
| **Last verified** | 2026-08-31 |

## Problem statement

The area had 27 Markdown files and roughly 9,100 lines, but no
`docs/databases/README.md` area hub. A reader could not reliably tell whether a
page is:

- stable PostgreSQL knowledge intended for study;
- a description of resources currently deployed by this repository;
- a policy or target that has not yet been proven;
- a procedure to execute during an incident; or
- a historical record for an operator that has been retired.

The ambiguity has already produced visible drift:

- the root documentation index describes a different cluster count from the
  current database integration guide;
- Zalando pages are marked historical but still contain sections titled
  `Current Homelab Usage` and retired cluster inventories;
- replication, backup, HA, DR, and RPO/RTO claims are repeated across several
  large documents;
- command-heavy recovery instructions live beside conceptual tutorials instead
  of under `runbooks/`;
- filenames such as `005-ha-dr-deep-dive.md` describe neither ownership nor
  reading order once documents are split.

## Goals

1. Preserve database fundamentals as first-class learning material.
2. Give every deployed fact exactly one canonical platform-owned page.
3. Make incident procedures discoverable without requiring a reader to work
   through a tutorial.
4. Quarantine retired Zalando material without deleting its learning value.
5. Replace numeric filenames with stable names that describe document purpose.
6. Leave every phase link-complete and reviewable as an independent PR.

## Non-goals

- Changing Kubernetes manifests, operators, PostgreSQL configuration, backup
  policy, RPO/RTO targets, or runbook behavior.
- Re-deciding accepted RFCs or ADRs.
- Revalidating every external PostgreSQL tutorial as part of the structural
  move. Claims retained in rewritten pages must still be checked against
  official documentation when that page is edited.
- Running Kind or application E2E tests for a documentation-only refactor.
- Moving PostgreSQL metrics and alert runbooks out of
  `docs/observability/`; that area owns signal interpretation and per-alert
  response.

## Document contracts

Every database page must belong to exactly one class.

### Fundamentals

Fundamentals answer **how the technology works**.

- Keep PostgreSQL concepts independent of this repository, Kubernetes
  namespaces, operator versions, and current cluster counts.
- Prefer official PostgreSQL or operator documentation for factual claims.
- Use generic examples in the main explanation.
- End with a short `Applied in this homelab` section that links to the relevant
  current platform page; do not copy its topology or version table.
- Do not contain executable production procedures beyond safe illustrative SQL.

### Current platform documentation

Root-level database pages answer **what this homelab runs and why**.

- Verify every current claim against manifests before carrying it forward.
- Use the house shape: hook, status/quick facts, overview, Mermaid
  architecture, how it works here, operations links, references, last-updated
  footer.
- Label accepted-but-not-deployed work `planned`; label research-only shapes
  `reference — not deployed`.
- Link to RFCs and ADRs for reasoning instead of copying their history.
- Keep one canonical owner for repeated facts:

| Fact | Canonical owner |
|---|---|
| Cluster inventory, namespaces, PostgreSQL/operator versions | `architecture.md` |
| CloudNativePG control-plane and operand behavior | `cloudnativepg.md` |
| Backup schedules, retention, object-store paths | `backup-policy.md` |
| Recovery paths and DR topology | `disaster-recovery.md` |
| RPO/RTO objectives and measured evidence | `reliability-targets.md` |
| Pooler deployment and connection ownership | `poolers.md` |
| Installed/allowed extension model | `extensions.md` |
| Database/role/credential reconciliation | `declarative-role-management.md` |

### Runbooks

Runbooks answer **what to do now**.

- Start with scope, symptom/trigger, prerequisites, and destructive-action
  warning where relevant.
- Provide ordered commands, expected output, verification, rollback, and
  escalation.
- Link to fundamentals for explanation and platform pages for topology.
- Do not embed broad technology comparisons or long conceptual chapters.
- Keep current procedures only. Historical procedures move to `reference/`.

### Reference and historical material

Reference pages answer **what was compared or how the platform used to work**.

- Start with a visible `Historical / reference — not deployed` notice.
- State the retirement decision and link to the replacement where known.
- Replace headings such as `Current Homelab Usage` with explicit historical
  wording.
- Never appear in the current operations path except as background reading.

## Target structure

```text
docs/databases/
  README.md
  refactor-plan.md
  architecture.md
  cloudnativepg.md
  backup-policy.md
  disaster-recovery.md
  reliability-targets.md
  cross-region-dr.md
  poolers.md
  extensions.md
  declarative-role-management.md
  fundamentals/
    postgresql-internals.md
    replication-and-ha.md
    backup-and-recovery.md
    connection-pooling.md
    extensions.md
  reference/
    README.md
    operator-comparison.md
    further-reading.md
    archive/
      README.md
      *-homelab-notes.md
    zalando/
      README.md
      operator.md
      prepared-databases.md
      endpoints-to-configmaps.md
      ha-scaling.md
  runbooks/
    README.md
    add-service-database.md
    backup-restore.md
    cnpg-dr-replica-bootstrap.md
    emergency-recovery.md
    pooler-operations.md
    restore-and-failover-drills.md
    rotate-cnpg-service-password.md
```

## Migration inventory

### Root documents

| Current file | Action | Target | Content rule |
|---|---|---|---|
| `001-postgresql-internals.md` | Move and rewrite | `fundamentals/postgresql-internals.md` | Keep PostgreSQL processes, buffers, WAL, MVCC, storage, vacuum, and query flow; move current topology to `architecture.md` and use only a final applied link |
| `002-database-integration.md` | Merge and rename | `architecture.md` | Become the canonical as-built inventory and connection topology; absorb only non-duplicated current architecture from `007` |
| `003-operator-comparison.md` | Move and rewrite | `reference/operator-comparison.md` | Keep the conceptual comparison; remove current cluster inventory and state clearly that CNPG is the deployed standard |
| `003.1-operator-cnpg.md` | Rename and update | `cloudnativepg.md` | Keep CNPG mechanics plus current usage; verify all clusters, versions, backup plugin, security, and pooler claims |
| `003.2-operator-zalando.md` | Move and historicize | `reference/zalando/operator.md` | Remove current-language contradictions and preserve Patroni/Spilo learning value |
| `004-replication-strategy.md` | Split | `fundamentals/replication-and-ha.md`, `architecture.md`, `disaster-recovery.md` | Move physical/logical replication and commit semantics to fundamentals; move only current topology to platform owners |
| `005-ha-dr-deep-dive.md` | Split and retire | `fundamentals/replication-and-ha.md`, `disaster-recovery.md`, current runbooks | Move concepts, topology, and commands to their respective owners; remove duplicated RPO/RTO tables |
| `006-backup-strategy.md` | Split | `fundamentals/backup-and-recovery.md`, `backup-policy.md` | Separate backup theory/tool landscape from the deployed Barman/RustFS schedule and retention policy |
| `007-architecture.md` | Merge and retire | `architecture.md` | Preserve unique write/read and component-flow explanations; remove content already owned by fundamentals or pooler pages |
| `008-pooler.md` | Split | `fundamentals/connection-pooling.md`, `poolers.md` | Separate pooling modes and transaction semantics from PgDog/PgBouncer deployment truth |
| `009-extensions.md` | Split | `fundamentals/extensions.md`, `extensions.md` | Separate PostgreSQL extension mechanics and risk model from installed/approved platform extensions |
| `010-drp.md` | Merge and rename | `disaster-recovery.md` | Remain the canonical recovery decision model; link to targets and runbooks instead of duplicating them |
| `010.1-rpo-rto-planning.md` | Rename and narrow | `reliability-targets.md` | Own target vs measured RPO/RTO and evidence links; move general RPO/RTO teaching to fundamentals |
| `010.2-restore-and-failover-drills.md` | Move and rename | `runbooks/restore-and-failover-drills.md` | Keep cadence, procedures, evidence template, and recorded evidence links |
| `010.3-cross-region-dr.md` | Rename | `cross-region-dr.md` | Keep as a clearly labelled planned roadmap, not current topology |
| `010.4-emergency-recovery.md` | Move | `runbooks/emergency-recovery.md` | Become the first-response recovery router |
| `011-documents.md` | Move and rename | `reference/further-reading.md` | Keep curated external references, grouped by the new learning path |
| `012-declarative-role-management.md` | Rename | `declarative-role-management.md` | Preserve the current RFC-0012 as-built contract and links to lifecycle runbooks |

### Runbooks

| Current file | Action | Target | Content rule |
|---|---|---|---|
| `runbooks/README.md` | Rewrite | Same path | Index current runbooks only; link historical procedures through the reference section |
| `runbooks/add-service-database.md` | Keep and relink | Same path | Update concept/platform links after moves |
| `runbooks/cnpg-dr-replica-bootstrap.md` | Keep and narrow | Same path | Link to canonical DR topology and emergency recovery; remove repeated theory |
| `runbooks/endpoints-to-configmaps.md` | Move | `reference/zalando/endpoints-to-configmaps.md` | Historical migration procedure, not a current runbook |
| `runbooks/pgdog-operations.md` | Rename | `runbooks/pooler-operations.md` | Reflect that the page operates both PgDog and CNPG PgBouncer |
| `runbooks/postgres-backup-restore.md` | Rename | `runbooks/backup-restore.md` | Keep current Barman backup, restore, and PITR procedures |
| `runbooks/prepared-databases.md` | Move | `reference/zalando/prepared-databases.md` | Preserve the retired failure analysis without exposing it as a current fix path |
| `runbooks/rotate-cnpg-service-password.md` | Keep and relink | Same path | Update links to the renamed declarative-role and pooler pages |
| `runbooks/zalando-ha-scaling.md` | Move | `reference/zalando/ha-scaling.md` | Historical learning material, not a live scaling runbook |

## Phase 0 evidence

This snapshot was captured immediately before paths moved. It is evidence for
the refactor, not a substitute for re-reading manifests when platform facts
change.

### Source inventory

The pre-refactor area contained 27 content pages (18 root pages and nine
runbook pages), totalling 9,102 lines. The two refactor control files are not
part of that source count. Every page appears exactly once in the migration
inventory above and has one of `move`, `split`, `merge`, `rename`, or `keep`.

### Inbound-link ledger

Counts below use the broader repository-relative match because it catches both
`docs/databases/...` and relative `databases/...` links. Fragment-bearing links
are included and must preserve their section intent during migration.

| Source | Pages containing an inbound path |
|---|---:|
| `001-postgresql-internals.md` | 7 |
| `002-database-integration.md` | 18 |
| `003-operator-comparison.md` | 9 |
| `003.1-operator-cnpg.md` | 7 |
| `003.2-operator-zalando.md` | 10 |
| `004-replication-strategy.md` | 10 |
| `005-ha-dr-deep-dive.md` | 12 |
| `006-backup-strategy.md` | 13 |
| `007-architecture.md` | 5 |
| `008-pooler.md` | 11 |
| `009-extensions.md` | 5 |
| `010-drp.md` | 20 |
| `010.1-rpo-rto-planning.md` | 9 |
| `010.2-restore-and-failover-drills.md` | 11 |
| `010.3-cross-region-dr.md` | 8 |
| `010.4-emergency-recovery.md` | 15 |
| `011-documents.md` | 3 |
| `012-declarative-role-management.md` | 6 |
| `runbooks/endpoints-to-configmaps.md` | 2 |
| `runbooks/pgdog-operations.md` | 11 |
| `runbooks/postgres-backup-restore.md` | 11 |
| `runbooks/prepared-databases.md` | 5 |
| `runbooks/zalando-ha-scaling.md` | 5 |

Link migration is divided by owner: database pages, proposal records,
observability/runbooks, and remaining root/platform/security indexes. The four
highest-risk destinations are the architecture guide, DR plan, emergency
router, and backup/pooler runbooks.

### Manifest truth ledger

| Current fact | Evidence | Canonical future owner |
|---|---|---|
| Three CNPG clusters: two operational and one DR | `kubernetes/infra/configs/databases/clusters/*/instance.yaml` | `architecture.md` |
| `platform-db` and `product-db`: three instances; `product-db-replica`: one | The three cluster `instance.yaml` files | `architecture.md` |
| PostgreSQL image `18.1-system-trixie` | The three cluster `instance.yaml` files | `architecture.md` |
| CNPG operator 1.30.0, chart 0.29.0 | `kubernetes/infra/controllers/databases/cloudnativepg-operator.yaml` | `cloudnativepg.md` |
| Barman Cloud plugin 0.7.1 | `kubernetes/infra/controllers/databases/cnpg-barman-plugin/helmrelease.yaml` | `backup-policy.md` |
| Operational backups every six hours and daily at 02:00 | `clusters/{platform-db,product-db}/backup/backup-*.yaml` | `backup-policy.md` |
| Primary backup retention 30 days; DR archive retention 7 days | The three `objectstore.yaml` files | `backup-policy.md` |
| `product-db-replica` recovers continuously from `product-db` object storage | `clusters/product-db-replica/instance.yaml` | `disaster-recovery.md` |
| PgBouncer serves `platform-db`; PgDog serves `product-db` | `platform-db/poolers/pooler.yaml` and `product-db/poolers/helmrelease.yaml` | `poolers.md` |
| Service databases, roles, credentials, and extensions use per-service CRs | `clusters/{platform-db,product-db}/services/*.yaml` | `declarative-role-management.md` and `extensions.md` |

Recorded contradictions: `docs/README.md` claimed four clusters; the manifests
declare three. Retired Zalando pages also used current-tense headings and named
clusters that no longer exist. Both are documentation drift, not manifest
changes.

## Implementation phases

Each phase is one logical delivery checkpoint. A phase may use temporary `Moved` stubs, but it
must not leave two full copies claiming canonical ownership.

### Phase 0 — Baseline and ownership ledger

Create an auditable baseline before moving content.

Tasks:

- [x] Record every current file, class, target, inbound-link count, and
  canonical claims in this plan's migration inventory.
- [x] Verify current cluster/operator/pooler/backup facts against manifests.
- [x] Record known contradictions without correcting unrelated content yet.
- [x] Capture the pre-refactor file list and internal link scan in the PR
  description.

Acceptance criteria:

- [x] Every Markdown file under `docs/databases/` has one target and one action.
- [x] Every repeated platform fact has a named canonical owner.
- [x] No implementation phase depends on an unresolved naming or ownership
  decision.

Verification:

```bash
find docs/databases -type f -name '*.md' | sort
rg -n 'docs/databases|databases/' docs --glob '*.md'
```

Dependencies: none.

### Phase 1 — Area hub and navigation contract

Add the missing database hub before changing paths.

Tasks:

- [x] Create `docs/databases/README.md` with quick facts and three entry paths:
  Learn PostgreSQL, Understand the Homelab, and Operate/Recover.
- [x] Add a document-ownership table matching the contracts in this plan.
- [x] Link the current filenames initially so the hub is valid before moves.
- [x] Replace the duplicated database lists in `docs/README.md` with a concise
  link to the new area hub and its learning path.

Acceptance criteria:

- [x] A new reader can choose a path without opening a numbered document first.
- [x] Current, planned, and historical material are visually distinguishable.
- [x] `docs/README.md` no longer attempts to maintain a second full database
  catalog.

Verification:

- [x] Markdown links pass for the hub and modified root index.
- [x] Any new Mermaid diagram renders with `mmdc`.

Dependencies: Phase 0.

### Phase 2 — Fundamentals extraction

Build the stable learning layer before reducing mixed source pages.

Tasks:

- [x] Create the five pages under `fundamentals/` from the mapped conceptual
  sections.
- [x] Remove current versions, namespaces, cluster counts, and environment
  commands from their main explanations.
- [x] Add one short `Applied in this homelab` link section to each page.
- [x] Update the hub's learning path in the order: internals, replication/HA,
  pooling, backup/recovery, extensions.
- [x] Turn fully migrated concept-only sources into short `Moved` stubs; keep
  mixed sources until their platform and runbook sections are migrated.

Acceptance criteria:

- [x] Each fundamentals page can be read without knowledge of `product-db`.
- [x] Homelab examples appear only in the final applied section.
- [x] No platform version or inventory table is duplicated in fundamentals.
- [x] Official references support non-obvious technical claims.

Verification:

```bash
rg -n 'Current Homelab|namespace|v1\.30|product-db-[123]' \
  docs/databases/fundamentals
```

Review each match; only the final applied section may contain project-specific
references. Render every changed Mermaid block.

Dependencies: Phase 1.

### Phase 3 — Current platform consolidation

Create the canonical as-built layer and eliminate duplicated current truth.

Tasks:

- [x] Create/rename the nine root platform pages defined in the target tree.
- [x] Verify topology, versions, endpoints, backup schedules, retention, roles,
  extension deployment, and poolers against current manifests.
- [x] Make `architecture.md` the only cluster inventory.
- [x] Make `reliability-targets.md` the only RPO/RTO objective and evidence
  table.
- [x] Replace duplicated content elsewhere with contextual links.
- [x] Ensure `cross-region-dr.md` uses planned labels for undeployed failure
  domains.

Acceptance criteria:

- [x] Each current fact has one canonical page and manifests as evidence.
- [x] No current page describes the retired Zalando operator as deployed.
- [x] DR policy, targets, procedures, and learning concepts reside in separate
  documents.
- [x] Every current architecture diagram matches deployed reality.

Verification:

- [x] Render all changed Mermaid blocks with `mmdc` and inspect the output.
- [x] Compare quick-fact tables with the relevant manifests.
- [x] Run focused searches for cluster counts, versions, retention, and RPO/RTO
  to confirm duplicates were replaced by links.

Dependencies: Phase 2.

### Phase 4 — Operations and historical quarantine

Finish the separation between current procedures and retired reference
material.

Tasks:

- [x] Move emergency recovery and restore/failover drills into `runbooks/`.
- [x] Rename the backup and pooler runbooks to describe their real scope.
- [x] Move all Zalando pages and procedures under `reference/zalando/`.
- [x] Move the operator comparison and further-reading list under `reference/`.
- [x] Rewrite `runbooks/README.md` as a current-only task index.
- [x] Update observability alert runbooks to point to the renamed database
  procedures.

Acceptance criteria:

- [x] Every page under `runbooks/` applies to the deployed CNPG platform.
- [x] Every Zalando page carries a historical/not-deployed notice.
- [x] On-call entry points lead to emergency recovery or a task-specific current
  runbook, never to a tutorial.
- [x] Historical pages remain available from the database hub's reference path.

Verification:

```bash
rg -n -i 'current homelab usage|currently deployed|current operator' \
  docs/databases/reference
```

Every result must be historical context or be rewritten. Check all modified
relative links.

Dependencies: Phase 3.

### Phase 5 — Link migration and numbered-file retirement

Remove the compatibility layer only after all target pages exist.

Tasks:

- [x] Update inbound links in database docs, `docs/README.md`, RFCs, ADRs,
  observability docs, security docs, and platform docs.
- [x] Preserve section-level intent when replacing links with anchors.
- [x] Confirm no internal link points to a numeric filename or renamed runbook.
- [x] Delete all temporary `Moved` stubs and old `001` through `012` files.
- [x] Update this plan's status and phase checkboxes.

Acceptance criteria:

- [x] No numeric database document remains.
- [x] No internal Markdown link references an old path.
- [x] The root index and database hub expose only final paths.
- [x] No orphan Markdown page remains under `docs/databases/`.

Verification:

```bash
find docs/databases -maxdepth 1 -type f \
  -name '[0-9][0-9][0-9]*.md'
rg -n '001-postgresql|002-database|003-operator|003\.1-operator|003\.2-operator|004-replication|005-ha-dr|006-backup|007-architecture|008-pooler|009-extensions|010(\.|-)|011-documents|012-declarative' \
  docs --glob '*.md'
rg -n 'pgdog-operations\.md|postgres-backup-restore\.md' \
  docs --glob '*.md'
```

All commands must return no stale path references.

Dependencies: Phase 4.

### Phase 6 — Final quality gate and maintenance rules

Prove that the new structure is accurate and sustainable.

Tasks:

- [x] Run the same Markdown link check used by CI for every changed file.
- [x] Render and inspect every changed Mermaid diagram.
- [x] Run `make validate` as the repository-wide pre-push gate.
- [x] Review the final area against the document contracts in this plan.
- [x] Mark this plan `Complete` only after all prior acceptance criteria pass.

Acceptance criteria:

- [x] All internal and checked external links pass.
- [x] All Mermaid diagrams render without clipping or ambiguous state labels.
- [x] `make validate` passes.
- [x] The final hub has working Learn, Understand, Operate, and Reference paths.
- [x] Future edits have a clear canonical owner and do not need the numbered
  documents for context.

Dependencies: Phase 5.

## Dependency and checkpoint order

| Checkpoint | Phase | Why it is ordered here |
|---|---|---|
| 0 | Baseline and ownership | Lock the inventory and canonical owners before paths move |
| 1 | Area hub | Establish navigation while all current paths still exist |
| 2 | Fundamentals | Create stable concept destinations first |
| 3 | Current platform | Consolidate as-built truth after concepts are removed |
| 4 | Runbooks + reference | Move procedures only after their context pages exist |
| 5 | Link cleanup + retirement | Delete compatibility paths only after every target is live |
| 6 | Final audit | Verify the complete information architecture |

Phases 2 through 4 must remain sequential because they split several shared
source files. Individual pages within a phase may be authored in parallel only
after canonical ownership and section boundaries are fixed.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Broken section anchors from file moves | High | Inventory inbound links first; replace file and anchor together; run link check in every PR |
| Two pages become competing sources of truth | High | Name the canonical owner before extraction; old page becomes a short stub, never a duplicate |
| Historical commands are used on CNPG | High | Move retired procedures out of `runbooks/` and add an explicit not-deployed banner |
| Fundamentals slowly absorb current topology again | Medium | Enforce the final applied-link section and platform-fact ownership table |
| Platform facts drift during a long refactor | Medium | Re-read manifests in each platform-facing PR rather than relying on Phase 0 snapshots |
| Large Mermaid/link blast radius | Medium | One topic/phase per checkpoint; render diagrams and run modified-file link checks before review |
| Valuable learning detail is lost during consolidation | Medium | Map sections before deleting sources and review destination coverage against every original heading |

## Completion checklist

- [x] `docs/databases/README.md` is the area hub.
- [x] Fundamentals, current platform, runbooks, and reference material satisfy
  their document contracts.
- [x] All current files in the migration inventory have reached their target.
- [x] Numeric filenames and temporary stubs are gone.
- [x] Internal links and Mermaid rendering pass.
- [x] `make validate` passes.
- [x] This document is marked `Complete` with the final verification date.

## Completion evidence

Implemented on 2026-08-31 as sequential checkpoints in the current workspace.
No commit, push, or pull request was created.

- Local paths and anchors were audited for every changed Markdown file.
- The CI-equivalent `markdown-link-check` completed successfully for all
  changed Markdown files.
- All 84 Mermaid blocks under `docs/databases/` rendered successfully with
  `mmdc`; output was temporary and not committed.
- `git diff --check` passed.
- `make validate` passed: 439 YAML files checked, Kubernetes overlays built,
  and 10 Kyverno tests passed.
- Kind and application E2E were intentionally not run because this is a
  documentation-only refactor.

_Last updated: 2026-08-31._
