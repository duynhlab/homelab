# RFC-0021 — Cutover rollback story

Answers the phase-0 gate question: **"If inventory deploys broken, how does the
platform get back to product?"** — per cutover, with the commands that flip it.
Written as the phase-0 seed for RUNBOOK-007; it became the **as-executed record** of
every cutover in this RFC, including the two gate decisions, three measured traps, and
the evidence that closed the irreversible steps.

| | |
|---|---|
| **Status** | as-executed; every cutover in this RFC has run. The flag-flip commands are kept as the historical record — the flags themselves were deleted in phase 4 |
| **⚠️ Worker section is HISTORICAL** | § [Worker version activation](#worker-version-activation-phase-3-before-the-write-cutover) describes a model **deleted** by [ADR-054](../../adr/ADR-054-temporal-worker-controller/). Do not follow it. See the banner in that section |
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

> ### ⚠️ HISTORICAL — do not follow this section
>
> Everything below records how phase 3 was executed in July 2026 and is kept as
> evidence. It describes a model that
> [ADR-054](../../adr/ADR-054-temporal-worker-controller/) **deleted** on
> 2026-08-21. Following it now does damage, in three specific ways:
>
> - **`order-worker.yaml` no longer means what it means here.** In this section it
>   is the *unversioned* worker, and step 4 says to delete it. That filename is now
>   the **single live `Connection` + `WorkerDeployment`** — deleting it removes the
>   versioned worker entirely.
> - **The activation Job does not exist.** `temporal-worker-set-current-version`
>   was deleted; the controller is the only writer of the Current version, and a
>   hand-run `set-current-version` competes with it.
> - **There is no per-build file.** A release is one line: the image tag in
>   `kubernetes/apps/order-worker.yaml`.
>
> Current procedure:
> [`application-delivery.md` § Releasing the order worker](../../../platform/application-delivery.md#releasing-the-order-worker).
> Incident diagnosis:
> [`OrderSagaNotCompleting`](../../../observability/runbooks/microservices/OrderSagaNotCompleting.md).

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

   **The activation Job must run AFTER the worker registers, not after it is Ready.**
   On a freshly created cluster the Worker Deployment does not exist until a worker
   has polled the task queue and registered its version, and `set-current-version`
   run before that fails with a message that points nowhere near the cause:

   ```
   Error: unable to get deployment conflict token: context deadline exceeded
   ```

   Measured 2026-08-06: the Job failed when instantiated ~80 s after the worker pod
   went Ready, and succeeded on the next attempt once
   `temporal worker deployment list` showed `order-fulfillment`. So gate the Job on
   the deployment existing, not on the pod:

   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal worker deployment list --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233
   # only once order-fulfillment is listed:
   kubectl -n temporal create job activate-$(date +%s) \
     --from=cronjob/temporal-worker-set-current-version
   ```

   A fresh cluster has **no** `currentVersionBuildID`, so this step is mandatory
   there rather than optional — versioned workers receive nothing until it runs.

   **READ THIS BEFORE TRUSTING A ZERO FROM ANY VERSION QUERY.** The search
   attribute and `temporal worker deployment describe` print the *same value in two
   different formats*, and the wrong one returns **0 instead of an error**:

   | Where you read it | Format |
   |---|---|
   | `describe` output (`versioningInfo.version`) | `order-fulfillment` **`.`** `1.13.0` |
   | `TemporalWorkerDeploymentVersion` search attribute | `order-fulfillment` **`:`** `1.13.0` |

   Measured on the local cluster with one workflow known (via `describe`) to be
   pinned to `1.13.0`:

   ```
   --query "TemporalWorkerDeploymentVersion='order-fulfillment:1.13.0'"  -> Total: 1   # correct
   --query "TemporalWorkerDeploymentVersion='order-fulfillment.1.13.0'"  -> Total: 0   # WRONG, and silent
   ```

   So an operator who copies the format from the neighbouring CLI output gets a
   confident zero and deletes a worker manifest that was still serving pinned
   histories — stranding sagas that hold stock and an authorization. Always use the
   **colon** form, and sanity-check the query by running it against the CURRENT
   build first: if that returns 0 too, the query is wrong, not the drain.

   `DrainageStatus: unspecified` is not evidence either. A build that never received
   work has nothing for Temporal to compute drainage from, so it stays `unspecified`
   forever — including on a freshly recreated cluster where the old builds ran once
   in a rollout and never took a workflow.
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
starts → drain → final delta backfill → verify ATP → flip → resume). The flip
is not done when the PR merges — it is done when the ORDER POD RENDERS IT:
after merge, `make sync` (publish the apps artifact + reconcile), wait for the
order rollout, and verify before resuming starts:

```bash
kubectl -n order get deploy order \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ORDER_STOCK_PARTICIPANT")].value}'
```

Resuming against an unverified render is how new sagas keep writing Product
after the final delta backfill — silently, since `product` is also the code
default.

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
rollback; the gates make it unnecessary, and each one is a MEASUREMENT, not an
assumption:

1. **Deprecation telemetry at zero for ≥ 2 weeks.** ⚠️ **WAIVED 2026-08-05 —
   see below.** As designed:
   `product_stock_surface_calls_total{rpc}` counts every hit on the surface
   being removed (`ReserveStock`, `ReleaseStock`). The clock starts when the
   counter is DEPLOYED, not when it is merged — the third
   merged-but-never-released lesson of phase 3 applies to instruments too.
   ```promql
   sum by (rpc) (increase(product_stock_surface_calls_total[14d]))
   ```

   > **Waiver, owner decision, 2026-08-05.** The instrument was deployed
   > 2026-07-31, so this window would have closed 2026-08-14. The owner chose
   > code evidence instead and accepted losing the safety net for an
   > unforeseen caller: the order saga's product branch is deleted in order
   > **1.13.0** (Current on the cluster, with no `productv1` client left at
   > all), checkout reads availability from inventory at canary 100%, and a
   > sweep of all repositories found no other reference.
   >
   > **The instrument is removed with the RPCs**, so this gate cannot be
   > checked retroactively: the query above now returns *empty*, and empty is
   > indistinguishable from zero on a dashboard. Do not read a flat panel as
   > evidence that the gate passed — it was waived, and this note is the
   > record. The remaining detection channel is `Unimplemented` replies, which
   > `grpcx` logs at error level, and only after something has already broken.
2. **Open workflows on the product branch = 0, and namespace retention (7 d)
   expired since the last one closed** — nothing left that could replay onto
   the branch being deleted. Still required, and phase 4 changed what happens
   if it is not met: order 1.13.0 **refuses** a product-participant history
   rather than running it, so such a saga stalls with its stock held instead
   of taking the wrong branch. The 1.12.x worker build must therefore keep
   polling until those histories drain — see the build manifests under
   `kubernetes/apps/`.
   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal workflow count --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233 \
       --query "TaskQueue='order-fulfillment' AND ExecutionStatus='Running' AND TemporalWorkerDeploymentVersion IS NULL"
   ```
   (product-path sagas predate versioning or run pinned to a pre-removal
   build; the removal itself ships as a NEW Worker Deployment Version, so old
   pinned histories keep their branch until drained.)
   **Deleting an old worker manifest — the falsifiable criterion.** "DRAINED" is
   not always observable (see above), so the check that actually holds is all four
   of these, in this order:

   1. `routingConfig.currentVersionBuildID` is a NEWER build than the one being
      deleted;
   2. `TemporalWorkerDeploymentVersion='<deployment>:<build>'` (**colon**) counts
      **0** across every status, not just Running — a closed workflow can still be
      queried, reset, or replayed against its pinned build;
   3. the same query against the *current* build returns non-zero, proving the
      query itself works;
   4. zero Running workflows on the task queue.

   **Satisfied 2026-08-06 for `1.10.0` and `1.12.0`**, and both manifests were
   removed on that evidence rather than on tidiness: Current is `1.13.0`, the colon
   query returns 0 for both and 1 for `1.13.0`, and the task queue has no Running
   workflows. Keeping them was not neutral — every build runs the fulfillment start
   outbox dispatcher, so a draining build can claim a row and start a saga that
   Current **refuses** (measured on Kind during P4-A: `1-12-0` claimed the row and
   closed it `DISPATCHED` while `1.13.0` panicked its task ten times unwatched).
   `ORDER_START_DISPATCHERS_ENABLED` (order `main`, post-`v1.13.0`) can silence that
   for future draining builds, but it cannot help images that predate the flag —
   for `1.10.0` and `1.12.0` deletion was the only mitigation.

3. **Staged schema drop with a backup + restore test first**, and the
   temporary backfill access (pg_hba `host product inventory` + the migration
   `000005` GRANT) revoked in the same wave.

   **SATISFIED 2026-08-05, with evidence** — unlike gate 1, this one was met
   rather than waived. Product migration `000006` cannot verify a backup from
   SQL, so the gate is a manual pre-step and the test was run end to end on
   local-stack before the migration was proposed:

   | Step | Command | Result |
   |------|---------|--------|
   | backup | `pg_dump -U postgres -d product -Fc > product-pre-000006.dump` | 12 KB dump |
   | up | the service's own `migrate` subcommand | `schema_migrations` 5 → 6 clean; column and `stock_reservations` gone |
   | down | the paired `.down.sql` applied by hand | column + `CHECK` + table + PK + index back, **every value 0**, ledger empty — shape only, as documented |
   | restore | `pg_restore` into a scratch database | `stock_quantity` 50/30/25/40 again, version 5 — **the backup is the data rollback** |
   | re-apply | `migrate` again | 5 → 6 clean |

   The revoke was probed separately, because the original claim was wrong: only
   `REVOKE SELECT` has effect, since Postgres grants `CONNECT`/`TEMPORARY` and
   schema `USAGE` to PUBLIC by default (measured: `connect=t usage=t select=f`
   after the revoke). **The pg_hba line is the boundary**, which is why removing
   it is part of the same wave rather than a follow-up. The migration also now
   refuses to drop while any undocumented role still holds `SELECT` on
   `products` — proven in both directions, including the recovery from the
   resulting dirty state.

   Before running it in the cluster: take the dump against `product-db-rw`, keep
   it outside the cluster, and confirm the restore into a scratch database — a
   backup nobody has restored is a hypothesis.

---
_Last updated: 2026-08-06_
