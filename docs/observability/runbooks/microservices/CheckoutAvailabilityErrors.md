# CheckoutAvailabilityErrors

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Manifest** | [`checkout-availability.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/checkout-availability.yaml) |
| **Metrics** | `checkout_availability_check_total{result}` |
| **Applies to** | checkout **0.5.0+** (RFC-0021 P4 made inventory the only availability authority). Earlier builds could fall back to product's stock column and this metric does not exist |

> **Reproducing this alert needs SUSTAINED traffic, not a burst.** The ratio is
> computed over `[10m]` and the debounce is `for: 10m` — the same length — so a
> short burst of fail-closed requests leaves the rate window at exactly the
> moment the debounce would mature and the alert never fires. Measured
> 2026-08-07: a ~30 s burst of 45 × 503 left the alert `inactive` for 14 minutes
> with the ratio back to 0; 13 minutes of paced traffic moved it
> `inactive → pending` in ~2 min and **firing at 11 m 26 s**. If you are
> verifying this alert, drive traffic for longer than the window — an operator
> who tests with a quick loop will wrongly conclude it is broken.

## Meaning
More than 1% of checkout's **answered** availability checks returned **error** for 10
minutes: `inventory.v1/CheckAvailability` is failing or timing out.

*Answered* is load-bearing in that sentence. The ratio's denominator names
`ok|shortage|error` explicitly and excludes `unknown_sku`, because a data gap is a
checkout-side refusal rather than an inventory answer that could have been an error —
letting it into the denominator would let a flood of missing balance rows push the
error share under the threshold and **suppress this page**. A missing balance row has
[its own alert](CheckoutAvailabilityUnknownSKU.md).

Checkout **fails closed** — an availability error becomes `ErrUpstream` (503), never
out-of-stock, because a timeout is not a shortage. So every affected request is a
shopper who cannot create or confirm a session.

There is **no fallback authority**. Phase 4 removed the product-availability path
deliberately: the column it read was frozen at the W7 write cutover, so a fallback
could only ever have answered with a stale number.

## Impact
Customers cannot check out for as long as this lasts. Both ends of the funnel are
affected — `POST /sessions` and `POST …/confirm` both resolve the catalog.

A confirm that fails here releases its idempotency key on a **detached** context, so
the shopper's same-key retry is not blocked behind the 90-second takeover window.
Sessions are left at `confirming` and recovered by `ExpireDue`'s parked-confirm
branch, which needs the Temporal worker running.

## Diagnosis
```promql
# by outcome — is it error, or is inventory refusing baskets?
checkout:availability_check:rate5m
checkout:availability_error:ratio5m

# is inventory itself unhealthy, or only this hop?
sum by (grpc_code) (rate(rpc_server_calls_total{app="inventory"}[5m]))
```

Then, in order of how often each is the cause:

1. **inventory-service health.** Pods, restarts, its own RED metrics and DB.
   ```bash
   kubectl -n inventory get pods
   kubectl -n inventory logs deploy/inventory --tail=100
   ```
2. **The hop.** `allow-inventory-grpc` must admit the checkout namespace, and
   checkout must be dialling the right target.
   ```bash
   kubectl -n inventory get networkpolicy allow-inventory-grpc -o yaml | grep -A3 checkout
   kubectl -n checkout exec deploy/checkout -- env | grep INVENTORY_GRPC_ADDR
   ```
3. **A wiring mistake looks identical to an outage here** — that is why checkout
   startup-validates `INVENTORY_GRPC_ADDR` and panics on a nil client. If the pods
   started, the address is non-empty and the client exists; if they are crash-looping
   with that panic, the wiring is the cause and the fix is the manifest, not inventory.

## Mitigation
- **Restore inventory.** There is nothing to fail over to, and that is by design.
- **Do NOT try to move checkout back to product for availability.** The flag is gone
  (checkout 0.5.0), the RPCs are gone (product 1.7.0), and the column is out of the
  read contract (product 1.8.0). Rolling checkout back to 0.4.x would default the
  source to `product` and answer from a frozen column — wrong answers instead of
  honest 503s. If inventory will be down long enough that this is tempting, take the
  storefront's checkout offline instead of serving stock numbers that are years stale.
- Sessions stuck at `confirming` recover when `expires_at` elapses via `ExpireDue`;
  confirm the Temporal worker is running, since that branch is its job.

## Escalation
Page. If inventory is healthy and the hop is open, escalate as a checkout↔inventory
contract problem and capture one failing trace end to end — the error is wrapped into
`ErrUpstream` at the logic layer, so the gRPC status is in the span, not the HTTP
response.

## References
- [`CheckoutAvailabilityRefusingEverything`](CheckoutAvailabilityRefusingEverything.md) — the other failure shape: inventory answering, and refusing everything
- [`docs/api/checkout.md`](../../../api/checkout.md) · [`docs/api/inventory.md`](../../../api/inventory.md)
- [RFC-0021](../../../proposals/rfc/RFC-0021/) — why there is one authority

---
_Last updated: 2026-08-05_
