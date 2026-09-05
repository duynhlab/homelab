# KedaScaledObjectErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | platform |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/keda/alerts.yaml` |
| **Metrics** | `keda_scaled_object_errors_total` |
| **Status** | active |
| **Dashboard** | Workflows / Async → KEDA — Worker Autoscaling (panel "ScaledObject errors") |
| **Local-stack** | not present — compose runs no KEDA |

## Meaning

KEDA has failed to reconcile one `ScaledObject` on every attempt for five
minutes. This is the object, not its trigger: the `scaleTargetRef` Deployment
cannot be found, the `HorizontalPodAutoscaler` KEDA owns for it was rejected,
or the object is malformed. The trigger may be perfectly healthy.

On this platform every `ScaledObject` is a per-version copy the Worker
Controller renders from a `WorkerResourceTemplate`, so the usual cause is
**lifecycle skew**: the controller deleted a version's Deployment and the
`ScaledObject` copy still points at it, or a copy was rendered before the CRD
was ready.

## Impact

That version is not autoscaled. For a Current version the queue can grow with
no replica change; for a version already gone the alert is noise with a real
message underneath — something in the controller ↔ KEDA hand-off did not clean
up, and the leaked HPA will keep `KubeHPAMaxedOut`-style series alive for an
object that no longer exists.

## Diagnosis

### PromQL

```promql
# The alert expr
sum by (exported_namespace, scaledObject) (rate(keda_scaled_object_errors_total[5m]))

# Registered ScaledObjects vs running worker versions (should match)
sum(keda_resource_registered_total{type="scaled_object"})
count(kube_deployment_status_replicas{namespace=~"order|checkout", deployment=~"order-fulfillment.*|checkout-abandon.*"})
```

### Grafana

- **Workflows / Async → KEDA — Worker Autoscaling** — "ScaledObject errors"
  names the object; "ScaledObjects registered" against the worker-replica
  panel shows whether there are more copies than versions.

### kubectl / logs

```bash
NS=order                                         # or checkout
SO=<scaledObject from the alert>

kubectl -n "$NS" describe scaledobject "$SO" | sed -n '/Conditions/,/Events/p'

# Does the target still exist
kubectl -n "$NS" get scaledobject "$SO" -o jsonpath='{.spec.scaleTargetRef}{"\n"}'
kubectl -n "$NS" get deploy

# The controller's per-version view: which copies it thinks it owns
kubectl -n "$NS" get wrt -o yaml | sed -n '/status:/,$p'
kubectl -n "$NS" get wd -o wide

# The HPA KEDA rendered for it
kubectl -n "$NS" get hpa | grep keda-hpa
kubectl -n "$NS" describe hpa keda-hpa-"$SO" | sed -n '/Conditions/,/Events/p'

kubectl -n keda logs deploy/keda-operator --since=15m | grep -i "$SO" | tail -20
```

Shapes:

1. **`scaleTargetRef` names a Deployment that is gone** — lifecycle skew. The
   controller should delete the copy with the Deployment; if the copy survived,
   the controller's delete failed (RBAC on `scaledobjects.keda.sh` is granted
   through `workerResourceTemplate.allowedResources` — check it was not removed).
2. **HPA rejected** — usually a validation error on min/max (`minReplicaCount`
   must be ≤ `maxReplicaCount`) after a template edit.
3. **Paused** — `autoscaling.keda.sh/paused: "true"` annotation on the object;
   KEDA reports it as an error class. Someone paused it by hand.

## Mitigation

1. Shape 1 → `kubectl -n "$NS" get wrt -o yaml` to confirm the controller no
   longer lists that build id, then let the controller's next reconcile delete
   it; only if it does not, delete the orphan `ScaledObject` **and** its
   `keda-hpa-*` HPA together, and open an issue against the controller's
   cleanup.
2. Shape 2 → fix the numbers in `kubernetes/apps/<worker-deployment>-scaler.yaml`
   by PR.
3. Shape 3 → remove the annotation on the rendered object only if you paused it;
   otherwise find out who did — the template does not carry it.
4. Never `kubectl scale` the versioned Deployment as a workaround; the HPA and
   the controller both revert it.

## Escalation

Ticket. It becomes a page only when the erroring object is the Current
version's and `TemporalTaskQueueBacklogGrowing` co-fires. What not to do:
delete every `ScaledObject` in the namespace "to start clean" — the controller
re-renders them, but the HPA history and the scale-down cooldown state are gone,
so every version scales out again from scratch.

## Related

- [KedaScalerErrors](KedaScalerErrors.md) — trigger failures, the other half.
- [KedaOperatorDown](KedaOperatorDown.md) — when nothing reconciles at all.
- [ADR-054](../../../proposals/adr/ADR-054-temporal-worker-controller/) — the
  version lifecycle whose skew this alert usually reflects.

```bash
git log --oneline -5 -- kubernetes/apps/order-fulfillment-scaler.yaml kubernetes/infra/controllers/temporal/worker-controller-helmrelease.yaml
```

---
_Last updated: 2026-09-05 — created with the KEDA install (ADR-055)_
