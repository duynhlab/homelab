# ADR-045: Rate-limit at the edge with local token buckets, not a global RLS

> **Decision summary:** We will rate-limit at the Envoy Gateway edge with
> BackendTrafficPolicy **local** token buckets per route, deploying no Rate Limit
> Service and no Redis dependency at the edge — because the platform's edge sees a
> handful of clients behind one NAT, so the per-client-IP fairness Kong's
> Valkey-backed counters provide today buys approximately nothing. We accept an honest
> semantic downgrade — one aggregate bucket per route, per proxy instance, with
> configured numbers halved for `replicaCount: 2` — in exchange for zero stateful
> components at the edge and a failure mode that cannot exist (in-process buckets
> neither fail open nor closed). Global rate limiting stays as a recorded escape
> hatch with a demonstrated-need trigger.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-11 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The edge rate-limiting mechanism and its semantics (bucket scope, numbers, headers, escape hatch). Not the edge product itself. |
| **Affected components** | BackendTrafficPolicy CRs on API and admin routes, CORS `expose` header list, Valkey db 1 (loses its second consumer), `local-stack/docs/e2e-audit.md` request pacing |
| **Related RFC** | [RFC-0024](../../rfc/RFC-0024/) |
| **Related research** | [research.md](../../rfc/RFC-0024/research.md) |
| **Related ADR** | [ADR-044](../ADR-044-envoy-gateway-platform-edge/) (the edge this policy attaches to) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0024 program — P2/P4/P5 trains |
| **Adoption** | **Complete** — measured on a cluster for the first time 2026-08-25: `make e2e-ratelimit GATE=kind` drove under and over the ceiling and returned **429 with draft-03 `X-RateLimit-*` headers** |

## Context

Today the edge rate limit is Kong's `rate-limiting` plugin with `policy: redis`:
**per-client counters** (identifier defaults to client IP on anonymous routes) shared
across the 2 proxy replicas in **Valkey db 1**, `fault_tolerant: true` (**fails
open** when Valkey is down), at 5 r/s / 100 r/min / 2 500 r/h on API routes and
1 200 r/min on admin UIs. Kong emits `RateLimit-*` headers, which appear in the CORS
expose list, and the E2E release audit derives its request pacing from these numbers.

[ADR-044](../ADR-044-envoy-gateway-platform-edge/) replaces Kong with Envoy Gateway,
which offers two mechanisms with different semantics
([rate-limit deep-dive](../../rfc/RFC-0024/research.md#rate-limiting-deep-dive--local-vs-global-owner-direction-local-first)):
**local** (a token bucket inside each Envoy instance — no extra components, but no
`Distinct` matching, so one aggregate bucket per route, per instance) and **global**
(an Envoy RLS Deployment + Redis — exact shared counters and per-client `Distinct`
buckets, i.e. Kong's semantics, at the cost of a new stateful component and a new
failure mode at the edge). A choice between them is a real semantic decision, not a
mechanical port, and it determines whether the edge keeps a Redis dependency.

## Scope

### In scope

- The edge rate-limiting mechanism: local vs global.
- Bucket semantics and how configured numbers account for replicas.
- The response-header vocabulary and its CORS ripple.
- The escape-hatch condition for adopting global rate limiting later.

### Out of scope

- The edge product and cutover style — [ADR-044](../ADR-044-envoy-gateway-platform-edge/).
- Service-side throttling or per-tenant quotas (none exist today; none are added).
- Valkey's other consumers (caching) — only the edge coupling to db 1 changes.
- Where the E2E gate runs — [ADR-046](../ADR-046-e2e-gate-kind-fallback/); only the
  audit's pacing numbers are affected here.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | No speculative stateful components | An RLS Deployment + Redis coupling exists only to preserve per-IP fairness that the homelab edge (single-digit clients behind one NAT) cannot observably use |
| 2 | Honest failure behavior | Kong's counters fail **open** when Valkey is down; an in-process bucket has no such mode — it cannot fail open or closed |
| 3 | Semantic honesty over parity theater | If per-IP fairness is lost, the record must say so plainly and define the trigger that would bring it back, rather than pretending local mode is a drop-in |
| 4 | Operational cost | Every edge component added is a component to patch, alert on, and debug; the edge should end this migration with fewer dependencies, not the same number re-branded |

## Decision

We will configure edge rate limiting as **BackendTrafficPolicy `rateLimit.local`**
rules per route, and we will **not deploy the Envoy RLS** or any Redis backend at the
edge. Valkey db 1 loses its second consumer.

The semantic change is accepted and stated plainly: local mode has **no `Distinct`
matching**, so each route gets **one aggregate token bucket per proxy instance** —
per-client-IP fairness is lost. For this platform's traffic (a handful of clients
behind one NAT) that fairness was decorative. Because buckets are per instance, the
effective ceiling is ≈ configured × replica count; **configured numbers are halved**
for `replicaCount: 2` so the fleet-wide ceiling approximates today's intent.
Rate-limit responses carry **`X-RateLimit` draft-03 headers**, which replace Kong's
`RateLimit-*` names in the CORS expose list; the E2E audit's request pacing
re-derives from the new numbers.

**Escape hatch, with a recorded trigger:** adopt global rate limiting (EnvoyGateway
`rateLimit.backend: Redis` → Valkey db 1, plus the RLS Deployment) **only on a
demonstrated multi-client fairness need — real abuse from distinct sources — not
speculation.** Global mode restores exact shared counters and per-client `Distinct`
buckets if that day comes.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Mechanism** | Edge rate limits are BTP `rateLimit.local` rules. No RLS Deployment, no `rateLimit.backend`, and no Redis/Valkey reference may exist in edge manifests absent the recorded trigger. |
| **Numbers** | Configured limits are the intended fleet-wide ceiling divided by the proxy replica count (halved at `replicaCount: 2`). A replica-count change re-derives every configured number in the same PR. |
| **Bucket scope** | One bucket per route (per instance). No per-IP or per-user matching may be attempted in local mode — `Distinct` requires global. |
| **Headers** | 429 responses use `X-RateLimit` draft-03 headers; the CORS expose list names them (not Kong's `RateLimit-*`). |
| **Escape hatch** | Switching to global rate limiting requires a documented abuse incident from distinct client sources, and a superseding ADR — not a config drive-by. |
| **Failure behavior** | There is none to configure: local buckets are in-process. No fail-open/fail-closed knob may be emulated with custom machinery. |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Local token buckets** | Zero extra components; no edge Redis; no failure mode; `shared`/`cost`/draft-03 header options | Per-IP fairness lost; per-instance approximation (numbers halved); semantics diverge from Kong today | Selected |
| **B — Global RLS from day one** | Exact shared counters; `Distinct` per-client buckets = Kong's semantics; `shadowMode` dry-run | +1 Deployment + Redis dependency at the edge; a new failure mode to operate; pays permanent cost for fairness no current client population exercises | Rejected |
| **C — Keep per-IP semantics via `Distinct`** | Closest to today's behavior | `Distinct` is global-only (official docs) — this option **is** option B with different framing | Rejected |
| **D — No edge rate limiting** | Nothing to configure | Removes a working abuse brake and the admin-UI request ceiling for zero savings — local mode costs no components anyway | Rejected |

### Why the selected option won

Option A is the only choice that satisfies drivers 1, 2, and 4 at once: the edge ends
the migration with strictly fewer dependencies (Valkey db 1 coupling deleted, no RLS),
and the one thing it gives up — per-IP fairness — is a capability the platform's
actual client population cannot demonstrate a use for. Driver 3 is satisfied by this
record itself: the downgrade is written down, halved numbers are a rule, and the road
back is a named trigger.

### Why the closest alternative lost

Option B preserves Kong's exact semantics, and that is precisely its weakness: it
preserves them **speculatively**. It re-couples the edge to Valkey (the dependency
this migration otherwise removes), adds an RLS Deployment to patch and alert on, and
re-introduces a distributed failure mode (RLS down → configurable allow/deny) — all
to keep per-client buckets fair between clients that do not exist. If they ever do,
the escape hatch is documented, mechanical, and reversible; paying for it in advance
is not.

## Consequences

### Positive consequences

- The edge has **no stateful dependency**: Valkey db 1's second consumer disappears,
  and today's fail-open behavior (limits silently off when Valkey is down) becomes
  structurally impossible.
- One fewer Deployment than the global alternative; nothing new to patch, monitor,
  or capacity-plan at the edge.
- Standard draft-03 `X-RateLimit` headers replace a vendor vocabulary.
- The escape hatch is pre-designed: global mode reuses Valkey db 1, so a future
  adoption is a bounded change, not a research project.

### Negative consequences and accepted trade-offs

- **Per-client-IP fairness is lost**: one noisy client can exhaust a route's bucket
  for everyone behind the same route. Accepted for a homelab edge whose clients sit
  behind one NAT.
- The ceiling is approximate: per-instance buckets make the effective limit
  load-balancing-dependent (≈ configured × replicas); halving compensates on average
  only.
- Every configured number is coupled to `replicaCount` by convention, enforced by
  review rather than by machinery.
- The header rename ripples: CORS expose list, any client reading `RateLimit-*`, and
  the E2E audit pacing all update with the cutover.

### Neutral consequences

- Services see no change; no service-side throttling exists before or after.
- Admin-UI routes keep a request ceiling (local bucket) alongside their CIDR fence.
- The E2E audit keeps asserting 429 behavior — only the numbers and headers change.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| BTP `rateLimit.local` rules on API and admin routes, numbers halved for `replicaCount: 2` | platform | RFC-0024 P2 | 429 observed at the per-instance threshold on Kind |
| CORS expose list updated to `X-RateLimit` draft-03 names | platform | RFC-0024 P2 | Browser preflight exposes the new headers |
| Remove the edge's Valkey db 1 coupling (Kong plugin CR deleted with ADR-044's sweep) | platform | RFC-0024 P5 | No edge manifest references Valkey |
| Re-derive E2E audit request pacing from the new numbers | platform | RFC-0024 P4/P6 | `local-stack/docs/e2e-audit.md` pacing rule cites the new limits |
| Per-route 429 counts kept as a post-migration signal | platform | RFC-0024 P4 | Dashboard/alert coverage per the observability cutover |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Local-only mechanism | Repo grep: no RLS Deployment, no `rateLimit.backend`, no edge Redis reference |
| Threshold behavior | Scripted burst against one instance returns 429 at the halved number; headers are draft-03 `X-RateLimit` |
| CORS ripple | Preflight response exposes the new header names; no `RateLimit-*` remains in the expose list |
| Pacing | E2E audit rows pass under the re-derived pacing |
| Escape hatch discipline | Any global-mode manifest without a superseding ADR fails review |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A **real abuse incident from distinct client sources** demonstrates a multi-client
  fairness need — the recorded escape-hatch trigger; adopt global mode via a
  superseding ADR.
- Proxy `replicaCount` grows beyond 2–3, making the per-instance approximation too
  loose to reason about.
- A client population with per-client SLAs or quotas appears (the platform gains real
  external consumers).

A review does not automatically reverse the decision. A changed decision requires a
new ADR that supersedes this one.

## References

- [RFC-0024](../../rfc/RFC-0024/) — Design Details → Rate limiting (decided)
- [RFC-0024 research — rate-limiting deep-dive](../../rfc/RFC-0024/research.md#rate-limiting-deep-dive--local-vs-global-owner-direction-local-first) — local vs global comparison, `Distinct` limitation (Context7-confirmed), Kong as-built numbers
- [ADR-044](../ADR-044-envoy-gateway-platform-edge/) — the edge this policy attaches to
- [`local-stack/docs/e2e-audit.md`](../../../../local-stack/docs/e2e-audit.md) — pacing rule that re-derives

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-10 | Proposed / Not started | Proposed inside the RFC-0024 review |
| 2026-08-11 | Accepted / Not started | Accepted with RFC-0024; numbering assigned 044–046 because ADR-039/040 were consumed by unrelated decisions (RFC text had said 045–047) |
| 2026-08-22 | Accepted / Partial | **Amendment — API route sizing raised from 2/Second to 25/Second per instance** (`policies/btp-api.yaml`, ~50/s across two replicas). The mechanism is unchanged: still `rateLimit.local`, still exactly one rule without `clientSelectors`, still no RLS and no Redis. What changed is the number, because the original sizing compared two things that are not comparable. The pre-cutover limit was billed **per client**; local mode has no client dimension, so halving it for two replicas produced an **aggregate** shared by every client, every identity and every route this policy targets. At ~4/s fleet-wide a single SPA page fanning out parallel calls could exhaust the bucket and see its own 429, and nothing measured it: this ADR's own validation row ("429 observed at the per-instance threshold on Kind") was never exercised, and the Kind runbook did not mention rate limiting at all. The new number matches the compose edge so a measurement means the same on both gates. Measured on Kind before and after: 25/s went from heavily limited to clean, while 200/s still returns 429 with the `X-RateLimit` draft-03 headers — raised, not disabled. Enforcement is now asserted by [`scripts/k6/ratelimit.js`](../../../../scripts/k6/ratelimit.js) ([ADR-056](../ADR-056-k6-e2e-assertion-layer/)). Note for anyone tempted to exempt a caller instead: a second rule **cannot** loosen the limit — Envoy Gateway applies every matching rule and rejects if any triggers, so `clientSelectors` can only ever make a subset stricter. |
| 2026-08-25 | Accepted / **Complete** | Kind gate passed — the validation row this ADR's own 2026-08-22 amendment admitted 'was never exercised' is now exercised. `make e2e-ratelimit` is a separate target from `make e2e`, which is why it had been missed. |

---
_Last updated: 2026-08-25 — Adoption → **Complete** on the Kind gate pass (ELIGIBLE); the History row was appended in the same edit._
