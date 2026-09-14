# KubeJobFailed

| | |
|---|---|
| **Severity** | warning |
| **Category** | workloads |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/workload-alerts.yaml` |
| **Metrics** | `kube_job_status_failed` (kube-state-metrics) |
| **Identity label** | `exported_namespace` is the Job namespace; `namespace` is the scrape target |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

A Job has failed pods for 5 minutes. The Job controller has exhausted (or is
burning through) its backoff retries — the work the Job carries did not
complete.

## Impact

A batch or backup task failed. The blast radius depends on the Job: a failed
database migration blocks the service rollout that waits on it, a failed
backup silently erodes the recovery point until the next successful run.

The alert summary and command use `exported_namespace`. On this platform,
kube-state-metrics is scraped without `honorLabels`; its target namespace is
stored as `namespace=kube-system`, while the observed Job namespace is
preserved as `exported_namespace`. Do not substitute the plain `namespace`
label when copying or editing this rule.

## Diagnosis

### kubectl / logs

```bash
kubectl describe job -n $NAMESPACE $JOB_NAME
kubectl logs -n $NAMESPACE job/$JOB_NAME --tail=200
```

### PromQL

```promql
# Alert expr
kube_job_status_failed > 0
```

Confirm that the selected series carries the Job identity expected by the
rendered command:

```promql
count by (exported_namespace, job_name, reason) (
  kube_job_status_failed > 0
)
```

## Mitigation

1. Check job logs for the failure reason.
2. For the migration init container (golang-migrate): check database
   connectivity and SQL syntax.
3. Retry: `kubectl delete job -n $NAMESPACE $JOB_NAME` (will be recreated if
   managed by Flux).

## Escalation

Ticket by default — most failed Jobs rerun cleanly once the cause is fixed.
Page if the failed Job is a database backup (recovery point at risk) or a
migration gating an in-flight release, especially when
[KubeDeploymentReplicasMismatch](KubeDeploymentReplicasMismatch.md) co-fires
on the waiting service. Do not blindly delete-and-retry a half-applied
migration Job: read the logs first, or the rerun can double-apply DDL against
an inconsistent schema.

---
_Last updated: 2026-09-14 — corrected the rendered namespace to the
kube-state-metrics `exported_namespace` label._
