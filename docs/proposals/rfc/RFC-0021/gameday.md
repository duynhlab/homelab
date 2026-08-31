# RFC-0021 — GameDay drill record

Answers the phase-7 exit-gate question: **"do the GameDay scenarios converge?"**
Five faults injected against the Kind cluster `homelab` on 2026-08-06, each one
aimed at a claim quoted from a runbook or design doc. Recovery is not the
criterion — **the data must be shown to converge**, so every drill records the
data state, not an HTTP code.

| | |
|---|---|
| **Status** | first recorded GameDay run; 4 claims held, 2 falsified, 1 partial |
| **Owning RFC** | [README.md](./README.md) § Rollout & rollback — phase 7 exit gate |
| **Sibling** | [cutover-rollback.md](./cutover-rollback.md) — the phase-0 rollback story |
| **Cluster** | Kind `homelab`, 4 nodes, every app Deployment at 1 replica, zero HPAs |
| **Window** | 2026-08-06 09:59:53Z → 10:42:02Z (UTC throughout) |

Before this run, **no drill had ever been recorded anywhere in the repo** —
[`010.2`](../../../databases/runbooks/restore-and-failover-drills.md#where-evidence-lives)
carried a template and no results, and
[RFC-0007](../RFC-0007/) still said "no drill recorded yet". A drill with no
recorded evidence did not happen, so this file is the evidence.

## Verdicts

| Drill | Fault | Claim tested | Verdict |
|-------|-------|--------------|---------|
| [G1](#g1--kill-inventory-mid-checkout) | inventory-service to 0 replicas, 12 min | fail closed, never oversell; `confirming` recovers via `ExpireDue` **only** with the Temporal worker up | **held** (both halves, including the negative) |
| [G2](#g2--kill-order-worker-mid-saga) | order-worker force-killed | workflow resumes, order reaches terminal, no side effect twice | **held** |
| [G4](#g4--provider-lost-response) | provider creates the charge and withholds the answer | doubt parks, resolution closes it under the **original** key, no second charge | **held** — but the fault was **not injectable** until G5's fix landed |
| [G5](#g5--the-discrepancy-that-was-already-firing) | none — explain a live `PaymentReconciliationDiscrepancy` | "anything counted here is real drift" | **falsified** — false positive from an image-version skew |
| [G3](#g3--cnpg-switchover-under-load) | `product-db` primary switchover under a live checkout funnel | RPO 0, **RTO < 30 s**, automatic; `-rw` endpoints updated **< 5 s** | RTO **held** (11.4 s measured); the `< 5 s` endpoint step **falsified** (12.6 s) |

Two documented commands did not exist as written, and both were found by trying
them rather than by reading: see [Falsified claims](#falsified-claims).

## Method

Each drill quotes the claim it tries to falsify with a `file:line` reference. A
drill that cannot fail proves nothing, so the quote comes first and the fault is
chosen to contradict it.

```mermaid
flowchart LR
    CLAIM["Quote the claim<br/>file:line"] --> INJECT["Inject the fault"]
    INJECT --> OBSERVE["Record: shopper view,<br/>alerts, DATA STATE"]
    OBSERVE --> RESTORE["Restore"]
    RESTORE --> CONVERGE["Prove convergence<br/>in the data"]

    classDef platform fill:#7c3aed,color:#fff,stroke:#5b21b6;
    classDef external fill:#64748b,color:#fff,stroke:#334155;
    classDef metric fill:#ffe8cc,color:#111,stroke:#e8590c;
    classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
    classDef data fill:#22c55e,color:#052e16,stroke:#15803d;
    class CLAIM platform;
    class INJECT external;
    class OBSERVE metric;
    class RESTORE service;
    class CONVERGE data;
```

**Harness.** A shopper is registered at the edge (`https://localhost`, header
`Host: gateway.duynh.me`), then driven through cart → session → address →
shipping → payment → confirm. `alice` does not exist on a fresh cluster. Totals
are steered onto mockpay's magic suffixes by choosing the catalogue price:
`total_minor = subtotal + 900 + floor((subtotal + 900) × 725 / 10000)` for a
`US` destination, so a `3.25` product bills `1313` and a `3.30` product bills
`1319`. Three catalogue products were created through the internal route and
given `inventory_balances` rows by hand; without a balance row checkout fails
closed at 503 and the drill measures the wrong thing.

## G1 — kill inventory mid-checkout

**Claims.** Both from
[`CheckoutAvailabilityErrors.md`](../../../observability/runbooks/microservices/CheckoutAvailabilityErrors.md):

> `:68` — "**Restore inventory.** There is nothing to fail over to, and that is by design."

> `:75-76` — "Sessions stuck at `confirming` recover when `expires_at` elapses via `ExpireDue`; confirm the Temporal worker is running, since that branch is its job."

The second sentence has two halves and only one had ever been exercised. The
negative half — that the session does **not** recover with the worker stopped —
is the falsifiable one, so the drill stopped the worker on purpose.

**Fault.** `kubectl delete pod -n inventory -l app.kubernetes.io/name=inventory`
then `kubectl scale deploy/inventory --replicas=0` to hold the outage. With one
replica and no HPA this is a total outage of the availability authority, which is
exactly the condition the fail-closed claim is written against. `drain` is not
usable here: the `*-primary` PDBs report `ALLOWED DISRUPTIONS: 0`.

| Step | Time (UTC) | Result |
|------|-----------|--------|
| inventory killed, replicas → 0 | 09:59:53.983 | `No resources found in inventory namespace` |
| checkout-worker → 0 replicas (for the negative half) | 10:01:23.717 | 8 sessions parked at `ready`/`confirming` |
| first confirm during the outage | 10:00:07 | **503** `{"code":"INTERNAL_ERROR","error":"Confirm temporarily unavailable, retry with the same Idempotency-Key"}`, header `retry-after: 2` |
| same-key retry | 10:00:08 | **503** again — not `409`, so the key really was released on a detached context |
| sustained load, 8 shoppers × ~10 min | 10:01:38 → 10:12:16 | **579 × 503**, 13 × 429 (Kong's 5/s edge limit), **zero 409 STOCK_UNAVAILABLE** |
| inventory restored | 10:12:16.266 | rollout complete in ~30 s |
| past every `expires_at`, worker still down | 10:31:37.464 | all 8 sessions **still `confirming`**, `all_past_due = t` |
| `GET` one session past expiry | 10:31:37 | **200**, still `confirming` — a read does not lazy-expire this state |
| checkout-worker restored | 10:32:03.241 → ready 10:32:10.802 | — |
| all 8 sessions recovered | 10:32:06.584 → 10:32:07.583 | `expired`, `expired_reason = timer` |

**Data state during the outage** — the whole point of the drill:

| Fault injected | Shopper outcome | Data row |
|---|---|---|
| availability authority absent, 592 confirm attempts | 503 + `Retry-After: 2`, key reusable | `orders` **unchanged** (2 rows), `inventory_movements` **unchanged** (4 rows), `inventory_balances` **unchanged** (`26/50/50`), 8 sessions at `confirming` |
| same, past `expires_at`, Temporal worker down | session unusable, no exit | 8 rows still `confirming`, `expired_reason` NULL — **the negative half of the claim, never previously tested** |
| worker restored | — | 8 rows → `expired`/`timer` within **4 s** of the worker becoming ready, 2 m 45 s after the earliest `expires_at` |

**Converged.** Never out-of-stock, nothing half-written, and the parked sessions
were released the moment their owner came back. Both halves of the runbook
sentence are now evidenced: the `ExpireDue` branch is genuinely the worker's job,
and with the worker gone the session has no other exit — matching
[`checkout.md`](../../../api/checkout.md) on `confirming` having no FSM edge to
`cancelled` and `lazyExpire` skipping the state.

**Alerts.**

| Alert | Severity | Fired | Resolved | Note |
|---|---|---|---|---|
| `CheckoutAvailabilityErrors` | critical | 10:11:15 (activeAt 10:00:30) | between 10:22:17 and 10:22:37 | fired **11 m 22 s** after the fault — `for: 10m` on a `[10m]` ratio; resolved ~10 min after restore, as the rate window emptied |
| `CheckoutHighErrorRate` (sloth burn rate) | **page** | 10:00:45 — **52 s** after the fault | **not resolved** by 10:42:02 | the fast-burn page is the real detector here |
| `CheckoutHighErrorRate` / `CheckoutHighOverallErrorRate` | ticket | already firing at 07:59:45, **before the drill** | — | pre-existing; cannot be used as drill evidence |

Two things worth carrying into on-call habits. First, the runbook for this alert
mentions **no** burn-rate or SLO alert at all (`grep -i 'burn\|slo\|error budget'`
returns nothing), yet the burn-rate page is what actually pages in under a
minute while the alert the runbook is named after takes eleven. Second, the
slow-burn ticket alerts were **already firing before the drill started**, so
"fired then resolved" is only demonstrable for the critical alert and the page.

**These readings are pre-#675.** One deliberate fail-closed condition paged
**twice** here — once through the precise `CheckoutAvailabilityErrors` rule and
once through the Sloth burn-rate page — which is exactly the duplicate-paging
that PR #675 landed Alertmanager inhibition for. That PR merged at **10:36:59Z**,
inside this drill's window and after every G1 observation above, so the table
records the behaviour it fixes rather than contradicting it. Re-running G1 after
#675 has reconciled should show the precise alert firing alone; that re-run has
not been done.

**Alert-volume note.** Generating >1 % of a `[10m]` ratio needs more than six
error checks in the window, because the denominator is `clamp_min(…, 1)`. One
failing basket does not move this alert; a single-shopper drill would have
concluded, wrongly, that the alert does not work.

## G2 — kill order-worker mid-saga

**Claims.**

> [`RFC-0021/README.md:324`](./README.md) — "kill-the-worker chaos between activity commit and response"

> [`RFC-0007/README.md:92`](../RFC-0007/) — Drill E pass criterion: "Workflow resumes; order reaches a terminal state"

Convergence here means more than a terminal status: **no side effect may have
happened twice**. The tripwires are `payments`, `ledger_transactions` where
`kind='capture'`, `inventory_movements`, and `inventory_reservations` — the last
because a `Release` that overtakes its `Reserve` would leak a hold, and v1
reservations never expire.

**G2a — worker absent for the whole saga.** The order-worker was force-killed and
scaled to 0, then a confirm was issued.

| Step | Time (UTC) | Result |
|------|-----------|--------|
| worker force-deleted, replicas → 0 | 10:15:23.540 | `--grace-period=0 --force`, no graceful drain |
| confirm | 10:15:23.827 | **201** — the shopper sees success; the handoff is async by design |
| observed state, worker down | 10:15:5x | order 4 `pending`, `workflow_id` NULL, outbox row `DISPATCHED`, workflow `order-fulfillment-4` **Running** with history `[WORKFLOW_EXECUTION_STARTED, WORKFLOW_TASK_SCHEDULED]` and `Pending Activities: 0` |
| side effects while parked | — | balances `26/50/49` unchanged, **no** payment row for order 4 |
| worker restored | 10:16:03.910 → ready 10:16:18.448 | — |
| order completed | 10:16:14.339 | terminal, before the rollout was even marked available |

The workflow was started by the **order API** pod, not the worker — so the fault
parks the saga at its first workflow task rather than losing it. That is the
durable-execution claim doing its job, and it is why the outbox row already read
`DISPATCHED`.

**G2b — force-kill 3 s into a live saga.** Ran, but the saga completes in ~700 ms
end to end (`AuthorizePayment` … `CapturePayment` all inside `10:16:59.62`–
`10:17:00.34`), so the kill at 10:17:02.576 landed after the last activity. The
intended "between activity commit and response" interleaving is **not reachable
by hand** at this saga latency. The genuine version of that interleaving was
reached in [G4](#g4--provider-lost-response) instead, where the provider holds
the response open for 15 s.

**Data state after resumption** (order 4):

| Fault injected | Saga outcome | Data row |
|---|---|---|
| worker absent for the entire saga, ~50 s | order **completed** | `payments` **1** row, `captured`, `mp_4`; `ledger_transactions kind='capture'` **1**; `payment_attempts` exactly `authorize SUCCESS` + `capture SUCCESS`; `inventory_movements` exactly `res:4:1` + `cmt:4:1`; balance `26 → 25`; reservation 4 `committed` |

**Converged.** Workflow resumed, order terminal, and every side effect appears
exactly once. The deterministic command ids (`res:<order>:<wh>`,
`cmt:<order>:<wh>`, unique on `inventory_movements.command_id`) and the
per-order payment key are what make the replay harmless.

## G4 — provider lost response

**Claim.**

> [`PaymentProviderUnknownRate.md:52-55`](../../../observability/runbooks/microservices/PaymentProviderUnknownRate.md) — "Restore the provider. Payment needs no intervention: every parked payment is resolved by the next request that touches it, or by the one-minute sweep, both re-asking under the original key."

**Fault.** A total whose minor value ends in `13`. mockpay mints the charge and
then goes silent past the client's 10 s timeout, so "the provider did it and we
do not know" is reproducible without killing anything.

**The fault was not injectable when the drill started.** A `1313` confirm at
10:16:59 was captured normally — no withhold, no doubt. The cause is the same
image skew G5 turned out to be: the cluster's mockpay predates the phase-6
ambiguity triggers. G4 only became runnable after the [G5](#g5--the-discrepancy-that-was-already-firing)
fix. That ordering is itself the finding: **the fault-injection matrix in
`docs/api/payments.md` was verified on local-stack, and nothing verified it in the
cluster** — which is where the phase-7 gate is assessed.

| Step | Time (UTC) | Result |
|------|-----------|--------|
| confirm, total `1313` | 10:33:11.840 → 10:33:12.170 | **201** in 0.32 s — shopper sees success |
| provider mints the charge | 10:33:12.267 | `mp_2`, `1313`, then silent |
| client gives up | 10:33:22.263 | `payment_attempts` id 14: `authorize`, `outcome_class = UNKNOWN`, `provider_status = no_answer`, key **`15:order:7`** |
| resolution re-asks | 10:33:22.377 | `payment_attempts` id 15: `authorize`, `SUCCESS`, key **`15:order:7`** — the *same* key |
| doubt closed | 10:33:22.380 | attempt 14 `resolved_at` set — **117 ms** of open doubt |
| order terminal | 10:33:23.145 | `pending → confirmed → completed` |

**Data state:**

| Fault injected | Saga outcome | Data row |
|---|---|---|
| provider created the charge, withheld the answer | order **completed** | provider ledger exactly **2** charges (`mp_1` from the G5 check, `mp_2` from this drill) — **no second charge**; `payments` 1 row `captured`; `ledger_transactions kind='capture'` **1**; `inventory_movements` exactly `res:7:2` + `cmt:7:2`; `payment_doubt_open` back to **0** |

**Converged**, and the claim holds in its strongest form: the re-ask used the
original key, the provider replayed rather than re-charged, and no operator
touched anything.

Two honest qualifications. The park was resolved by the **request path**, not the
one-minute sweep — the saga's own retry got there first, which is the common case
the runbook describes but leaves the sweep untested. And `payments.status` was
never directly observed at `processing`: the park lasted 117 ms and the evidence
is the attempt log, which is the row the design says owns it. A separate reading
worth a follow-up: `payment_provider_unknown_total{operation="authorize"}` and
`payment_provider_request_duration_seconds_count{op="charge",outcome="unknown"}`
both read **2** against a single parked attempt row, so the counter is counting
round-trips the attempt log does not distinguish.

## G5 — the discrepancy that was already firing

**Claim.** From the alert this drill had to explain, firing since 09:11:15 with a
real `payment_reconciliation_discrepancies_total{kind="missing_internal"} = 1`:

> [`rfc0021-phase6.yaml:141-145`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-phase6.yaml) — "Parked payments are excluded from the report by design … so anything counted here is real drift"

> [`PaymentReconciliationDiscrepancy.md:58-60`](../../../observability/runbooks/microservices/PaymentReconciliationDiscrepancy.md) — "Drive corrections **through the service**: a capture retry, a void, or a refund posts the ledger legs and the outbox event together. Direct SQL changes the row and leaves the ledger asserting the opposite."

**Verdict: false positive.** No money drifted. The discrepancy was manufactured
by the question, not found in the books.

**Root cause.** mockpay was pinned at `1.0.0`
([`kubernetes/apps/mockpay.yaml`](../../../../kubernetes/apps/mockpay.yaml), set
once in PR #438 and never bumped) while payment ran `1.5.0`. mockpay `1.0.0`'s
`GET /transactions` reads `page`/`page_size` only — it has no `created_at` on the
transaction at all, so it **cannot** honour `from`/`to` and returns the whole
ledger. Windowed reconciliation
([ADR-035](../../adr/ADR-035-windowed-reconciliation/)) compares a
window-bounded internal set against that unbounded reply, and every charge older
than the window reads as `missing_internal` — precisely the artefact the design
names and claims to avoid.

The timeline the alert drew is fully explained by the automatic window
(`[frontier − 1h, now − 5m]`, frontier trailing 5 min): a charge is inside the
1 h lookback for about 65 minutes after creation and permanently outside it
afterwards.

| Run | Time | Scanned | Found | Why |
|---|---|---|---|---|
| 1 | 08:00:54 | 1 | **1** | charge created 07:59:35 is *above* the first `through` of 07:55:54 |
| 2–14 | 08:05:54 → 09:05:54 | 1 | 0 | inside `[frontier − 1h, through]` |
| 15+ | 09:10:54 onward | 1 | **1** | frontier − 1h passed 07:59:35 — outside forever |

**Proof by explicit window** — driven through the service's own endpoint, per the
runbook's "through the service" instruction, with no SQL written:

| Window asked for | `transactions_scanned` | `discrepancies_found` |
|---|---|---|
| `from=07:00Z&through=10:00Z` (covers the charge) | 2 | **0** |
| `from=09:00Z&through=10:00Z` (excludes it) | **2** | **1** — `mp_1`, `missing_internal` |

`transactions_scanned` pinned at 2 in both runs is the tell: if the provider had
honoured the bounds, the second run would have excluded `mp_1` from *both* sides
and scanned 1. It did neither. Confirmed directly against the provider —
`GET /transactions?from=…&to=…` on mockpay `1.0.0` returned all five charges,
byte-identical to the unbounded call.

**Fix, and its verification.** `mockpay.yaml` now pins `1.5.0` — the tag that
added the windowed listing (payment-service PR #52) and already matches payment —
plus payment's `$imagepolicy` marker so the two cannot drift apart again. Rolled
on the cluster at 10:21:19 and re-measured:

| Check | mockpay 1.0.0 | mockpay 1.5.0 |
|---|---|---|
| malformed `from` | silently ignored | **400 Bad Request** (refused, not dropped) |
| transaction shape | no `created_at` | carries `created_at` |
| window excluding the only charge | returns it | `total: 0` |
| recon run, window excluding the charge | `scanned` 2, found 1 | **`scanned` 0** |
| recon run, window covering the charge | — | `scanned` 1, **found 0** |

**Consequences of the roll, recorded because they will confuse the next reader.**
mockpay's state is in-memory, so restarting it emptied the provider ledger and
its `mp_N` counter reset. Two effects:

1. Internal payments 3–5, still inside the recon window, became
   `missing_provider` — a *second* `PaymentReconciliationDiscrepancy` series
   (`kind="missing_provider"`, activeAt 10:26:15). It self-clears as those rows
   age out of the 1 h lookback, roughly 11:22.
2. `payments.provider_payment_id` now holds `mp_1` **twice** (payment 1 from
   07:59, payment 6 from 10:22). Restarting an in-memory provider breaks the
   uniqueness of the provider reference.

Neither is money drift, and both are artefacts of using a mock. They are worth
knowing before anyone restarts mockpay in anger during an incident.

**Closing evidence, 11:02.** The automatic 5-minute pass is clean and its scan
count now tracks the window instead of the whole ledger:

| Run | Time | `transactions_scanned` | `discrepancies_found` |
|---|---|---|---|
| 73 | 10:45:54 | 18 | **0** |
| 74 | 10:50:54 | 19 | **0** |
| 75 | 10:55:54 | 19 | **0** |
| 76 | 11:00:54 | 19 | **0** |

The `missing_provider` burst from the restart stopped at 10:40:54 after 26 rows
and has not recurred — it aged out of the lookback exactly as predicted, with no
intervention. Both alert series are still `firing` at 11:03 because the
expression is `increase(…[1h]) > 0`: they clear about an hour after their last
increment (`missing_internal` ~11:21, `missing_provider` ~11:41). **A counter-based
alert with a 1 h window cannot show recovery any faster than that**, which is
worth knowing before someone reaches for a second fix during an incident.

## G3 — CNPG switchover under load

**Claim.**

The pre-drill estimates under test were RPO 0, database failover under 30
seconds, and the `-rw` endpoint update under 5 seconds. Those estimates were
retired after this GameDay produced measured application-visible evidence.

**Instrumentation.** Two probes at 0.3 s / 0.5 s resolution ran across the
switchover, plus a 10-shopper confirm funnel at 1.2 s spacing:

- **write probe** — `POST /cart/v1/private/cart`, an `INSERT … ON CONFLICT` that
  [`cart.md:137-138`](../../../api/cart.md) says the pooler must route to the
  primary. This measures *app-visible write availability through PgDog*, which is
  the number the claim is really about.
- **topology probe** — `endpointslice` for `product-db-rw` plus
  `.status.currentPrimary` / `targetPrimary` / `phase`.

**Fault.** `kubectl cnpg promote product-db product-db-2 -n product`, issued
10:39:32.531. The documented command does not exist — see below.

| Time (UTC) | +Δ from promote | Topology | Write probe |
|---|---|---|---|
| 10:39:32.531 | — | `currentPrimary` `product-db-1` | 200 |
| 10:39:32.902 | +0.373 s | `targetPrimary` → `product-db-2`, phase `Switchover in progress`; `-rw` still `10.244.2.32` | 200 |
| 10:39:33.246 | +0.717 s | — | **first 500** |
| 10:39:34.298 | +1.769 s | **`-rw` endpoints EMPTY** | 500 |
| 10:39:42.050 | +9.521 s | `currentPrimary` → `product-db-2` | — |
| 10:39:44.685 | +12.156 s | — | **first 200 again** |
| 10:39:45.157 | +12.628 s | **`-rw` → `10.244.1.28`** | 200 |
| 10:40:03.043 | +30.513 s | phase → `Cluster in healthy state` | 200 |

**Measured RTO = 11.4 s** (first write failure 10:39:33.246 → first subsequent
success 10:39:44.685; 4 failed samples out of 108). The `-rw` endpoint list was
**empty for 10.9 s**, which accounts for almost the whole outage: PgDog followed
the DNS change promptly once there was something to follow.

**Data state:**

| Fault injected | Shopper outcome | Data row |
|---|---|---|
| primary switchover, 10 confirms across the window | 3 × 201 before, **4 × 500**, 3 × 201 after | the 4 failures wrote **nothing**: sessions left at `ready` with `order_id` NULL — failed closed, never half-written |
| same-key retry after failover | **201**, order created | the idempotency key really was released |
| whole-cluster invariant, after | — | **24 orders, all `completed`**, zero non-terminal; **24 payments, 24 distinct `order_id`**, all `captured`; zero duplicate `capture` ledger legs; `inventory_reservations` 24 `committed` / **0** other; `reserved = 0` and `sum(reserved_delta) = 0` on every SKU, so no leaked hold; `on_hand` reconciles exactly against `sum(on_hand_delta)` per SKU |

**Converged**, and RPO 0 held — nothing was lost and nothing was half-written.

**Two findings the claim did not cover.**

1. **The shopper sees a bare `500`, not a `503`.** All four failures returned
   `{"code":"INTERNAL_ERROR","error":"Internal server error"}` with **no
   `Retry-After`**. [`checkout.md:149`](../../../api/checkout.md) maps *order and
   product* transients on confirm to `503` + `Retry-After`; a failover of
   checkout's **own** database is not in that mapping. An 11-second planned,
   expected, self-healing event is presented as an unretryable internal error —
   compare G1, where the same endpoint returned a clean `503` + `retry-after: 2`.
2. **A planned switchover trips a critical WAL-archive alert for 30 minutes.**
   The promoted primary failed to archive its timeline history file exactly once:
   `pg_stat_archiver` on `product-db-2` reads `failed_count = 1`,
   `last_failed_wal = 00000002.history`, `last_failed_time = 10:39:41.463`, while
   `archived_count = 2` and the cluster's `ContinuousArchiving` condition is
   `True`. Because `CNPGWALArchiveFailing` is
   `increase(cnpg_pg_stat_archiver_failed_count[30m]) > 0 for 5m`, one transient
   promotion artefact holds a **critical** alert for half an hour on a cluster
   whose archiving is healthy. Its runbook does not mention promotion, switchover,
   or timeline history as a cause.

**Blast radius, worth writing down.** `product-db` hosts **every** application
database — `product`, `order`, `checkout`, `cart`, `payment`, `inventory` — so
this drill is not a product-service drill. An 11-second write outage there is an
11-second write outage for the entire platform. The name understates it.

### 010.2 evidence record

Filed in the shape
[`010.2`](../../../databases/runbooks/restore-and-failover-drills.md#evidence-log-template)
asks for. This is that file's **first** completed record.

| Field | Value |
|-------|-------|
| Drill ID | `DR-2026-08-B` |
| Date / operator | 2026-08-06 / platform engineering (GameDay, RFC-0021 phase 7) |
| Drill type | **B** — planned switchover |
| Cluster + namespace | `product-db` / `product` (3 instances; `product-db-1` → `product-db-2`) |
| Backup ID + completion time | n/a — switchover, not a restore. `LastBackupSucceeded: True` before and after |
| Recovery target (timestamp/LSN) | n/a |
| Start → end (UTC) | 10:39:32.531 → 10:40:03.043 (phase `healthy`); write availability restored 10:39:44.685 |
| **Measured RTO** | **11.4 s** write-unavailability through PgDog (SLO `< 30 s` — **pass**) |
| **Measured/estimated RPO** | **0** — 24/24 orders terminal and consistent across four databases; no transaction lost or half-applied |
| Schema validation | pass — no migration involved; all app databases readable and writable on the new primary |
| Row-count validation | pass — orders 24 / payments 24 / distinct `order_id` 24 / committed reservations 24; per-SKU `on_hand` reconciles to `sum(on_hand_delta)` |
| App smoke test | pass — funnel confirmed before, failed closed during, confirmed after; same-key retry succeeded |
| Deviations & follow-ups | `kubectl cnpg switchover` does not exist (used `promote`); `-rw` endpoints empty 10.9 s vs the documented `< 5 s`; checkout returns `500` without `Retry-After`; `CNPGWALArchiveFailing` false positive for 30 min |
| Sign-off (IC) | pending review on the PR that adds this record |

Per [RFC-0007:166-171](../RFC-0007/), a pass updates the as-built row in
[`010.1`](../../../databases/reliability-targets.md#as-built-rporto-today),
which this change does.

## Falsified claims

Recorded plainly, because a falsified claim is the most valuable outcome of a
drill. Fixed in this change unless marked tracked.

| # | Claim | Reality | Action |
|---|---|---|---|
| F1 | `mockpay.yaml` tracks the payment image | pinned `1.0.0` since PR #438 while payment reached `1.5.0`; the skew manufactured a permanent critical alert **and** made the phase-6 ambiguity faults uninjectable | **fixed** — pin `1.5.0` + payment's `$imagepolicy` marker |
| F2 | `kubectl cnpg switchover <cluster> -n <ns>` (`010.2:79`, `010.4:64`, `005:347`, `005:481`) | `Error: unknown command "switchover" for "kubectl cnpg"` — plugin v1.30.0 has `promote`, not `switchover` | **fixed** — corrected to `kubectl cnpg promote <cluster> <instance>` |
| F3 | `disaster-recovery.md:447` "`kubectl cnpg` plugin is not installed locally at the time of writing" | installed, v1.30.0 (`Build: {Version:1.30.0 Commit:4b5e244a7}`) | **fixed** |
| F4 | `PaymentReconciliationDiscrepancy.md:38` Diagnosis SQL `SELECT id, started_at, finished_at, status, scanned, found FROM reconciliation_runs` | `ERROR: column "scanned" does not exist` — the columns are `transactions_scanned` and `discrepancies_found`. The runbook's first query has never run | **fixed**, plus the window-asymmetry false-positive check the drill needed |
| F5 | `-rw` endpoints updated `< 5s` (`005:337`) | 12.6 s, with the endpoint list **empty** for 10.9 s | **tracked** — the `< 30 s` RTO claim it serves still holds; the sub-step figure needs re-measuring on real hardware before it is rewritten |
| F6 | "anything counted here is real drift" (`rfc0021-phase6.yaml:144`) | true of the detector's intent, false of what fired: an unbounded provider reply is indistinguishable from drift | **tracked** — the reconciler asks for bounds but never verifies the provider honoured them. Any provider that paginates differently reproduces this without a mock |

## Tracked items

1. **The reconciler trusts an unbounded provider reply.**
   [`docs/api/payments.md`](../../../api/payments.md) states that "both sides are
   asked for the same bounds" and calls that symmetry the correctness argument.
   The *request* is symmetric; nothing checks the *response*. A provider that
   ignores or truncates the window turns every older charge into a phantom
   `missing_internal`. Fixing the mock removed today's instance and left the
   class open. Owner: payment-service. Not edited here — `docs/api/` has an open
   docs-sync PR (#674) and this accuracy note belongs in it.
2. **`CNPGWALArchiveFailing` has no switchover awareness** (G3 finding 2). A
   promotion always fails one timeline-history archive. Candidate fixes: exclude
   `*.history`, or gate on the `ContinuousArchiving` condition. Runbook now
   documents the false positive; the rule is untouched.
3. **Checkout maps its own database outage to `500` without `Retry-After`**
   (G3 finding 1) — owner: checkout-service, not homelab.
4. **~~The one-minute doubt sweep is still untested~~ — **tested 2026-08-07.** A
`…13` no-answer payment was parked and mockpay was then scaled to 0 so the
REQUEST path could not resolve it either (that 117 ms close is why G4 never
reached the sweep). With the provider restored and the payment untouched by any
request, the sweep re-asked under the original key three times — 10:18:13
UNKNOWN → 10:19:23 UNKNOWN → **10:20:13 SUCCESS** — and the intent left
`processing` for `authorized`. Previously untested.** G4's park was closed by the
   request path in 117 ms. Exercising the sweep needs a park nobody retries — an
   abandoned checkout against a silent provider.
5. **Mid-activity kill is not reachable by hand** (G2b). A ~700 ms saga needs
   either a provider-side hold (as G4 has) or an in-activity fault hook to test
   the commit/response interleaving deliberately.
6. **`payment_provider_unknown_total` reads 2 against one parked attempt row**
   (G4). Counter-vs-attempt-log accounting needs one look.
7. **Re-run G1 after #675.** Its Alertmanager inhibition landed mid-drill, so the
   duplicate-paging row in G1's alert table is a pre-fix reading. One repeat run
   confirms the suppression works under a real fail-closed outage.
8. **Metric label drift**: the runbook and the live series use
   `payment_reconciliation_discrepancies_total{kind}`;
   [`RFC-0021/README.md:270`](./README.md) writes `{class}`. The DB column is
   `class`. Not corrected here to keep this change to drill evidence.

## Gate assessment

Phase 7's exit gate is "GameDay scenarios converge; all migration flags removed"
([`README.md:293`](./README.md)). On the convergence half:

- **All five scenarios converged in the data.** No oversell, no double charge, no
  double deduct, no leaked reservation, no half-written order, no lost
  transaction. 24 of 24 orders reached a terminal state across four injected
  faults and a primary switchover.
- **The convergence claims held. Two operability claims did not**, and one of
  them (F1) meant a documented fault could not be injected in the cluster at all
  until this change. A gate assessed on local-stack evidence would have missed it.
- Remaining before the gate closes: items 1 and 2 above are the ones that would
  mislead an on-call engineer. Items 3–8 are follow-ups, not blockers.

The flag-cleanup half of the gate is out of scope here.

## Reproducing this

```bash
# edge + a shopper (alice does not exist on a fresh cluster)
curl -sk -H 'Host: gateway.duynh.me' -H 'Content-Type: application/json' \
  -X POST https://localhost/auth/v1/public/auth/register \
  -d '{"username":"gameday","email":"gameday@duynh.me","password":"Password123!","first_name":"G","last_name":"D"}'

# a catalogue product needs an inventory_balances row or checkout fails closed at 503
kubectl exec -n product deploy/product -c product -- wget -qO- \
  --post-data='{"name":"GameDay Widget","price":3.25,"description":"…13 trigger","category":"gameday"}' \
  --header='Content-Type: application/json' \
  http://localhost:8080/product/v1/internal/products
kubectl exec -n product product-db-1 -c postgres -- psql -U postgres -d inventory \
  -c "insert into inventory_balances (sku_id,warehouse_id,on_hand,reserved,safety_stock,version)
      values ('2',1,50,0,0,1) on conflict do nothing;"

# G1 / G2 — involuntary kills. Never `drain`: the *-primary PDBs allow 0 disruptions.
kubectl scale deploy/inventory -n inventory --replicas=0
# The label was `app=order-worker-<build>` when this drill ran. Since ADR-054 the
# worker's pod template is hand-written and carries no bare `app:` label, so that
# selector matches NOTHING -- the drill would inject no fault and pass silently.
kubectl delete pod -n order -l app.kubernetes.io/name=order-worker --grace-period=0 --force
# To kill only one version (the interesting case now that two can coexist):
#   kubectl delete pod -n order -l temporal.io/build-id=<build id> --grace-period=0 --force

# G3 — switchover. `kubectl cnpg switchover` does not exist; `promote` does.
kubectl cnpg promote product-db product-db-2 -n product

# G5 — windowed reconciliation, through the service. Pass explicit bounds:
# a param-less run advances the watermark to now-5m and moves the ground you are testing.
kubectl exec -n payment deploy/payment -c payment -- wget -qO- --post-data='' \
  'http://localhost:8080/payment/v1/internal/payments/reconciliation/runs?from=2026-08-06T07:00:00Z&through=2026-08-06T10:00:00Z'

# alerts (vmalert is reachable at the edge)
curl -sk -H 'Host: vmalert.duynh.me' https://localhost/api/v1/alerts
```

Two harness traps worth inheriting. `sleep`-then-`grep -q` in a pipeline reports
failure **for a match**, because `grep` exits early and the producer takes
SIGPIPE — do not use `set -o pipefail` with it. And OTLP is a push pipeline:
poll for a metric with a cap instead of querying once and concluding it is
missing.

## References

- [README.md](./README.md) — RFC-0021, phase 7 exit gate.
- [cutover-rollback.md](./cutover-rollback.md) — per-phase rollback commands.
- [RFC-0007](../RFC-0007/) — the drill programme; Drill E is G2, Drill B is G3.
- [runbooks/restore-and-failover-drills.md](../../../databases/runbooks/restore-and-failover-drills.md) — drill procedures and the evidence template.
- [reliability-targets.md](../../../databases/reliability-targets.md) — the RPO/RTO targets G3 verifies.
- [CheckoutAvailabilityErrors.md](../../../observability/runbooks/microservices/CheckoutAvailabilityErrors.md) — G1's claims.
- [PaymentProviderUnknownRate.md](../../../observability/runbooks/microservices/PaymentProviderUnknownRate.md) — G4's claim.
- [PaymentReconciliationDiscrepancy.md](../../../observability/runbooks/microservices/PaymentReconciliationDiscrepancy.md) — G5's claim.
- [ADR-035](../../adr/ADR-035-windowed-reconciliation/) — the windowing G5 tested.

---
_Last updated: 2026-08-06_
