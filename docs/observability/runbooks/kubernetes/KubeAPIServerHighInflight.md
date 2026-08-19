# KubeAPIServerHighInflight

| | |
|---|---|
| **Severity** | warning |
| **Category** | saturation |
| **Source** | `kubernetes/infra/configs/observability/metrics/prometheusrules/kubernetes/apiserver-alerts.yaml` |
| **Metrics** | `apiserver_current_inflight_requests` (kube-apiserver) |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

Inflight requests exceed 200 for 5 minutes. Something — usually a controller
in a tight reconciliation loop — is holding the API server's concurrency
budget open faster than requests complete.

## Impact

The control plane is saturated: once inflight hits the server's
`--max-requests-inflight` ceiling, new requests get 429-rejected, and
controllers across the cluster start missing their reconcile windows. This is
the saturation signal that precedes latency, errors, and ultimately an
unresponsive API server.

## Diagnosis

### PromQL

```promql
# Alert expr
max(apiserver_current_inflight_requests{job="apiserver"}) > 200

apiserver_current_inflight_requests
```

## Mitigation

1. Identify controllers making excessive API calls.
2. Check for tight reconciliation loops in Flux or other operators.
3. Increase API server `--max-requests-inflight` if legitimately needed.

## Escalation

Ticket by default — a plateau just above 200 with normal latency is a noisy
controller to hunt down. Page if inflight keeps climbing or
[KubeAPIServerHighLatency](KubeAPIServerHighLatency.md) /
[KubeAPIServerErrorRate](KubeAPIServerErrorRate.md) co-fire — that is the
overload spiral heading for [KubeAPIServerDown](KubeAPIServerDown.md).
Do not raise `--max-requests-inflight` as the first response: a hot
reconcile loop will consume any ceiling you give it, and the higher limit
just moves the collapse point.

## Related

- [KubeAPIServerDown](KubeAPIServerDown.md),
  [KubeAPIServerHighLatency](KubeAPIServerHighLatency.md),
  [KubeAPIServerErrorRate](KubeAPIServerErrorRate.md) — the four golden
  signals of the same control plane; read them together.

---
_Last updated: 2026-08-19 — split out of infrastructure-alerts.md into the kubernetes/ domain folder_
