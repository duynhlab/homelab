# PaymentReconciliationDiscrepancy

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness / money — ledger vs provider drift |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_reconciliation_discrepancies_total{class}` |

## Meaning
A reconciliation pass found at least one payment whose internal state
disagrees with the provider's ledger. Until RFC-0021 phase 6 this counter had
no alert at all — reconciliation found drift and told nobody.

Payments parked in `processing` are **excluded** from the report by design:
their disagreement is not drift, it is a question the attempt log owns and the
doubt sweep is working on. So anything counted here is real drift between what
we believe and what the provider holds.

Classes (`class` — the label matches the DB column since payment 1.5.2; it was `kind` before):

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
SELECT id, started_at, finished_at, status, transactions_scanned, discrepancies_found
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

### Rule out the window first — `missing_internal` is usually not drift

A pass compares a **window-bounded** internal set against whatever the provider
returns for the same bounds ([ADR-035](../../../proposals/adr/ADR-035-windowed-reconciliation/)).
The request is symmetric; nothing verifies that the **reply** was. A provider that
ignores, truncates, or paginates past the window answers with older charges, and
every one of them reads as `missing_internal` — a discrepancy that is an artefact
of the question, not a fact about the money.

Two cheap checks, in this order:

```sql
-- Does the internal row actually exist? If yes, this is NOT missing_internal.
SELECT id, status, amount_minor, created_at
FROM payments WHERE provider_payment_id = '<provider_payment_id>';
```

```bash
# Re-ask with a window that covers the charge's creation time. Explicit bounds
# only: a param-less run ADVANCES the watermark to now-5m and moves the ground
# you are testing. A backfill with an old `through` is a safe no-op.
kubectl exec -n payment deploy/payment -c payment -- wget -qO- --post-data='' \
  'http://localhost:8080/payment/v1/internal/payments/reconciliation/runs?from=<before>&through=<after>'
```

If the covering window returns **0** discrepancies while the automatic pass keeps
reporting the same charge, the books match and the window is the bug. The tell is
`transactions_scanned`: it should **shrink** as the window narrows. A count that
stays flat while the internal set narrows means the provider is not honouring the
bounds. Found this way by
[GameDay drill G5](../../../proposals/rfc/RFC-0021/gameday.md#g5--the-discrepancy-that-was-already-firing),
where a mockpay image pinned five minor versions behind payment discarded `from`
and `to` and manufactured a permanent critical alert.

A charge falls out of the automatic window's 1 h lookback about **65 minutes**
after creation, so this false positive has a signature: clean for an hour, then
dirty on every pass forever.

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
- Keep the provider's build in step with payment's. `mockpay` runs the payment
  image under a different subcommand, so its tag carries payment's
  `$imagepolicy` marker — a skew there is indistinguishable from money drift.
- Restarting `mockpay` empties its in-memory ledger and resets its `mp_N`
  counter. Expect a burst of `missing_provider` for every internal payment still
  inside the window (self-clearing as they age out), and note that
  `provider_payment_id` stops being unique across restarts.

_Last updated: 2026-08-02_
