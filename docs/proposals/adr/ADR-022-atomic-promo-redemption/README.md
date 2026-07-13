# ADR-022: Count promo redemptions atomically at confirm, before the attempt marker

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-13 | [RFC-0015](../../rfc/RFC-0015/) |

## Context

Promo codes have three counters that must never lie: a global redemption cap,
a per-user limit, and "one use per purchase". The confirm flow they join is
already crash-hardened (ADR-018 and the P2 doubt cycles): an Idempotency-Key
claim, a session↔claim binding, and an attempt marker written strictly before
`CreateOrder` — replays and re-drives must converge without double effects.
Applying a code is a UX step (an abandoned session must never burn a use), so
the counting has to happen inside confirm, where every step already has
exactly-once semantics to preserve.

## Decision

We count a redemption in **one transaction at confirm, positioned strictly
BEFORE the attempt marker**, and skip it entirely on marker re-entries:

1. `SELECT … FOR UPDATE` on the `promo_codes` row — every redemption of a
   code serializes here, which makes the per-user `count(*)` phantom-free.
2. `INSERT INTO promo_redemptions … ON CONFLICT (code, session_id) DO
   NOTHING` — the idempotency anchor, evaluated **before** any expiry or cap
   check: a crash-re-driven confirm whose redemption already committed
   short-circuits to success, so time flipping the expiry between attempts
   can never reject (or strip) a redemption that already happened.
3. Only when the insert was real: expiry check, global-cap conditional
   increment, per-user count — any failure rolls the whole tx back.

Exhausted/expired at this gate **strips the promo to `shipping_set` under
the claim binding** (the PRICE_CHANGED shape) and releases the claim: a lost
409 followed by a same-key retry lands on INVALID_TRANSITION — the shopper
re-runs the funnel and *sees* the stripped totals — never a silent
full-price order. The Idempotency-Key is never consumed by a rejection.

The discount itself re-derives from fresh components at every totals change
(quote, address-invalidation re-clamp, confirm requote) and crosses
`CreateOrder` as `discount_minor` (with the P3-gap fix: fee and tax now
cross too), so the charged total equals the session total. Successful
confirms backfill `promo_redemptions.order_id` — ops can distinguish a used
redemption from a burned one.

## Alternatives considered

**Count at apply time.** Pros: trivial. Cons: every abandoned session burns
a use; un-counting on expiry needs a compensator with its own crash windows.
Rejected — the RFC's own requirement.

**Redeem after the marker (with `CreateOrder`'s idempotency as the shield).**
Pros: a redemption then provably implies an order attempt. Cons: the
doubt-cycle reviewers broke it twice — an exhausted/expired result after the
marker must strip the session, but un-parking a marker-set session violates
the P2 invariant (the marker means an order may exist), and clearing the
marker re-opens the requote-after-order hole. Rejected.

**Advisory-only caps (check at apply, trust the count).** Pros: no lock.
Cons: two same-user sessions racing a per-user limit of 1 both pass a read
check; the global cap overshoots under load. Rejected — the caps are the
product feature.

## Consequences

- Redemptions of one code serialize on its row: a viral code becomes a hot
  row. Acceptable at platform scale; a sharded counter is the escape hatch
  and would slot behind the same repo method.
- A redemption committed by a confirm that then parks forever (lost key,
  crash) stays burned until ops intervene; `order_id IS NULL` on the
  redemption row plus a terminal/parked session is the safe deletion
  signal (documented in the runbook). The apply-time preview honestly
  reflects such burned uses.
- Seeds (WELCOME10, SAVE5, EXPIRED1, ONETIME, SCARCE) ship in the migration
  for the learning platform — a real campaign lifecycle (activation windows,
  audit) is out of scope and noted as future work.
- Revisit trigger: promo stacking (multiple codes per session) or
  order-level refunds needing redemption reversal.

---
_Last updated: 2026-07-13_
