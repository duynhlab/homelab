# FulfillmentStartOutboxFailed

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_fulfillment_start_outbox_failed` |
| **Applies to** | All builds. `PARTICIPANT_UNSERVABLE` exists from order **1.13.0** (RFC-0021 P4) |

## Meaning
At least one outbox row is **FAILED**: the dispatcher will not start that order's
saga. FAILED is terminal and nothing retries it — requeuing is a deliberate human
act.

Read `last_error_code` first, because there are **two families** and they need
different handling. Do not assume the row spent two hours retrying.

| Family | Codes | What the dispatcher decided |
|---|---|---|
| **Refused on the first claim** | `TOKEN_CLEARED`, `TOO_OLD`, `ABANDONED_RUN`, `PARTICIPANT_UNSERVABLE` | The row can never be started as it stands, so retrying would only delay the same verdict |
| **Attempt cap exhausted** | `UNAVAILABLE`, `DEADLINE_EXCEEDED`, `INTERNAL`, `RESOURCE_EXHAUSTED`, `NAMESPACE_NOT_FOUND`, `INVALID_ARGUMENT`, `DESCRIBE_FAILED`, `ORDER_LOAD_FAILED`, `UNKNOWN` | ~20 claims, roughly two hours of backoff, all failing transiently. The code names the last cause |

Per code:

| Code | Cause | Was money moved? |
|---|---|---|
| `TOKEN_CLEARED` | The payment token was cleared, so a start would authorize against the demo fallback rather than the customer's instrument | No |
| `TOO_OLD` | Past the workflow-id dedup window, so a start could no longer be proven not to duplicate a saga that already ran | **Unknown** — a saga may have run and closed |
| `ABANDONED_RUN` | A run exists but stopped without finishing (terminated, timed out, failed, cancelled) | **Possibly** — inspect that run |
| `PARTICIPANT_UNSERVABLE` | The row's stock participant is a branch this build no longer has (RFC-0021 P4 removed the product-service branch), and Temporal confirmed **no execution exists** | No |
| transient codes | Temporal or Postgres was unreachable for the whole cap | No |

## Impact
The **order** is untouched by any of this: it stays `pending`, no automation will
move it, and the customer sees an order that never progresses. The reconciler does
not scan pending orders, so this alert is the only thing pointing at it.

`PARTICIPANT_UNSERVABLE` is not an outage. It means the fleet is running a build
that cannot serve an order created before the RFC-0021 P3 participant cutover. It
should be zero on a fleet with no pre-cutover pending orders; a non-zero value that
appears at a worker rollout means the rollout's versioning preconditions were not
met — see the order worker build manifest under `kubernetes/apps/` and
[application delivery](../../../platform/application-delivery.md).

## Diagnosis
### PromQL
```promql
max(order_fulfillment_start_outbox_failed)
sum by (result) (rate(order_fulfillment_start_dispatch_total[1h]))
# participant resolutions that ended in a refusal rather than a start
sum by (participant, source) (rate(order_fulfillment_start_participant_total{result="refused"}[1h]))
```

### SQL — the worklist
```sql
SELECT f.order_id, f.attempts, f.last_error_code, f.payment_method_cleared,
       f.participant, o.status, o.total, o.version, f.created_at
FROM fulfillment_start_requests f JOIN orders o ON o.id = f.order_id
WHERE f.status = 'FAILED' ORDER BY f.created_at;
```
Group by `last_error_code` first: one code across many rows is an outage, many
different codes is per-order data.

### Always check Temporal before writing anything
```bash
temporal workflow describe -w order-fulfillment-<order-id> -n mop
```
A live or closed execution changes the answer for every code. Never fail an order
whose saga is still running — it will go on to capture.

## Mitigation
Per row, choose one — do not blanket-requeue.

### 1. `PARTICIPANT_UNSERVABLE`
No execution exists (the dispatcher verified that before failing the row), so
nothing was authorized and no stock is held. Two options:

- **Fail the order** (below) if the customer can re-checkout. This is normally
  right: the order predates the participant cutover and is stale by definition.
- **Serve it instead** by keeping a worker build that still has the removed branch
  polling the task queue until such orders drain (order 1.12.x is the last build
  that can). Then requeue the row. Choose this only if the order must complete.

### 2. Requeue — only for a transient code, recent, and `payment_method_cleared = false`
```sql
UPDATE fulfillment_start_requests
SET status = 'PENDING', attempts = 0, next_attempt_at = now(), last_error_code = NULL
WHERE order_id = <id> AND status = 'FAILED' AND payment_method_cleared = false;
```
With `payment_method_cleared = true` the dispatcher refuses the row again; that
guard is intentional, so do not clear the flag to work around it.

### 3. Fail the order
There is no operator API for this — `CancelOrder` rejects a `pending` order — so it
is raw SQL, and since RFC-0021 P5 the order is an aggregate with a version and an
append-only history. A bare `UPDATE orders SET status='failed'` skips all of it and
leaves an order nobody can explain. Write the whole transition:

```sql
BEGIN;
UPDATE orders
SET status = 'failed', failure_code = 'WORKFLOW_START_FAILED',
    version = version + 1, updated_at = now()
WHERE id = <id> AND status = 'pending' AND version = <version read above>;
-- Expect UPDATE 1. Anything else means the order moved while you were looking:
-- ROLLBACK and re-read.
INSERT INTO order_status_history (order_id, command_id, from_status, to_status,
                                  reason_code, actor_type, actor_id, note)
VALUES (<id>, 'fail:<id>:WORKFLOW_START_FAILED', 'pending', 'failed',
        'WORKFLOW_START_FAILED', 'OPERATOR', '<your-operator-id>',
        'outbox row FAILED with <last_error_code>; incident <id>');
COMMIT;
```

Preconditions, all of them: Temporal shows no live execution for the order, the
row's code says no money moved (table above), and the CAS matched. If the code is
`TOO_OLD` or `ABANDONED_RUN`, inspect the run and settle payment first — a refund
or void is a payment-service action, not something this UPDATE performs.

## Escalation
Page. Then split the worklist by code:

- All one transient code → one Temporal or Postgres outage longer than two hours.
  That is its own incident; check the deploy/incident timeline.
- `PARTICIPANT_UNSERVABLE` appearing at a rollout → a worker-versioning problem,
  not an order problem. Stop the rollout before more orders land here.
- Mixed codes → per-order data, work the list.

---
_Last updated: 2026-08-04_
