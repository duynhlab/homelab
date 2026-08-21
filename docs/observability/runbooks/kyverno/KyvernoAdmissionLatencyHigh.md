# KyvernoAdmissionLatencyHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | latency |
| **Source** | [`kyverno/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/kyverno/alerts.yaml) |
| **Metrics** | `kyverno_admission_review_duration_seconds_bucket` |
| **Status** | active |
| **Dashboard** | GitOps → Kyverno |
| **Local-stack** | not present — no Kubernetes admission layer in the compose stack |

## Meaning

The p99 of Kyverno's admission review has been above **1 second** for 10
minutes. For scale: the measured p99 on an idle cluster on 2026-08-21 was
**4.95 ms**, so the threshold sits roughly 200× above normal — this is not a
tight alert, and firing means something is genuinely wrong.

## Impact

Kyverno sits on the **write path** of every apply in the covered namespaces, so
its latency is the API server's latency for those requests. Past the API
server's webhook timeout the request fails outright, and — this is the part
worth internalising — **it does not fail looking like a Kyverno problem**.

That exact chain played out on 2026-08-21. A full node disk made webhook calls
exceed their 5s budget, and what an operator saw was:

```
ClusterSecretStore/openbao dry-run failed (InternalError): Internal error occurred:
failed calling webhook "validate.clustersecretstore.external-secrets.io": ...
context deadline exceeded
```

followed by 14 Kustomizations parked on `dependency ... is not ready`, then an
API server returning `EOF`, then a phantom `Forbidden` on VictoriaMetrics CRs.
Nothing in that sequence names latency, and none of it was an RBAC or
External Secrets defect.

## Diagnosis

### PromQL

```promql
histogram_quantile(0.99,
  sum by (le, job) (rate(kyverno_admission_review_duration_seconds_bucket[5m]))
) > 1

# Is it Kyverno's own work, or is it waiting on the API server?
histogram_quantile(0.99, sum by (le) (rate(kyverno_policy_execution_duration_seconds_bucket[5m])))
sum by (job) (rate(kyverno_client_queries_total[5m]))

# Is the whole node/API server slow, i.e. is Kyverno the symptom?
histogram_quantile(0.99, sum by (le) (rate(apiserver_request_duration_seconds_bucket[5m])))
```

If `policy_execution_duration` is fast while `admission_review_duration` is
slow, Kyverno is **waiting**, not computing — look outward.

### Grafana

- **GitOps → Kyverno** — admission review latency next to policy execution
  latency; the gap between them is the whole diagnosis.
- **Observability → Kubernetes cluster overview** — node CPU, memory and disk,
  to answer the "is Kyverno the symptom" question in one look.

### kubectl / logs

```bash
kubectl -n kyverno top pod
kubectl -n kyverno get pod -l app.kubernetes.io/component=admission-controller \
  -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'

# The platform-level checks first -- cheaper and more often the answer
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name) DiskPressure=\([.status.conditions[]|select(.type=="DiskPressure")|.status][0]) MemoryPressure=\([.status.conditions[]|select(.type=="MemoryPressure")|.status][0])"'
kubectl top nodes

# On Kind/podman the node filesystem is the podman machine's, and kubectl
# cannot see it filling up:
podman machine ssh "df -h /"
```

### VictoriaLogs / traces

```logsql
_time:30m namespace:"kyverno" | filter _msg:~"timeout|deadline|slow" | limit 50
```

## Mitigation

1. **Check node disk and pressure before touching Kyverno.** On Kind that means
   `podman machine ssh "df -h /"` — `kubectl` reports the node's *allocatable*
   figure and will look healthy while the machine's shared filesystem is full.
2. If the admission controller is CPU-throttled at its limit
   (`500m` today), raise the limit in
   [`kyverno/helmrelease.yaml`](../../../../kubernetes/infra/controllers/kyverno/helmrelease.yaml)
   — with the measurement in the commit message, matching how the rustfs and
   PgDog limits were raised.
3. If a single policy dominates `kyverno_policy_execution_duration_seconds`,
   look at its `match` breadth before its logic. A rule matching `kinds: [Pod]`
   cluster-wide costs more than one scoped to namespaces.

**Do not** widen `config.resourceFilters` to shed load. Those filters are the
platform's blast-radius control — `kube-system`, `flux-system`, `cert-manager`
and `external-secrets-system` are excluded deliberately so a Kyverno problem
cannot wedge Flux, and adding namespaces silently removes policy coverage from
them.

## Escalation

**Ticket** while applies still succeed. **Page** when webhook timeouts begin
appearing in Flux Kustomization messages or API server logs — at that point the
platform cannot converge, and the cause is very likely *not* Kyverno.

If a node disk or `KubeAPIServerHighLatency` alert co-fires, treat those as the
incident and this as a downstream reading.

## Related

```bash
git log --oneline -5 -- kubernetes/infra/controllers/kyverno/helmrelease.yaml
```

- [KyvernoControllerDown](./KyvernoControllerDown.md) — the hard version of the
  same failure.
- [KubeAPIServerHighLatency](../kubernetes/KubeAPIServerHighLatency.md) — the
  usual upstream cause.
