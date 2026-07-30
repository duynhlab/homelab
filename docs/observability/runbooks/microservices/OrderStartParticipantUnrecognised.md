# OrderStartParticipantUnrecognised

| | |
|---|---|
| **Severity** | warning |
| **Category** | correctness / cutover |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_fulfillment_start_participant_total{participant,source}` |

## Meaning
A saga start read a `participant` value it does not recognise and used its own
`ORDER_STOCK_PARTICIPANT` instead. That order's stock branch was therefore chosen by
the process, not by the order's own record.

`source` says where each start's decision came from:

| `source` | Meaning |
|---|---|
| `recorded` | The order's row named a branch this build knows. The steady state. |
| `absent` | Nothing recorded — resolved to the **product** path (every reader of that column means product by an empty value). Should decay to zero as pre-column orders age out. |
| `unrecognised` | **This alert.** A value no build understands. |

## Impact
The start is not blocked — falling back is deliberate, because the workflow *panics*
on a participant it cannot map and a stalled saga is worse than a start on the
flag's branch. But the order now runs a branch its row does not name, which is
exactly the state [`OrderParticipantDisagreement`](OrderParticipantDisagreement.md)
reports later, from the other end.

## Diagnosis
### PromQL
```promql
increase(order_fulfillment_start_participant_total{source="unrecognised"}[30m])
sum by (participant, source) (rate(order_fulfillment_start_participant_total[15m]))
```

### The offending rows
The dispatcher logs the raw value it discarded:
```logql
{namespace="order"} |= "unknown stock participant"
```
```sql
SELECT order_id, participant, status, created_at
FROM fulfillment_start_requests
WHERE participant IS NOT NULL AND participant NOT IN ('product', 'inventory');
```
That query returning **nothing** while the counter rises means the value came from
the inline start path (which does not log it — the gRPC transport has no logger by
design) and the row has since been corrected, or a newer build is writing a value
this one cannot read.

## Mitigation
1. If rows are found: they were hand-edited or written by a build predating the
   `CHECK` constraint. Decide the correct branch from the workflow history, not from
   the flag:
   ```bash
   temporal workflow show --workflow-id order-fulfillment-<id> \
     --namespace mop | grep -i -m1 -E 'ReserveInventory|ReserveStock'
   ```
   then set the column to match what actually ran.
2. If nothing is found and the count keeps rising, a **newer** order-service is
   writing a participant this build cannot read. Roll the fleet forward rather than
   back: a mixed fleet where one half cannot read the other's values makes every
   deferred start resolve by flag.
3. Verify the constraint is present — its absence is how such a value gets in:
   ```sql
   SELECT conname FROM pg_constraint
   WHERE conname = 'fulfillment_start_requests_participant_check';
   ```

## Prevention
Migration `000010` constrains the column to `('product','inventory')` or NULL, so no
client can write an unusable value. The resolver keeps falling back rather than
passing an unknown value to the workflow, and counts every time it has to.

## References
- [`OrderParticipantDisagreement`](OrderParticipantDisagreement.md)
- [`docs/api/temporal-order-fulfillment.md`](../../../api/temporal-order-fulfillment.md)
- [RFC-0021 cutover rollback](../../../proposals/rfc/RFC-0021/cutover-rollback.md)

---
_Last updated: 2026-07-29_
