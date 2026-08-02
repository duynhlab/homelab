# PaymentProviderUnknownRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability — provider answers going missing |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_provider_unknown_total{operation}`, `payment_provider_request_duration_seconds{op,outcome}` |

## Meaning
Provider round-trips are returning **no verdict at all** — a timeout, a
transport failure, or a 5xx — faster than one every twenty seconds. Each one
parks a payment.

This is the leading indicator: it fires while the backlog is still small, and
it points at the provider rather than at us. The distinction the metric encodes
matters: a 429 means the provider refused the request and did nothing with it
(decided, safe to redo, counted as `outcome="transient"`), while everything
counted here means the work may have happened.

## Impact
Customers on the affected path get 503 with "retry with the same
Idempotency-Key". Nothing is lost — resolution re-asks under the same key, so
the provider replays rather than repeats — but the doubt worklist fills and
will age into [PaymentDoubtStale](PaymentDoubtStale.md) if answers never come.

## Diagnosis
```promql
# which operation is affected
sum by (operation) (rate(payment_provider_unknown_total[15m]))

# is it slow, or silent? unknown = no answer; transient = refused
sum by (op, outcome) (rate(payment_provider_request_duration_seconds_count[5m]))
histogram_quantile(0.95, sum by (le, op) (
  rate(payment_provider_request_duration_seconds_bucket[5m])))

# is the mechanism keeping up?
sum(rate(payment_attempt_resolution_total[15m]))
max(payment_doubt_open)
```
Then check the provider itself. In this platform that is the `mockpay`
deployment:
```bash
kubectl -n payment get pods -l app.kubernetes.io/name=mockpay
kubectl -n payment logs deploy/mockpay --tail=100
```
A pod restarting, or NetworkPolicy blocking the hop, produces exactly this
signature. So does a magic-amount test: a charge ending in `13` withholds its
answer for 15 seconds on purpose, so an e2e run will move this counter
legitimately.

## Recovery
Restore the provider. Payment needs no intervention: every parked payment is
resolved by the next request that touches it, or by the one-minute sweep, both
re-asking under the original key.

## Prevention
- The sweep is bounded per tick so recovery does not become a stampede against
  a provider that is only just back.
- If this fires without a provider fault, suspect the hop: DNS, NetworkPolicy,
  or a client timeout shorter than the provider's own latency.

_Last updated: 2026-08-02_
