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

This alert exists for one specific silent failure: a Worker Deployment Version
that is **Current with no worker serving it**. The failure mode survives
[ADR-054](../../../proposals/adr/ADR-054-temporal-worker-controller/) — what
changed is that no human can cause it any more, and no human can fix it by hand
(see Mitigation). Under ADR-030 it was a mis-run activation Job; now it is the
controller or the `Connection` being unhealthy. Verified live: the workflows
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
First suspect, before anything else — the versioning routing. Read it from the CR,
which is the cheapest and most reliable source:
```bash
kubectl -n order get wd order-fulfillment
#   NAME               CURRENT      TARGET       RAMP %
#   order-fulfillment  <build id>   <build id>   (empty when settled)
kubectl -n order get wd order-fulfillment -o jsonpath='{.status.conditions}' | jq .
kubectl -n order get po -L temporal.io/build-id
```
Read it in this order, and stop at the first thing that is wrong:

- **`CURRENT` empty** → the controller never set it. Suspect the controller or the
  `Connection`, not the saga:
  `kubectl -n temporal get hr temporal-worker-controller-crds temporal-worker-controller`
  and `kubectl -n temporal logs deploy/temporal-worker-controller-manager --tail=50`.
- **`CURRENT` set but no pod carries that build id** → the version is Current with
  nothing serving it. This is the failure. It happens now by a version being scaled
  down inside its `sunset.scaledownDelay` while still Current, or by the versioned
  Deployment failing to schedule — `kubectl -n order describe deploy -l temporal.io/deployment-name=order-fulfillment`.
- **`CURRENT` set and a Ready pod carries it** → the stall is elsewhere. Worker
  crash-looping, Temporal frontend down (`temporal-local` Kustomization), or a
  dependency the activities call hanging fleet-wide.

More than one build-id label is **normal**: a drained version stays up for
`sunset.scaledownDelay` (1h). Check the extras are tracked rather than orphaned:
```bash
kubectl -n order get wd order-fulfillment \
  -o jsonpath='{range .status.deprecatedVersions[*]}{.buildID}{" drainedSince="}{.drainedSince}{"\n"}{end}'
```

Server-side view, if you need it. **Note the name**: the controller registers
`<namespace>/<resource-name>`, so the bare `order-fulfillment` errors with *"no
Worker Deployment found … does your Worker Deployment have pollers?"* — which
reads like a confirmed incident and is not one:
```bash
kubectl -n temporal exec deploy/temporal-admintools -- \
  temporal worker deployment describe --namespace mop \
    --address temporal-frontend.temporal.svc.cluster.local:7233 \
    --name order/order-fulfillment
```

**Do not diagnose from `task-queue describe`.** Without `--select-build-id` it
reports the UNVERSIONED queue only — zero backlog, empty `Pollers` — on a
perfectly healthy versioned cluster. Even *with* `--select-build-id <build>` the
`Pollers` table is empty here (verified 2026-08-22 against a healthy cluster), so
an empty poller list proves nothing either way. Liveness comes from
`kubectl get wd` plus the pods.

### PromQL
```promql
sum(increase(order_fulfillment_start_participant_total[15m]))
sum by (outcome) (increase(order_saga_outcome_total[15m]))
sum by (result) (rate(order_fulfillment_start_dispatch_total[15m]))
```

## Mitigation
1. **Version mismatch — do NOT set Current by hand.** The controller is the only
   writer of that setting ([ADR-054](../../../proposals/adr/ADR-054-temporal-worker-controller/)
   § Decision rules), and `status.managerIdentity` names it. A hand-run
   `temporal worker deployment set-current-version` does not fix anything: the
   controller reconciles it back, and you have added a second writer to an
   incident. The `set-current-version` CronJob that used to be the mitigation here
   is **deleted**.

   The fix is in git. Correct the image tag or the pod template in
   `kubernetes/apps/order-worker.yaml`, then `make flux-push && make flux-sync`.
   The controller derives the build id, creates the Deployment, and promotes it.
   Reverting to a previously deployed template re-promotes that build id rather
   than minting a new one.

   Workflows stuck on their **first** workflow task are not yet pinned, so they
   route to the new Current and resume; a workflow already pinned to a version
   with live pollers is unaffected. Nothing is lost — tasks waited, they did not
   fail.
2. **Controller down** → `kubectl -n temporal get hr temporal-worker-controller`.
   Nothing about the saga can be fixed while its lifecycle owner is absent.
3. **Worker pod down** → fix the Deployment's cause (image pull, resources,
   admission); the queue drains on its own once a poller of the Current build
   exists.
4. Do **not** cancel or reset the stuck workflows. They are healthy workflows
   waiting for a poller, and every one carries an authorized payment.

## Prevention
Mostly structural now rather than checked. The build id is **derived** by the
controller and exists in exactly one place, so the drift this alert used to catch
— an image tag, an env `BUILD_ID`, a filename and a CronJob flag disagreeing — has
nothing left to disagree with. `validate_worker_build_id()` and its four-way
equality are deleted; `validate_worker_versioning()` in `scripts/flux-validate.sh`
now refuses the one reachable mistake: a pod template that **hand-sets** the
version identity the controller injects.

What is genuinely less covered than before, and worth knowing on call: nothing
asserts the controller is Ready. `temporal-local` health-checks the Temporal
HelmRelease and frontend Deployment, not the manager — `wait: true` is what covers
it. So "the controller is down" is a real diagnosis to reach for, and it did not
exist under ADR-030.

## References
- [ADR-054](../../../proposals/adr/ADR-054-temporal-worker-controller/) — the
  controller owns the lifecycle; **read this first**
- [RFC-0026](../../../proposals/rfc/RFC-0026/) — why, and the tradeoffs
- [ADR-030](../../../proposals/adr/ADR-030-temporal-workflow-versioning/) — the
  versioning decision, which stands; its *rollout mechanism* is superseded
- [`kubernetes/apps/order-worker.yaml`](../../../../kubernetes/apps/order-worker.yaml)
  — the one file a fix edits
- [Releasing the order worker](../../../platform/application-delivery.md#releasing-the-order-worker)
- [RFC-0021 cutover rollback](../../../proposals/rfc/RFC-0021/cutover-rollback.md)
  — **historical**: describes the per-build manifest and activation Job that no
  longer exist. Do not follow it during an incident.

---
_Last updated: 2026-08-22 — rewritten for ADR-054. Every command in Diagnosis was
run against a healthy cluster first: the three it replaced returned an error, an
empty table, and a false positive respectively._
