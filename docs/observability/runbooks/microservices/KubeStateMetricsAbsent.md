# KubeStateMetricsAbsent

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |
| **Metrics** | `kube_pod_info` (absent) |

## Meaning
`kube_pod_info` has no series. kube-state-metrics stopped reporting — or its
scrape broke.

## Impact
`MicroserviceDown` joins its heartbeat check against `kube_pod_info` (so that
rollout-replaced pods do not page). While this alert fires, that `and` matches
nothing: **no per-pod silent-death alert can trigger anywhere on the platform.**
`MicroserviceAllInstancesDown` (whole-app outage) does not use the join and
keeps working.

## Diagnosis
```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=kube-state-metrics
kubectl -n kube-system logs deploy/kube-state-metrics --tail=20
```
Then the scrape side: is vmagent still scraping the target
(`VMAgentScrapePoolHasNoTargets`), and does the query
`count(kube_pod_info)` return anything in VictoriaMetrics?

## Mitigation
Restore kube-state-metrics (restart the deployment; it is stateless). There is
no fallback mode to configure — the join is deliberately fail-closed-with-a-page
rather than fail-open-with-noise.

## References
- [MicroserviceDown](MicroserviceDown.md) — the alert this one guards

---
_Last updated: 2026-07-31_
