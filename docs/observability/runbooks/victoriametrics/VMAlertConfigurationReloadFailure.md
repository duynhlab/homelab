# VMAlertConfigurationReloadFailure

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmalert-alerts.yaml` |
| **Metrics** | `vmalert_config_last_reload_successful == 0` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAlert |
| **Local-stack** | present |

## Meaning

vmalert rejected a rule-configuration reload and **kept running the last good
set**. Evaluation continues; the rules being evaluated are stale.

Worse than the vmagent equivalent. A stale scrape config loses metrics you can
see are missing. A stale rule config means a **new alert you added is not
running**, and there is no way to tell from the outside — the absence of an alert
looks identical whether the rule is healthy and quiet or not loaded at all.

## Impact

Silent gaps in alert coverage. Anything added, fixed, or re-scoped since the last
successful reload is not in effect. On this platform that includes recent work:
newly wired `runbook_url` annotations, repaired expressions, and any rule added
in the last change.

## Diagnosis

```promql
vmalert_config_last_reload_successful
time() - vmalert_config_last_reload_success_timestamp_seconds     # how stale, in seconds
```

```bash
kubectl logs -n monitoring deploy/vmalert-victoria-metrics -c config-reloader --tail=50
kubectl logs -n monitoring deploy/vmalert-victoria-metrics --tail=100 | grep -i 'reload\|parse\|rule'

# Does the running rule count match what the repo declares
kubectl exec -n monitoring deploy/vmalert-victoria-metrics -- \
  wget -qO- 'http://localhost:8080/api/v1/rules' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('running rules:', sum(len(g.get('rules',[])) for g in d['data']['groups']))"
```

Comparing that count against the repo is the honest check — the staleness
timestamp tells you *when*, the count tells you *whether it matters*.

## Mitigation

1. Read the parse error; it names the rule group and usually the line.
2. Fix the `PrometheusRule` in git. The VM Operator converts it to a `VMRule` and
   regenerates vmalert's config — editing the generated object is pointless.
3. Verify with the rule count and the reload timestamp, not with the alert
   clearing.

## Escalation

Warning. Escalate if the last successful reload is hours old: every change since
then is unenforced, and the longer it runs the more likely someone is relying on
an alert that does not exist.

## Related

- [VMAlertAlertingRulesError](VMAlertAlertingRulesError.md)
- [VMAgentConfigurationReloadFailure](VMAgentConfigurationReloadFailure.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
