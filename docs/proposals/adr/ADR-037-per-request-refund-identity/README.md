# ADR-037: Let the Caller Name Each Refund

> **Decision summary:** We will scope refund idempotency by a caller-supplied
> request id rather than by the order alone, because only the caller knows whether
> two refunds are the same intent. We accept validating caller-supplied text that
> reaches a provider key in exchange for an order being able to owe more than one
> refund.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-04 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The refund idempotency key on payment-service's internal gRPC surface, and the ids order-service sends |
| **Affected components** | payment-service (gRPC), order-service (fulfillment saga + cancellation workflow), `duynhlab/pkg` proto |
| **Related RFC** | [RFC-0021](../../rfc/RFC-0021/) (Phase 6) |
| **Related research** | [research.md](../../rfc/RFC-0021/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | pkg v0.32.0, payment-service #51, order-service #169 |
| **Adoption** | Complete |

## Context

Payment-service derived a refund's idempotency key from the order:
`refund:order:<id>`. That gave an order **one refund identity for its whole
life**.

Phase 5 ([ADR-033](../ADR-033-order-status-cancellation/)) made the collision
reachable. An order can now owe two distinct refunds:

| Refund | Raised by | Amount |
|---|---|---|
| compensation | the fulfillment saga, when a post-capture pre-pivot step fails | the order total |
| cancellation remainder | the cancellation workflow, when a customer cancels | whatever is still out |

Both arrived under the same key, so the second was rejected outright — not
answered "already done", but never sent. Two distinct movements of money sharing
one name, with the later one silently impossible.

The same key is what reaches the provider, so the problem is not only local
bookkeeping: without distinct identities the provider cannot tell the two refunds
apart either, and a retry of one cannot be told from a request for the other.

## Scope

### In scope

- Where a refund's identity comes from.
- What that identity must satisfy before it is used in a key.
- Behaviour when a caller supplies none.
- The identities order-service sends for its two refunds.

### Out of scope

- The HTTP refund surface, which takes a client-supplied `Idempotency-Key`
  already and is subject to the legacy-endpoint deprecation.
- Refund amount reconciliation, an existing v1 limit.
- Partial-refund policy: how many refunds an order may owe is the caller's
  business, not this decision's.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Two movements of money must have two identities | Sharing one makes the second unsendable, and makes a retry indistinguishable from a new request |
| 2 | Stability across retries | An identity that changes per attempt turns a retry into a second payout |
| 3 | Safe rollout | A saga mid-flight must keep replaying onto the key it started with |
| 4 | Traceability | The identity appears in our keys, our logs and the provider's dashboard |

## Decision

We will take the refund identity from the **caller**, as
`RefundRequest.refund_request_id` (added additively as field 4 in pkg v0.32.0),
and build the key as `refund:order:<id>:<request_id>`. Only the caller knows
whether two refunds are the same intent, so only the caller can name them.

An **empty** request id keeps the historical `refund:order:<id>` key, so a saga
mid-flight across the rollout retries onto the key it started with.

order-service sends **constants**, one per purpose: `compensation` and
`cancellation`. They are constants because an identity has to be stable across
every retry of the same intent — a purpose identifies one intended movement of
money per order, and a second attempt at that purpose is that same money.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | The caller owns the identity; payment-service never invents or derives one from request contents |
| **Stability** | An identity is stable across retries of the same intent — a constant or a durable value, never generated per attempt |
| **Validation** | Validated at the boundary: at most 64 characters, `[A-Za-z0-9._:-]` only, refused before any refund is attempted |
| **Compatibility** | Empty id ⇒ the historical key shape, unchanged |
| **Boundary** | The id is an identity, not a reason; the human-readable reason stays a separate field |
| **Failure behavior** | A malformed id is `InvalidArgument` and no provider call happens |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Caller-supplied request id, empty means the old key** | The caller is the only party that knows what "the same refund" means; rollout-safe by construction | Caller-supplied text reaching a provider key, so it must be validated | Selected |
| **B — Server-derived key from (order, amount, reason)** | No proto change, no caller discipline | Two refunds of the same amount for the same reason collide, and a retry of a *changed* amount looks like a new refund. It infers intent from contents, which is the mistake in a different place | Rejected |
| **C — Key by the refund row id** | Guaranteed unique, trivially stable | The row does not exist until the request is accepted, so it cannot key the request that creates it | Rejected |
| **D — Allow unlimited refunds and drop key scoping** | No collision by definition | Removes the protection entirely: a retried refund becomes a second payout, which is the failure the key exists to prevent | Rejected |

### Why the selected option won

Driver 1 asks a question only the caller can answer, and A is the only option that
lets it answer. B and C both try to derive identity from something the server can
see, and identity is not a function of contents or of a row that does not exist
yet. A also gets driver 3 for free: "empty means the old key" makes the rollout a
non-event rather than a migration.

### Why the closest alternative lost

B is close and requires no proto change, which is genuinely attractive. It loses
because its collision set is worse than the one it replaces: two refunds of equal
amount and reason are exactly what a partial-refund flow produces, and it also
breaks the retry guarantee — correcting an amount would mint a new identity and
pay out twice. It trades a visible rejection for a silent double payment.

## Consequences

### Positive consequences

- An order can owe more than one refund, and each is retryable on its own terms.
- The provider sees distinct keys for distinct refunds, so its own idempotency
  works with ours instead of against it.
- Rollout needed no coordination: an empty field is the old behaviour exactly.

### Negative consequences and accepted trade-offs

- **Caller-supplied text reaches an idempotency key and a provider key.** Hence
  boundary validation — bounded length, and characters that read the same in a log
  line, a URL and a provider dashboard. A key that cannot be quoted back verbatim
  is a key nobody can trace.
- **Correctness now depends on caller discipline.** A caller that generates a
  fresh id per attempt turns a retry into a second payout. Mitigated by making the
  order side's ids constants and asserting them in workflow tests, so a future
  change that collapses them back into one name fails there.
- **The activity signature changed**, which is a rollout boundary even though the
  replay gate passes (Temporal compares commands, not activity payloads). It ships
  as a new Worker Deployment Version under [ADR-030](../ADR-030-temporal-workflow-versioning/).
- **Two purposes are a starting set, not a taxonomy.** A third refund reason will
  need its own id, and nothing enforces that they stay distinct beyond review.

### Neutral consequences

- order-service moved from pkg v0.30.0 to v0.32.0 for the proto field.
- The HTTP surface is unaffected; it already carries a client key.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Additive proto field | pkg | v0.32.0 | `buf breaking` clean |
| Accept and validate the id; scope the key | payment-service | #51 | Distinct ids ⇒ distinct keys; malformed ⇒ `InvalidArgument` with no provider call |
| Send distinct ids per purpose | order-service | #169 | Workflow tests assert which identity each path sends |
| New Worker Deployment Version | homelab | rollout | Activation job run; replay gate green |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Distinct identities ⇒ distinct keys | Unit test on the gRPC surface |
| Backward compatibility | Absent id produces the historical key shape |
| Boundary validation | Four malformed shapes (whitespace, path escape, over-length, newline) refused before any refund is attempted |
| Stability | Order-side ids are constants, asserted per code path in workflow tests |
| Determinism | Replay gate green over the gen-2 corpus |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A third distinct refund purpose appears, making an ad-hoc constant set
  insufficient.
- Refunds become partially automatic (per-line-item returns), where identity is
  per line rather than per purpose.
- A caller is found generating ids per attempt, which would mean the discipline
  needs enforcing in code rather than in review.
- The legacy HTTP refund path is removed, at which point the empty-id
  compatibility branch can go with it.

## References

- [RFC-0021](../../rfc/RFC-0021/) — platform overhaul umbrella (Phase 6)
- [Payment contract](../../../api/payments.md) · [Order contract](../../../api/order.md)
- [ADR-010](../ADR-010-shared-idempotency-library/) — the key machinery this scopes
- [ADR-033](../ADR-033-order-status-cancellation/) — the cancellation refund that made the collision reachable
- [ADR-030](../ADR-030-temporal-workflow-versioning/) — why the activity change needs a new worker build

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-04 | Accepted / Complete | Shipped in pkg v0.32.0, payment-service #51, order-service #169 |

---
_Last updated: 2026-08-04_
