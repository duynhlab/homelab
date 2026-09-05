# VMAlertAlertmanagerErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_alerts_send_errors_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

vmalert cannot deliver fired alerts to Alertmanager. Rules evaluate correctly and
fire correctly — **the notification does not arrive**.

This is the most self-defeating failure in the group: the alerting system's
inability to alert. Nothing downstream of Alertmanager can report it, because
nothing downstream is receiving anything.

## Impact

**Alerts fire into nothing.** Every rule on the platform keeps working and no one
is told. The only surviving signal is the **Watchdog** dead-man's-switch: it
always fires, so if Watchdog stops arriving at its receiver, the pipeline is
broken. That is precisely the case this alert covers and cannot itself report.

## Diagnosis

```promql
sum(rate(vmalert_alerts_send_errors_total[5m]))
sum(rate(vmalert_alerts_sent_total[5m]))
up{job=~".*vmalertmanager.*"}
```

```bash
kubectl get pods -n monitoring | grep alertmanager
kubectl logs -n monitoring deploy/vmalert-victoria-metrics --tail=100 | grep -i alertmanager

# Is Alertmanager receiving anything at all
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://vmalertmanager-victoria-metrics.monitoring.svc:9093/api/v2/status' | head -20
```

Confirm from the receiving end too — Karma or the Alertmanager API should show
Watchdog. If Watchdog is missing there, delivery is broken regardless of what
this alert says.

## Mitigation

1. **Alertmanager down** → [VMServiceDown](VMServiceDown.md).
2. **Reachable but rejecting** → check its config; a bad route or receiver
   definition rejects on load.
3. **Network** → the Service resolves and the port answers, or it does not.

## Escalation

Warning by label, and effectively critical in practice. Escalate **out of band** —
paging through the system that cannot page is not a plan.

## Related

- [VMServiceDown](VMServiceDown.md) — Alertmanager is one of the nine jobs.
- [VMAlertRemoteWriteDroppingData](VMAlertRemoteWriteDroppingData.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
