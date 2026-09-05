# VMAgentTooManyScrapeErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `vm_promscrape_scrapes_failed_total` |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

vmagent is failing to scrape targets. Note this is the **collection** end of the
pipeline — [VMRowsRejectedOnIngestion](VMRowsRejectedOnIngestion.md) is the other
end, and they have nothing to do with each other.

vmagent on this platform runs `selectAllByDefault`, so it picks up every
ServiceMonitor, PodMonitor and VMNodeScrape in the cluster. That is convenient
and it means **a broken scrape config anywhere becomes vmagent's problem**.

## Impact

The failing target's metrics are missing. Everything reading them — dashboards,
alerts, SLOs — degrades silently, because a missing series is not an error
anywhere. This is how an alert stops being able to fire without anyone noticing.

## Diagnosis

```promql
topk(10, sum by (job) (rate(vm_promscrape_scrapes_failed_total[5m])))
count by (job) (up == 0)
```

The targets page names the exact error:

```bash
kubectl port-forward -n monitoring deploy/vmagent-victoria-metrics 8429:8429 &
# then open /targets, or:
kubectl exec -n monitoring deploy/vmagent-victoria-metrics -- \
  wget -qO- 'http://localhost:8429/api/v1/targets' | head -40
```

Common shapes: a pod that no longer exists but whose monitor remains, a port that
moved, TLS or auth against a scrape that needs it, and a target whose `/metrics`
is slower than the scrape timeout.

## Mitigation

1. **Target genuinely gone** → remove the monitor. A monitor with no targets is
   worse than nothing: see
   [VMAgentScrapePoolHasNoTargets](VMAgentScrapePoolHasNoTargets.md).
2. **Target exists, endpoint wrong** → fix the monitor in git.
3. **Timeout** → the exporter is slow; raising the timeout hides it.

## Escalation

Warning. Escalate if the failing job backs an alert that matters — losing the
scrape silently disables every rule built on it.

## Related

- [VMAgentScrapePoolHasNoTargets](VMAgentScrapePoolHasNoTargets.md)
- [VMTooManyLogs](VMTooManyLogs.md)
- [VMRowsRejectedOnIngestion](VMRowsRejectedOnIngestion.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
