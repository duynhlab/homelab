# OrderParticipantDisagreement

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / cutover |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_reconciler_participant_disagreements_total{row_participant}` |

## Meaning
An order holds an inventory reservation while its own outbox row
(`fulfillment_start_requests.participant`) does not say `inventory`.

Those two records are written from one value, so they only come apart one way: a
saga start resolved the stock branch from **its process's**
`ORDER_STOCK_PARTICIPANT` instead of from the order. That is reachable while the
flag is mid-rollout and replicas disagree — a first attempt commits the order and
fails its inline start, the client retries, and the retry lands on a replica on the
other side of the flip.

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
1. **Stop the rollout.** Do not continue flipping `ORDER_STOCK_PARTICIPANT` while
   this fires; finish converging the replicas that are already rolling.
2. Confirm every `order` and `order-worker` pod reports the same flag (command
   above). Once they do, no new order can disagree.
3. Leave the repaired orders alone — the hold was committed or released correctly.
   Do **not** rewrite `participant` to match: the column is the record of what was
   decided, and editing it makes the next reconciler pass judge from a value nobody
   wrote at start time.
4. If the count keeps rising with a single consistent flag everywhere, the cause is
   not the rollout: a start path is deciding the branch itself. Check that every
   start resolves through `fulfillment.ParticipantFor` (order-service).

## Prevention
Every start path — inline REST, inline gRPC, and the outbox dispatcher — resolves
the branch from the order's recorded participant, never from the process flag. An
absent value resolves to the product path rather than to the flag, and the column is
`CHECK`-constrained to the enum.

## References
- [`docs/api/temporal-order-fulfillment.md`](../../../api/temporal-order-fulfillment.md)
- [RFC-0021 cutover rollback](../../../proposals/rfc/RFC-0021/cutover-rollback.md)
- [`OrderStartParticipantUnrecognised`](OrderStartParticipantUnrecognised.md)

---
_Last updated: 2026-07-29_
