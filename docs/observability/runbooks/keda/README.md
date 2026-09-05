# KEDA Alert Runbooks

Per-alert investigation guides for KEDA, the autoscaler
[ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/) installed to
size both Temporal workers from task-queue backlog. Four rules, all about
KEDA's own health: the operator being scraped, the external-metrics adapter
being scraped, a trigger failing its metric fetch, and a `ScaledObject` failing
to reconcile. The first two are separate on purpose — the operator publishes
every `keda_*` series while the adapter serves `external.metrics.k8s.io`, so the
adapter can die with the operator perfectly healthy and scaling still stops. What the scaler *does* to the
workers is alerted on the Temporal side
(`TemporalTaskQueueBacklogGrowing`, `TemporalScheduleToStartLatencyHigh` —
[runbooks/temporal/](../temporal/README.md)). One file per alert name.

| Quick facts | |
|---|---|
| Alert rules | [`prometheusrules/keda/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/keda/alerts.yaml) |
| Alert catalog | [§8c KEDA autoscaling](../../alerting/alert-catalog.md#8c-keda-autoscaling) |
| Dashboard | Workflows / Async → **KEDA — Worker Autoscaling** ([`grafana/dashboards/keda.json`](../../../../kubernetes/infra/configs/observability/grafana/dashboards/keda.json)) |
| Install | [`controllers/keda/helmrelease.yaml`](../../../../kubernetes/infra/controllers/keda/helmrelease.yaml), wave `keda-local` |
| Scaler templates | [`apps/order-fulfillment-scaler.yaml`](../../../../kubernetes/apps/order-fulfillment-scaler.yaml), [`apps/checkout-abandon-scaler.yaml`](../../../../kubernetes/apps/checkout-abandon-scaler.yaml) |
| Template | [`_TEMPLATE.md`](../_TEMPLATE.md) |

## Index

| Alert | Sev | Source | Status | Runbook |
|-------|-----|--------|--------|---------|
| KedaOperatorDown | critical | keda/alerts | active | [KedaOperatorDown.md](KedaOperatorDown.md) |
| KedaMetricsApiServerDown | critical | keda/alerts | active | [KedaMetricsApiServerDown](KedaMetricsApiServerDown.md) |
| KedaScalerErrors | warning | keda/alerts | active | [KedaScalerErrors.md](KedaScalerErrors.md) |
| KedaScaledObjectErrors | warning | keda/alerts | active | [KedaScaledObjectErrors.md](KedaScaledObjectErrors.md) |

## Domain specifics

- **Extra quick-facts rows:** none beyond the standard template set.
- **Metric names are KEDA 2.20's.** `keda_scaler_detail_errors_total` is the
  per-scaler error counter; `keda_scaler_errors_total` does not exist, and the
  chart's own values example still cites a pre-2.x name. Check
  `label_values(up, job)` before trusting a job regex.
- **The namespace label.** KEDA stamps its own `namespace` (the
  `ScaledObject`'s), so under the operator scrape the target namespace wins and
  KEDA's becomes `exported_namespace` — the label the official KEDA board and
  these rules use. Confirming it on Kind is an ADR-055 audit row; if the live
  series carry `namespace`, change the rules and the board variable together.
- **Nothing here is yours to scale by hand.** The Worker Controller owns each
  version's Deployment, KEDA owns the HPA, and `WorkerResourceTemplate` owns the
  `ScaledObject`. `kubectl scale`, `kubectl delete scaledobject` and editing the
  rendered trigger metadata are all reverted within a reconcile; changes go
  through the template by PR.
- **Diagnosis dialect:** `kubectl describe scaledobject` conditions first (they
  carry the trigger's error text), then the operator log, then PromQL for how
  long and how wide.
- **Local-stack:** none of these alerts exist on the compose stack — it runs no
  KEDA — so every runbook carries the same "not present" row.

## Template

Every runbook here follows [`_TEMPLATE.md`](../_TEMPLATE.md): quick facts →
Meaning → Impact → Diagnosis → Mitigation → Escalation (→ Related).

---
_Last updated: 2026-09-05 — created with the KEDA install (ADR-055)_
