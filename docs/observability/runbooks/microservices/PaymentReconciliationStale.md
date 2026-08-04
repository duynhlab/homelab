# PaymentReconciliationStale

| | |
|---|---|
| **Severity** | critical |
| **Category** | observability / money — the detector has stopped |
| **Manifest** | [`rfc0021-phase6.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) |
| **Metrics** | `payment_reconciliation_watermark_age_seconds`, `payment_reconciliation_runs_total` |

## Meaning
Reconciliation has not **completed** a pass in over 30 minutes.

The frontier (`reconciliation_watermark`) is where the last completed pass
finished, and it advances only on completion. Its age is therefore the one
signal that separates *"reconciliation is running and finding nothing"* from
*"reconciliation has stopped"* — the discrepancy counter reads zero in both
cases.

## Impact
Nothing user-facing is broken at the moment this fires. What it takes with it
is the reason it pages: while reconciliation is stopped,
[PaymentReconciliationDiscrepancy](PaymentReconciliationDiscrepancy.md) —
itself a page — **cannot fire at all**, so real ledger-vs-provider drift
accumulates unseen. A monitor that has stopped monitoring is an incident.

Healthy values sit **under ~600 seconds**: the window deliberately stops short
of now by a 5-minute settlement lag, and the age then oscillates by the
5-minute ticker interval between passes. A value that grows past that without
coming back down is the symptom.

## Diagnosis
```promql
# is it growing without bound, or just oscillating?
payment_reconciliation_watermark_age_seconds

# are passes running, and do they finish?
sum by (result) (increase(payment_reconciliation_runs_total[1h]))

# how long is a pass taking? a window that stops draining shows here first
histogram_quantile(0.95, sum by (le) (
  rate(payment_reconciliation_run_duration_seconds_bucket[15m])))
```

| Reading | Cause |
|---|---|
| `runs_total{failed}` rising | passes run and fail — check the payment logs for the detection error; the frontier is correctly refusing to advance |
| no `runs_total` increase at all | the ticker is not firing: the pod is down, or the reconciler was never constructed (no provider ledger configured → reconciliation disabled, and the trigger endpoint answers 503) |
| runs completing but the age still climbing | passes are completing over a window that keeps ending further in the past — look at run duration and at whether something is holding the lease |
| `409` from a manual trigger | the single-writer lease is held. If nothing should be holding it, look for a stuck session: `SELECT * FROM pg_locks WHERE locktype='advisory'` |

```sql
-- the frontier itself, and the last few passes
SELECT through_time, updated_at, now() - through_time AS age FROM reconciliation_watermark;
SELECT id, status, started_at, finished_at, scanned, found
FROM reconciliation_runs ORDER BY id DESC LIMIT 10;
```

## Recovery
1. **Restore whatever stopped the pass** — the pod, the database, or the
   provider ledger endpoint. The ticker resumes on its own; nothing needs
   re-arming.
2. **Do not advance the frontier by hand.** It means "everything before this
   has been compared", and moving it over ground nobody compared hides drift
   permanently. Let a real pass move it.
3. If the gap is long, **backfill explicitly** rather than waiting for the
   lookback to crawl over it:
   ```bash
   curl -X POST "http://payment:8080/payment/v1/internal/payments/reconciliation/runs?from=<RFC3339>&through=<RFC3339>"
   ```
4. Once passes complete again, check
   [PaymentReconciliationDiscrepancy](PaymentReconciliationDiscrepancy.md):
   drift that accumulated while the detector was down surfaces on the first
   successful pass.

## Prevention
A pass holds one pooled connection for its duration (the single-writer lease),
so pool exhaustion can starve it. `MicroserviceDown` and the database alerts
own the underlying causes; this alert exists because none of them can tell you
that the *consequence* — undetected money drift — is currently in effect.

_Last updated: 2026-08-04_
