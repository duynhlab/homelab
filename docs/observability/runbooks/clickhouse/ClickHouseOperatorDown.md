# ClickHouseOperatorDown

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `up{job=~".*clickhouse-operator.*"} == 0` |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present — no operator in the compose stack |

## Meaning

The Altinity `clickhouse-operator` (chart 0.27.3, ns `monitoring`) is not being
scraped for 10 minutes.

The operator pod carries **two** surfaces on one ServiceMonitor with two
endpoints, split by port: `ch-metrics` is the metrics-exporter (the CHI's engine
view, `chi_clickhouse_*`), and `op-metrics` is the operator control plane. Both
go down together when the pod does.

## Impact

Two distinct losses, and they matter differently.

**Reconciliation stops.** The CHI and CHK are no longer reconciled: a lost pod is
not recreated, spec changes are not applied, and the StatefulSets are frozen as
they are. Existing ClickHouse replicas keep serving — the data path does not go
through the operator.

**Half the monitoring goes blind.** Every `chi_clickhouse_*` series stops, which
means [ClickHouseReplicaUnreachable](ClickHouseReplicaUnreachable.md),
[ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md),
[ClickHouseDiskAlmostFull](ClickHouseDiskAlmostFull.md),
[ClickHouseDiskCritical](ClickHouseDiskCritical.md),
[ClickHouseTooManyParts](ClickHouseTooManyParts.md) and
[ClickHouseInsertsDelayed](ClickHouseInsertsDelayed.md) all go **silent, not
red**. The per-pod `:9363` alerts survive, because they scrape the servers
directly.

That asymmetry is the reason to treat this as more than a controller restart:
while it is down, an absence of ClickHouse alerts means nothing.

## Diagnosis

```bash
kubectl get pods -n monitoring -l app=clickhouse-operator -o wide
kubectl logs -n monitoring deploy/clickhouse-operator --tail=100
kubectl describe pod -n monitoring -l app=clickhouse-operator | tail -30

# Is it the pod, or the scrape
kubectl get servicemonitor -n monitoring | grep -i clickhouse
```

### PromQL

```promql
up{job=~".*clickhouse-operator.*"} == 0

# Confirm the blindness: these should be absent while it is down
count(chi_clickhouse_metric_fetch_errors)
```

## Mitigation

1. Read the logs before restarting — a crashlooping operator usually names its
   reason (RBAC, CRD version, memory).
2. The operator is a `HelmRelease`; if it will not come back, check
   [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md).
3. While it is down, monitor ClickHouse from the **server** side instead —
   `ClickHouseMetrics_*`, `ClickHouseAsyncMetrics_*` and `ClickHouseErrorMetric_*`
   are all still arriving from `:9363`.

## Escalation

Warning by severity, but weigh the blindness. If anything else about ClickHouse
is suspect at the same time, treat this as the first thing to fix — you cannot
diagnose the store while half its telemetry is missing.

## Related

- [ClickHouseOperatorReconcileErrors](ClickHouseOperatorReconcileErrors.md) — the
  operator alive but failing.
- [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md)

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
