# ADR-088: Apply Database Authorization from the Platform, Not from Service Code

> **Decision summary:** We will have the platform create the owner and migrator
> roles, make the migrator act as the owner at login, and apply every object
> privilege, because a service in a real organisation receives a user name and
> a password and nothing else. A role catalog Job (non-superuser, re-run every
> 10 minutes) owns the roles; in-database grants are owned per database by
> that Job or by pgroles. We accept a privileged platform executor and a
> 10-minute drift window in exchange for service repositories that know
> nothing about roles.

| Attribute | Value |
|-----------|-------|
| **Status** | Accepted |
| **Decision date** | 2026-10-12 |
| **Owners** | `platform` |
| **Deciders** | `owner (duynhlab)` |
| **Scope** | Role catalog and object privileges of every application database on CNPG |
| **Affected components** | `platform-db/authz/` (Job, CronJob, `db_authz`), CNPG bootstrap SQL, the guard queries, the domain ResourceSets, local-stack, service repositories (removal only) |
| **Related RFC** | [RFC-0029](../../rfc/RFC-0029/) |
| **Related research** | [research.md](../../rfc/RFC-0029/research.md) |
| **Supersedes** | [ADR-085](../ADR-085-service-migrations-own-authorization/) |
| **Superseded by** | — |
| **Implementation tracking** | RFC-0029: D1 (`review`, Job) · D2 (`user`, `shipping`, `notification`, pgroles) · product-db after |
| **Adoption** | Partial: `review` (D1, 2026-10-15), `user`, `shipping`, `notification` (D2) on `platform-db`; `product-db` next |

## Context

[ADR-085](../ADR-085-service-migrations-own-authorization/) put grants and
default privileges in each service's migrations and made the migration session
switch to the owner with `migratex.WithSetRole`. review-service `v2.5.0` shipped
it. Converting the next three services showed the cost: every service repo
carried role names, a `DB_MIGRATION_ROLE` variable, an authorization migration
and tests that create roles. In the organisations this platform imitates, the
database roles, their memberships and their grants belong to the platform team;
an application receives credentials.

ADR-085's main argument was also wrong: it held that only a migration running as
the owner can set the owner's default privileges. A member of the owner with
`INHERIT` sets them with `ALTER DEFAULT PRIVILEGES FOR ROLE <owner>`, and a
role-level `ALTER ROLE <migrator> SET role = <owner>` makes the migrator act as
the owner from login without any code (PG-09).

## Scope

### In scope

- Who creates `<svc>_owner` and `<svc>_migrator`, their attributes, the
  migrator's `role=` default and password, and their memberships.
- Who applies `CONNECT`, `USAGE`, the owner's default privileges, grants on
  existing objects and `REVOKE EXECUTE … FROM PUBLIC`.
- The executor those run as, and how drift is repaired or reported.

### Out of scope

- The three-role shape itself ([ADR-084](../ADR-084-split-service-database-roles/)).
- The membership guard's design ([ADR-086](../ADR-086-guard-membership-options/)); this ADR adds edges and two queries to it.
- Runtime password rotation (OpenBAO static roles, ADR-025).

## Decision drivers

- A service repository must not name a role, run `GRANT` or `SET ROLE`.
- Every object has exactly one controller; two reconcilers on one object fight.
- The executor is not a superuser (CNPG superuser access stays disabled).
- Services are added after bootstrap: nothing may depend on `postInitSQL` for a
  service.
- Drift is repaired where possible and reported where not.

## Decision

1. **Executor.** `authz_admin` (NOLOGIN, `CREATEROLE`, `INHERIT`) is created once
   by the cluster bootstrap SQL and is not a CNPG `DatabaseRole`. `db_authz` is a
   CNPG `DatabaseRole` (LOGIN, `inRoles: [authz_admin]`, password random per
   cluster in OpenBAO). Work runs as `db_authz` with `role=authz_admin` and
   `createrole_self_grant=set,inherit` in the session options.
2. **Role catalog.** A Job (on change) and a CronJob (every 10 minutes) in
   `platform-db/authz/` create `<svc>_owner` and `<svc>_migrator`, set
   `ALTER ROLE <svc>_migrator SET role = <svc>_owner`, grant
   `<svc>_owner TO <svc>_migrator WITH INHERIT FALSE, SET TRUE, ADMIN FALSE`, set
   the migrator's password from its Secret, revoke every undeclared membership,
   and fail the run when the result still differs.
3. **In-database grants.** Exactly one owner per database: the same Job
   (`GRANT_SERVICES`, review) or a pgroles `PostgresPolicy` in `adopt` mode (the
   other services, from D2). Both apply the same statements, except that a
   pgroles table wildcard cannot leave out `schema_migrations` (PGR-10).
4. **CNPG** keeps the runtime login and password, the `Database`
   (`owner: <svc>_owner`), `pg_hba`, and `db_authz`.
5. **Service repositories** call `migratex.Run(fsys, dir, dsn)` with no role
   option and ship no authorization SQL.

### Decision rules

- A role, membership or grant is declared in exactly one of: CNPG, the catalog
  Job, a pgroles policy.
- pgroles never owns a role (only in-database grants): with a non-superuser
  executor its `additive` mode repairs no attribute drift, and `adopt` revokes
  the executor's own creator memberships (PGR-04, PGR-08).
- `db_authz.inRoles` is `[authz_admin]` and never grows.
- A new service is one PR: runtime `DatabaseRole`, `Database`, Secrets, `pg_hba`
  lines, its name in `ROLE_SERVICES` (and `GRANT_SERVICES` or a policy), the
  guard rows.

## Alternatives considered

| Option | Outcome |
|---|---|
| Keep ADR-085 (service migrations + `WithSetRole`) | Rejected: role knowledge in every service repo |
| `postInitSQL` for the role catalog | Rejected: runs once at bootstrap; a service added later needs manual SQL |
| pgroles for roles and grants | Rejected for roles (PGR-01, -04, -06, -08); kept for in-database grants |
| CNPG `DatabaseRole` for owner and migrator, SQL only for `role=` | Rejected: CNPG cannot set `rolconfig`, and the SQL executor would need `ADMIN` on roles it did not create |
| One executor role in CNPG listing every owner in `inRoles` | Rejected: CNPG creates it with `CREATE ROLE … IN ROLE`, which deadlocks a new cluster (CNPG-10); without them CNPG revokes its memberships (CNPG-08) |
| Superuser executor | Rejected: standing superuser credential |

### Why the selected option won

A Job is plain SQL that controls every option PostgreSQL 18 exposes (including
`SET FALSE`, which pgroles cannot express) and fails loudly; the CronJob turns
it into a reconciler. pgroles adds self-healing and plan review where it is
reliable: inside one database.

### Why the closest alternative lost

pgroles for everything was the owner's first choice. The lab showed a
non-superuser executor cannot let pgroles own roles safely: in `adopt` the plan
revoked the executor's own `ADMIN` on every role it created, and declaring that
membership fails when the role is created in the same plan.

## Consequences

### Positive consequences

- Service repositories carry no role names, no grants, no role variables.
- Owner, migrator and grants are reconciled after bootstrap; adding a service
  needs no manual SQL.
- Drift is repaired within 10 minutes, or the Job fails and `KubeJobFailed`
  fires.

### Negative consequences and accepted trade-offs

- `authz_admin` holds `ADMIN` on every catalog role and inherits every owner:
  whoever holds `db_authz`'s password can act as any service owner. Mitigated by
  a random per-cluster password, `pg_hba` lines only for `postgres` and the
  managed databases, `connectionLimit: 10` (the Job plus one pgroles pool per
  policy), and the guard on its edge.
- Up to 10 minutes of drift.
- The platform knows one name from the migration tool: the Job creates
  golang-migrate's `schema_migrations` as the owner before the first migrate,
  because the owner's default privileges would otherwise grant it to the
  runtime until the next run.
- In a pgroles-owned database the runtime holds CRUD on `schema_migrations`
  (owner decision, 2026-10-15): pgroles 0.13.0 rejects a table wildcard plus
  `ensure: absent` on one table (PGR-10), and without the wildcard `adopt`
  revokes the runtime's grants on every table a migration adds. The Job-owned
  databases keep the runtime off the table.
- `authz_admin` is bootstrap SQL; a cluster that predates it needs the line run
  once by hand.
- Two mechanisms (Job and pgroles) for in-database grants, kept deliberately to
  compare them.

### Neutral consequences

- `migratex.WithSetRole` is removed (`migratex/v0.39.0`); review-service drops
  `000004_authorization` (greenfield).

## Implementation obligations

- `authorization.md` documents the split, the executor and the evidence.
- Every converted service adds its migrator edge to `pg_role_membership`, its
  migrator to `pg_role_config`, its database to `pg_default_privileges` (Job
  path), the `absent()` selectors and `smoke.js`.
- The Kind gate runs K3.4, K3.7–K3.10 on a fresh cluster before a service tag.

## Validation and compliance

- K3.8/K3.9 (`scripts/db-authz-check.sh`) as the real logins; K3.10 Job and
  CronJob succeeded; K3.7 guards reporting and zero drift.
- Drift drill: change `role=`, a default ACL and a grant by hand; the next
  CronJob run restores them; a `postgres`-granted membership fails the run.

## Revisit triggers

- pgroles models the executor's creator memberships (then it can own roles).
- CNPG gains `rolconfig` or membership options on `DatabaseRole`.
- A production target where the platform team uses a different reconciler.

## Evidence

Measured 2026-10-12 on Kind `platform-db` (CNPG 1.30.1, PostgreSQL 18.6,
pgroles 0.13.0, synthetic `lab*` roles), except CNPG-10 (source), JOB-02
(2026-10-14, `postgres:18-alpine` with the review-service binary) and
JOB-03/JOB-04 (2026-10-15, the D1 gate):

| Row | Result |
|---|---|
| PGR-01 | Declaring `admin: true` for the executor on a role created in the same plan fails ("ADMIN option cannot be granted back to your own grantor"); the plan rolls back whole |
| PGR-02 | `createrole_self_grant=set,inherit` in the connection options gives the executor INHERIT on roles it creates; no `ALTER ROLE` on the executor needed |
| PGR-03 | A CNPG `Database` whose owner does not exist yet retries and is created once the owner appears |
| PGR-04 | `adopt` plans to revoke every undeclared membership of the executor, including its implicit ADMIN |
| PGR-05 | `REVOKE EXECUTE … FROM PUBLIC` plans only at default-privilege scope `global` |
| PGR-06 | One policy may own a role per database target, external roles included |
| PGR-07 | Per-database policy in `adopt`: a GRANT, a REVOKE and a default-ACL change were each reverted within one interval |
| PGR-08 | `additive`: `RESET role`, `INHERIT`, a stray membership and a new password were not repaired and reported no drift |
| PGR-09 | A drifted password is not re-applied (only on a Secret change) |
| PGR-10 | 2026-10-15, pgroles CLI 0.13.0 against `postgres:18`: a `"*"` table grant plus `ensure: absent` for the same role on `schema_migrations` fails validation ("declare privilege SELECT as present for one object selector and absent for another — grants apply before revokes, so the plan could never converge") |
| CNPG-08 | A `DatabaseRole` without `inRoles` makes CNPG revoke the role's other memberships; with dependants it fails and blocks every later change to the role |
| CNPG-09 | Listing the memberships in `inRoles` stops the revoke |
| CNPG-10 | CNPG creates a role with `CREATE ROLE … IN ROLE <inRoles>` (`internal/management/controller/roles/postgres.go`, v1.30.1) |
| JOB-01 | Job SQL for roles and grants: correct, idempotent, controls `SET` |
| JOB-02 | `apply.sh` with `authz_admin`/`db_authz`: review migrated and seeded as `review_migrator` with no role variable; every object owned by `review_owner`; seven drifts restored; a `postgres`-granted membership fails the run |
| JOB-03 | Fresh Kind, 2026-10-15: the catalog, ACLs and default ACLs above in [`authorization.md`](../../../databases/authorization.md#evidence); K3.4 99/99, K3.8–K3.9 12/12, K3.7 5/5, `make e2e GATE=kind` green; four in-reach drifts repaired by one run with their guards at 1 then 0; a `postgres`-granted membership failed the run and fired `KubeJobFailed` |
| JOB-04 | First bring-up: migrate created `schema_migrations` four seconds after a CronJob run and the runtime held it with `INSERT`/`DELETE`; the Job now creates the table first (fresh `postgres:18` + review `2.6.0`: runtime denied before and after migrate) |

## References

- [RFC-0029](../../rfc/RFC-0029/), [research](../../rfc/RFC-0029/research.md)
- [`authorization.md`](../../../databases/authorization.md)
- [ADR-084](../ADR-084-split-service-database-roles/), [ADR-085](../ADR-085-service-migrations-own-authorization/), [ADR-086](../ADR-086-guard-membership-options/)

## History

| Date | Status / adoption | Change |
|------|-------------------|--------|
| 2026-10-12 | Accepted / Not started | Owner paused RFC-0029 Phase 3 (2026-10-09), chose the platform-owned model, then Job for roles and pgroles for in-database grants after the lab |
| 2026-10-14 | Accepted / Not started | D1 opened: executor split into `authz_admin` + `db_authz` (CNPG-10); review on the catalog Job; pkg `migratex/v0.39.0`, review-service `#208` |
| 2026-10-15 | Accepted / Partial | D1 merged (#1267, review 2.6.0). D2: user, shipping, notification on the catalog Job + pgroles policies; neutral `platform` bootstrap database; `notification_runtime` rotated by OpenBAO; PGR-10 accepted (runtime holds `schema_migrations` in pgroles-owned databases) |
