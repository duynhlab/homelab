# PaymentAttemptEvidenceLost

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness / money — unverified state |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_attempt_write_failures_total` |

## Meaning
A provider round-trip could not be written to `payment_attempts`.

That log is not bookkeeping — it is the only record of WHICH operation is in
doubt and under WHICH key to ask again. So payment refuses to park an intent
whose evidence did not land: a row in `processing` that no attempt explains
cannot be resolved by a retry or by the sweep, and only manual SQL would move
it. The pre-park state stands instead.

## Impact
The state that stands is a claim the provider never confirmed:

| Parked operation | What the row now says | What may be true |
|---|---|---|
| capture | `captured`, capture ledger posted | the provider never took the money |
| void | `voided` | the hold is still live |
| authorize | `pending` | a charge exists provider-side with no local reference |
| refund | `pending` | the refund may already have paid out |

Only reconciliation will notice the first two, and only if the provider
ledger is reachable.

## Diagnosis
```promql
sum by (operation) (increase(payment_attempt_write_failures_total[1h]))
```
Then find the window and the cause — the failure is also on the request span
with `payment.id`, `payment.operation` and `payment.outcome_class`
attributes, so a trace search on the error is the fastest route to the exact
payments.

```sql
-- payments touched in the window whose state has no matching attempt row
SELECT p.id, p.status, p.provider_payment_id, p.updated_at
FROM payments p
WHERE p.updated_at BETWEEN $FROM AND $TO
  AND NOT EXISTS (SELECT 1 FROM payment_attempts a WHERE a.payment_id = p.id);
```

The write itself failing almost always means the database was unavailable or
the table was locked; check CNPG cluster health for the same window.

## Recovery
1. Fix the underlying write failure first — everything else is downstream.
2. For each payment in the window, **verify against the provider by hand**.
   The service cannot do it: it has no record of which key was used.
3. Drive corrections through the service where a path exists (a capture
   retry, a refund retry under the original caller key). Reserve direct SQL
   for cases with no path, and record the decision.

## Prevention
A duplicate row refused by the one-SUCCESS-capture index is **not** counted
here — that is `ErrDuplicateAttempt`, which means another writer got there
first, not that evidence was lost.

_Last updated: 2026-08-02_
