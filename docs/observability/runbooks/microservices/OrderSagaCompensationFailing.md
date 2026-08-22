# OrderSagaCompensationFailing

| | |
|---|---|
| **Severity** | critical |
| **Category** | correctness |
| **Manifest** | [`rfc0021-write-migration.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/rfc0021-write-migration.yaml) |
| **Metrics** | `order_saga_compensation_total{step,result}` |

## Meaning
A compensation step has been returning errors for 15m. Compensations are the saga's
undo path (release stock, void or refund payment, cancel shipment, fail the order)
and they retry **harder** than forward steps — so a sustained error rate means the
retries themselves are exhausting.

## Impact
Orders are left partially unwound: stock reserved but the order failed, money
authorized but not voided, a shipment created for an order that will not ship. The
inventory reconciler covers **only the stock half**; payment and shipment residue
needs a human.

## Diagnosis
### PromQL
```promql
sum by (step, result) (rate(order_saga_compensation_total[15m]))
sum by (outcome) (rate(order_saga_outcome_total[15m]))
max(order_reconciler_backlog)
```
`step` names the failing compensation: `release_stock`, `void_payment`,
`refund_payment`, `cancel_shipment`, `fail_order`.

### kubectl / logs
```bash
kubectl logs -n order -l app.kubernetes.io/name=order-worker --tail=300 | grep -iE "compensation|failOrder"
```

### Temporal
Filter workflows by failed status and inspect the compensation activity's attempts.
The last failure distinguishes a downstream outage from a business rejection.

## Mitigation
1. `release_stock` failing ⇒ the reconciler will release the stock for failed orders
   on its next pass; confirm via
   [OrderReconcilerBacklogNotDraining](OrderReconcilerBacklogNotDraining.md) that it
   drains. This is the one compensation with a safety net.
2. `void_payment` / `refund_payment` failing ⇒ **money is exposed**. Reconcile
   against payment-service (`GetPayment` per order) and settle manually; there is no
   automatic repair for the money half in this phase.
3. `fail_order` failing ⇒ the order row still reads `confirmed` while the saga
   compensated. Expect `STOCK_RETURNED` breaches; the reconciler deliberately does
   not claim the customer was charged in that state, so check payment before acting.
4. `cancel_shipment` failing ⇒ contact shipping-service; a stray shipment is a
   physical-world cost.

## Escalation
Page. Sustained compensation failure is the saga losing its ability to unwind, which
is a money-and-goods integrity incident rather than a latency one.
