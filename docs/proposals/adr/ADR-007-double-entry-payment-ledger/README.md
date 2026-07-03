# ADR-007: Record money movement in an append-only double-entry ledger

Record every settled payment movement (capture, refund, reversal) as a balanced,
append-only double-entry ledger transaction, posted in the same database
transaction as the state change it settles.

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-04 | [RFC-0010](../../rfc/RFC-0010/) |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

The payment service tracks a payment's lifecycle on the `payments` row (a status
column plus lifecycle timestamps) and the sum of its `refunds`. That is enough to
answer *"what state is this payment in?"* but not *"where did the money go, and does
it all add up?"* — there is no independent audit trail, and nothing detects drift
between what the service believes and what actually settled at the provider.

Payments are money. We want an accounting record that is:

- **auditable** — every movement traceable to its source (capture / refund) and
  its provider reference;
- **self-checking** — a system-wide invariant that must always hold, so drift is
  detectable (the reconciliation phase will assert it);
- **immutable** — a posted entry is never edited; a correction is a new entry, so
  history cannot be silently rewritten.

Two constraints shaped the design. First, the local app role is a Postgres
**superuser** (`postgres`), and the cluster role is a dedicated owner — so any
"cannot modify" guarantee must hold even for a superuser. Second, the capture flow
already uses a compare-and-swap (CAS: `UPDATE … WHERE status = $expected`) and
must stay idempotent under crash-recovery re-drives; the ledger must inherit that
idempotency without a second, parallel mechanism.

## Decision

We will keep an **append-only, double-entry ledger** in three tables —
`ledger_accounts` (a fixed chart of accounts: `customer_funds`,
`merchant_revenue`, `provider_clearing`), `ledger_transactions` (one per
settled movement, tagged `capture | refund | reversal` with the provider
reference in `external_ref`), and `ledger_entries` (the balanced legs).

Every posting obeys **double-entry**: at least two legs, every amount positive,
and Σdebit = Σcredit — enforced in code before the insert. A capture posts
`debit customer_funds / credit merchant_revenue`; a refund and a failed-capture
reversal post the mirror. Balances and the "does everything net to zero?" guard
are **derived by querying the entries**, never stored.

Two mechanisms make it correct:

- **Posting rides the CAS, in the same transaction.** The ledger entry is written
  in the same DB transaction as the state change that settles the money, and only
  when that CAS actually flips a row. A stale CAS (re-entry, race, or an
  already-captured payment) flips nothing and therefore posts nothing — so the
  ledger is idempotent *by construction*, with no uniqueness index. The row and the
  ledger can never disagree, because they commit together. A provider-capture
  failure is compensated by a new **reversal** transaction (append-only — never a
  delete), netting the capture back to zero.
- **Append-only is enforced by triggers, not `REVOKE`.** `BEFORE UPDATE OR DELETE`
  (row) plus `BEFORE TRUNCATE` (statement — row triggers miss `TRUNCATE`) triggers
  on all three tables — entries, the transactions that give them meaning, and the
  fixed chart of accounts — raise an exception. A trigger fires even for a
  superuser; `REVOKE` would not, and would be a no-op against the local role. This
  is **defense-in-depth, not an absolute barrier**: a superuser can still `REPLACE`
  the trigger function. True tamper-resistance is a deployment property — in the
  cluster the ledger objects are owned by a migration role and the app role holds
  `INSERT`/`SELECT` only.

```mermaid
sequenceDiagram
    participant L as logic/v1
    participant DB as Postgres (one tx)
    participant P as provider
    L->>DB: BEGIN; CAS authorized→captured (RETURNING amount)
    alt row flipped (1 row)
        L->>DB: post balanced capture entries
        DB-->>L: COMMIT
        L->>P: capture
        opt provider fails
            L->>DB: BEGIN; CAS captured→authorized + reversal entries; COMMIT
        end
    else stale (0 rows)
        DB-->>L: ErrStaleTransition — nothing posted
    end
```

Only **settled** money is posted: authorize, void, and expire move a hold, not
money, so they post nothing.

## Alternatives considered

- **A single "amount settled" column on `payments`.** Simplest, but no audit trail,
  no independent record, and nothing to reconcile against — it restates the status,
  it doesn't corroborate it. Rejected: the whole point is an independent, checkable
  record.
- **Enforce immutability with `REVOKE UPDATE, DELETE`.** Standard, declarative, but
  a superuser bypasses grants — and the local app role *is* a superuser, so the
  guarantee would silently not hold in local/e2e. Rejected in favour of a trigger,
  which holds regardless of role.
- **Idempotent posting via a unique index (`payment_id, kind`) + `ON CONFLICT`.**
  Works for capture, but partial refunds legitimately produce several `refund`
  transactions per payment, so the index would have to special-case kind and refund
  id. The CAS-ride achieves idempotency for free and reuses the pattern the service
  already depends on. Rejected as redundant machinery.
- **Post the ledger after the provider confirms, in its own transaction.** Matches
  the intuition that money moves when the provider says so, but a crash between
  provider-success and the ledger write leaves a captured payment with no entry — a
  real imbalance. Posting in the same tx as the CAS (and reversing on provider
  failure) keeps the row and the ledger consistent at every instant. Rejected.

## Consequences

- **Capture is now a transaction.** It was a bare CAS; it becomes `CAS + ledger
  post` committed together (`CaptureWithLedger`), and a provider failure runs a
  compensating `ReverseCapture` transaction rather than a plain status rollback.
- **The ledger is queryable and self-checking.** Per-account balances and a global
  imbalance count (transactions whose legs don't net to zero, which must be 0) are
  available now; the reconciliation phase will assert the invariant continuously.
- **Corrections are additive.** Because entries are immutable, any fix is a new
  reversing transaction — the audit trail only ever grows.
- **Holds are not on the ledger.** Authorize/void/expire post nothing, so the ledger
  reflects settled money only; readers must not treat it as a lifecycle log.
- **The imbalance guard checks the ledger against itself, not the provider.** A
  crash between the capture commit and a confirmed provider capture leaves the
  ledger asserting revenue the provider never collected — internally balanced, so
  the guard reads 0. Closing this needs a provider↔ledger **reconciliation** sweep
  and a `provider_clearing` in-flight leg (customer_funds → provider_clearing on
  capture, → merchant_revenue on provider confirmation); both are deferred to the
  reconciliation phase, which depends on the provider/webhook work landing first.
  Until then the ledger is authoritative for *what the service settled*, not yet
  reconciled against *what the provider collected*.
- **Revisit trigger:** if payments span multiple providers or currencies, or if a
  cross-service ledger becomes necessary, the fixed three-account chart and the
  in-service posting model will need to be reopened.

---

_Last updated: 2026-07-04_
