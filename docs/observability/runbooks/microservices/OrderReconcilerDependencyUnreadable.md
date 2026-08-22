# OrderReconcilerDependencyUnreadable

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_repairs_total{action="unreadable"}` |

## Meaning
The reconciler has been unable to determine an order's state for 20m — either
`GetReservation` against inventory-service failed with something other than
NOT_FOUND, or `DescribeWorkflowExecution` against the Temporal frontend failed.

It **defers rather than guessing**: acting on an order whose saga state is unknown
is how a reconciler writes into a live compensation and causes the breach it would
then report.

Counted rather than only logged for a specific reason: a permanently unreadable
order otherwise produces ~1,440 warning lines a day and nothing an operator can
alert on.

## Impact
Repairs have **stopped** for the affected orders. `order_reconciler_backlog` may
still read low, because an order only enters the backlog once it has been terminal
for the 5m settle delay — so this alert leads the backlog alert, not the reverse.
Nothing is known to be wrong yet; nothing is being fixed either.

## Diagnosis
### PromQL
```promql
sum(increase(order_reconciler_repairs_total{action="unreadable"}[15m]))
sum by (action) (rate(order_reconciler_repairs_total[10m]))   # unreadable vs deferred
```

### kubectl / logs
```bash
kubectl logs -n order -l app.kubernetes.io/name=order-worker --tail=200 | grep -E "could not read a reservation|could not determine whether the saga"
kubectl -n inventory get pods -l app=inventory
kubectl -n temporal get pods -l app.kubernetes.io/component=frontend
```
The two log messages distinguish the dependency: the first is inventory, the second
is Temporal.

### Which dependency
```promql
sum by (grpc_code) (rate(grpc_server_handled_total{app="inventory"}[5m]))
```
`PermissionDenied` or `Unavailable` with healthy pods points at NetworkPolicy —
check that order-worker is allowed to reach `inventory:9090` and
`temporal-frontend:7233`.

## Mitigation
- Restore the dependency. No cleanup is needed: every repair is idempotent and
  unsettled rows are re-examined on the next pass, so the reconciler catches up
  by itself.
- If the outage will be long and the backlog is growing, that is expected — do not
  disable the reconciler to quiet the alert. `ORDER_RECONCILER_ENABLED=false` is
  for when its *judgement* is suspect, not when its dependencies are down.

## Escalation
Follow the inventory-service or Temporal runbooks; this alert is a symptom of
theirs. Escalate here only if both dependencies look healthy, which would point at
NetworkPolicy or DNS rather than the services.
