# PaymentDoubtStale

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness / money — unresolved provider outcome |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_doubt_oldest_age_seconds`, `payment_doubt_open` |

## Meaning
A provider round-trip has been unanswered for over an hour. RFC-0021 phase 6
lets payment record "we asked, and we do not know what happened" instead of
guessing — and the design is only defensible because that doubt is supposed
to settle itself. Two automatic paths exist:

- **the request path** — any operation touching the payment re-asks the
  provider first, under the original idempotency key
- **the sweep** — a one-minute ticker works the whole worklist oldest-first

An hour means neither is converging.

## Impact
One customer's money is in a state nobody can name. Depending on the parked
operation: a card may hold an authorization we cannot see, a capture may have
taken money the books do not confirm, or a refund may have paid out with no
row recording it. The order side fails closed — a cancellation on a
`processing` payment parks the order in `manual_review` rather than settling
it — so nothing downstream compounds the error, but nothing resolves it
either.

## Diagnosis
```sql
-- The worklist, oldest first. `operation` says WHAT is in doubt and
-- `idempotency_key` is what a replay must use.
SELECT a.id, a.payment_id, a.refund_id, a.operation, a.provider_status,
       a.idempotency_key, a.created_at, now() - a.created_at AS age
FROM payment_attempts a
WHERE a.outcome_class = 'UNKNOWN' AND a.resolved_at IS NULL
ORDER BY a.created_at;

-- What the payment claims right now.
SELECT id, status, provider_payment_id, amount_minor, captured_at, updated_at
FROM payments WHERE id = $PAYMENT_ID;
```

Three causes, distinguishable from the row:

| Symptom | Cause |
|---|---|
| `idempotency_key` empty on an `authorize` row | The charge cannot be replayed — its key came from the caller and was not recorded. No automatic escape exists. |
| Sweep failures counted for the same operation | The row will not load, or the refund has no key. See [PaymentDoubtSweepFailing](PaymentDoubtSweepFailing.md). |
| Neither | The provider is still not answering. Check `payment_provider_unknown_total` and the provider's own health. |

## Recovery
1. **Ask the provider yourself** for the reference in `provider_ref` (or, for
   an authorize with none, search the provider by amount and time window).
2. **Drive the answer through the service, not through SQL.** Any operation on
   the payment resolves it first — a `Capture`/`Void` retry, or a refund retry
   under the original key. That path posts the ledger legs and closes the
   attempt; hand-edited rows do neither.
3. Only if the service cannot reach the provider at all, record the operator
   decision and open an incident — do **not** flip `payments.status` by hand
   while the ledger says otherwise.

## Prevention
- An `authorize` attempt with no recorded key is the one unresolvable shape.
  It only occurs for rows written before the key column existed
  (migration 000011).
- Watch [PaymentProviderUnknownRate](PaymentProviderUnknownRate.md): it fires
  while the backlog is still small.

_Last updated: 2026-08-02_
