# Watchdog

| | |
|---|---|
| **Severity** | none |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/watchdog.yaml` |
| **Metrics** | `vector(1)` — always true |
| **Status** | active · **always firing, by design** |
| **Dashboard** | Karma · Alertmanager |
| **Local-stack** | present |

## Meaning

A **dead-man's-switch**. It fires continuously and forever. Its purpose is
inverted from every other alert on the platform: you are not meant to react when
it arrives, you are meant to react when it **stops**.

Because it always fires, its presence at the receiving end proves the entire
pipeline works: vmalert evaluated a rule, sent it to Alertmanager, and
Alertmanager routed it. Its absence proves one of those links is broken.

## Impact of its absence

If Watchdog stops arriving, **assume every other alert is also not arriving.**
The platform has no other way to detect that, because every other detection
mechanism runs through the same pipeline. Nothing will page you to say paging is
broken.

That covers exactly the failure
[VMAlertAlertmanagerErrors](../victoriametrics/VMAlertAlertmanagerErrors.md)
describes and cannot itself report.

## Diagnosis — when it goes missing

Walk the pipeline in order; each step tells you whether to continue:

```bash
# 1. Is vmalert evaluating at all
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://localhost:8080/api/v1/rules' | head -5

# 2. Is Watchdog among the alerts vmalert considers firing
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://localhost:8080/api/v1/alerts' | grep -o Watchdog | head -1

# 3. Did Alertmanager receive it
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://vmalertmanager-victoria-metrics.monitoring.svc:9093/api/v2/alerts?active=true' \
  | grep -o Watchdog | head -1

# 4. Are the components even up
kubectl get pods -n monitoring | grep -E 'vmalert|alertmanager'
```

Whichever step is the first to fail names the broken link.

## Mitigation

Restore the link that failed:

| Failing step | Runbook |
|---|---|
| vmalert not evaluating | [VMServiceDown](../victoriametrics/VMServiceDown.md), [VMAlertConfigurationReloadFailure](../victoriametrics/VMAlertConfigurationReloadFailure.md) |
| Evaluated but not delivered | [VMAlertAlertmanagerErrors](../victoriametrics/VMAlertAlertmanagerErrors.md) |
| Alertmanager has it, you do not | Routing and receiver config — the last hop |

**Never silence Watchdog.** A silenced dead-man's-switch is a dead-man's-switch
that cannot do its one job, and the silence will look identical to a working
pipeline.

## Escalation

Its absence is effectively critical regardless of the `none` severity, and it
must be escalated **out of band** — by definition the alerting path is the thing
in question.

## Related

- [VMAlertAlertmanagerErrors](../victoriametrics/VMAlertAlertmanagerErrors.md)
- [VMServiceDown](../victoriametrics/VMServiceDown.md)

---
_Last updated: 2026-09-05 — created; this alert had no runbook_
