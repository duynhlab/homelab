# PaymentReconciliationDiscrepancy

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness / money — ledger vs provider drift |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_reconciliation_discrepancies_total{kind}` |

## Meaning
A reconciliation pass found at least one payment whose internal state
disagrees with the provider's ledger. Until RFC-0021 phase 6 this counter had
no alert at all — reconciliation found drift and told nobody.

Payments parked in `processing` are **excluded** from the report by design:
their disagreement is not drift, it is a question the attempt log owns and the
doubt sweep is working on. So anything counted here is real drift between what
we believe and what the provider holds.

Classes (`kind`):

| Class | Meaning |
|---|---|
| `status_mismatch` | both sides know the charge, they disagree about its state |
| `amount_mismatch` | the amounts differ (amount wins over status when both do) |
| `missing_provider` | we have a `provider_payment_id` the provider does not know |
| `missing_internal` | the provider has a charge we have no row for |

## Impact
Money is either collected and not booked, or booked and not collected. One
class self-heals: internal `authorized` while the provider says `captured` is
the lost-capture-response window, and auto-heal converges it by re-driving the
CAS-guarded capture without ever calling the provider (ADR-012). Every other
class waits for a human.

## Diagnosis
```sql
-- the most recent run and what it found
SELECT id, started_at, finished_at, status, scanned, found
FROM reconciliation_runs ORDER BY id DESC LIMIT 5;

SELECT provider_payment_id, class, internal_status, provider_status,
       internal_amount_minor, provider_amount_minor, resolution
FROM reconciliation_discrepancies
WHERE run_id = $RUN_ID ORDER BY class;
```
`resolution` tells you what the heal pass did: `healed`, `skipped` (not a
healable class, or a concurrent write won the CAS), `failed` (the heal errored
— also logged), or `detected` when heal is disabled.

Cross-check `missing_internal` against `payment_attempts`: a charge the
provider has and we do not is the classic lost-authorize-response, and it may
already be represented as a parked payment with no reference.

## Recovery
1. Confirm the provider's view directly for each discrepancy — the report is a
   snapshot and the provider may have moved since.
2. Drive corrections **through the service**: a capture retry, a void, or a
   refund posts the ledger legs and the outbox event together. Direct SQL
   changes the row and leaves the ledger asserting the opposite.
3. For `missing_internal` with no local row at all, the money exists at the
   provider with nothing claiming it — treat as an incident and reconcile the
   customer's order by hand.

## Prevention
- Auto-heal (`RECON_HEAL_ENABLED`) converges the one safe class. It is enabled
  only alongside these alerts, because a heal nobody can see is worse than a
  discrepancy nobody heals.
- Reconciliation v1 scans the full payment set per pass; windowing is a later
  slice.

_Last updated: 2026-08-02_
