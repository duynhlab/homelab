# PaymentDoubtSweepFailing

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / money — automatic resolution not running |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_doubt_sweep_failures_total` |

## Meaning
The background sweep skipped a worklist entry **entirely** — it never reached
the provider. This is deliberately distinct from a resolution that ran and
learned nothing: that one is progress, and it is counted as
`payment_attempt_resolution_total{outcome_class="UNKNOWN"}`.

Three shapes reach this counter:

| Cause | What the row looks like |
|---|---|
| The payment or refund would not load | a database error; usually transient |
| A refund carries no `idempotency_key` | pre-migration row — a replay would be a second payout, so the sweep refuses |
| An `authorize` attempt on a payment that already has a `provider_payment_id` | logically answered already; the row should have been closed |

## Impact
Those entries have **no automatic escape**. They will sit until a caller
happens to touch the payment, and otherwise age into
[PaymentDoubtStale](PaymentDoubtStale.md). Nothing is corrupted; nothing is
progressing either.

## Diagnosis
```promql
sum by (operation) (increase(payment_doubt_sweep_failures_total[1h]))
```
```sql
-- the entries the sweep cannot act on
SELECT a.id, a.payment_id, a.refund_id, a.operation, a.idempotency_key,
       a.created_at, p.status AS payment_status, r.status AS refund_status
FROM payment_attempts a
LEFT JOIN payments p ON p.id = a.payment_id
LEFT JOIN refunds  r ON r.id = a.refund_id
WHERE a.outcome_class = 'UNKNOWN' AND a.resolved_at IS NULL
ORDER BY a.created_at;
```
A NULL `payment_status` or `refund_status` in that join is the load failure.
An empty `idempotency_key` on a refund row is the unresolvable shape.

## Recovery
- **Database errors:** fix the database; the next tick retries by itself.
- **Refund with no key:** ask the provider by hand whether the refund exists
  for that charge and amount, then drive the answer through the service (a
  refund retry under the original caller key) rather than by SQL.
- **Already-answered authorize:** the payment has a provider reference, so the
  charge is known. Closing that attempt is safe once you have confirmed the
  reference matches.

## Prevention
Every attempt written since migration 000011 records its key, so the
unresolvable shapes are historical rows only.

_Last updated: 2026-08-02_
