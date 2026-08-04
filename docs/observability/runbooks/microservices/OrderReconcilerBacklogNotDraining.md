# OrderReconcilerBacklogNotDraining

| | |
|---|---|
| **Severity** | warning |
| **Category** | database / correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_backlog` |
| **Applies to** | order **1.13.0+** (RFC-0021 P4 removed the product stock branch). On 1.12.x and earlier the resolver fell back to the process's `ORDER_STOCK_PARTICIPANT` and started the saga anyway — the pre-P4 notes below still apply there |

## Meaning
`max(order_reconciler_backlog) > 0` for 15m. At least one order that reached a
terminal status (`confirmed` or `failed`) has not had its inventory reservation
confirmed to agree with that outcome.

The gauge is a **query against `fulfillment_start_requests`**, not a counter kept
in memory — it counts rows with `reconciled_at IS NULL`. A repair that succeeds
settles its row, so anything visible here is work the reconciler could not do.

15m rather than 10m is deliberate: the scan ignores orders that became terminal
less than 5 minutes ago (it must not race the saga's own commit) and passes run
once a minute, so a legitimately-in-flight order occupies the backlog for several
minutes before anything examines it.

## Impact
Stock is either **held against an order that will never ship** (reserved units that
no reaper releases — v1 reservations do not expire) or **consumed for an order that
did not happen**. Both are silent: the customer sees nothing, and the inventory
balance is wrong until someone acts.

## Diagnosis
### PromQL
```promql
max(order_reconciler_backlog)
sum by (action) (rate(order_reconciler_repairs_total[15m]))
```
`action` tells you *why* it is not draining:
- `breach` — unrepairable; see [OrderReconcilerInvariantBreach](OrderReconcilerInvariantBreach.md).
- `failed` — the repair RPC itself is failing; inventory is reachable but rejecting.
- `deferred` — the saga is still open; the reconciler will not touch a live workflow.
- `unreadable` — inventory or Temporal cannot be reached; see [OrderReconcilerDependencyUnreadable](OrderReconcilerDependencyUnreadable.md).
- no series at all — passes are not running (worker down, or `ORDER_RECONCILER_ENABLED=false`).

### SQL
```sql
SELECT f.order_id, o.status, f.participant, f.reconcile_breach_code, o.updated_at
FROM fulfillment_start_requests f JOIN orders o ON o.id = f.order_id
WHERE f.reconciled_at IS NULL
ORDER BY (f.reconcile_breach_code IS NOT NULL), o.updated_at;
```
Same ordering the scan uses: repairable work first, known breaches last.

### kubectl / logs
```bash
kubectl logs -n order -l app=order-worker --tail=300 | grep -i reconcil
```
Each order is reported **once**, not once per pass — a single line is the normal
representation of a persistent problem, not a transient one.

## Mitigation
1. Read `action` and follow the matching runbook above.
2. `deferred` that never clears ⇒ a stuck workflow: inspect it in the Temporal UI
   (`order-fulfillment-<order_id>`) and terminate it if it is genuinely dead. The
   reconciler treats a closed or missing workflow as safe to act on.
3. `failed` ⇒ check inventory-service health and the order→inventory
   NetworkPolicy. Repairs are idempotent, so recovery needs no cleanup: the next
   pass re-drives them.
4. Do **not** hand-set `reconciled_at` to silence this. That is the one action
   that makes the inconsistency invisible instead of fixed.

## Escalation
Non-zero **and** rising over an hour, or any `breach`, is a data-integrity
incident: page. The posture is **fix-forward**: there is no flag to revert since
RFC-0021 P4 removed the product stock branch, and participant is pinned per
workflow, so orders already in flight settle where they started regardless.
