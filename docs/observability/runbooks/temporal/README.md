# Temporal Alert Runbooks

Per-alert investigation guides for the Temporal work layer — the server
(frontend/history/matching/worker roles of the official chart), the two
versioned workers under the Worker Controller (`order/order-fulfillment`,
`checkout/checkout-abandon`), and, since ADR-055, the KEDA scaler that sizes
those workers from task-queue backlog. Server metrics are scraped through the
chart's ServiceMonitors (`job=~".*temporal.*"`); worker metrics are the Go SDK's
OTel series pushed through the OTel Collector (`pkg/temporalx`). One file per
alert name; the schedule-to-start warning/critical pair shares one file.

| Quick facts | |
|---|---|
| Alert rules | [`configs/temporal/prometheusrule.yaml`](../../../../kubernetes/infra/configs/temporal/prometheusrule.yaml) — outside `prometheusrules/`, which is why the catalog's count command misses this group |
| Alert catalog | [§8 Temporal / Pyroscope / Watchdog](../../alerting/alert-catalog.md#8-temporal--pyroscope--watchdog) |
| Scaler | [`apps/order-fulfillment-scaler.yaml`](../../../../kubernetes/apps/order-fulfillment-scaler.yaml), [`apps/checkout-abandon-scaler.yaml`](../../../../kubernetes/apps/checkout-abandon-scaler.yaml) — one `ScaledObject` per running worker version ([ADR-055](../../../proposals/adr/ADR-055-keda-worker-autoscaling/)) |
| Template | [`_TEMPLATE.md`](../_TEMPLATE.md) |

## Index

| Alert | Sev | Source | Status | Runbook |
|-------|-----|--------|--------|---------|
| **Server** (group `temporal`) | | | | |
| TemporalServerDown | critical | prometheusrule | active | [TemporalServerDown.md](TemporalServerDown.md) |
| TemporalServiceErrorRateHigh | warning | prometheusrule | active | [TemporalServiceErrorRateHigh.md](TemporalServiceErrorRateHigh.md) |
| TemporalPersistenceErrorRateHigh | warning | prometheusrule | active | [TemporalPersistenceErrorRateHigh.md](TemporalPersistenceErrorRateHigh.md) |
| **Workers** (group `temporal-worker`) | | | | |
| TemporalWorkflowFailureRateHigh | warning | prometheusrule | active | [TemporalWorkflowFailureRateHigh.md](TemporalWorkflowFailureRateHigh.md) |
| TemporalActivityFailureRateHigh | warning | prometheusrule | active | [TemporalActivityFailureRateHigh.md](TemporalActivityFailureRateHigh.md) |
| TemporalWorkerRequestErrorRateHigh | warning | prometheusrule | active | [TemporalWorkerRequestErrorRateHigh.md](TemporalWorkerRequestErrorRateHigh.md) |
| TemporalWorkerTaskSlotsExhausted | warning | prometheusrule | active | [TemporalWorkerTaskSlotsExhausted.md](TemporalWorkerTaskSlotsExhausted.md) |
| **Capacity / autoscaling** (group `temporal-worker`, ADR-055) | | | | |
| TemporalScheduleToStartLatencyHigh | warning / critical | prometheusrule | active | [TemporalScheduleToStartLatencyHigh.md](TemporalScheduleToStartLatencyHigh.md) |
| TemporalTaskQueueBacklogGrowing | warning | prometheusrule | active | [TemporalTaskQueueBacklogGrowing.md](TemporalTaskQueueBacklogGrowing.md) |

## Domain specifics

- **Extra quick-facts rows:** none beyond the standard template set.
- **Two label dialects for "which queue".** SDK metrics carry `task_queue`
  with the CRD's value (`order-fulfillment`); server metrics carry `taskqueue`
  with underscores (`order_fulfillment`). A query that mixes them matches
  nothing and reports no error.
- **Diagnosis dialect:** PromQL first for the worker group (the SDK series say
  which worker and which queue), then `kubectl -n <ns> get wd,scaledobject,hpa`
  for the version and scaler view, then `temporal task-queue describe
  --report-stats` from the admintools pod for the server's own word.
- **Replica count is not yours to edit.** The Worker Controller owns each
  version's Deployment and KEDA's HPA owns its replica count; `kubectl scale`
  is reverted within seconds by one or the other. Capacity changes go through
  the scaler template by PR.
- **Dashboards:** **Temporal — Workflows & Activities** (SDK rows) and its
  **Server** row (backlog, backlog age); **KEDA — Worker Autoscaling** (same
  folder) for what the scaler computed per version, what its HPA did, and KEDA's
  own errors (`keda_scaler_metrics_value`, `keda_scaler_detail_errors_total`).
- **Local-stack:** the compose stack runs the server and both workers and
  scrapes the same series, so every alert here is present locally; the scaler
  is not (compose has no KEDA), so the autoscaling rows describe a condition
  local-stack can produce but not answer.

## Template

Every runbook here follows [`_TEMPLATE.md`](../_TEMPLATE.md): quick facts →
Meaning → Impact → Diagnosis → Mitigation → Escalation (→ Related).

---
_Last updated: 2026-09-05 — created with the two ADR-055 capacity alerts; the seven existing Temporal runbooks (2026-09-05, #993) had no folder index_
