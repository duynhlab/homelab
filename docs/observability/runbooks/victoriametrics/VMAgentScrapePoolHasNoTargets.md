# VMAgentScrapePoolHasNoTargets

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/victoriametrics/vmagent-alerts.yaml` |
| **Metrics** | `vm_promscrape_targets{status="up"}` per pool |
| **Status** | active |
| **Dashboard** | VictoriaMetrics → VMAgent |
| **Local-stack** | present |

## Meaning

A scrape pool exists and matches **nothing**. The config is loaded, vmagent is
happy, and zero targets are being scraped.

This is the most dangerous shape of monitoring failure on this platform, because
it **reads as coverage**. A ServiceMonitor in git looks like the thing is
monitored; a pool with no targets means it is not, and nothing errors.

There is precedent worth remembering: the Kyverno admission webhook sat on the
write path of every apply with no scrape at all, because the values set
`serviceMonitor` at a nesting level the chart did not define — a flag that read
as enabled and did nothing.

## Impact

Silent blindness for whatever that pool was meant to cover. Every alert built on
those metrics becomes unfireable without saying so.

## Diagnosis

```promql
sum by (job) (vm_promscrape_targets{status="up"}) == 0
count by (job) (up)
```

```bash
kubectl exec -n monitoring deploy/vmagent-victoria-metrics -- \
  wget -qO- 'http://localhost:8429/api/v1/targets?state=dropped' | head -40

kubectl get servicemonitor,podmonitor,vmnodescrape -A | grep -i <name>
```

The usual causes are all selector problems: labels on the monitor that no Service
carries, a `namespaceSelector` that excludes the target, or a named port the
Service does not define.

## Mitigation

1. Compare the monitor's selector against the actual object labels — they
   disagree more often than anything else.
2. Named ports must exist on the Service. Operator-generated Services often carry
   only some ports, which is why several scrapes on this platform use PodMonitors
   instead.
3. If the pool is obsolete, delete it. A monitor kept "just in case" is a claim
   of coverage that is not true.

## Escalation

Warning by label. Weigh it by what is uncovered — a pool with no targets in front
of a critical component is effectively a missing alert.

## Related

- [VMAgentTooManyScrapeErrors](VMAgentTooManyScrapeErrors.md) — targets exist but
  fail, which is at least visible.
- [VMAgentConfigurationReloadFailure](VMAgentConfigurationReloadFailure.md)

---
_Last updated: 2026-09-05 — created; the victoriametrics alert groups had no runbooks at all_
