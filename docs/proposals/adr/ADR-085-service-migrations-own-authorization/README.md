# ADR-085: Own Object ACLs and Default Privileges in Service Migrations

> **Decision summary:** We will have each service's own migrations, running as
> its owner role, grant runtime access, set default privileges and backfill
> existing objects, because the repository that changes a schema is the only
> place that knows which objects exist. We accept authorization SQL in every
> service repo in exchange for no second schema-migration system.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-06 |
| **Owners** | `platform` |
| **Deciders** | `owner (duynhlab)` |
| **Scope** | Object privileges and default privileges inside every application database |
| **Affected components** | Service repositories (migrations), migration Jobs, the platform's database runbooks |
| **Related RFC** | [RFC-0029](../../rfc/RFC-0029/) |
| **Related research** | [research.md](../../rfc/RFC-0029/research.md) |
| **Supersedes** | — |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0029 Phase 2 (canary `review`) and Phase 3 |
| **Adoption** | Not started |

## Context

No platform manifest declares object privileges today, and `pg_default_acl` was
empty in every audited database. Two PostgreSQL behaviours make that matter once
roles split ([ADR-084](../ADR-084-split-service-database-roles/)):

- Default privileges are **creator-scoped**. They apply only to objects created
  by the role that set them, so they must be set by the owner and objects must be
  created after `SET ROLE` to that owner (PG-03, PG-04).
- A per-schema `REVOKE … FROM PUBLIC` default is a no-op; only the **global**
  form stops new functions from being executable by PUBLIC (PG-05). Objects that
  already exist get nothing from a new default and need an explicit backfill
  (PG-06).

CNPG `DatabaseRole` cannot express any of this. Something has to own object
authorization, and it has to know every object a service creates.

## Scope

### In scope

- Where object ACLs, default privileges and the backfill are written and run.
- The minimum privilege content every converted service carries.

### Out of scope

- The role model itself (ADR-084).
- Row-level security and `SECURITY DEFINER` functions (RFC-0029 Phase 4).
- Drift detection on memberships (ADR-086).

## Decision drivers

| Priority | Driver | Why it matters |
|---------:|--------|----------------|
| 1 | Correct for objects that do not exist yet | A new table must work on its first deploy without a manual `GRANT` |
| 2 | One owner of each schema change | Authorization must move in the same commit as the DDL it governs |
| 3 | No second migration engine | Ordering and rollback must not be duplicated in homelab |
| 4 | Expressible without a new controller | Every added controller is another credential and another failure mode |

## Decision

We will put object authorization in each service's versioned migrations, run by
the migration Job as `<svc>_migrator` after `SET ROLE <svc>_owner`. Every
converted service carries, in its migrations:

1. `ALTER DEFAULT PRIVILEGES` for `<svc>_runtime` on tables (`SELECT, INSERT,
   UPDATE, DELETE`) and sequences (`USAGE, SELECT`), set by the owner;
2. a **global** `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM
   PUBLIC`;
3. on a cluster that already holds data only, a one-time backfill of the same
   grants on existing objects. This platform converts on fresh clusters
   (amended 2026-10-06), so its services ship no backfill;
4. `USAGE` on the application schema for the runtime.

No platform Job applies object ACLs across services.

### Decision rules

| Rule | Required behavior |
|------|-------------------|
| **Ownership** | The service repository owns its authorization SQL |
| **Write path** | Only the migration Job, after `SET ROLE <svc>_owner`, changes object privileges |
| **Read path** | Runtime access comes only from these grants and defaults, never from ownership |
| **Boundary** | Homelab does not run a cross-service ACL Job; pgroles is not used as an authorization controller |
| **Failure behavior** | A migration that creates objects without the owner role fails review |
| **Compatibility** | A new privilege need is a migration in the service repo, reviewed with the code that needs it |

## Alternatives considered

| Option | Benefits | Costs / risks | Result |
|--------|----------|---------------|--------|
| **A — Service-owned authorization migrations** | Moves with the schema; no new engine | SQL in every service repo; cross-repo coordination at cutover | Selected |
| **B — Central platform authorization Job** | One policy surface | Homelab couples to every schema; duplicates migration ordering and rollback | Rejected |
| **C — Declarative policy controller (pgroles)** | Converges defaults and grants, polls for drift, recorded reviews | Cannot manage membership `SET`; `v1alpha1`; needs its own privileged executor; a second controller on roles CNPG manages | Rejected as controller; may return as a read-only reviewer under its own ADR |

### Why the selected option won

Only the service knows which objects its next migration creates, and default
privileges only work when set by the role that creates them. Keeping both in the
same migration makes Driver 1 true by construction.

### Why the closest alternative lost

pgroles would make the PG-05 global revoke and the default grants declarative,
but it cannot express the membership options ADR-086 must protect, and it brings
a privileged executor with exactly the credential problem RFC-0029 Phase 0 just
removed.

## Consequences

### Positive consequences

- New objects are usable by the runtime on their first deploy.
- PUBLIC can no longer execute newly created functions.
- An authorization change is reviewed next to the code that needs it.

### Negative consequences and accepted trade-offs

- Every converted service repo carries authorization SQL and must keep it
  correct.
- Drift in object ACLs (a hand-run `GRANT`) is not detected by this decision.
- A migration written without `SET ROLE` silently produces objects owned by the
  migrator; review and the catalog check in validation must catch it.

### Neutral consequences

- Service repos gain a migration at cutover; homelab gains no new component.

## Implementation obligations

| Obligation | Owner | Tracking | Completion signal |
|------------|-------|----------|-------------------|
| Authorization migration in `review-service` | review-service | canary PR | defaults present in the catalog |
| Decide and verify how the migration tool reaches `SET ROLE` | platform | decided 2026-10-06: `migratex.WithSetRole` (duynhlab/pkg) fed by `DB_MIGRATION_ROLE`; canary PR verifies | objects created by the Job are owned by `review_owner` |
| A reusable SQL snippet in the database runbooks | platform | [`authorization.md`](../../../databases/authorization.md#the-migration-contract) | second service copies it |
| `docs/api` | — | N/A | no route or RPC change |

## Validation and compliance

| Requirement | Verification |
|-------------|--------------|
| Defaults set by the owner | `pg_default_acl` has rows whose `defaclrole` is `<svc>_owner` |
| PUBLIC loses EXECUTE globally | a function created after cutover has no PUBLIC `EXECUTE` in its ACL |
| Backfill complete | every pre-existing table grants the runtime the same privileges as a new one |
| Objects created as owner | catalog query: no application object owned by `<svc>_migrator` |

## Revisit triggers

Re-open this decision when one or more of the following become true:

- More than a few services need identical authorization SQL and it drifts
  between repos.
- A real requirement for row-level security or definer functions appears.
- A policy controller can express membership `SET` options and runs without a
  standing privileged executor.

A review does not automatically reverse the decision. A changed decision
requires a new ADR that supersedes this one.

## References

- [RFC-0029](../../rfc/RFC-0029/)
- [RFC-0029 research](../../rfc/RFC-0029/research.md) — deep dive on ownership and default privileges; PG-03…06
- [ADR-084](../ADR-084-split-service-database-roles/), [ADR-086](../ADR-086-guard-membership-options/)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-10-06 | Proposed / Not started | Drafted from RFC-0029 |
| 2026-10-06 | Accepted / Not started | Accepted with RFC-0029 |
| 2026-10-06 | Accepted / Not started | **Amended** (owner, RFC-0029 Phase 1): the mechanism is `migratex.WithSetRole` in `duynhlab/pkg` (fails hard when `SET ROLE` is denied or the role is empty), chosen over a catalog `ALTER ROLE … SET role` default and over pgroles; no backfill on this platform (greenfield). The `0001_authorization` snippet is in [`authorization.md`](../../../databases/authorization.md) |
