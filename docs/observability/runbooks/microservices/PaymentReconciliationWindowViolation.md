# PaymentReconciliationWindowViolation

| | |
|---|---|
| **Severity** | warning |
| **Signal** | `increase(payment_reconciliation_window_violations_total[1h]) > 0` |
| **Meaning** | The provider returned transactions **outside** the `[from, through)` window the reconciliation pass requested |

## Why this exists

The first GameDay's `PaymentReconciliationDiscrepancy` was a false positive
manufactured exactly this way: mockpay 1.0.0 ignored its `from`/`to` bounds,
so a bounded internal set faced the provider's whole ledger and every older
charge read as `missing_internal`. The pass now **verifies** the answer:
out-of-window rows are excluded from classification and the watermark holds,
so the window is re-covered on the next pass. This alert is what makes that
refusal visible — a silently held watermark would look like a reconciler
that stopped.

## Diagnosis

1. Payment logs carry one warning per excluded row:
   `provider transaction outside the requested window` with the id,
   `created_at`, and the bounds.
2. Compare with the provider's paging behaviour — is it ignoring bounds
   entirely (every row violates) or leaking edge rows (off-by-one on the
   half-open boundary)?
3. Check `payment_reconciliation_watermark_age_seconds` — it will grow while
   passes refuse to advance; `PaymentReconciliationStale` fires at 30m of
   that, which is the escalation.

## Mitigation

- Provider-side fix (mockpay: image skew — check the deployed tag against
  payment's, the F1 lesson). The watermark self-heals on the first clean
  pass; no manual advance exists, by design.

## Related

- `PaymentReconciliationStale` — the escalation when the frontier stays held
- `PaymentReconciliationDiscrepancy` — what this alert protects from false positives
