# KedaOperatorDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | platform |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/keda/alerts.yaml` |
| **Metrics** | `up{job=~".*keda-operator.*"}` (the chart's ServiceMonitor), `keda_build_info` |
| **Status** | active |
| **Dashboard** | Workflows / Async → KEDA — Worker Autoscaling (row "KEDA health") |
| **Local-stack** | not present — compose runs no KEDA |

## Meaning

The KEDA operator scrape has read `0` for five minutes, or **no `keda_*` series
exists at all** (`absent(keda_build_info)` — `keda_build_info` is the one metric
KEDA exports even with zero scalers, so its absence means the scrape itself is
gone, not that KEDA is idle).

KEDA is the only thing that evaluates a `ScaledObject`. With the operator down
nothing polls `temporal-frontend:7233`, the HPAs KEDA owns receive no metric, and
every worker version stays at whatever replica count it had. Nothing crashes;
the workers simply stop following the backlog
([ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/)).

## Impact

Under steady load nothing changes. Under a burst the order and checkout queues
grow while replicas do not — the shape `TemporalTaskQueueBacklogGrowing` and
`TemporalScheduleToStartLatencyHigh` will page on a few minutes later, without
naming the cause. During a rollover a new build id gets no `ScaledObject` at all
until KEDA is back (the controller still renders the copy; KEDA just never reads it).

## Diagnosis

### PromQL

```promql
# The alert expr, both halves
up{job=~".*keda-operator.*", job!~".*metrics-apiserver.*"}
absent(keda_build_info)

# Which job labels the KEDA scrape actually produces on this cluster
label_values(up, job)   # Grafana Explore; or: count by (job) (up{job=~".*keda.*"})

# Is the metrics adapter (the external.metrics.k8s.io side) also gone
up{job=~".*keda.*metrics-apiserver.*"}
```

### Grafana

- **Workflows / Async → KEDA — Worker Autoscaling** — the "Operator up" and
  "Metrics adapter up" stats, and whether "ScaledObjects registered" dropped to
  no data at the same moment.

### kubectl / logs

```bash
kubectl -n keda get deploy,pods
kubectl -n keda describe deploy keda-operator | sed -n '/Conditions/,/Events/p'
kubectl -n keda logs deploy/keda-operator --since=15m | tail -40
kubectl -n keda get servicemonitor            # the two the chart renders
kubectl -n monitoring get vmagent -o yaml | grep -n selectAllByDefault

# The wave that owns KEDA
flux get kustomization keda-local
flux get helmrelease -n keda keda
```

Three shapes:

1. **Pod not running** — OOMKilled or CrashLoop. The Kind-sized limits in
   `controllers/keda/helmrelease.yaml` (384Mi operator) are guesses until the
   audit measures them; an OOM here is a sizing bug, not a KEDA bug.
2. **Pod running, `up == 0`** — the metrics port (8080) is refused; check the
   `prometheus.operator.enabled` value and the Service the ServiceMonitor targets.
3. **Pod running, `absent()`** — the ServiceMonitor is not selected: label drift
   or `prometheus.operator.serviceMonitor.enabled` regressed. Same failure the
   Kyverno group recorded on 2026-08-21.

## Mitigation

1. Shape 1 → `kubectl -n keda rollout restart deploy/keda-operator`; if it OOMs
   again, raise `resources.operator.limits.memory` in the HelmRelease by PR.
2. Shape 2/3 → fix the values in `controllers/keda/helmrelease.yaml`; Flux
   reconciles `keda-local`. Do not hand-edit the ServiceMonitor — the chart owns it.
3. While KEDA is down and a burst is live: the versioned Deployments can be
   scaled by hand **only** through the `WorkerDeployment` (`kubectl -n order
   patch wd order-fulfillment --type=merge -p '{"spec":{"replicas":2}}'`), never
   `kubectl scale` on the Deployment. Revert when KEDA is back; the HPA resumes
   ownership on its next reconcile.

## Escalation

Page. The alert is quiet in effect but loud in consequence: the platform's only
autoscaler is off. What not to do: delete the `ScaledObject`s to "unblock" the
HPAs — KEDA owns them and the controller re-renders them; deleting the
`HorizontalPodAutoscaler`s KEDA created leaves the Deployments at their last
count with no owner at all.

## Related

- [KedaScalerErrors](KedaScalerErrors.md) — the operator is up but a trigger is
  failing.
- [TemporalTaskQueueBacklogGrowing](../temporal/TemporalTaskQueueBacklogGrowing.md)
  — what fires next if this stays down under load.

```bash
git log --oneline -5 -- kubernetes/infra/controllers/keda/ kubernetes/clusters/local/keda.yaml
```

---
_Last updated: 2026-09-05 — created with the KEDA install (ADR-055)_
