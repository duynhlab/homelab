# KubeAPIServerHighLatency

| | |
|---|---|
| **Severity** | warning |
| **Category** | latency |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/apiserver-alerts.yaml` |
| **Metrics** | `apiserver_request_duration_seconds_bucket` (kube-apiserver) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

API server P99 latency exceeds 1s for non-LIST/WATCH verbs for 10 minutes.
The deployed expr also excludes CONNECT — exec/port-forward/attach are
long-lived streams whose "latency" is the session length.

## Impact

Controllers and CLI time out, and reconcile lags: Flux, the operators, and
HPA all react to the cluster more slowly, so rollouts stall and self-healing
is delayed. Application traffic is unaffected — this is control-plane
responsiveness, not the data path.

## Diagnosis

### PromQL

```promql
# Alert expr
histogram_quantile(0.99,
  sum by (le, verb, resource) (
    rate(apiserver_request_duration_seconds_bucket{job="apiserver", verb!~"LIST|WATCH|CONNECT"}[5m])
  )
) > 1

# P99 latency by verb and resource
histogram_quantile(0.99,
  sum by (le, verb, resource) (
    rate(apiserver_request_duration_seconds_bucket{verb!~"LIST|WATCH"}[5m])
  )
)
```

## Mitigation

1. Check for slow admission webhooks.
2. Check etcd latency.
3. Look for resource-intensive custom controllers.

## Escalation

Ticket by default — slow but succeeding control-plane calls degrade
operations, not shoppers. Page if it co-fires with
[KubeAPIServerErrorRate](KubeAPIServerErrorRate.md) or
[KubeAPIServerHighInflight](KubeAPIServerHighInflight.md), the classic
overload trio that precedes [KubeAPIServerDown](KubeAPIServerDown.md).
Do not delete admission webhooks (Kyverno's included) to shave latency — you
would be trading milliseconds for the cluster's policy enforcement.

## Related

- [KubeAPIServerDown](KubeAPIServerDown.md),
  [KubeAPIServerErrorRate](KubeAPIServerErrorRate.md),
  [KubeAPIServerHighInflight](KubeAPIServerHighInflight.md) — the four golden
  signals of the same control plane; read them together.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
