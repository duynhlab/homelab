# Alerts / SLO

The entry point for any firing `alertname`, and the one path that has no
per-alert runbook.

## Authoritative docs

- Runbook index (one folder per domain, one file per alert):
  [runbooks/README.md](../../../../../docs/observability/runbooks/README.md).
- Full rule inventory, severity, links:
  [alert-catalog.md](../../../../../docs/observability/alerting/alert-catalog.md).
- The signal/runbook contract and validation levels:
  [alert-lifecycle-and-runbooks.md](../../../../../docs/observability/alerting/alert-lifecycle-and-runbooks.md).
- Per-alert template: [`_TEMPLATE.md`](../../../../../docs/observability/runbooks/_TEMPLATE.md).

## Manifests

- `kubernetes/infra/configs/observability/metrics/prometheusrules/**`
- Temporal rules: `kubernetes/infra/configs/temporal/prometheusrule.yaml`
- SLO: Sloth `PrometheusServiceLevel` from the `slo` chart +
  `kubernetes/infra/configs/observability/sloth/`.

## Flow

1. Grep the tree for the exact `alertname`; open its file.
2. Follow `_TEMPLATE.md` section order: Meaning → Impact → Safety → Diagnosis →
   Mitigation → Recovery validation → Escalation.
3. Re-derive any count from the rules — the catalog Summary is **derived**, not
   a cached constant:
   `rg -c '^\s*- alert:' kubernetes/infra/configs/observability/metrics/prometheusrules`.

## SLO burn-rate exception

Burn-rate pages have **no** per-alert tree. Route through
[slo-burn-rate-alerts.md](../../../../../docs/observability/alerting/slo-burn-rate-alerts.md)
to the owning service, then into that service's RED runbook. Do not map a burn
page onto a RED alert file.

## Boundary

- A real alert with no file is a recorded **gap**: use the catalog for context
  and report the gap; do not invent steps.
- Verify the signal is live and labels are current before tuning a threshold
  ([evidence-correlation](../evidence-correlation.md)).
