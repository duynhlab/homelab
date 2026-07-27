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
