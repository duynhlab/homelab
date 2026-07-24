# RFC-0021 — Baseline e2e results (phase 0)

The pre-refactor saga behaviors, proven on current `main` before any inventory
work lands (planning gate §0.7). Every later phase's acceptance runs are judged
against this record. Runner: a **local-only** driver script (kept out of the
repo — a developer convenience, not a tracked artifact) executed against a full
local-stack (`docker compose up -d --build`, all sibling repos on `main`). The
scenarios and their pass/fail table below are the durable record; the canonical,
tracked e2e gate is the Phase A/B/C protocol in
[`local-stack/README.md`](../../../../local-stack/README.md#e2e-audit-before-pushing-backend--real-browser).

| | |
|---|---|
| **Run** | 2026-07-23T03:34:00Z · local-stack, Kind not involved |
| **Result** | **18 PASS · 0 FAIL · 1 SKIP** (capture-failure injection — see S7) |
| **Owning RFC** | [README.md](./README.md) § Rollout (phase 0 exit) |

## Results

| Scenario | Check | Result | Detail |
|----------|-------|--------|--------|
| S1 happy path | confirm | PASS | order confirmed via saga |
| S1 | payment | PASS | captured |
| S1 | shipment | PASS | one shipment row |
| S1 | stock | PASS | 10−2=8 (reserve decrements `stock_quantity`) |
| S1 | cart | PASS | cleared post-pivot |
| S1 | notify | PASS | 2 inbox rows (order-placed + receipt) |
| S2 payment decline | decline | PASS | magic amount (total 25.02 → `%100==02`) → order failed |
| S2 | stock | PASS | untouched — authorize declined before reserve |
| S3 TOCTOU race | race | PASS | two users, last unit: exactly one winner |
| S3 | void | PASS | loser's authorization voided (compensation) |
| S3 | stock | PASS | last unit sold exactly once — no oversell |
| S4 duplicate confirm | replay | PASS | same Idempotency-Key → same order, one saga |
| S4 | effect | PASS | stock decremented exactly once |
| S5 shipment failure | fail | PASS | shipping down → retries exhausted → order failed |
| S5 | release | PASS | stock released by compensation |
| S5 | void | PASS | authorization voided |
| S6 worker outage | queued | PASS | order pending while worker down (durable task queue) |
| S6 | heal | PASS | worker restart → converged confirmed |
| S7 capture failure | capture | SKIP | mockpay drives failures from charge amounts only — no capture-failure knob; injection lands with the phase-7 chaos program |

## What this proves (and what it deliberately doesn't)

- The behaviors RFC-0021 must **preserve** across the extraction are green:
  all-or-nothing reserve with no oversell under contention (S3), full reverse
  compensation pre-pivot (S2/S5), confirm idempotency end to end (S4), and
  durable convergence across a worker outage (S6).
- S3 also demonstrates today's semantics the target model changes: the loser
  fails at *reserve* (after authorize), and "sold" is implicit in the
  decrement — under inventory, the same scenario must end with one
  `COMMITTED` reservation and one `RELEASED`.
- Capture-outcome-unknown and capture-definite-failure are **not provable
  today** (S7) — exactly the payment-hardening gap phase 6 addresses.

## Reproducibility

Repo SHAs the stack was built from (`main` everywhere):

| Repo | SHA |
|------|-----|
| auth-service | `05cf110` |
| user-service | `a0cf2ec` |
| product-service | `7a689e9` |
| cart-service | `42997a1` |
| order-service | `dc8bf3f` |
| checkout-service | `be4406c` |
| payment-service | `0db03d5` |
| shipping-service | `a507d7e` |
| notification-service | `c730817` |
| review-service | `293933c` |
| frontend | `adfaf56` |
| pkg | `decd505` |

Re-run: bring local-stack up healthy, then drive the scenarios above (the
local-only script paces calls ≥0.3s under Kong's 5 req/s limit, restores the
guinea-pig product row on exit, and exits non-zero on any FAIL) — or run the
tracked Phase A/B/C protocol from the local-stack README, which is the
canonical pre-push gate.

---
_Last updated: 2026-07-24_
