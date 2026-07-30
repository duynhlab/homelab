# RFC-0021 — Cutover rollback story

Answers the phase-0 gate question: **"If inventory deploys broken, how does the
platform get back to product?"** — per cutover, with the commands that flip it.
This is the seed for RUNBOOK-007 (written in full at phase 3).

| | |
|---|---|
| **Status** | phase-0 deliverable; commands become executable as the flags land |
| **Owning RFC** | [README.md](./README.md) § Rollout & rollback |

## Phase 2 prep (backfill + structural shadow) — nothing to roll back

Phase 2 does **not** change the read authority. Checkout keeps reading
availability from Product; Inventory is only *observed* via structural shadow
reads (`CHECKOUT_AVAILABILITY_SOURCE=shadow`) and populated once by the backfill
below. The flip to Inventory reads is a **phase-3** step (next section) — it waits
for the write cutover, because Inventory reflects real-time stock only after it
starts taking live writes. Rolling back phase 2 is trivial: set the flag back to
`product` (shadow stops); no data moved, nothing to reconcile.

### Backfill (one-shot, drained window)

Inventory balances are populated once from product stock by the `inventory`
image's `backfill` subcommand, shipped as a **suspended CronJob template**
(`kubernetes/apps/inventory-backfill-cronjob.yaml`) — never scheduled. Run it
manually inside the (drained) window:

```bash
kubectl -n inventory create job inventory-backfill-$(date +%s) \
  --from=cronjob/inventory-backfill
kubectl -n inventory logs -f job/inventory-backfill-<id>   # inspect the report
```

- **Prerequisites:** the pg_hba `host product inventory` line on product-db and
  `GRANT SELECT ON products` to the `inventory` role (product-service migration
  `000005`) — both temporary, revoked at Phase 4/7 contraction.
- **Safety:** the backfill refuses a non-empty `inventory_balances` (no
  overwrite path) and reads product read-only; a zero-row read fails loud. To
  redo, truncate `inventory_balances` + its backfill movements and re-run.
- **Rollback:** nothing to undo — Product still owns writes; delete the balances
  if abandoning.

## Worker version activation (phase 3, before the write cutover)

ADR-030 versions the saga with Worker Deployment Versions. The manifests ship the
versioned worker **side by side** with the unversioned one — never as an in-place
env flip, which registers the deployment with **no Current version and zero task
flow** (verified live: new workflows hang with no error anywhere). Activation is a
deliberate operator step, in this order:

1. **Merge lands the versioned worker inert.** `order-worker-1-8-0` polls as
   `order-fulfillment` build `1.8.0` and receives nothing. Verify it joined:
   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal worker deployment describe --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233 \
       --name order-fulfillment
   ```
   Expect the version listed with pollers and **no Current** set. The unversioned
   worker keeps serving everything.
2. **Activate** — the one atomic step. Instantiate the suspended CronJob template
   (instantiate, never resume: Flux owns the template, and its schedule is an
   impossible date precisely so nothing but this command can run it):
   ```bash
   kubectl -n temporal create job order-set-current-$(date +%s) \
     --from=cronjob/temporal-worker-set-current-version
   ```
   From this moment new workflows start **pinned** to `1.8.0`; the unversioned
   worker only drains what it already owns. `temporal worker deployment
   set-ramping-version` exists for a percentage ramp if wanted — the CronJob sets
   Current outright, which is proportionate to this platform's volume.
3. **Watch the drain.** Sagas run seconds-to-minutes, so the unversioned side
   empties fast. The unversioned worker never appears as a version row in
   `describe`, so its drain gate is the visibility count (query verified live):
   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal workflow count --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233 \
       --query "TaskQueue='order-fulfillment' AND ExecutionStatus='Running' AND TemporalWorkerDeploymentVersion IS NULL"
   ```
   `OrderSagaNotCompleting` is the backstop for an activation that routed to a
   version nobody serves.
4. **Retire when that count reads 0, in its own PR.** Delete `order-worker.yaml`
   (the unversioned worker) and flip `ORDER_RECONCILER_ENABLED` to `"true"` on
   the versioned worker **in the same change** — one reconciler judge at all
   times, never zero, never two. The flux-validate guard treats the unversioned
   file as optional and discovers versioned files by glob, so neither this PR nor
   the next release edits the guard. Versioned→versioned cycles later DO get the
   `DRAINED` state in `describe`; this visibility query is the unversioned-era
   substitute.
5. **Rollback:** point Current back at pollers that exist. Back to a previous
   *versioned* build → the CronJob template (its `--build-id` is guarded against
   the deployed manifest). Back to the *unversioned* worker — the only fallback
   in this first window — the flag is `--unversioned`, via the raw CLI in the
   [OrderSagaNotCompleting runbook](../../../observability/runbooks/microservices/OrderSagaNotCompleting.md).
   Workflows stuck on their first task are not yet pinned and re-route; never
   delete a worker Deployment whose version still shows open workflows.

The next release repeats the cycle with a new `order-worker-<build>.yaml`: land
inert → activate → drain → retire the previous file.

## Write cutover (phase 3) — flag-stops-the-bleeding, then fix forward

The saga's stock participant is `ORDER_STOCK_PARTICIPANT`
(`product|inventory`). The flip happens inside a controlled window (pause
starts → drain → final delta backfill → verify ATP → flip → resume).

- **Before any new workflow has taken the inventory branch:** revert the flag;
  new workflows take the product path; nothing to reconcile. This is the only
  window where "rollback" is symmetric.
- **After inventory has taken live writes:** the flag revert only stops *new*
  workflows from using inventory — it must **not** be treated as a data
  rollback, because Product's stock columns are stale from the moment
  inventory accepted its first write.
  1. Flip `ORDER_STOCK_PARTICIPANT=product` to stop new inventory-branch
     workflows (only if Product data was kept authoritative per the cutover
     design — otherwise skip and fix forward).
  2. Keep the deployed worker: it must retain **both** workflow branches;
     in-flight inventory-version histories drain on the inventory path
     (`workflow.GetVersion` markers are one-way — never revert worker code to
     a build without the branch).
  3. Reconcile: either replay inventory movements back onto Product stock
     (only for a short-lived cutover that failed immediately), or — the
     default stance — **fix forward**: repair inventory and re-flip, because
     re-establishing Product as authority after divergence is the riskier
     migration.
- **Verify:** zero `RESERVED`-stuck reservations for drained workflows
  (reconciler report), order confirm rate at baseline, no negative-ATP alert.

### Read flip (after the write cutover) — reversible by flag, minutes

Only once Inventory is live-written and stable do we move checkout's *read*
authority. The availability read source is `CHECKOUT_AVAILABILITY_SOURCE`
(`product|shadow|inventory`, startup-validated via `pkg/flagx`), stepped
`shadow → canary → inventory`.

- **Trigger to roll back:** checkout confirm error-budget burn, Inventory latency
  breaching the deadline budget, or shadow/canary mismatch during the ramp.
- **Action:** revert the flag on `kubernetes/apps/services/checkout.yaml` to
  `shadow` (keep measuring) or `product` via a one-line PR; `make flux-sync`; pods
  pick it up on rollout restart — minutes.
- **Safety:** a read flip moves no data — `GetProducts` stays a live fallback, so
  reverting the read flag is always safe and needs no reconciliation (independent
  of the write-path rollback above).
- **Verify:** confirm success rate at baseline (CP-0 dashboard);
  `inventory_shadow_compare_total` keeps flowing while on `shadow`.

## Contract removal (phase 4) — not reversible, gated so it never needs to be

Dropping `stock_quantity`/`stock_reservations` and the stock RPCs has no
rollback; the gates make it unnecessary: deprecation telemetry at zero for
≥2 weeks, open-workflow count on the old branch = 0 + retention expired,
staged schema drop with backup + restore test first.

---
_Last updated: 2026-07-27_
