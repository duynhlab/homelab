# VMAlertRecordingRulesError

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_recording_rules_errors_total` |
| **Status** | active · 525 recording rules |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

A **recording** rule fails to evaluate. Recording rules pre-compute series that
other rules and dashboards then read, so a failure here propagates: the recorded
series stops updating, and everything downstream sees stale or absent data.

## Impact

Worse than it looks, because the failure is one step removed from where it shows.
An alert reading a recorded series that stopped updating does not error — it
evaluates against nothing and stays quiet. This platform has a documented case of
that exact shape: `edge:rq_429_ratio:rate5m` produced `samples=0` for months
because its source metric did not exist, and `Edge429RatioHigh` could never fire.
Nothing reported an error at any point.

## Diagnosis

```bash
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://localhost:8080/api/v1/rules' \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
for g in d['data']['groups']:
    for r in g.get('rules',[]):
        if 'record' in r or r.get('type')=='recording':
            if r.get('lastError') or int(r.get('lastSamples',0) or 0)==0:
                print(f\"{r.get('name'):45} samples={r.get('lastSamples')} err={r.get('lastError') or '-'}\")"
```

That query catches both failure modes at once: rules that **error**, and rules
that succeed while producing **zero samples**. The second is not this alert — it
is invisible to every alert — and it is the one worth looking for while you are
here.

## Mitigation

1. Fix the rule in git.
2. If it produces zero samples without erroring, check that its source metric
   actually exists. Names drift when a component is upgraded.

## Escalation

Warning. Escalate based on what reads the recorded series.

## Related

- [VMAlertAlertingRulesError](VMAlertAlertingRulesError.md)
- [VMAlertRemoteWriteDroppingData](VMAlertRemoteWriteDroppingData.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
