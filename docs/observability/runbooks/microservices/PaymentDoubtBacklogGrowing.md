# PaymentDoubtBacklogGrowing

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / money — unresolved provider outcomes |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_doubt_open`, `payment_provider_unknown_total`, `payment_attempt_resolution_total` |

## Meaning
More than ten provider round-trips have been unanswered for half an hour. No
single one is old enough to page yet — that is
[PaymentDoubtStale](PaymentDoubtStale.md) — but the set is not draining.

Doubt is created by `payment_provider_unknown_total` and settled by
`payment_attempt_resolution_total`. A standing backlog means the first rate
exceeds the second.

## Impact
Each open entry is one customer whose payment answered 503 and whose money is
in an unnamed state. Nothing is lost — resolution re-asks under the same key,
so the provider replays rather than repeats — but the customer-facing path is
degraded and the backlog will age into the critical alert.

## Diagnosis
```promql
# doubt created vs doubt settled
sum(rate(payment_provider_unknown_total[15m]))
sum(rate(payment_attempt_resolution_total[15m]))

# which operation dominates
sum by (operation) (payment_doubt_open)     # if the gauge is split later
sum by (operation) (rate(payment_provider_unknown_total[15m]))

# is the provider simply slow or silent?
histogram_quantile(0.95, sum by (le, op, outcome) (
  rate(payment_provider_request_duration_seconds_bucket[5m])))
```

| Reading | Meaning |
|---|---|
| creation high, resolution high | The provider is flapping. The mechanism is working; wait, and watch the age. |
| creation high, resolution ~0 | The provider is down. Resolution has nothing to learn. |
| creation ~0, resolution ~0, backlog flat | The sweep is not running — check the payment pod's job logs for `Resolve unknown provider outcomes`. |

## Recovery
Usually none from our side: the mechanism is doing what it was built to do
while an upstream is unhealthy. Act when the backlog stops draining after the
provider recovers — that points at the sweep, not the provider.

## Prevention
The sweep is bounded at 50 entries per minute deliberately, so a provider
outage cannot turn into a flood against a provider that is already
struggling. A backlog larger than that drains at 50/min once answers return;
that is expected, not a fault.

_Last updated: 2026-08-02_
