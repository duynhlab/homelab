# OrderSagaNotCompleting

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability / cutover |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_fulfillment_start_participant_total`, `order_saga_outcome_total` |

## Meaning
Order sagas have been **starting** for 15 minutes and **none has reached a
terminal outcome**. Money and stock work is queued and going nowhere.

This alert exists for one specific silent failure (ADR-030): a Worker Deployment
Version made **Current with no worker serving it**. Verified live: the workflows
hang with no error in any log, no failed activity, and no SDK metric — no worker
ever receives the task, so nothing worker-side can report it. Only the
start/outcome pair, measured end to end, can see it.

The expression uses `unless` rather than `== 0` deliberately: a total stall
leaves `order_saga_outcome_total` with no increase at all — an **empty vector**,
which an equality comparison would silently drop.

## Impact
Every new order sits `pending` — authorized payments not captured, stock not
reserved, customers waiting. The outbox gauges stay green (rows are DISPATCHED;
the workflow *did* start), so nothing else fires.

## Diagnosis
First suspect, before anything else — the versioning routing:
```bash
kubectl -n temporal exec deploy/temporal-admintools -- \
  temporal worker deployment describe --namespace mop \
    --address temporal-frontend.temporal.svc.cluster.local:7233 \
    --name order-fulfillment
```
Compare the **Current version's build id** against the workers actually running:
```bash
kubectl -n order get deploy -l app.kubernetes.io/component=worker \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
kubectl -n temporal exec deploy/temporal-admintools -- \
  temporal task-queue describe --namespace mop \
    --address temporal-frontend.temporal.svc.cluster.local:7233 \
    --task-queue order-fulfillment
```
- Current build id has **no matching Deployment / no pollers** → this is the
  failure. Someone activated a version before (or after) its worker existed.
- Pollers exist and match → the stall is elsewhere: worker crash-looping
  (`kubectl -n order get pods`), Temporal frontend down (`temporal-local`
  Kustomization), or a dependency the activities call hanging fleet-wide.

### PromQL
```promql
sum(increase(order_fulfillment_start_participant_total[15m]))
sum by (outcome) (increase(order_saga_outcome_total[15m]))
sum by (result) (rate(order_fulfillment_start_dispatch_total[15m]))
```

## Mitigation
1. **Version mismatch:** point Current back at pollers that exist. Which
   invocation depends on what is still serving:
   - the previous **versioned** build still runs → the CronJob template is only
     correct if its guarded `--build-id` IS that build; otherwise use the raw CLI
     with the served build id;
   - only the **unversioned** worker remains (the first-cutover window) → the
     flag is `--unversioned`, not `--build-id`:
   ```bash
   kubectl -n temporal exec deploy/temporal-admintools -- \
     temporal worker deployment set-current-version --namespace mop \
       --address temporal-frontend.temporal.svc.cluster.local:7233 \
       --deployment-name order-fulfillment --unversioned --yes
   ```
   Workflows stuck on their **first** workflow task are not yet pinned, so they
   re-route to the new Current and resume; a workflow already pinned to a version
   with live pollers is unaffected. Nothing is lost — tasks waited, they did not
   fail.
2. **Worker down:** fix the Deployment; the queue drains on its own.
3. Do **not** cancel or reset the stuck workflows. They are healthy workflows
   waiting for a poller, and every one carries an authorized payment.

## Prevention
`scripts/flux-validate.sh` fails the build when the versioned worker's image
tag, its `TEMPORAL_WORKER_BUILD_ID`, and the CronJob's `--build-id` /
`--deployment-name` disagree — the drift that creates a Current version nobody
serves. Activation is a suspended CronJob template, never a reconciled Job, so
Flux can neither activate a version early nor fight a mid-ramp operator.

## References
- [ADR-030](../../../proposals/adr/ADR-030-temporal-workflow-versioning/)
- [RFC-0021 cutover rollback](../../../proposals/rfc/RFC-0021/cutover-rollback.md)

---
_Last updated: 2026-07-30_
