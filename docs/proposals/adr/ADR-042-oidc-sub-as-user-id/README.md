# ADR-042: Use the OIDC subject as the application user_id, as a string, fleet-wide

> **Decision summary:** We will make `user_id = token.sub`, persisted as a
> `VARCHAR(255)` string in every service, replacing the integer `auth.users.id`
> that is today's fleet-wide identifier — executed as an in-place greenfield
> migration with no dual column, no backfill, and no compatibility window. We
> accept editing shipped initial migrations and two proto field types, and we
> give up ordered, compact numeric ids, in exchange for one canonical opaque
> identifier that arrives verified in every token and deletes all nine
> numeric-parse sites — including two that fail unsafely today.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-08-11 |
| **Owners** | `duynhne` |
| **Deciders** | `duynhne` |
| **Scope** | The type and source of the application user identifier in every schema, proto, shared module, and seed |
| **Affected components** | user, cart, order, review, notification, payment, checkout schemas; notification + payment protos; `pkg/idempotency`; order-saga Temporal inputs; all seeds |
| **Related RFC** | [RFC-0022](../../rfc/RFC-0022/) — identity design record, **executed by [RFC-0024](../../rfc/RFC-0024/)** |
| **Related research** | [RFC-0022 research.md](../../rfc/RFC-0022/research.md) — [Identity data blast radius](../../rfc/RFC-0022/research.md#identity-data--the-real-blast-radius) |
| **Related ADR** | [ADR-041](../ADR-041-keycloak-platform-idp/) (the issuer whose `sub` this adopts), [ADR-043](../ADR-043-oidc-browser-workload-trust/) (how the token carrying `sub` reaches the platform), [ADR-010](../ADR-010-shared-idempotency-library/) (the shared module whose `UserID` type changes) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0024 program — phases P1/P3/P5 (PR trains) |
| **Adoption** | Not started |

## Context

Today the application identity is the integer `auth.users.id`, minted by
auth-service at registration. Every domain service persists it, several parse
it back out of the verified token's `sub` claim with `strconv.Atoi`, and two
of those sites fail unsafely: `review_repo.go:82` swallows the conversion
error entirely, and the order saga's `activities.go:155` raises a
**non-retryable** Temporal error on a non-numeric subject — meaning any
non-integer `sub` hard-fails an in-flight fulfillment saga.

ADR-041 replaces the minting authority: Keycloak's `sub` is an opaque UUID
string, not an integer, so the identifier question must be decided before any
schema, proto, or seed is written against the new issuer. The full audited
inventory of what the integer touches is in
[RFC-0022 research → Identity data](../../rfc/RFC-0022/research.md#identity-data--the-real-blast-radius):
five `INTEGER` columns, payment's two `BIGINT` columns, checkout's `BIGINT`
idempotency column beside its already-`TEXT` session columns, the shared
`pkg/idempotency` module's `int64`, two numeric proto fields, nine `Atoi`
sites, and the Temporal workflow inputs.

The migration cost is uniquely low right now: the platform is greenfield —
local databases re-seed from zero, no production identities exist, and the
cutover starts with empty Temporal history, so no in-flight workflow ever sees
both identifier types.

## Scope

### In scope

- The canonical application user identifier: its source (`token.sub`), its
  type (string, `VARCHAR(255)`), and its uniqueness of representation
  (single-issuer collapse of `(iss, sub)` to `sub`).
- The migration shape: in-place greenfield edits, no transition machinery.
- The type change in every schema, proto, shared module, and Temporal input
  that carries the identifier.
- The role of `preferred_username` / `email`: display claims only.

### Out of scope

- Who issues the token and what `sub` contains — [ADR-041](../ADR-041-keycloak-platform-idp/).
- How tokens are obtained by browsers and whether services exchange tokens —
  [ADR-043](../ADR-043-oidc-browser-workload-trust/).
- Multi-issuer identity, account linking, tenancy (a future ADR revisits the
  single-issuer collapse only if those arrive).
- Ownership and role *authorization* semantics — unchanged; only the key's
  type changes.

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | One verified identifier, zero conversions | The token's `sub` is what every service already validates; parsing it into an int adds nine failure points, two of which fail unsafely today |
| 2 | Greenfield window | Empty databases and empty Temporal history make an in-place type change safe; every deferred month makes it a real migration |
| 3 | Issuer-portability of the schema | An opaque string column outlives the choice of IdP; a numeric column re-couples every schema to whoever mints integers |
| 4 | Simplicity of the end state | No mapping tables, no dual columns, no per-service translation layer to operate forever |
| 5 | Constraint preservation | `UNIQUE(user_id, …)` semantics must survive the type change unchanged |

## Decision

We will use the OIDC subject as the application user identifier:
`user_id = token.sub`, persisted as a **string** (`VARCHAR(255)`) in every
service, fleet-wide.

The identity model is logically `(iss, sub)`; storage collapses it to `sub`
because exactly one issuer is accepted platform-wide (ADR-041) and every
service fully validates the token — issuer included — before trusting the
value. No separate `customer_id` is introduced. `preferred_username` and
`email` are display claims and are never used as ownership or lookup keys.

The migration is **greenfield and in-place**: no dual column, no backfill, no
compatibility window. The five `INTEGER` columns (`user_profiles.user_id`,
`cart_items.user_id`, `orders.user_id`, `reviews.user_id`,
`notifications.user_id`), payment's two `BIGINT` columns
(`payments.user_id`, `idempotency_keys.user_id`), and checkout's `BIGINT`
`idempotency_keys.user_id` are edited **in their existing 000001/000002
migrations** rather than appended as new migrations — the schemas have never
held production data, so rewriting history is honest, and it keeps
first-migration readability. `pkg/idempotency` changes `Record.UserID` from
`int64` to `string` in a single coordinated version bump. The notification
proto changes its two `int32` user fields to `string`; the payment proto
changes its `int64` user field to `string`.

All ~9 `strconv.Atoi(sub)` call sites are **deleted**, including
`review_repo.go:82` (which swallows the error today) and the order saga's
`activities.go:155` (whose `Atoi` raises a non-retryable Temporal error).
Empty Temporal history at cutover sidesteps in-flight compatibility: no
running workflow ever carries an integer input into a string-typed activity.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | The verified token's `sub` is the only source of `user_id`. Request payloads must never override it; internal RPCs carry it explicitly as a string. |
| **Type** | `user_id` is a string (`VARCHAR(255)` in SQL, `string` in Go and proto) everywhere. No service reintroduces a numeric user identifier, parse, or cast. |
| **Single-issuer collapse** | Storing bare `sub` is valid only while exactly one issuer is accepted and every service validates it. A second issuer reopens this ADR before any token is trusted. |
| **Display claims** | `preferred_username` / `email` may be rendered, logged per data policy, or shown — never persisted as an ownership key or used in a WHERE clause for authorization. |
| **Constraints** | Existing uniqueness semantics (`UNIQUE(user_id, product_id)`, `UNIQUE(user_id, idempotency_key)`, `UNIQUE(user_id)`) carry over the type change unchanged. |
| **No transition machinery** | No mapping table, dual column, backfill job, or int-fallback path may be merged. The cutover is atomic per the greenfield rebuild contract. |
| **Failure behavior** | An empty `sub` after verification is a 401 (authmw contract); no handler treats it as anonymous. |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — `sub` as string, in-place greenfield migration** | One verified identifier end-to-end; deletes all nine parse sites and both unsafe failures; schemas become issuer-agnostic; cheapest it will ever be | Edits shipped initial migrations; two proto field-type changes; loses compact ordered ids | Selected |
| **B — Mapping table (`sub` → serial int) per service** | Keeps compact int keys and existing column types; familiar FK ergonomics | Every service gains a lookup on every authenticated request plus create-on-first-sight races; N tables re-implement identity resolution forever; the map *is* a compatibility layer with no consumer | Rejected |
| **C — Keep int ids; store a numeric attribute in Keycloak** | Zero schema change | Recouples identity to a platform-minted counter; the IdP must be writable at registration to allocate ids (a provisioning hook ADR-041 deliberately avoids); `sub` and `user_id` diverge, so tokens alone no longer authorize rows | Rejected |
| **D — Dual-write transition (both columns, cut over later)** | Textbook zero-downtime shape | Machinery for a problem the platform does not have: there is no data to keep alive and no traffic to keep serving; every piece must be built, tested, and then deleted | Rejected |

### Why the selected option won

Option A is the only end state with zero moving parts: the value every
service already verifies is the value it stores, compares, and forwards.
Drivers 1 and 4 are satisfied outright, and driver 2 makes the one real cost —
a fleet-wide type change — nearly free, because nothing exists to migrate.
Editing the 000001/000002 migrations in place (rather than stacking an ALTER
on schemas that never shipped data) keeps each service's schema history
readable as a single truthful statement.

### Why the closest alternative lost

Option B is the credible enterprise answer, and it loses on what it must be
built *for*. A mapping table earns its keep when external subjects must
coexist with established numeric keys — existing data, existing FKs, existing
integrations. This platform has none of those: the integer keys have no
consumers a string cannot serve, and the uniqueness constraints transfer
unchanged. What B adds is permanent: a per-service resolution query on the
hot path, a create-on-first-sight race to handle, and a second identifier
whose only purpose is to be translated back. Paying a one-time greenfield
edit to avoid a forever-component is the better trade.

## Consequences

### Positive consequences

- One identifier flows HTTP → gRPC → DB → Temporal with no conversion; the
  nine `Atoi` sites and their two unsafe failure modes are gone.
- Schemas are issuer-agnostic: any future IdP that presents a verified string
  subject fits without another fleet migration.
- Checkout's already-`TEXT` session columns stop being the odd ones out; the
  fleet converges on one convention.
- Seeds become deterministic against ADR-041's fixed demo-user UUIDs.

### Negative consequences and accepted trade-offs

- Shipped 000001/000002 migrations are edited in place — safe only because of
  the greenfield rebuild contract, and existing local environments must
  rebuild from zero rather than migrate forward.
- Proto field type changes (notification `int32`→`string` ×2, payment
  `int64`→`string`) are wire-breaking; acceptable only because the whole
  fleet cuts over in one program.
- String keys are larger than integers in rows and indexes, and carry no
  ordering; any future "newest users" need uses timestamps, not id order.
- `pkg/idempotency`'s type change requires a coordinated version bump across
  all consumers (all are on one pkg version today).

### Neutral consequences

- Uniqueness and ownership-scoping semantics are unchanged — only the key's
  type differs.
- The single-issuer collapse is a recorded constraint, not a limitation felt
  today; multi-issuer arrival has a named revisit path.
- Observability data policy already forbids `sub` as a metric label; that rule
  is unaffected by the type change.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Edit the 5 INTEGER + 3 BIGINT `user_id` columns to `VARCHAR(255)` in their 000001/000002 migrations | `duynhne` | RFC-0024 P3 | Clean rebuild creates string columns; constraints intact |
| `pkg/idempotency` `Record.UserID` `int64`→`string` + coordinated version bump | `duynhne` | RFC-0024 P3 | All consumers on the new version; no int64 user field remains |
| Notification (`int32`→`string` ×2) and payment (`int64`→`string`) proto changes | `duynhne` | RFC-0024 P3 | Regenerated stubs; cross-service calls pass string `user_id` |
| Delete all ~9 `strconv.Atoi(sub)` sites (incl. `review_repo.go:82`, saga `activities.go:155`) | `duynhne` | RFC-0024 P3 | `grep` for `Atoi` on subject paths returns nothing; saga input is string end-to-end |
| Re-seed all domain data against fixed-UUID subjects | `duynhne` | RFC-0024 P3 | Seeds idempotent; ownership smoke tests pass |
| Update service contracts | `duynhne` | `docs/api/{user,cart,order,review,notification,payment,checkout}.md`, `api.md` | As-built docs show string `user_id` everywhere |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| String round-trip | E2E test: a UUID subject flows HTTP → gRPC → DB → Temporal and back without conversion or truncation |
| No payload override | Contract test: request bodies carrying a different `user_id` cannot change row ownership |
| Constraint survival | Schema test: uniqueness constraints reject duplicates with string keys exactly as with integers |
| No numeric parse | Repo check: no `strconv.Atoi`/numeric cast on any subject-derived value in any service |
| Saga safety | Workflow test: order fulfillment completes with a UUID subject; no non-retryable identity error path exists |
| Empty-sub rejection | authmw test: verified token with empty `sub` yields 401 on every private route |
| Documentation | All touched `docs/api/` contracts link this ADR |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- A second accepted issuer, account linking, or tenancy arrives — the
  `(iss, sub)`→`sub` collapse is no longer sound and needs an explicit
  representation.
- A requirement appears that genuinely needs compact or ordered numeric user
  keys (e.g. an integration contract outside our control).
- Index or storage cost of string keys becomes measurable at this platform's
  scale (not expected; would need evidence).

A review does not automatically reverse the decision. A changed decision
requires a new ADR that supersedes this one.

## References

- [RFC-0022](../../rfc/RFC-0022/) — identity design record (§ Application user identifier)
- [RFC-0022 research — Identity data: the real blast radius](../../rfc/RFC-0022/research.md#identity-data--the-real-blast-radius)
- [RFC-0024](../../rfc/RFC-0024/) — executing program (phases P1/P3/P5)
- [ADR-041](../ADR-041-keycloak-platform-idp/) · [ADR-043](../ADR-043-oidc-browser-workload-trust/)
- [ADR-010](../ADR-010-shared-idempotency-library/) — the shared idempotency module
- [`docs/api/api.md`](../../../api/api.md) — shared token/principal contract
- [`docs/api/pkg.md`](../../../api/pkg.md) — pkg module layering

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-08-10 | Proposed / Not started | Proposed inside the RFC-0022/RFC-0024 review |
| 2026-08-11 | Accepted / Not started | Accepted with the RFC-0024 program review (this PR); numbering assigned 041–043 because ADR-039/040 were consumed by unrelated decisions |

---
_Last updated: 2026-08-11_
