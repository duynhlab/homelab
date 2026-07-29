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

### Worker Versioning — the other half of the same cutover

The flag decides which *branch* a new workflow takes; Worker Versioning decides
which *worker build* serves it ([ADR-030](../../adr/ADR-030-temporal-workflow-versioning/)).
Worker Deployment **`order-fulfillment`**, Build ID = the order-worker image tag
(`1.7.0` today) — `TEMPORAL_WORKER_DEPLOYMENT_NAME` / `TEMPORAL_WORKER_BUILD_ID` in
`kubernetes/apps/order-worker.yaml`, kept equal to `image.tag` by `make validate`.

**Not yet exercised anywhere:** no versioned worker has polled a cluster, so
`list` returns an empty table and there is no Current version yet.

Order is not negotiable — **deploy the build, confirm it polls, then make it
Current.** `set-current-version` fails by default until a worker of that version
has polled (CLI 1.7.3: `no Worker Deployment found with name 'order-fulfillment';
does your Worker Deployment have pollers?`).

1. **Deploy the build.** Bump `image.tag` and `TEMPORAL_WORKER_BUILD_ID` together
   (`make validate` rejects a drift), `make flux-sync`, wait for the rollout.
2. **Confirm the version registered:**
   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal worker deployment list --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233
   ```
3. **Make it Current** — new workflows start on it. The suspended CronJob
   (`kubernetes/infra/controllers/temporal/worker-set-current-version-cronjob.yaml`)
   already carries the deployed tag and `--yes`:
   ```bash
   kubectl -n temporal create job order-set-current-<tag>-$(date +%s) \
     --from=cronjob/temporal-worker-set-current-version
   ```
4. **Verify** (`describe` takes `--name`; only `set-current-version` takes
   `--deployment-name`):
   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal worker deployment describe --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233 \
       --name order-fulfillment
   ```

**Ramp instead of a hard switch.** `set-ramping-version` sends a percentage of new
workflows to the new version — same flags plus `--percentage` (float, 0–100) and
`--delete` to remove the ramp. `--percentage 100` is *not* a substitute for
`set-current-version`.

```bash
kubectl -n temporal exec deploy/temporal-admintools -- \
  temporal worker deployment set-ramping-version --namespace mop \
    --address temporal-frontend.temporal.svc.cluster.local:7233 \
    --deployment-name order-fulfillment --build-id <tag> --percentage 10 --yes
```

`--yes` is required on both commands: without it the CLI prompts, and a pod with
no TTY hangs until `activeDeadlineSeconds`.

- **Rollback = point Current back, and it moves nothing in flight.** Previous
  versions stay registered, and each workflow is **pinned** to the version that
  started it. Setting Current back only redirects *new* workflows; in-flight ones
  keep draining on the old version — which is why two worker deployments coexist
  for the whole window.
- **Rolling back cannot use the CronJob** — its `--build-id` is held equal to the
  deployed `image.tag`, so it can only ever name the newest build. Set an older
  version Current directly:
  ```bash
  kubectl -n temporal exec deploy/temporal-admintools -- \
    temporal worker deployment set-current-version --namespace mop \
      --address temporal-frontend.temporal.svc.cluster.local:7233 \
      --deployment-name order-fulfillment --build-id <previous-tag> --yes
  ```
- **Do not scale the old worker to zero to "finish" a rollback.** Its pinned
  workflows would stop progressing with no error. Retire the old build only once
  it has no open workflows left (Temporal UI).

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
_Last updated: 2026-07-29_
