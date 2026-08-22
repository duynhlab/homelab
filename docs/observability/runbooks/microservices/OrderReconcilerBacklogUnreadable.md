# OrderReconcilerBacklogUnreadable

| | |
|---|---|
| **Severity** | warning |
| **Category** | database / observability |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_backlog` (by its **absence**) |

## Meaning
`absent(order_reconciler_backlog)` for 20m — **no** process is reporting the
backlog.

This alert exists because the gauge's failure mode is disappearance, not a high
value. Its callback queries the order database; when that read fails it logs and
publishes **nothing**, deliberately, because publishing `0` would tell an operator
"every order's stock agrees" during a database problem — the one thing that must
never be said falsely.

Both the order **API** and the **worker** report it (it is a query with no
dependency on the repair loop), so a single pod restarting cannot trigger this.
20m also sits above the 15m dwell of
[OrderReconcilerBacklogNotDraining](OrderReconcilerBacklogNotDraining.md) so a
rolling restart of both Deployments cannot trip it.

## Impact
The backlog is **unknown**, not zero. Stranded stock may be accumulating with no
signal. Note that
[OrderReconcilerBacklogNotDraining](OrderReconcilerBacklogNotDraining.md) cannot
fire while the series is absent, so this alert is the only cover for that window.

## Diagnosis
### PromQL
```promql
absent(order_reconciler_backlog)
order_reconciler_backlog                      # which reporters, if any, remain
up{app=~"order|order-worker"}
```
Other order series still flowing (`order_fulfillment_start_outbox_pending`,
`http_server_request_duration_seconds_count`) narrows this to the **query**, not
the process or the OTLP pipeline. That separation is by design: a callback that
returned its error would blank every metric in the process, so absence of *only*
this series means the database read failed.

### kubectl / logs
```bash
kubectl logs -n order -l app.kubernetes.io/name=order-worker --tail=200 | grep "could not read the reconciler backlog"
kubectl logs -n order -l app=order --tail=200      | grep "could not read the reconciler backlog"
```
The log line carries the database error verbatim.

## Mitigation
- `42703 column ... does not exist` ⇒ the app is running ahead of its schema. Check
  `SELECT version FROM schema_migrations` on the order database against the
  migration files; the settlement columns arrive in **000009**. Run the migration
  Job. This is the expected reading during a deploy where the app rolled before
  migrations completed.
- Connection/timeout errors ⇒ treat as a PgDog/CNPG issue and follow the PostgreSQL
  runbooks; the reconciler recovers on its own once reads succeed.
- Both order pods gone ⇒ the platform has a bigger problem than this alert.

## Escalation
Escalate with the PostgreSQL on-call if the cause is the database. Do not
"fix" this by making the gauge publish 0 — that trades a visible unknown for an
invisible wrong answer.
