# VMAlertAlertingRulesError

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_alerting_rules_errors_total` |
| **Status** | active · 814 rules evaluating, 0 lastError at last audit |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

One or more **alerting** rules fail to evaluate — a query error, a datasource
error, or a timeout.

**A rule that errors is a rule that cannot fire.** That is the whole reason this
alert is important: the failure is silent in every other direction. Nothing about
a broken alert looks broken; it simply never triggers.

Worth distinguishing from a rule that is merely *inert*. This platform has both:
rules that error (this alert), and rules whose expression matches nothing at all,
which vmalert reports as perfectly healthy. The second kind needs an audit, not
an alert — the alert catalog marks the known ones with 💤.

## Impact

Whatever those rules protect is unprotected, and nothing else will tell you.

## Diagnosis

vmalert's API names the failing rule and the error:

```bash
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://localhost:8080/api/v1/rules' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    for r in g.get('rules',[]):
        if r.get('lastError'):
            print(r.get('name'), '->', r['lastError'][:120])"
```

```promql
sum by (group) (rate(vmalert_alerting_rules_errors_total[5m]))
sum(rate(vmalert_execution_errors_total[5m]))
```

Common causes: a PromQL error introduced by an edit, a query too slow for
`-datasource.queryTimeout` under load, or the datasource being unreachable.

## Mitigation

1. **Query error** → fix the rule in git; the operator regenerates the config.
2. **Timeout** → the rule is too expensive. A recording rule is the usual answer.
3. **Datasource unreachable** → not a rule problem; see
   [VMServiceDown](VMServiceDown.md).

## Escalation

Warning by label, but weigh it by which rule. A broken critical alert is a
missing safety net, and the incident it would have caught arrives without
warning.

## Related

- [VMAlertRecordingRulesError](VMAlertRecordingRulesError.md)
- [VMAlertTooManyMissedIterations](VMAlertTooManyMissedIterations.md)
- [VMAlertConfigurationReloadFailure](VMAlertConfigurationReloadFailure.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
