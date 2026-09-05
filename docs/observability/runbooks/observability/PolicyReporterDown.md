# PolicyReporterDown

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/policy-reporter-alerts.yaml` |
| **Metrics** | `up{job=~".*policy-reporter.*"} == 0` |
| **Status** | active |
| **Dashboard** | Security → Kyverno / Policy Reporter |
| **Local-stack** | not present |

## Meaning

Policy Reporter is down. It is the **UI and metrics surface** over Kyverno's
`PolicyReport` objects at `kyverno.duynh.me`.

The distinction that matters, and the reason this is only a warning:
**enforcement is unaffected.** Kyverno's admission webhook is a separate
component and keeps admitting or rejecting exactly as before. What is lost is
*visibility* into what it decided.

## Impact

- `kyverno.duynh.me` is unavailable.
- Policy metrics stop, so any dashboard or alert reading them goes blank.
- `PolicyReport` objects **keep being written** by Kyverno — the data is intact,
  only the view is gone.

## Diagnosis

```bash
kubectl get pods -A | grep -i policy-reporter
kubectl logs -n <ns> deploy/policy-reporter --tail=80

# The data itself, straight from the API -- the fallback while the UI is down
kubectl get policyreport,clusterpolicyreport -A
kubectl get policyreport -A -o json | python3 -c "
import sys,json,collections
d=json.load(sys.stdin); c=collections.Counter()
for r in d['items']:
    for k,v in (r.get('summary') or {}).items(): c[k]+=v
print(dict(c))"
```

That last command is the point of this runbook: the reports are still there, and
`kubectl` reads them fine.

## Mitigation

1. It is a HelmRelease — [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md).
2. While it is down, use `kubectl get policyreport -A` rather than waiting for
   the UI.
3. Do **not** conclude that policy enforcement has stopped. If admission itself
   were failing, the symptom would be applies being rejected or hanging, not this
   alert.

## Escalation

Warning. Not urgent — no enforcement gap, and the underlying data is intact.

## Related

- [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md)
- Kyverno admission alerts — those *do* cover the enforcement path.

---
_Last updated: 2026-09-05 — created; this alert had no runbook_
