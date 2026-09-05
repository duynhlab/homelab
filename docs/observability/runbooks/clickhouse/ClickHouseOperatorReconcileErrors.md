# ClickHouseOperatorReconcileErrors

| | |
|---|---|
| **Severity** | warning |
| **Category** | observability |
| **Source** | `.../prometheusrules/observability/clickhouse-alerts.yaml` |
| **Metrics** | `clickhouse_operator_host_reconciles_errors` — operator control plane (`op-metrics`) |
| **Status** | active |
| **Dashboard** | ClickHouse → Server engine |
| **Local-stack** | not present |

## Meaning

`rate(clickhouse_operator_host_reconciles_errors[15m]) > 0` — the operator is
alive and **failing to reconcile hosts**. The CHI may be stuck between spec and
reality: what is declared in git is not what is running, and the operator cannot
close the gap.

Distinct from [ClickHouseOperatorDown](ClickHouseOperatorDown.md), where the
operator is absent. Here it is present, trying, and erroring — which is the
harder case, because the metrics view stays healthy and nothing else looks wrong.

## Impact

Changes to the `ClickHouseInstallation` do not land. A replica that dies may not
be replaced correctly. The running store is usually fine; what is broken is
convergence — the same class of failure as a stuck Flux Kustomization, one layer
down.

## Diagnosis

```bash
kubectl logs -n monitoring deploy/clickhouse-operator --tail=200 | grep -iE 'error|fail|reconcile'

# What the CHI thinks its own status is
kubectl get chi -n monitoring clickhouse -o jsonpath='{.status}' | head -c 800; echo

# Does the StatefulSet match the CHI's intent
kubectl get sts -n monitoring -l clickhouse.altinity.com/chi=clickhouse
kubectl get pods -n monitoring -l clickhouse.altinity.com/chi=clickhouse -o wide
```

### Causes seen on this platform

- **A pod cannot schedule.** The pod template uses
  `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity, one replica per
  node, and Kind has exactly three workers. If a node is unavailable the third
  replica cannot be placed, and that is deliberate — an unschedulable replica is
  a signal, not something to hide by relaxing the rule.
- **Kyverno admission.** The rendered pod must satisfy explicit namespace, a
  pinned image, requests plus a memory limit, and both probes. A change that
  drops any of them is rejected at admission and surfaces here.
- **A spec change the operator cannot apply in place.** Some CHI fields require
  recreation; the operator will error rather than act destructively.

### PromQL

```promql
rate(clickhouse_operator_host_reconciles_errors[15m]) > 0
clickhouse_operator_host_reconciles_errors
```

## Mitigation

1. Read the operator log first — it names the host and the reason.
2. If the cause is a rejected pod spec, fix it in git and let Flux apply it. Do
   not `kubectl edit` the CHI; the `clickhouse-local` Kustomization will revert
   it and you will lose the change without noticing.
3. If a replica is `Pending`, the fix is node capacity, not the anti-affinity
   rule.

## Escalation

Warning. Escalate if the CHI is stuck in a state where a replica is missing —
that is a redundancy loss, and the store is one failure from
[ClickHouseAllReplicasUnreachable](ClickHouseAllReplicasUnreachable.md).

## Related

- [ClickHouseOperatorDown](ClickHouseOperatorDown.md)
- [ClickHouseReplicaUnreachable](ClickHouseReplicaUnreachable.md)
- [FluxHelmReleaseNotReady](../gitops/FluxHelmReleaseNotReady.md)

---
_Last updated: 2026-09-05 — created; the clickhouse alert group had no runbooks at all_
