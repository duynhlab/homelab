# PyroscopeDown

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/pyroscope-alerts.yaml` |
| **Metrics** | `up{job=~".*pyroscope.*"} == 0` — 2 targets (pyroscope + its alloy) |
| **Status** | active |
| **Dashboard** | Observability → Profiling |
| **Local-stack** | not present |

## Meaning

Continuous profiling is not being ingested or is not queryable. Two targets are
in scope: `pyroscope` itself and `pyroscope-alloy`, the agent that collects
profiles.

Which one is down matters: alloy down means profiles are not **collected**;
pyroscope down means they are not **stored or served**.

## Impact

Deliberately the mildest alert in the observability set. Profiling is a debugging
aid, not a production signal — nothing user-facing depends on it, and no other
alert reads from it.

What is lost is retrospective: profiles for the outage window will not exist when
someone later asks why a service was slow then.

## Diagnosis

```bash
kubectl get pods -n profiling 2>/dev/null || kubectl get pods -A | grep -i pyroscope
kubectl logs -n profiling pyroscope-0 --tail=80
kubectl logs -n profiling pyroscope-alloy-0 --tail=50
```

```promql
up{job=~".*pyroscope.*"}
count(up{job=~".*pyroscope.*"})       # 2 when healthy
```

Pyroscope is a StatefulSet with a PVC on `standard` — the same local-path story
as everything else, so disk pressure on its node is a plausible cause.

## Mitigation

1. **OOM or disk** → profiling retention is the lever; it is the least valuable
   data on the platform to shorten.
2. **Config or chart failure** → it is a HelmRelease;
   [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md).
3. Low urgency by design. Do not displace real work for it.

## Escalation

Warning, and rarely worth escalating on its own. Fix it during normal hours.

## Related

- [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md)
- [VMServiceDown](../victoriametrics/VMServiceDown.md) — same shape, far higher
  stakes.

---
_Last updated: 2026-09-05 — created; this alert had no runbook_
