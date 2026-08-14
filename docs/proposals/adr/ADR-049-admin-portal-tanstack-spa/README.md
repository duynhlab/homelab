# ADR-049: Build the Admin Portal as a separate React SPA on the TanStack stack

> **Decision summary:** We will build the Backoffice as its own static React
> 19 + TypeScript + Vite SPA (repository `admin-service`, local dev `:3009`)
> on TanStack Router/Query/Table/Form with zod, Tailwind CSS v4 + shadcn/ui,
> and keycloak-js — because the admin workload is URL-addressable,
> server-paginated, form-heavy state that this stack models with one authority
> per state type, and shadcn's data-table idiom is TanStack Table. We accept a
> second frontend convention set beside the customer SPA (react-router/SWR)
> in exchange for the workload fit, in-memory token handling, and a
> deliberately narrow, owner-selected toolchain.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-13 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The Admin Portal's application architecture: repository, runtime, routing/state/table/form libraries, styling system, auth adapter, serving model. |
| **Affected components** | New `admin-service` repository (static SPA), local-stack (`:3009`, admin origin), future `kubernetes/apps/` ResourceSet |
| **Related RFC** | [RFC-0023](../../rfc/RFC-0023/) |
| **Related research** | [research.md](../../rfc/RFC-0023/research.md) — stack comparison + Context7 audit |
| **Related ADR** | [ADR-047](../ADR-047-protected-apis-on-owning-services/) (the APIs consumed), [ADR-048](../ADR-048-admin-portal-no-bff/) (direct-call topology), [ADR-041](../ADR-041-keycloak-platform-idp/) (the IdP keycloak-js speaks to) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0023 program — SPA foundation + page trains |
| **Adoption** | Partial — `admin-service` runs the chosen stack as-built (TanStack Router/Query/Table v9 + Form, zod, Tailwind v4, shadcn preset, keycloak-js), with URL-owned list state and one shared table/detail convention across every screen. Verified locally (Playwright + axe against the live stack); the cluster deployment is merged but unverified until the Kind gate |

## Context

The Backoffice needs cross-customer tables (server pagination/sort/filter),
command forms with validation + idempotency + confirmation, URL-restorable
list state, and role-gated navigation. The customer SPA's stack
(react-router 7 Declarative Mode + SWR + hand-rolled forms, plain JS) predates
all of those needs and models none of them directly.

The owner selected the TanStack stack after a researched comparison
(RFC-0023 research: reuse-customer-stack, Refine, and Next.js alternatives all
recorded), pinned the local dev port to `:3009` (`:3002` is Grafana), and
named the personal **`product-design` skill** as the portal's UI design
authority — its preferred stack is exactly this one. keycloak-js was chosen
over `oidc-client-ts` for in-memory-by-default tokens and platform vendor
alignment; the customer SPA already ships keycloak-js 26.x since the RFC-0024
identity cutover.

## Scope

### In scope

- Repository shape, build/serve model, and the one-authority-per-state-type
  library assignment for the Admin Portal.

### Out of scope

- The customer SPA's stack (its own migration plans are separate work).
- SSR/TanStack Start/Next.js, mobile, TanStack Store/Virtual, Recharts — all
  RFC-0023 non-goals until their documented triggers fire.
- Exact dependency versions — pinned in `package.json` at implementation,
  re-verified against current docs at scaffold time.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Workload fit | Server-paginated tables, validated command forms, URL state — the portal is made of exactly these |
| 2 | One authority per state type | URL ↔ Router, remote ↔ Query, table ↔ Table, drafts ↔ Form; no state copied between owners |
| 3 | Security posture | In-memory tokens + PKCE by default (keycloak-js), improving on the customer SPA's documented localStorage trade-off |
| 4 | Consistency cost | A second convention set is a real tax — it must buy measurable fit |

## Decision

We will build the Admin Portal as a static React 19 + TypeScript (strict) +
Vite SPA in the **`admin-service`** repository (owner-chosen name; despite the
suffix it is a frontend — no Go service, no database, per ADR-048), served by
nginx on `:80` mirroring the customer SPA's build/serve patterns, local dev on
**`:3009`**.

| Concern | Authority |
|---------|-----------|
| Routing / URL state | TanStack Router, file-based, `validateSearch` (zod), `_authenticated` layout guard |
| Remote server state | TanStack Query (key factories, targeted invalidation, AbortSignal) |
| Tables | TanStack Table (`manualPagination` + `rowCount`, server sort/filter) |
| Forms | TanStack Form + zod (Standard Schema, no adapter) |
| Styling / primitives | Tailwind CSS v4 + shadcn/ui, tokens per the `product-design` skill |
| Auth/session | keycloak-js (`admin-portal` client, PKCE S256, in-memory tokens, `updateToken` → `login()` fallback) |
| Business truth | The owning Go services — never the SPA |

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | Remote records are never copied into a client store; every state type has exactly one authority above |
| **Boundary** | The repo ships static assets only; the frontend guard is UX — services re-check every request (ADR-047) |
| **Tokens** | In memory only; never localStorage/sessionStorage; never logged |
| **Tables** | Server-driven pagination/sort/filter only — no unbounded client datasets |
| **Design system** | shadcn primitives stay pristine; customization at call sites; `product-design` skill governs tokens and states |
| **Compatibility** | Divergence from the customer SPA's conventions is accepted and documented — do not port its SWR/react-router idioms in |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Separate SPA on TanStack stack** | Workload fit; one authority per state; shadcn table idiom native | Second convention set to maintain | **Selected** |
| **B — Reuse customer SPA stack (react-router + SWR + RHF)** | One convention set; shared review muscle | Models none of the admin workload directly; drags the localStorage-era auth layer forward; still a new app | Rejected — recorded as the standing reuse alternative |
| **C — Admin framework (Refine)** | CRUD scaffolding for free | Generic data-provider abstractions fight command-shaped APIs (idempotency, reasons, FSM transitions) | Rejected |
| **D — Next.js / SSR** | Familiar meta-framework | Server runtime for a static, authenticated, SEO-less tool; conflicts with static nginx serving | Rejected (non-goal) |

### Why the selected option won

Drivers 1–3 all point the same way: the portal is tables + forms + URL state
behind an OIDC guard, and option A is the only one where each of those has a
first-class, documented owner (Context7-audited patterns in research.md).

### Why the closest alternative lost

Option B's consistency benefit is real but buys the wrong thing: consistency
with an app whose own stack is under migration pressure, at the cost of
hand-building tables, form state, and URL round-tripping the admin tool needs
on day one.

## Consequences

### Positive consequences

- Every RFC-0023 frontend requirement maps to a library-native pattern —
  less bespoke state code to review.
- In-memory tokens + PKCE improve the platform's browser auth posture.
- The `product-design` skill gives the portal a coherent visual system from
  the first screen.

### Negative consequences and accepted trade-offs

- Two frontend convention sets in the platform until/unless the customer SPA
  converges — a real maintenance and review tax, accepted knowingly.
- TanStack Router/Query/Table/Form is a larger initial learning surface than
  the customer SPA's stack.

### Neutral consequences

- The repo mirrors customer-SPA build/serve/test conventions (Vite, nginx,
  `VITE_*` conditional bake, Playwright + axe) — same operational shape,
  different application libraries.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Repo scaffold + foundation (auth, shell, DataTable/Form conventions) | `admin-service` | RFC-0023 SPA train | Real login e2e against local-stack Keycloak; tsc/eslint/build clean |
| Version pins re-verified at scaffold | `admin-service` | package.json | Lockfile committed; versions match current upstream docs |
| Playwright + axe gate | `admin-service` | CI | Login + guard smoke green |
| Deployment mirror (compose `3009:80`, later ResourceSet) | homelab | RFC-0023 later trains | Portal served beside the customer SPA |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| One authority per state | Review rule: no remote record in component state/stores; keys include validated search |
| Token posture | Code review + e2e: no web-storage token, none in logs |
| Server-driven tables | Review: every list passes `manualPagination` + server `rowCount` |
| Static-only repo | Repo review: no server code (ADR-048 boundary) |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- The customer SPA completes a migration onto an overlapping stack — then
  converge conventions deliberately.
- TanStack Start/SSR becomes necessary (auth-gated server rendering need).
- Table virtualization / charting triggers fire (documented in RFC-0023).

A review does not automatically reverse the decision. A changed architectural
decision requires a new ADR that supersedes this one.

## References

- [RFC-0023](../../rfc/RFC-0023/) · [research](../../rfc/RFC-0023/research.md) (stack comparison + Context7 audit log)
- [ADR-047](../ADR-047-protected-apis-on-owning-services/) · [ADR-048](../ADR-048-admin-portal-no-bff/)
- `product-design` skill — the portal's UI design authority (agent IDE, not this repo)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-10 | Proposed / Not started | Owner selected the TanStack stack during RFC-0023 review (as draft ADR-044, renumbered 049 on 2026-08-11) |
| 2026-08-13 | Accepted / Not started | Accepted with RFC-0023 |

---
_Last updated: 2026-08-13_
