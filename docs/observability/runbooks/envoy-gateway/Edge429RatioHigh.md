# Edge429RatioHigh

| | |
|---|---|
| **Severity** | warning |
| **Category** | traffic |
| **Source** | [`envoy-gateway/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/envoy-gateway/alerts.yaml) |
| **Metrics** | `edge:rq_429_ratio:rate5m` (local rate-limit `rate_limited` counter) |

## Meaning

More than 5% of requests are being rejected by the edge's **local** token
buckets (ADR-045: local-first rate limiting, no global rate-limit service). The
counter is the edge's own, so these 429s never reached a backend.

## Impact

Real users are being turned away, or an abusive client is being contained —
those look identical in the ratio and opposite in the response. Deciding which
is the whole job of this runbook.

## Diagnosis

```promql
# Ratio and absolute volume: 5% of 10 rps is not 5% of 1000 rps
edge:rq_429_ratio:rate5m
sum(rate(envoy_http_downstream_rq_xx{envoy_response_code_class="4"}[5m]))
```

The access log is what separates one client from many, because the ratio cannot:

```logsql
{container_name="local-stack-gateway-1"} | json | status == 429
# group by `client` — one address dominating = containment working as designed
```

Also check whether the budget itself changed. The buckets are declared in
`BackendTrafficPolicy` (`configs/envoy-gateway/policies/btp-*.yaml`); a halved
budget looks exactly like a traffic spike.

```bash
git log --oneline -5 -- kubernetes/infra/configs/envoy-gateway/policies/
```

### Grafana

**Envoy Global** — response-class panel; a 4xx band appearing without a matching
rise in total requests points at a policy change rather than load.

## Mitigation

- Abusive single client: leave the limit alone; that is the limit working.
- Legitimate growth: resize the bucket in the policy manifest with the new
  number justified in the commit — and remember the local bucket is **per
  proxy**, so the effective budget scales with fleet size (ADR-045's known
  trade-off).
- Never raise a limit to silence the alert during an incident without recording
  why; the next reader needs the reasoning more than the number.

## Escalation

Ticket. Page only if the 429s are hitting checkout or payment routes, where a
rejected request costs an order.
