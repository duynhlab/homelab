# OrderParticipantDisagreement

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / cutover |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_participant_disagreements_total{row_participant}` |
| **Applies to** | order **1.13.0+** (RFC-0021 P4 removed the product stock branch). On 1.12.x and earlier the resolver fell back to the process's `ORDER_STOCK_PARTICIPANT` and started the saga anyway — the pre-P4 notes below still apply there |

## Meaning
An order holds an inventory reservation while its own outbox row
(`fulfillment_start_requests.participant`) does not say `inventory`.

Those two records are written from one value, so they only come apart if a start
resolved the stock branch from something other than the order's own record. That was
reachable during the RFC-0021 P3 write cutover, when each process carried its own
`ORDER_STOCK_PARTICIPANT` and replicas mid-rollout disagreed: a first attempt commits
the order and fails its inline start, the client retries, and the retry lands on a
replica on the other side of the flip.

**Since RFC-0021 P4 that mechanism no longer exists** — the flag is gone, there is no
fallback, and a participant this build cannot serve is refused rather than
substituted. A new disagreement therefore means something else: a hand-edited row, a
restored database, or a start path that decides the branch itself.

`row_participant` says which reading was recorded: `product` (an explicit
product-path row) or `absent` (a row written before the column existed).

## Impact
**Not** stranded stock: the reconciler repairs the hold either way, and this fires
*because* it did. What is wrong is the record of which branch ran — and that record
is what every later judgement reads:

- the reconciler decides whether a missing reservation is normal or a lost write
  from it, so while rows are wrong its verdicts are made on wrong data;
- the outbox dispatcher starts deferred sagas from it, so a wrong row sends a retry
  down the wrong branch.

Counted **once per order**, so every increase is a distinct order. There is no
honest threshold above zero.

## Diagnosis
### PromQL
```promql
increase(order_reconciler_participant_disagreements_total[30m])
sum by (row_participant) (order_reconciler_participant_disagreements_total)
# which branch starts are resolving, and from what
sum by (participant, source) (rate(order_fulfillment_start_participant_total[15m]))
```

### Is the flag actually inconsistent right now?
```bash
kubectl -n order get pods -o json | jq -r '
  .items[] | .metadata.name + " " +
  ((.spec.containers[0].env // [])
    | map(select(.name=="ORDER_STOCK_PARTICIPANT")) | .[0].value // "unset")'
```
Two different values across `order` / `order-worker` pods is the cause.

### Are the pods even the cause any more?
Only if the fleet still runs a pre-P4 order build. Check what is deployed before
chasing pod env at all:
```bash
kubectl -n order get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

### Which orders
```sql
SELECT order_id, participant, status, reconciled_at, reconcile_breach_code
FROM fulfillment_start_requests
WHERE reconciled_at > now() - interval '1 hour'
ORDER BY reconciled_at DESC;
```
Cross-check the branch a suspect order actually ran:
```bash
temporal workflow show --workflow-id order-fulfillment-<id> \
  --namespace mop | grep -i -m1 -E 'ReserveInventory|ReserveStock'
```

## Mitigation
1. **On a pre-P4 fleet:** stop the rollout and finish converging the replicas that
   are already rolling; two different `ORDER_STOCK_PARTICIPANT` values across
   `order` / `order-worker` pods is the cause. Once they agree, no new order can
   disagree.
2. **On a P4 or later fleet:** the flag does not exist, so this is not a rollout
   problem. Work the orders individually — establish the branch from the workflow
   history (command above) and treat a row that contradicts it as corrupted input,
   not as a decision.
3. Leave the repaired orders alone — the hold was committed or released correctly.
   Do **not** rewrite `participant` to match: the column is the record of what was
   decided, and editing it makes the next reconciler pass judge from a value nobody
   wrote at start time.
4. If the count keeps rising with nothing above explaining it, a start path is
   deciding the branch itself. Every start must resolve through
   `fulfillment.ParticipantFor` and create the saga through `fulfillment.Start`,
   which refuses an unservable participant (order-service).

## Prevention
Every start path — inline gRPC and the outbox dispatcher — resolves the branch from
the order's recorded participant, and since RFC-0021 P4 anything but `inventory` is
REFUSED rather than substituted: an absent or product value still means
product-service, and no start invents a different answer for it. The guard also sits
inside `fulfillment.Start`, the single place a saga is created, so a future start path
inherits it. The column stays `CHECK`-constrained to the enum.

## References
- [`docs/api/temporal.md`](../../../api/temporal.md)
- [RFC-0021 cutover rollback](../../../proposals/rfc/RFC-0021/cutover-rollback.md)
- [`OrderStartParticipantUnrecognised`](OrderStartParticipantUnrecognised.md)

---
_Last updated: 2026-08-04_
