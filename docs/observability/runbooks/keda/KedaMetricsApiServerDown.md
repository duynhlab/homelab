# KedaMetricsApiServerDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | platform |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/keda/alerts.yaml` |
| **Metrics** | `up{job=~".*keda.*metrics-apiserver.*"}` **or `absent()` of it** (the chart's ServiceMonitor for `keda-operator-metrics-apiserver`) |
| **Status** | active |
| **Dashboard** | Workflows / Async → KEDA — Worker Autoscaling (row "KEDA health", stat "Metrics adapter up") |
| **Local-stack** | not present — compose runs no KEDA |

## Meaning

The KEDA **external-metrics adapter** has been unreachable for five minutes.

KEDA is two processes, and this is the one that is easy to forget. The operator
(`keda-operator`) watches `ScaledObject`s, evaluates the triggers, and owns every
`keda_scaler_*` series. The adapter (`keda-operator-metrics-apiserver`,
`cmd/adapter` upstream) registers the `external.metrics.k8s.io` APIService and
answers the HPA's metric queries by proxying to the operator over gRPC.

So this alert names a failure that
[`KedaOperatorDown`](KedaOperatorDown.md) structurally **cannot** see: the
operator stays healthy, `keda_build_info` and every scaler series keep flowing,
`KedaScalerErrors` stays quiet — and scaling still stops, because the HPAs get an
error instead of a metric.

## Impact

Every HPA KEDA owns reports `ScalingActive=False` / `FailedGetExternalMetric` and
holds its **last** replica count. Under steady load nothing looks wrong. Under a
burst the order and checkout queues grow while replicas do not, and the first
automated symptom is `TemporalTaskQueueBacklogGrowing` or
`TemporalScheduleToStartLatencyHigh` some minutes later — pointing at the workers
rather than at the adapter
([ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/)).

A broken APIService is also visible cluster-wide: `kubectl top`-style external
metric reads and any `kubectl get --raw /apis/external.metrics.k8s.io/v1beta1`
fail, and an unavailable APIService can slow API discovery for other clients.

## Diagnosis

### PromQL

```promql
# The alert expr, both halves. The absent() half is load-bearing: scaling the
# Deployment to 0 removes the Service endpoint, so the target disappears and `up`
# is ABSENT rather than 0 — measured on Kind 2026-09-05, where `== 0` alone
# matched nothing while the HPA was already reporting ScalingActive=False.
up{job=~".*keda.*metrics-apiserver.*"}
absent(up{job=~".*keda.*metrics-apiserver.*"})

# The contrast that identifies this failure: operator healthy, adapter not
up{job=~".*keda-operator.*"}

# The operator is still publishing, which is why nothing else fires
keda_build_info
sum by (exported_namespace, scaledObject, scaler) (rate(keda_scaler_detail_errors_total[5m]))
```

### Grafana

- **Workflows / Async → KEDA — Worker Autoscaling**, row "KEDA health" — the
  "Metrics adapter up" stat against "Operator up". One down and one up is this
  alert; both down is `KedaOperatorDown`.
- Row "Scaling" — `kube_horizontalpodautoscaler_status_current_replicas` going
  flat while the backlog panel keeps climbing is the visible signature.

### kubectl

```bash
# Is the APIService actually serving
kubectl get apiservice v1beta1.external.metrics.k8s.io
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" | head -c 400

# The pod and why it is unhappy
kubectl -n keda get pods -l app.kubernetes.io/name=keda-operator-metrics-apiserver
kubectl -n keda logs deploy/keda-operator-metrics-apiserver --tail=100

# What the HPAs think — this is the confirming evidence
kubectl -n order describe hpa
kubectl -n checkout describe hpa   # look for FailedGetExternalMetric / ScalingActive=False
```

## Common causes

| Cause | Signal | Action |
|---|---|---|
| Pod OOMKilled or crash-looping | `kubectl -n keda get pods`, restart count | Raise `resources.metricServer.limits.memory` in the HelmRelease (currently 384Mi) |
| Cannot reach the operator's gRPC metrics service | Adapter logs: dial errors to `keda-operator:9666` | Check the operator pod and the `keda-operator` Service's `metricsservice` port |
| APIService certificate expired or not yet issued | `kubectl get apiservice v1beta1.external.metrics.k8s.io` shows `FailedDiscoveryCheck` | The chart self-generates its serving cert; delete the pod to re-issue, then re-check |
| Scheduling failure after a node reclaim | Pod `Pending` | Kind has been CPU-starved before — check node allocatable |

## Resolution

1. Confirm the contrast above (operator up, adapter down). If **both** are down,
   work [`KedaOperatorDown`](KedaOperatorDown.md) instead — it is the wider fault.
2. Fix the pod (usually a restart or a memory bump), then verify the APIService
   returns `True` and an HPA leaves `ScalingActive=False`.
3. Do **not** delete the `ScaledObject`s to "unstick" scaling. Deleting one
   removes the HPA and drops the version to its Deployment replica count — and
   because ADR-055 hands replica ownership to the autoscaler (`spec.replicas` is
   absent from the `WorkerDeployment`), nothing writes it back. The
   `WorkerResourceTemplate` will re-render the `ScaledObject` on the next
   reconcile anyway.
4. If the adapter is genuinely unrecoverable and a burst is in progress, the
   manual bridge is `kubectl -n <ns> scale deploy <versioned-deployment>
   --replicas=N`. The HPA will take the value back the moment the adapter
   returns; record it in the incident notes so the change is not mistaken for
   drift.

## Related

- [`KedaOperatorDown`](KedaOperatorDown.md) — the operator half; excludes this job on purpose
- [`KedaScalerErrors`](KedaScalerErrors.md) — the trigger fails, the pipeline is fine
- [`TemporalTaskQueueBacklogGrowing`](../temporal/TemporalTaskQueueBacklogGrowing.md) — the delayed downstream symptom
- [`ADR-055`](../../../proposals/adr/ADR-055-keda-worker-autoscaling/) — why KEDA owns replicas at all

---
_Last updated: 2026-09-05_
