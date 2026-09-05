# VMTooManyLogs

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/health-alerts.yaml` |
| **Metrics** | `vm_log_messages_total{level="error"}` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → Health |
| **Local-stack** | present |

## Meaning

A VictoriaMetrics component is logging errors at an elevated rate. Deliberately
broad — it is the net that catches failures no specific rule models, which on a
vendor component is most of them.

## Impact

None by itself. Its value is as a **leading indicator**: the component is
unhappy about something before that something has a dedicated alert.

## Diagnosis

The metric counts; the log explains. Go straight to the log:

```bash
kubectl logs -n monitoring deploy/vmsingle-victoria-metrics --tail=200 | grep -i error | sort | uniq -c | sort -rn | head
kubectl logs -n monitoring deploy/vmagent-victoria-metrics  --tail=200 | grep -i error | sort | uniq -c | sort -rn | head
kubectl logs -n monitoring deploy/vmalert-victoria-metrics  --tail=200 | grep -i error | sort | uniq -c | sort -rn | head
```

```promql
sum by (job) (rate(vm_log_messages_total{level="error"}[5m]))
```

Grouping identical lines is the fastest way in: one message repeated a thousand
times is one problem, not a thousand.

## Mitigation

Whatever the log says. Recurring causes on this platform:

- vmagent scrape failures against a target that has gone away →
  [VMAgentTooManyScrapeErrors](VMAgentTooManyScrapeErrors.md)
- vmalert rule evaluation errors →
  [VMAlertAlertingRulesError](VMAlertAlertingRulesError.md)
- query parse errors from a dashboard → harmless to the store, fix the panel

## Escalation

Warning. Rarely the incident; often the earliest evidence of one.

## Related

- [VMAgentTooManyScrapeErrors](VMAgentTooManyScrapeErrors.md)
- [VMAlertAlertingRulesError](VMAlertAlertingRulesError.md)
- [VMSingleRequestErrorsToAPI](VMSingleRequestErrorsToAPI.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
