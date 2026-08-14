# ADR-047: Expose administrative commands through role-gated protected APIs on owning services

> **Decision summary:** We will serve every Backoffice operation through new
> `/{service}/v1/protected/…` routes implemented by the **owning service** —
> requiring the `backoffice_admin` realm role verified in-service, the actor
> taken from the verified token, idempotency on retryable commands, and a
> durable audit record committed with the write — because the live operator
> paths today (raw-SQL runbook, "manual fix" doc, zero-caller commands) bypass
> every guardrail the platform has. We accept new edge surface and repeated
> per-service route work in exchange for keeping domain ownership intact and
> making privileged contracts explicit instead of letting `internal` routes
> drift into accidental admin endpoints.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-13 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | Which audience, transport, and guard privileged browser-driven operations use. The portal's frontend stack (ADR-049) and the no-BFF topology (ADR-048) are separate records. |
| **Affected components** | `pkg/authmw` (role gate), product / inventory / order / payment / shipping / user services (protected route groups), Envoy Gateway HTTPRoutes + `jwt-edge` SecurityPolicy (both config sets), `docs/api/api.md` conventions |
| **Related RFC** | [RFC-0023](../../rfc/RFC-0023/) |
| **Related research** | [research.md](../../rfc/RFC-0023/research.md) |
| **Related ADR** | [ADR-041](../ADR-041-keycloak-platform-idp/) (the realm that mints `backoffice_admin`), [ADR-044](../ADR-044-envoy-gateway-platform-edge/) (the edge these routes ride), [ADR-003](../ADR-003-jwt-validation-in-services-not-kong/) (services stay the authoritative verifier), [ADR-048](../ADR-048-admin-portal-no-bff/), [ADR-049](../ADR-049-admin-portal-tanstack-spa/) |
| **Supersedes** | RFC-0010's older *signed-webhook* reading of the `protected` class (webhooks stay `public` + HMAC) |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0023 program — authmw train, per-service slice A/B trains |
| **Adoption** | Partial — the audience is real on **five** services (inventory, order, payment, shipping, user): role-gated `/protected/` groups behind the staff issuer, edge HTTPRoutes in both config sets, verified end to end through the local edge (audit rows A17/A18). **product** is slice B and has no protected surface yet; the cluster edge is unverified until the Kind gate |

## Context

The platform has four route audiences (`public`, `private`, `protected`,
`internal`), but `protected` has only ever existed as a definition in
[`docs/api/api.md`](../../../api/api.md#audience-segments) — zero routes
implement it. Meanwhile real operator needs are served outside every guardrail:

- Releasing an order from `manual_review` is a **raw-SQL runbook**.
- Fixing a missing inventory balance is documented as "a manual fix" while
  idempotent, actor-aware stock commands sit implemented with **zero callers**.
- Payment reconciliation writes a report no endpoint can read.
- Product mutation is seed-only, through an unauthenticated `internal` route
  fenced by NetworkPolicy alone.

A Backoffice browser is privileged but **outside the cluster trust boundary**.
Routing it to `internal` endpoints would silently redefine `internal` as
"anything an admin token can reach"; giving it SQL keeps the guardrail bypass.
RFC-0022/0024 delivered the missing identity prerequisite: the realm mints
`backoffice_admin` in `realm_access.roles`, and `pkg/authmw` normalizes roles.

## Scope

### In scope

- The audience (`/{service}/v1/protected/…`), guard chain, and cross-cutting
  conventions (role, actor, idempotency, audit, pagination) for privileged
  browser-driven operations.
- Which component enforces each link of the chain (edge vs service).

### Out of scope

- The portal's frontend architecture ([ADR-049](../ADR-049-admin-portal-tanstack-spa/)).
- Whether an aggregation layer fronts these APIs ([ADR-048](../ADR-048-admin-portal-no-bff/)).
- Fine-grained operator roles, maker-checker, refunds, forced FSM transitions —
  deferred, each needing its own safety review (RFC-0023 Non-Goals).

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Domain ownership | The service that owns the invariant must own the privileged write path; nothing else may mutate its state |
| 2 | Security posture | Privileged browser traffic must be explicitly contracted, role-gated in-service, and audited — not tunneled through `internal` |
| 3 | Operability | Every live operator pain (manual_review, stock fix, recon triage) becomes a governed, observable path |
| 4 | Simplicity | Reuse the existing edge, authmw, and route-group patterns; no new infrastructure component |

## Decision

We will expose administrative operations exclusively as
`/{service}/v1/protected/…` HTTP routes on the owning services.

Every protected route passes the same layered guard as `private` routes —
Envoy Gateway's `jwt-edge` SecurityPolicy does the coarse signature/issuer/
audience/expiry check, and the owning service's `pkg/authmw` re-verifies
authoritatively — plus one net-new in-service link:
`MiddlewareRequireRole("backoffice_admin")`, returning the shared error
envelope with `403 FORBIDDEN` on a role miss. The edge never checks roles;
the browser never reaches `/internal/`.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | Only the service owning the domain implements its protected routes; no cross-service writes |
| **Write path** | Browser → edge (`jwt-edge` coarse) → owning service (authmw + role gate) — every link fails closed |
| **Actor** | `actor_sub` comes from the verified token `sub`, never from the request body |
| **Idempotency** | Retryable commands carry `Idempotency-Key` (payment-lineage style) or body `command_id` (inventory style); same key + changed payload → `409` |
| **Audit** | A durable audit record commits **in the same transaction** as the write; a failed audit insert fails the command |
| **Boundary** | No protected route on a browser path may proxy to `/internal/`; existing seed-only internal routes are replaced, not promoted |
| **Pagination** | Protected lists use the standard `page`/`page_size` envelope, including on services whose public reads diverge |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Protected routes on owning services** | Ownership intact; explicit contracts; reuses edge + authmw | Per-service route work; more edge surface | **Selected** |
| **B — Promote existing `internal` routes to the browser** | Zero new routes to write | Redefines `internal`; seed-only routes are unauthenticated; no role gate, no audit | Rejected |
| **C — Central admin backend with its own DB access** | One place to guard | Breaks domain ownership; second writer to every schema; invariants re-implemented | Rejected |
| **D — Keep SQL runbooks** | No code | No validation, no audit, no idempotency; already caused the pains above | Rejected (status quo) |

### Why the selected option won

Only option A satisfies drivers 1 and 2 simultaneously: the owning service
keeps its invariants and gains an explicit, guarded, audited privileged
surface. The per-service cost is bounded — the route-group and middleware
patterns already exist (payment's `RegisterRoutes`/mount split is the
template).

### Why the closest alternative lost

Option B is cheaper only until the first incident: the seed-only product
create is unauthenticated by design (NetworkPolicy-fenced), and promoting it
to a browser path would ship an unguarded admin endpoint. Explicit contracts
are the point, not the tax.

## Consequences

### Positive consequences

- Every operator action gets validation, a role gate, an actor, idempotency,
  and an audit trail — the raw-SQL and "manual fix" paths become retireable.
- `protected` stops being a paper audience; api.md conventions become
  enforceable in review.
- Inventory's already-built stock commands finally get a caller.

### Negative consequences and accepted trade-offs

- New edge surface per service (HTTPRoutes + SecurityPolicy attachments) to
  keep scoped and audited.
- One coarse role: every operator is superuser-shaped until a role split.
- Slice-by-slice delivery: services grow protected groups at different times.

### Neutral consequences

- Service repos each gain an authmw + role-gate wiring (product, inventory,
  shipping get their first authmw import).

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| `MiddlewareRequireRole` in `pkg/authmw` | pkg | RFC-0023 train 1 | Unit-tested 403 envelope; one version bump consumed by services |
| Protected route groups per service (slice A then B) | service repos | RFC-0023 trains 2-3 | Routes live behind role gate in compose e2e |
| Edge exposure (HTTPRoute + `jwt-edge`) per service, both config sets | homelab | RFC-0023 trains 2-3 | Unauthenticated `/protected/` request rejected at the edge (audit row) |
| Protected conventions in `docs/api/api.md` + owning service contracts | homelab | RFC-0023 train 0+ | Docs match as-built routes |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Role gate fails closed | Compose e2e: customer token (bob) → 403 `FORBIDDEN` on every protected route |
| Edge coarse check | Compose e2e: tokenless `/protected/` request rejected at the edge, never reaching the service |
| Actor from token | Handler tests: body-supplied actor ignored; audit rows carry token `sub` |
| Audit atomicity | Service tests: forced audit failure rolls back the command |
| No browser → `internal` | Route inventory in `docs/api/` + edge config review; no HTTPRoute exposes `/internal/` |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A second operator role is needed (role split → fine-grained gate design).
- A protected command requires cross-service coordination that per-service
  routes cannot express (saga-style admin operations).
- Workload identity (SPIFFE-style) replaces NetworkPolicy as the `internal`
  fence, changing the audience boundary this ADR leans on.

A review does not automatically reverse the decision. A changed architectural
decision requires a new ADR that supersedes this one.

## References

- [RFC-0023](../../rfc/RFC-0023/) · [research](../../rfc/RFC-0023/research.md)
- [`docs/api/api.md` — audience segments](../../../api/api.md#audience-segments)
- [ADR-044](../ADR-044-envoy-gateway-platform-edge/) — the edge these routes ride
- [OrderManualReviewBacklog runbook](../../../observability/runbooks/microservices/OrderManualReviewBacklog.md) — the raw-SQL path this decision retires

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-10 | Proposed / Not started | Decision recorded during RFC-0023 review (as draft ADR-042, renumbered 047 on 2026-08-11) |
| 2026-08-13 | Accepted / Not started | Accepted with RFC-0023; edge mechanics restated EG-native per ADR-044 (RFC text predates the Kong retirement) |

---
_Last updated: 2026-08-13_
