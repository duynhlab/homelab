# ADR-030: Adopt Temporal Worker Versioning; re-platform onto the official Temporal chart

Version the order saga with **Temporal Worker Versioning** (Worker Deployment
Versions), and replace the alexandrevilain temporal-operator with the **official
`temporalio/helm-charts`** release so the cluster can run the server version
Worker Versioning requires.

| Status | Date | Related RFC | Related research |
|--------|------|-------------|------------------|
| Accepted | 2026-07-28 | [RFC-0021](../../rfc/RFC-0021/) | [RFC-0021 research.md](../../rfc/RFC-0021/research.md) |

> Supersedes the deployment half of
> [ADR-002](../ADR-002-deploy-temporal-via-operator/) (deploy Temporal via the
> alexandrevilain operator). ADR-001 (adopt Temporal) stands unchanged.

## Context

RFC-0021 phase 3 moves the order saga's stock writes from product-service to
inventory-service. Workflows already in flight when the new worker rolls out
**must keep executing the old call graph** (Product `ReserveStock`/`ReleaseStock`,
no `CommitInventory`), while new workflows take the Inventory path. Temporal
offers two sanctioned mechanisms:

- **Worker Versioning** — Worker Deployment Versions: each worker build declares
  a deployment name + build ID, the server pins every workflow to the version
  that started it, and routes its tasks only to workers of that version. The
  workflow code carries no migration branches.
- **Patching (`workflow.GetVersion`)** — an in-workflow marker recorded in
  history; one binary serves both call graphs, and the branch stays in the code
  until every old history has drained.

Worker Versioning is what current Temporal docs recommend for production
rollouts. Its floor (verified 2026-07-27; re-platform decided 2026-07-28): **server ≥ 1.29.1**, Go SDK ≥ 1.35
(platform is on 1.44/1.45 ✔), CLI ≥ 1.4.1, UI ≥ 2.38.

The blocker was the deployment stack, not the SDK: the platform ran Temporal
**1.24.2** under the alexandrevilain temporal-operator, whose compatibility
matrix — including its latest release — supports **1.18.x–1.28.x** only. No
operator version can run a 1.29+ server, so Worker Versioning was unreachable
while the operator owned the deployment. Meanwhile the official
`temporalio/helm-charts` chart 1.6.0 ships server **1.31.2**.

A third, tempting-but-wrong option exists because the saga calls activities by
method identity on a shared struct: silently repointing `Activities.Product` at
inventory-service would keep activity *names* identical, so old histories would
replay "green" while actually executing against a different stock authority
mid-flight — a correctness trap, not a migration.

## Decision

**Re-platform Temporal onto the official chart, then version with Worker
Versioning.**

1. **Deployment.** `kubernetes/infra/configs/temporal/helmrelease.yaml` runs the
   official chart (pinned `1.6.0`, server 1.31.2). The operator HelmRelease and
   the `TemporalCluster`/`TemporalNamespace` CRs are commented out in place
   (`controllers/temporal/`, `configs/temporal/cluster.yaml`, `namespace.yaml`)
   so a rollback has the exact prior manifests (the data half of a rollback is a
   PITR — see Consequences). Carried over unchanged: persistence
   on the CNPG `platform-db` (`temporal` + `temporal_visibility`, pre-created by
   postInitSQL, `createDatabase: false` because the role has no CREATEDB),
   `numHistoryShards: 512`, the `platform-db-temporal-secret` ESO secret, and —
   critically — the Service name **`temporal-frontend`**, so every service's
   `TEMPORAL_HOSTPORT` is untouched. The `mop` namespace moves from the retired
   CRD to the chart's namespace Job (same 168h retention); the Web UI Service
   becomes `temporal-web` (ingress updated). `schema.useHelmHooks: false` because
   Flux does not reconcile Helm hooks.
2. **Versioning.** Worker builds declare a Worker Deployment Version
   (`pkg/temporalx` gains the options; consumers opt in by env). The stock-write
   migration ships as a new build: existing workflows stay pinned to the old
   version and drain there, new workflows start on the new version and take the
   Inventory path. Two worker deployments run side by side during the cutover
   window until the old version has no open workflows.
3. **Participant stays pinned in the workflow input.** `ORDER_STOCK_PARTICIPANT`
   (flagx enum, default `product`) is read by the order **API** and stamped into
   the workflow input at the single `fulfillment.Start` seam. The worker never
   reads the flag, so a flag revert only redirects *new* workflows — a workflow
   that reserved in Inventory always compensates/commits in Inventory.
4. **New activity names.** The Inventory branch calls `ReserveInventory`,
   `ReleaseInventory`, `CommitInventory`. `Activities.Product` is never
   repointed.
5. **The replay corpus stays.** Real exported histories in
   `order-service/internal/saga/testdata/` are replayed by `go test` on every
   saga change. Worker Versioning protects *running* workflows; the corpus is the
   pre-merge check that a change is history-compatible at all, and the safety net
   if a build ever ships unversioned.

## Alternatives considered

- **`workflow.GetVersion` patching (with the operator kept).** Pros: no
  infrastructure change; smallest blast radius; the mechanism was already
  designed for this migration. Cons: keeps the platform on a server line that
  cannot do Worker Versioning at all, so *every* future workflow migration pays
  the marker tax; markers accumulate in workflow code and can only be removed
  after full history drain. Rejected once the re-platform put Worker Versioning
  in reach — the owner chose to unblock the mechanism rather than work around it.
- **Keep the operator, wait for upstream 1.29 support**
  (alexandrevilain/temporal-operator#987). Pros: no migration work; keeps the
  `TemporalNamespace`/CRD conveniences. Cons: blocks phase 3 on an unmerged
  upstream PR with no timeline. Rejected.
- **Repoint `Activities.Product` at inventory (no versioning at all).** Pros:
  smallest diff. Cons: silently changes the stock authority of in-flight sagas —
  replays look deterministic while the side effects moved, and compensation could
  release against a service that never reserved. Rejected as a correctness trap.
- **Official chart's bundled Postgres.** Rejected: every other database on the
  platform is CNPG-managed with Barman backups; a chart-bundled Postgres would be
  an unmanaged exception.

## Consequences

- **Lost with the operator:** the `TemporalCluster`/`TemporalNamespace` CRDs and
  their reconciliation, the cert-manager-backed admission webhook (and the
  `cert-manager-local` dependency it forced), and CRD-based Flux health checks.
  Temporal health is now the HelmRelease plus the frontend Deployment;
  helm-controller waits for release resources by default, so a Ready HelmRelease
  also means the namespace Job completed — preserving the ordering guarantee
  `apps-local` relied on (the order worker dials namespace `mop` at startup).
- **Gained:** server 1.31.2 (Worker Versioning capable), upstream-supported
  chart, no webhook to keep alive, and namespace/search-attribute management
  through chart values instead of a CRD.
- **Migration cost:** search attributes (RFC-0021 P3) must now be registered via
  chart values or an admin-tools job rather than `customSearchAttributes` on the
  CRD; `pkg/temporalx` must grow versioning options (cross-cutting — every
  service that runs a worker consumes it) and needs a new release.
- **Operationally heavier cutover than a marker:** Worker Versioning means
  running two worker deployments during the window and watching the old version
  drain, instead of one binary with a branch. That is the trade accepted for a
  mechanism that does not leave residue in workflow code.
- **Data note:** the Kind cluster is rebuilt per `make up`, so the re-platform
  lands as a fresh install against the pre-created databases; there is no
  1.24→1.31 in-place history migration to prove. A long-lived cluster would need
  a sequential server-version upgrade path instead — recorded here so nobody
  assumes this jump is generally safe.
- **Prune order matters on a LIVE cluster.** Applying this change to a cluster
  that is already running the operator means Flux prunes both the `TemporalCluster`
  /`TemporalNamespace` CRs and the operator that reconciles them. If the operator
  goes first, CR deletion can hang on its finalizers with no controller left to
  clear them, stalling the Kustomization. On such a cluster, delete the CRs
  **while the operator is still running**, then apply. The platform's Kind cluster
  is rebuilt per `make up`, so the practical path here is a fresh install with
  nothing to prune (verified: no Kind cluster exists at the time of this change).
- **Verification is deferred:** Temporal is not running on a live cluster right
  now, so this ADR's manifests are proven by `helm template` + `make validate`
  only. First live proof comes at the next `make up` (the RFC-0021 final
  acceptance audit).

---

**Rollback is not manifest-only.** Un-commenting the operator manifests restores
the control plane, but the chart's schema job upgrades `temporal` +
`temporal_visibility` to the 1.31.2 schema, which a 1.24.2 server cannot read. A
genuine rollback therefore needs a `platform-db` point-in-time restore of both
databases to a pre-upgrade timestamp, then the manifest revert — in that order.

**Revision note (same day).** This ADR first recorded the opposite decision:
`GetVersion` patching, operator retained, official chart staged commented-out as
a future path — because Worker Versioning looked hard-blocked upstream. The owner
then chose to remove the block by re-platforming onto the official chart, so the
decision was rewritten in place before any implementation landed. The superseded
staging artifact (`controllers/temporal/official-chart-staged.yaml`) is deleted;
the operator manifests remain commented out for rollback.

---

## History

| Date | Change |
|------|--------|
| 2026-07-28 | Accepted; re-platform + Worker Versioning decided (see the revision note above). |
| 2026-07-29 | **Placement corrected and the retired manifests deleted.** The chart was first added under `configs/temporal/`, co-located with the operator CRs it replaced. That is the wrong half of the tree: `controllers/` holds platform components installed by a chart (Kong, Valkey, OpenBAO, Vector, Jaeger — 26 HelmReleases) and `configs/` holds the CRs and configuration they consume. It also left two files named `helmrelease.yaml`, one live and one dead. The chart now lives at `controllers/temporal/helmrelease.yaml`, applied by the single `temporal-local` Kustomization — excluded from the controllers umbrella exactly as `kong-local` is, because it needs a database and CRDs the umbrella cannot order. Its two satellite objects went to the homes their object types already have rather than into a Temporal-specific Kustomization: the Web UI route joined `configs/kong/ingress-infra.yaml` alongside every other infra UI, and the alerts became one more directory under `configs/observability/metrics/prometheusrules/`. Both had been the platform's ONLY exceptions of their kind — the alert catalog had to spell the rule one out to stay accurate. Net effect: one fewer Kustomization than before this change, not one more. This supersedes the Consequences note that the operator manifests are "commented out in place for rollback": they are deleted, because git already holds them and a genuine rollback needs the `platform-db` PITR described above regardless. Also added both temporal paths to `scripts/flux-validate.sh`, which had been validating neither. |

---

_Last updated: 2026-07-29_
