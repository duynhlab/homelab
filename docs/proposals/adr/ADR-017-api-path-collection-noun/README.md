# ADR-017: Collection-noun segment after the audience in every API path

| Status | Date | Related RFC |
|--------|------|-------------|
| Accepted | 2026-07-12 | — |

> **Don't forget: every decision is a tradeoff.** Record what you gave up, not just
> what you gained.

## Context

The Variant A URL shape (`/{service}/v1/{audience}/{resource…}`, naming
convention v2.0.0) fixed the prefix but left `{resource…}` under-specified —
two bullet points ("plural nouns for collections", "custom actions as POST
sub-paths") with no examples and no exception list. An audit on 2026-07-12
found 13 of 43 HTTP routes violating them, each service having improvised at
scaffold time:

- **auth** — 5 verb routes with no resource segment (`/auth/v1/public/login`).
- **shipping** — verb routes (`/track`, `/estimate`) and a foreign-owned
  collection name (`/internal/orders/:orderId` for what is a *shipment* lookup).
- **notification** — verb prefix on the internal surface (`/notify/email`,
  `/notify/sms`) while the private surface correctly used `notifications`.
- **payment** — secondary collections not anchored under the service's own
  noun (`/public/webhooks/mockpay`, `/internal/reconciliation/runs`).

With checkout-service (RFC-0015) about to scaffold new routes, the rule had to
be made explicit before the drift compounded.

## Decision

We will require the segment **immediately after `{audience}` to be a
collection noun owned by the service** — by default the plural of the
service's domain noun:

```
/{service}/v1/{audience}/{collection}/{resource…}
```

- `users`, `products`, `carts`→`cart` (see exceptions), `orders`, `reviews`,
  `notifications`, `shipments`, `payments` — and secondary resources nest
  under that noun (`payments/webhooks/mockpay`, `payments/reconciliation/runs`).
- **Exceptions (explicit, closed list):** `auth` keeps the literal `auth`
  segment (it owns no natural collection — `/auth/v1/public/auth/login`);
  `cart` stays singular (a per-user singleton).
- Lookup-by-foreign-key on an owned collection uses a nested path segment
  (`/shipments/orders/:orderId`).
- The 13 non-conforming routes are renamed now, in an
  **expand → migrate → contract** sequence: new canonical paths and deprecated
  aliases ship together (expand, minor release), all callers move in the same
  release wave (frontend, `AUTH_JWKS_URL` defaults, `MOCKPAY_WEBHOOK_URL`),
  and a follow-up major release removes the aliases (contract) once the
  rollout is verified. Routes with **zero live HTTP callers** (shipping
  internal, notification `notify/*` — both hops are gRPC today) rename
  directly with no alias.

The full route inventory and rule text live in
[`docs/api/api-naming-convention.md`](../../../api/api-naming-convention.md) (v3.0.0).

## Alternatives considered

### Literal service-name segment (singular) on all 43 routes
- Pros: the purest reading of the shape; zero ambiguity.
- Cons: renames all 43 routes (30 already conform to the plural reading),
  breaking every consumer for no semantic gain; `orders` → `order` reads
  worse, not better.
- Rejected: 3× the blast radius to fix routes that were never the problem.

### Soft rule — noun-style required, secondary collections stay top-level
- Pros: only 5 routes change (shipping public, notification internal);
  `webhooks/…` and `reconciliation/…` are defensible owned collections.
- Cons: keeps two segment grammars alive; the next service scaffold has to
  choose again — exactly how the drift happened.
- Rejected: the platform owner chose one grammar everywhere over minimal diff.

### Keep as-is, document the exceptions
- Pros: zero migration cost.
- Cons: 13 grandfathered shapes become permanent precedent (Hyrum's Law);
  every future review re-litigates them.
- Rejected: cheapest now, most expensive forever.

## Consequences

- **Positive:** one grammar for every route; path ownership is grep-able
  (`/payments/` ⇒ payment-service); checkout-service scaffolds against a rule,
  not a vibe; Kong prefixes and NetworkPolicy fences are unchanged except one
  added webhook prefix.
- **Negative / accepted:** paths repeat the service noun
  (`/payment/v1/private/payments`) — mild stutter, harmless; a two-release
  migration (expand now, contract later) with a window where deprecated
  aliases answer alongside canonical paths; auth's `auth/auth` segment reads
  awkwardly and is codified as a permanent exception; the naming-convention
  doc bumps to a breaking v3.0.0 and all its consumers (docs, audit scripts,
  service READMEs) had to move in lockstep.
- The **contract release** must remove: the 8 service-side aliases, the old
  Kong webhook prefix (`/payment/v1/public/webhooks/`, cluster Ingress +
  local-stack kong.yml), and flip the local-stack A7 audit from
  "aliases 200" to "aliases 404".

## References

- [`docs/api/api-naming-convention.md`](../../../api/api-naming-convention.md) — v3.0.0 rule + inventory
- [ADR-003](../ADR-003-jwt-validation-in-services-not-kong/) · [ADR-006](../ADR-006-rs256-jwt-kong-edge-auth/) — the auth-path surfaces this rename touches
- Google API Design Guide (collections & custom methods)

_Last updated: 2026-07-12_
