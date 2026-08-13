# ADR-048: Call owning services directly from the Admin Portal; defer an admin BFF

> **Decision summary:** We will have the Admin Portal call each owning
> service's protected API directly through the platform edge, with no admin
> backend, admin database, or BFF in front — because MVP screens are
> single-domain, a BFF would be a second writer-shaped component with nothing
> to own, and commands must stay visibly owned by the right service. We accept
> per-domain frontend fan-out on dashboard-style pages in exchange for zero
> new backend components and an unambiguous ownership story; a **read-only**
> `admin-api` aggregator remains the named escape hatch with an explicit
> trigger.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-13 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The call topology between the Admin Portal and the platform APIs — whether anything aggregates or proxies in between. |
| **Affected components** | Admin Portal SPA (`admin-service` repo), Envoy Gateway routes, the six services carrying protected routes |
| **Related RFC** | [RFC-0023](../../rfc/RFC-0023/) |
| **Related research** | [research.md](../../rfc/RFC-0023/research.md) |
| **Related ADR** | [ADR-047](../ADR-047-protected-apis-on-owning-services/) (the APIs being called), [ADR-049](../ADR-049-admin-portal-tanstack-spa/) (the SPA doing the calling) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0023 program — SPA trains |
| **Adoption** | Not started |

## Context

The Backoffice MVP is deliberately narrow: single-domain screens (stock pages
talk to inventory, order pages to order, …) plus a dashboard of independent
attention cards. A BFF/aggregator in front of the protected APIs would need
its own deployment, edge exposure, authentication posture, and observability —
while owning no business data and implementing no domain invariant. The
platform has already rejected accidental second writers repeatedly (see
ADR-047 alternatives); a BFF is the read-side version of the same temptation.

The real risk a BFF hedges against — dashboard/global-search fan-out becoming
operationally unreasonable — is measurable and has not occurred (the MVP
dashboard is a handful of cards, each backed by one owning endpoint).

## Scope

### In scope

- The MVP call topology: `Admin Portal → Envoy Gateway → owning service`.
- The conditions under which an aggregation layer would be reconsidered.

### Out of scope

- The protected API conventions themselves ([ADR-047](../ADR-047-protected-apis-on-owning-services/)).
- Server-side rendering or edge deployment of the portal (RFC-0023 non-goals).

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Minimal blast radius | No new backend component, database, or deployment to operate for an MVP |
| 2 | Ownership clarity | A command's network path shows which service owns it |
| 3 | Reversibility | A read aggregator can be added later without breaking any contract |

## Decision

We will point the Admin Portal at the owning services directly, through the
platform edge on the `/protected/` audience. No admin backend service, no
admin database, no BFF ships in the MVP; the `admin-service` repository
contains only the static SPA.

A future `admin-api` may aggregate **reads** (global search, dashboards, case
views) if the fan-out trigger fires. It would own no business data, implement
no domain invariant, and never carry writes — commands stay direct to the
owning service permanently.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | Every portal request terminates at the service owning the domain |
| **Write path** | Commands are always portal → edge → owning service; an aggregator may never proxy a write |
| **Read path** | MVP reads are direct; aggregation requires the revisit trigger plus a new ADR |
| **Boundary** | The `admin-service` repo ships static assets only — no server code, no DB credentials, no domain types beyond API contracts |
| **Failure behavior** | Each dashboard card / page section fails independently; one failed domain read never blanks the page or fabricates state |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Direct calls, no BFF** | Zero new backend; ownership visible; smallest MVP | Per-domain fan-out on dashboards; N CORS-scoped clients in one SPA | **Selected** |
| **B — Read/write BFF (`admin-api`)** | One frontend-shaped API; server-side joins | New service + deployment with nothing to own; write proxying blurs ownership; slower MVP | Rejected |
| **C — GraphQL gateway** | Flexible queries for future screens | Heaviest option: new runtime, schema layer, and caching semantics for a single-operator MVP | Rejected |

### Why the selected option won

Driver 1 is decisive for an MVP with one operator: every alternative adds a
deployable component whose only job is indirection. Driver 2 compounds it —
the portal's network tab is the ownership documentation.

### Why the closest alternative lost

The BFF's genuine benefit (aggregated reads) is not needed by any MVP screen,
and taking it early costs a permanent component. Deferring keeps the option
open at the price of a revisit trigger — the cheapest hedge available.

## Consequences

### Positive consequences

- MVP ships with zero new backend surface to secure, monitor, or upgrade.
- Rollback is deleting a frontend deployment and edge routes.

### Negative consequences and accepted trade-offs

- Dashboard-style pages fan out one request per domain; the portal must
  tolerate partial failure everywhere.
- Global search across domains is impossible until (if ever) the aggregator
  exists.

### Neutral consequences

- The SPA carries per-domain API clients and query keys — more frontend code,
  all of it view-layer.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Per-domain query keys + independent card/page error states | `admin-service` | RFC-0023 SPA trains | Killing one service in compose degrades only its cards (e2e row) |
| No server code / DB access in `admin-service` | `admin-service` | repo review | Repo contains static SPA only |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Direct topology | Compose e2e: portal traffic appears only on edge routes of owning services |
| Partial-failure tolerance | E2E: stop one service → its cards error, siblings render |
| No write aggregation ever | Review rule: any future `admin-api` ADR must restate the reads-only boundary |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A screen genuinely needs cross-domain joins (global search, case timeline)
  and client-side composition is measurably unreasonable (payload or latency).
- Dashboard fan-out exceeds what the edge rate posture comfortably carries.
- A second consumer (mobile ops, external tooling) needs the same aggregated
  reads.

A review does not automatically reverse the decision. A changed architectural
decision requires a new ADR that supersedes this one.

## References

- [RFC-0023](../../rfc/RFC-0023/) · [research](../../rfc/RFC-0023/research.md)
- [ADR-047](../ADR-047-protected-apis-on-owning-services/)
- [`docs/api/api.md` — aggregation rules](../../../api/api.md#aggregation-rules)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-10 | Proposed / Not started | Decision recorded during RFC-0023 review (as draft ADR-043, renumbered 048 on 2026-08-11) |
| 2026-08-13 | Accepted / Not started | Accepted with RFC-0023 |

---
_Last updated: 2026-08-13_
