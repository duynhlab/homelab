# ADR-030: Version the order saga with `workflow.GetVersion`; Worker Versioning is the target

Use `workflow.GetVersion` patching (change ID `inventory-extraction-v1`) plus a
participant field pinned in the workflow input for the RFC-0021 phase-3 stock
migration; adopt Temporal Worker Versioning later, once the platform can run a
server that supports it.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-27 | [RFC-0021](../../rfc/RFC-0021/) | [RFC-0021 research.md](../../rfc/RFC-0021/research.md) |

## Context

RFC-0021 phase 3 moves the order saga's stock writes from product-service to
inventory-service. `OrderFulfillmentWorkflow` histories in flight at the moment
the new worker deploys **must replay exactly the old call graph** (Product
`ReserveStock`/`ReleaseStock`, no `CommitInventory`), while new workflows take
the Inventory path. Temporal offers two sanctioned mechanisms:

- **Worker Versioning** (Worker Deployment Versions / Build IDs) — the approach
  official docs recommend for production rollouts: whole worker deployments are
  versioned and the server routes each workflow to a compatible build.
- **Patching (`workflow.GetVersion`)** — an in-workflow marker: the first
  execution records a version in history; replays read it back, so one worker
  binary serves both call graphs deterministically.

The platform constraint is decisive and was verified against current docs
(Context7, 2026-07-27): Worker Versioning requires **Temporal Server ≥ 1.29.1**
(Go SDK ≥ 1.35, CLI ≥ 1.4.1). The platform runs server **1.24.2** managed by the
alexandrevilain temporal-operator, whose compatibility matrix — including its
latest release — supports Temporal **1.18.x–1.28.x** only. Worker Versioning is
therefore **hard-blocked upstream** today: no operator version can run a 1.29
server. (Upstream is moving: operator PR #987 adds 1.29 support.)

A third, tempting-but-wrong option exists because the saga calls activities by
method identity on a shared struct: silently repointing `Activities.Product` at
inventory-service would keep activity *names* identical, so old histories would
replay "green" while actually executing against a different stock authority
mid-flight — a correctness trap, not a migration.

## Decision

**Now (phase 3):** version the workflow with **`workflow.GetVersion`**:

- One marker at the top of `OrderFulfillmentWorkflow`:
  `workflow.GetVersion(ctx, "inventory-extraction-v1", workflow.DefaultVersion, 1)`.
- A new optional input field `StockParticipant` (`""`/`"product"` | `"inventory"`),
  stamped **at start time** by the order API from `ORDER_STOCK_PARTICIPANT`
  (flagx enum, default `product`) in the single `fulfillment.Start` seam. The
  worker never reads the flag — its behavior is input-driven, so the participant
  is **pinned per workflow**: a flag revert only redirects *new* workflows; a
  workflow that reserved in Inventory always compensates/commits in Inventory.
- The Inventory branch uses **new activities** (`ReserveInventory`,
  `ReleaseInventory`, `CommitInventory`); the Product branch stays byte-for-byte
  today's call graph. `Activities.Product` is never repointed.
- The two mechanisms split responsibilities: `GetVersion` protects **history
  compatibility** (an old binary that picks up a v1 history fails the workflow
  task loudly and Temporal retries it onto a capable worker — corruption becomes
  retry); the input field selects the branch for **new** workflows.
- A replay-test corpus (real exported histories in `internal/saga/testdata/`)
  lands **before** any workflow change and gates every later saga PR.

**Later (target):** adopt **Worker Versioning** when it becomes runnable here.
To keep that path warm without betting the migration on upstream timing, the
platform keeps the temporal-operator as-is and **stages the official
`temporalio/helm-charts` deployment alongside it, fully commented out — never
deployed** (`kubernetes/infra/controllers/temporal/`). **Revisit triggers:**
temporal-operator releases 1.29 support (PR #987) *or* the staged official chart
is promoted; either unlocks server ≥ 1.29.1 and reopens this decision.

## Alternatives considered

- **Worker Versioning now.** Pros: official production recommendation; clean
  build routing; no in-code markers. Cons: **infeasible** — requires server
  ≥ 1.29.1; the operator (any version) caps at 1.28.x; adopting it would mean
  abandoning the operator (losing `TemporalNamespace`/CRD conveniences) and a
  self-managed migration project before any phase-3 work. Rejected for now,
  recorded as the target.
- **Repoint `Activities.Product` at inventory (no versioning).** Pros: smallest
  diff. Cons: silently changes the stock authority of in-flight sagas — replays
  look deterministic while the side effects moved; compensation could release on
  a service that never reserved. Rejected as a correctness trap.
- **Input-field branching only (no `GetVersion`).** Pros: one mechanism. Cons:
  no protection against rolling-deploy skew or an accidental worker rollback to
  a binary without the branch — an old binary would replay a v1 history down the
  product path *silently*. The marker makes that failure loud. Rejected.
- **Replace the operator with the official helm chart now.** Pros: unlocks
  1.29+. Cons: a standalone infra migration (datastore, namespace, TLS, CRD
  conveniences lost) gating the entire write path on it. Rejected; staged
  commented-out instead.

## Consequences

- One worker binary carries **both branches** until the phase-4 gates (old-path
  telemetry zero + open-workflow count zero + retention expired) — removing the
  `DefaultVersion` branch earlier would strand replayable histories. The
  `GetVersion` marker is one-way: never deploy a worker build without both
  branches (encoded in RUNBOOK-007).
- Deploy order is a hard rule: the v1-capable worker rolls out **before** any
  manifest sets `ORDER_STOCK_PARTICIPANT=inventory`.
- The replay corpus becomes a standing merge gate for `internal/saga` — a small
  ongoing cost that pays for itself at every worker deploy.
- The staged official chart is inert (commented out, not in any kustomization);
  it documents the upgrade path at zero runtime cost, but is one more artifact
  to keep loosely in sync.
- **Trade-off accepted:** `GetVersion` markers accumulate in workflow code and
  each future migration adds another; Worker Versioning would centralize this.
  That debt is bounded (this is the platform's first marker) and the exit path
  is recorded above.

---

_Last updated: 2026-07-27_
