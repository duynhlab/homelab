# KubeAPIServerErrorRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | errors |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/apiserver-alerts.yaml` |
| **Metrics** | `apiserver_request_total` (kube-apiserver) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

5xx error rate exceeds 3% for 10 minutes. The API server is accepting
requests but failing them — on this platform the usual suspects are a broken
admission webhook or etcd trouble, not the API server binary itself.

## Impact

Reconcile and ops break: Flux applies, operator updates, and kubectl
mutations fail at a 3%+ clip, so GitOps drifts and rollouts half-apply.
A failing *mutating* webhook can push this toward 100% for the resources it
matches, blocking all writes of that kind.

## Diagnosis

### PromQL

```promql
# Alert expr
sum(rate(apiserver_request_total{job="apiserver", code=~"5.."}[5m]))
/ sum(rate(apiserver_request_total{job="apiserver"}[5m]))
> 0.03

# Error rate by verb and resource
sum by (verb, resource, code) (rate(apiserver_request_total{code=~"5.."}[5m]))
```

## Mitigation

1. Check for failing webhooks (`MutatingWebhookConfiguration`,
   `ValidatingWebhookConfiguration`).
2. Check etcd connectivity.
3. Review recent CRD changes.

## Escalation

Ticket by default at a few percent — retry loops in controllers absorb a lot.
Page if the rate climbs toward double digits, if writes to a whole resource
class are blocked by a dead webhook, or if
[KubeAPIServerHighLatency](KubeAPIServerHighLatency.md) /
[KubeAPIServerHighInflight](KubeAPIServerHighInflight.md) co-fire. Do not
delete a failing webhook configuration as a shortcut — Kyverno's admission
policies are the cluster's guardrails; fix or scale its backing pods instead.

## Related

- [KubeAPIServerDown](KubeAPIServerDown.md),
  [KubeAPIServerHighLatency](KubeAPIServerHighLatency.md),
  [KubeAPIServerHighInflight](KubeAPIServerHighInflight.md) — the four golden
  signals of the same control plane; read them together.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
