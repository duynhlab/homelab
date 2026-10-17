# Database Authorization (owner / migrator / runtime)

Every service database has three roles: one owns the objects, one changes the
schema, and one serves traffic. The platform creates them and decides what each
may do; a service only receives a user name and a password. A compromised
service can read and write its own rows; it cannot change, drop or take
ownership of its own schema.

| | |
|---|---|
| **Status** | **Deployed** on `platform-db` for `review`, `user`, `shipping` and `notification`, and on `product-db` for every product-db service (RFC-0029 product-db waves 1 and 2). Wave 2 adds `cart`, `order`, `checkout` and `payment`, with `order-worker` and `checkout-worker` on their service's runtime login: every service is on the split |
| **Design records** | [RFC-0029](../proposals/rfc/RFC-0029/) · [ADR-084](../proposals/adr/ADR-084-split-service-database-roles/) (three roles) · [ADR-088](../proposals/adr/ADR-088-platform-owns-database-authorization/) (the platform owns authorization; supersedes ADR-085) · [ADR-086](../proposals/adr/ADR-086-guard-membership-options/) (guard) |
| **Roles per service** | `<svc>_owner` (NOLOGIN) · `<svc>_migrator` (LOGIN, NOINHERIT, `role=<svc>_owner`) · `<svc>_runtime` (LOGIN) |
| **Who applies what** | CNPG: runtime login, database, `pg_hba`, `db_authz` · role catalog Job + CronJob per cluster: owner, migrator, memberships, and (Job-owned services) in-database grants · pgroles: in-database grants for `user`, `shipping`, `notification` and all six product-db databases |
| **What a service knows** | `DB_USER` / `DB_PASSWORD` for `migrate`/`seed` and for serving. No role name, no `GRANT`, no `SET ROLE` |
| **Drift** | The CronJob re-applies every 10 minutes; `pg_role_membership`, `pg_role_config`, `pg_default_privileges` guards and their alerts; Kind gate rows |
| **Rollout model** | Greenfield: no legacy login, no compatibility window. Rollback is `git revert` + a fresh `make up` |

## Concept

PostgreSQL decides what a session may do from the role it is acting as. Before
this design, one role per service did everything: it logged in for traffic, ran
migrations and owned every table. Whoever held that password could `DROP TABLE`,
`ALTER` a column or change a grant, because the owner can always do that.

The split gives each job its own identity:

| Role | Logs in | Owns | Can do |
|---|---|---|---|
| `<svc>_owner` | never | the database, its schemas and every object | everything on its objects, but nobody holds a password for it |
| `<svc>_migrator` | yes, from the `migrate` init container and the seed | nothing | becomes the owner at login: the platform sets `ALTER ROLE <svc>_migrator SET role = <svc>_owner`, and the membership is `INHERIT FALSE, SET TRUE`. `RESET ROLE` returns to the owner, not to the login |
| `<svc>_runtime` | yes, from the service pods (through the pooler) | nothing | `SELECT/INSERT/UPDATE/DELETE` on tables and `USAGE/SELECT` on sequences, through the owner's default privileges |

Everything that is not "the service's own schema" is platform work. The service
repo creates tables and indexes in its migrations and nothing else:

| Job | Owner |
|---|---|
| Runtime login, its password, the `Database` (`owner: <svc>_owner`), `pg_hba` | CNPG (`DatabaseRole`, `Database`, `instance.yaml`) |
| Owner and migrator roles, the migrator's `role=`, the migrator → owner membership, the migrator's password | Role catalog Job + CronJob, one per cluster (`platform-db/authz/`, `product-db/authz/`; one copy of `apply.sh` and `roles.sql`) |
| In-database grants: `CONNECT`, `USAGE`, the owner's default privileges, grants on existing objects, `REVOKE EXECUTE … FROM PUBLIC` | Role catalog Job for `review`; a pgroles `PostgresPolicy` per database for `user`, `shipping`, `notification`, `product`, `inventory`, `cart`, `order`, `checkout`, `payment` |
| The executor those jobs run as | `authz_admin` (bootstrap SQL) reached by the `db_authz` login (CNPG) |

## Architecture

### Connection paths

This diagram answers which login reaches each cluster by which path. Only the
services' runtime traffic goes through a pooler: PgBouncer on `platform-db`,
PgDog on `product-db`. Everything that depends on the session's identity (the
migrator's `role=`, the authorization executors, the password rotator) and the
clients that need long-lived sessions connect to the primary directly; `pg_hba`
admits each login to its own databases only. A transaction pooler would hand
the migrator's server connection, and its `role=`, to other clients.

```mermaid
flowchart TB
    subgraph cluster["Kind cluster · homelab"]
        subgraph papps["platform-db services · user, shipping, notification, review"]
            ppod["service pods<br/>as &lt;svc&gt;_runtime"]:::service
            pmig["migrate init container + seed<br/>as &lt;svc&gt;_migrator<br/>role= applies at login"]:::worker
        end
        subgraph rapps["product-db services · product, inventory, cart, order, checkout, payment"]
            rpod["service pods + order/checkout workers<br/>as &lt;svc&gt;_runtime"]:::service
            rmig["migrate init container + seed<br/>as &lt;svc&gt;_migrator"]:::worker
        end
        pgr["pgroles operator · pgroles-system<br/>as db_authz → authz_admin"]:::platform
        bao["OpenBAO database engine<br/>as vault_rotator"]:::platform
        other["Temporal · Keycloak<br/>long-lived sessions (ADR-041)"]:::service
        subgraph plat["platform namespace"]
            pjob["authz Job + CronJob<br/>as db_authz → authz_admin"]:::platform
            pooler["platform-db-pooler-rw<br/>PgBouncer · transaction"]:::data
            prw[("platform-db primary · -rw :5432")]:::data
        end
        subgraph prod["product namespace"]
            rjob["authz Job + CronJob<br/>as db_authz → authz_admin"]:::platform
            pgdog["pgdog-product :6432<br/>PgDog · transaction"]:::data
            rrw[("product-db primary · -rw :5432")]:::data
        end
    end

    ppod -->|"pooled"| pooler -->|"same login"| prw
    pmig --> prw
    pjob --> prw
    bao --> prw
    other --> prw
    rpod -->|"pooled · payment over TLS, verify-full"| pgdog -->|"same login"| rrw
    rmig --> rrw
    rjob --> rrw
    pgr --> prw
    pgr --> rrw

    classDef service fill:#cffafe,color:#164e63,stroke:#0891b2;
    classDef worker fill:#fef3c7,color:#78350f,stroke:#d97706;
    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
```

PgDog lists every product-db service under its `<svc>_runtime` login; the
order and checkout workers use their service's runtime login. payment's
runtime reaches PgDog over client TLS (`sslmode=verify-full`;
[poolers](poolers.md#tls)), and `pg_hba` admits `payment_runtime` and
`payment_migrator` on `hostssl` lines only. The other services stay plaintext
to PgDog.

`product` is also `product-db`'s bootstrap database: `bootstrap.initdb` creates
it owned by a role named `product`. That role is bootstrap-only. Its
`DatabaseRole` keeps it `NOLOGIN`, `pg_hba` has no line for it, and the
`Database` object hands the database to `product_owner` (CNPG reassigns it once
the catalog Job has created the owner). `platform-db` instead bootstraps a
neutral `platform` database; product-db keeps its original names by decision
(owner, 2026-10-16).

### Who applies what

This diagram answers which component writes which part of the authorization,
where each credential comes from, and how drift is seen. It covers the
converted services on both clusters.

```mermaid
flowchart LR
    subgraph cluster["Kind cluster · homelab"]
        subgraph sec["credentials"]
            kv["OpenBAO KV · openbao<br/>runtime, migrator, db_authz"]:::platform
            dbe["OpenBAO database engine<br/>notification_runtime"]:::platform
            eso["External Secrets · external-secrets-system"]:::platform
            ks["Kubernetes Secrets<br/>cluster + service namespaces"]:::platform
        end
        subgraph writers["writers, one per object"]
            cnpg["CNPG operator · cloudnative-pg<br/>runtime DatabaseRole, db_authz,<br/>Database, pg_hba"]:::platform
            job["authz Job + CronJob, one per cluster<br/>owner, migrator, role=, memberships,<br/>review grants, schema_migrations"]:::platform
            pgr["pgroles operator<br/>grants of user, shipping, notification<br/>and the six product-db databases"]:::platform
        end
        cat[("platform-db + product-db catalogs<br/>roles · memberships · ACLs · default ACLs")]:::data
        subgraph obs["detection"]
            exp["CNPG exporter in each instance<br/>guard queries"]:::platform
            vm["VictoriaMetrics + vmalert · monitoring<br/>CNPG*Drift · KubeJobFailed"]:::platform
        end
    end

    kv --> eso
    dbe --> eso
    eso --> ks
    ks -->|"passwordSecret"| cnpg
    ks -->|"db_authz, migrator passwords"| job
    ks -->|"db_authz"| pgr
    cnpg --> cat
    job --> cat
    pgr --> cat
    dbe -->|"rotates every 720 h"| cat
    cat -->|"read by"| exp --> vm

    classDef platform fill:#ede9fe,color:#4c1d95,stroke:#7c3aed;
    classDef data fill:#dcfce7,color:#14532d,stroke:#16a34a;
```

Services read their two Secrets (runtime, migrator) and nothing else; they do
not appear here because they write no authorization.

## How it works in this platform

### Naming

| Thing | Convention | Example (`review` on `platform-db`) |
|---|---|---|
| Database | `<svc>` | `review` |
| Roles | `<svc>_owner`, `<svc>_migrator`, `<svc>_runtime` | `review_owner`, `review_migrator`, `review_runtime` |
| Runtime `DatabaseRole` | `<cluster>-role-<svc>-runtime` | `platform-db-role-review-runtime` |
| `Database` object | `<svc>-database`, `spec.owner: <svc>_owner` | `review-database` |
| Secrets (cluster and app namespace, same name) | `<cluster>-<svc>-runtime-secret`, `<cluster>-<svc>-migrator-secret`; the owner has none | `platform-db-review-migrator-secret` |
| OpenBAO KV | `secret/local/databases/<cluster>/<svc>-runtime`, `…/<svc>-migrator` | `secret/local/databases/platform-db/review-runtime` |
| `pg_hba` | `host <svc> <svc>_runtime …`, `host <svc> <svc>_migrator …`, `host <svc> db_authz …` (`hostssl` for payment's runtime and migrator). No line for the owner | — |
| Executor | `authz_admin` (NOLOGIN, CREATEROLE) and `db_authz` (LOGIN, member of `authz_admin`), one pair per CNPG cluster | KV `…/platform-db/db-authz` |

Names considered and not used:

| Name | Why not |
|---|---|
| `_app`, `_rw` | Ambiguous: `_rw` promises a `_ro` sibling that does not exist, and every role is "the app" |
| `_deploy` | Migrations also run in local-stack and in tests, not only at deploy |
| `_ddl` | The migrator also seeds data, which is not DDL |
| `_admin` | Suggests `ADMIN OPTION`, which this role must never have |
| keeping `<svc>` for runtime | A bare service name hides which of the three identities a log line, a connection or an alert refers to |

### The executor: `authz_admin` and `db_authz`

The role catalog runs as a non-superuser. Two roles make that work with CNPG:

- **`authz_admin`** (NOLOGIN, `CREATEROLE`, `INHERIT`) is created once by the
  cluster's bootstrap SQL and is **not** a CNPG `DatabaseRole`. It creates every
  catalog role, so PostgreSQL 16+ gives it `ADMIN` on each one, and the session
  setting `createrole_self_grant = 'set, inherit'` also gives it `SET` and
  `INHERIT`, which `ALTER DEFAULT PRIVILEGES FOR ROLE <svc>_owner` needs.
- **`db_authz`** is the login (a CNPG `DatabaseRole` with `inRoles:
  [authz_admin]`, password random per cluster in OpenBAO). The Job connects with
  `PGOPTIONS='-c role=authz_admin -c createrole_self_grant=set,inherit'`.

Why not one role: CNPG creates a `DatabaseRole` with `CREATE ROLE … IN ROLE
<inRoles>`, so listing the owners there deadlocks a new cluster (the executor
cannot be created before the owners it creates); and leaving them out makes
CNPG revoke the executor's memberships on every reconcile (lab CNPG-08).
`authz_admin` holds those memberships where CNPG never looks.

An existing cluster that predates this design runs the bootstrap line once:

```sql
CREATE ROLE authz_admin NOLOGIN CREATEROLE INHERIT;  -- as postgres, on the primary
```

### The role catalog Job

`platform-db/authz/` holds `apply.sh`, `roles.sql` and `grants.sql`, rendered
into a hashed ConfigMap. Two workloads run the same script:

| Workload | When | Why |
|---|---|---|
| `Job/platform-db-authz` | On every change to the SQL or the service lists (the ConfigMap hash changes; Flux recreates the Job) | A new service gets its roles without waiting |
| `CronJob/platform-db-authz` | Every 10 minutes | Undoes drift. A failed run fires `KubeJobFailed`; job TTL is 1 h so the alert resolves after a fix |

`ROLE_SERVICES` lists the services whose owner and migrator the catalog owns;
`GRANT_SERVICES` lists the services whose in-database grants it owns (the
others have a pgroles policy). Each cluster has its own Job and CronJob
(`platform-db-authz` in `platform`, `product-db-authz` in `product`) running the
same `apply.sh` and `roles.sql`; `PGHOST` picks the cluster. Today
`platform-db` runs `ROLE_SERVICES=review user shipping notification` with
`GRANT_SERVICES=review`, and `product-db` runs `ROLE_SERVICES=product
inventory cart order checkout payment` with no Job-owned grants. Per service, `roles.sql`:

1. creates `<svc>_owner` and `<svc>_migrator` if missing and restates
   `LOGIN`/`INHERIT`/`CREATEROLE`/`CONNECTION LIMIT` (`CREATEDB`, `REPLICATION`
   and `BYPASSRLS` default to false and only a superuser can change them);
2. `ALTER ROLE <svc>_migrator RESET ALL` then `SET role = '<svc>_owner'`;
3. `GRANT <svc>_owner TO <svc>_migrator WITH INHERIT FALSE, SET TRUE, ADMIN FALSE`
   (re-issuing it rewrites drifted options);
4. revokes every other membership of the two roles, except `authz_admin`'s
   creator edges, then **fails the run** if anything still differs: a revoke
   PostgreSQL skipped because another grantor (for example `postgres`) holds the
   edge is drift the executor may not repair, and a red Job is how it surfaces.

The migrator's password is set only when the migrator can no longer log in with
the Secret's value, so the verifier is not rewritten every 10 minutes.

`grants.sql`, per Job-owned database, as `authz_admin` inheriting the owner:

```sql
GRANT CONNECT ON DATABASE <svc> TO <svc>_runtime, <svc>_migrator;
GRANT USAGE ON SCHEMA public TO <svc>_runtime;
-- golang-migrate's bookkeeping table, created as the owner before the first
-- migrate (same DDL as migrate's CREATE TABLE IF NOT EXISTS, which adopts it).
SET ROLE <svc>_owner;
CREATE TABLE IF NOT EXISTS public.schema_migrations
  (version bigint NOT NULL PRIMARY KEY, dirty boolean NOT NULL);
RESET ROLE;
ALTER DEFAULT PRIVILEGES FOR ROLE <svc>_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <svc>_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE <svc>_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO <svc>_runtime;
-- Global, not IN SCHEMA: only a global entry cancels PUBLIC EXECUTE (PG-05).
ALTER DEFAULT PRIVILEGES FOR ROLE <svc>_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- then, for every table and sequence the owner already has: REVOKE ALL from
-- the runtime and grant exactly the set above, in one transaction;
-- schema_migrations gets nothing.
```

`schema_migrations` is created by the Job, not by the first migrate. The
owner's default privileges would otherwise hand it to the runtime with
`INSERT`/`DELETE` until the next CronJob run: on the first Kind gate
(2026-10-15) migrate ran at 03:10:04, four seconds after a CronJob run
finished, and K3.8 read the table as `review_runtime`.

### The pgroles policies

`platform-db/authz/policies/<svc>.yaml` owns the in-database grants for `user`,
`shipping` and `notification`: one `PostgresPolicy` per database, `mode: apply`,
`reconciliation_mode: adopt`, every 5 minutes. It connects as `db_authz` with
`setRole: authz_admin`, declares the three roles `external` (pgroles never
creates or alters a role, ADR-088), and states the same set as `grants.sql`:
`CONNECT` for the runtime and migrator, `USAGE` on `public`, the owner's table
and sequence defaults, the global `REVOKE EXECUTE` from `PUBLIC`, and `"*"`
grants on the tables and sequences that exist.

One difference is accepted by decision (owner, 2026-10-15): **the runtime of a
pgroles-owned database holds CRUD on `schema_migrations`**. pgroles 0.13.0
rejects a table wildcard combined with `ensure: absent` on one table ("declare
privilege SELECT as present for one object selector and absent for another …
could never converge", PGR-10), and without the wildcard `adopt` revokes the
runtime's grants on every table a migration adds. The Job-owned `review` keeps
the stricter shape. K3.8 encodes both (`scripts/db-authz-check.sh`).

### The notification runtime and OpenBAO

OpenBAO's database engine rotates `notification_runtime`'s password (static role
`notification-runtime`, ADR-025) through `vault_rotator`, which holds `ADMIN` on
it (`t/f/f`, guarded by ADR-086). Both roles and that edge are bootstrap SQL in
`instance.yaml`, because CNPG cannot express the edge's options; the runtime's
`DatabaseRole` has no `passwordSecret`, and ESO reads
`database/static-creds/notification-runtime` every minute.

### The bootstrap database

`initdb` creates a neutral `platform` database owned by a `platform` role that
nothing uses (no `pg_hba` line). Every service database is a `Database` CR owned
by `<svc>_owner`; an initdb-created owner would be made by the superuser, which
`authz_admin` cannot administer.

### Wiring in the domain ResourceSets

| Container | Host | `DB_USER` / `DB_PASSWORD` |
|---|---|---|
| service | pooler (`db_host`) | `username` / `password` of `inputs.db_runtime_secret` |
| `migrate` | primary `-rw` (`db_migration_host`), never a pooler | `username` / `password` of `inputs.db_migrator_secret` |

That is all a service receives. `role=` is applied by PostgreSQL at login, so
the migrator must reach the primary directly: a transaction-mode pooler would
hand its server connection to other clients. Seeding follows the migration:
`scripts/kind-seed.sh` and the local-stack `<svc>-seed` service use the
migrator's credentials.

Poolers carry only `<svc>_runtime`.

### The migration contract (service repos)

- Migrations create schema objects. They never `GRANT`, `ALTER DEFAULT
  PRIVILEGES`, `SET ROLE` or name a role; `migratex.Run(fsys, dir, dsn)` takes no
  role option (pkg `migratex/v0.39.0`).
- A function the runtime must call is the exception that needs the platform: add
  its `GRANT EXECUTE` to the service's grants (Job or pgroles policy), because
  PUBLIC has no `EXECUTE` by default.

### Detection and gates

| Signal | Where | What it proves |
|---|---|---|
| `CNPGRoleMembershipDrift` (critical) | [runbook](../observability/runbooks/postgresql/CNPGRoleMembershipDrift.md) | Every guarded edge (`vault_rotator → notification_runtime`, each `<svc>_migrator → <svc>_owner`, `db_authz → authz_admin`) has its specified options |
| `CNPGRoleConfigDrift` (critical, 15 m) | [runbook](../observability/runbooks/postgresql/CNPGRoleConfigDrift.md) | The migrator's `rolconfig` is exactly `role=<svc>_owner` |
| `CNPGDefaultPrivilegesDrift` (critical, 15 m) | [runbook](../observability/runbooks/postgresql/CNPGDefaultPrivilegesDrift.md) | The owner's table, sequence and function defaults are exactly the declared set |
| `KubeJobFailed` | the catalog CronJob | The last run could not converge (drift outside the executor's reach, a missing role, a missing database) |
| Kind gate K3.4 | `scripts/db-isolation-sweep.sh` | Each login reaches only its own database; only `db_authz` reaches `postgres` |
| Kind gate K3.7 | `smoke.js` against VictoriaMetrics | Every guard reports and nothing has drifted |
| Kind gate K3.8 | `scripts/db-authz-check.sh`, as `<svc>_runtime` | The runtime cannot `CREATE`, `ALTER`, `DROP` or become the owner; `schema_migrations` is refused for Job-owned databases and readable for pgroles-owned ones (PGR-10) |
| Kind gate K3.9 | `scripts/db-authz-check.sh`, as `<svc>_migrator` | The migrator is the owner at login and after `RESET ROLE`, its `rolconfig` is `role=<svc>_owner`, and its membership is `f/f/t` |
| Kind gate K3.10 | `kubectl` | The catalog Job completed and the CronJob's last run succeeded |

A PR that converts a service adds its migrator edge, role config and database to
the three guard queries, the `absent()` selectors and `smoke.js` in the same PR.

### local-stack

Compose plays the platform: `local-stack/postgres/init.sql` creates the three
roles and the migrator's `role=` for all ten services; each `<svc>-migrate` and `<svc>-seed` connects as the migrator
with no role variable, and a `<svc>-authz` one-shot service runs **the
cluster's own `grants.sql`** after the migration, standing in for pgroles for
the pgroles-owned services. Two deliberate differences stay: local-stack
revokes `CONNECT` on every database from `PUBLIC`, because it has no other
connection fence (the cluster fences with `pg_hba`, ADR-015); and every
local-stack runtime is refused `schema_migrations`, where the cluster's
pgroles-owned ones hold it (PGR-10).

### Rollback and existing data

There is no compatibility window and no legacy login. Rolling back is
`git revert` plus a fresh `make up`. A cluster that already holds data would
need a one-time, privileged ownership transfer (`REASSIGN OWNED` or
`ALTER … OWNER TO <svc>_owner`) run by an operator; that path is described for
reference only and is **not exercised here**.

## Evidence

**Runtime test, 2026-10-14**, `postgres:18-alpine` container with the bootstrap
roles CNPG would create (`authz_admin`, `db_authz IN ROLE authz_admin`,
`review_runtime`), `apply.sh` run as `db_authz`, and the real review-service
binary (`d14e06f`, `migratex/v0.39.0`) running `migrate` and `seed` as
`review_migrator` with no role variable:

```text
     role       |     member      |   grantor   | adm | inh | set
-----------------+-----------------+-------------+-----+-----+-----
 authz_admin     | db_authz        | postgres    | f   | t   | t
 review_migrator | authz_admin     | authz_admin | f   | t   | t
 review_migrator | authz_admin     | postgres    | t   | f   | f
 review_owner    | authz_admin     | authz_admin | f   | t   | t
 review_owner    | authz_admin     | postgres    | t   | f   | f
 review_owner    | review_migrator | authz_admin | f   | f   | t

 review_migrator | rolcanlogin t | rolinherit f | {role=review_owner}

 S | public | {review_runtime=rU/review_owner}
 f | -      | {review_owner=X/review_owner}
 r | public | {review_runtime=arwd/review_owner}

 tablename         | tableowner          -- after `migrate` as review_migrator
 reviews           | review_owner
 schema_migrations | review_owner

review_runtime: SELECT count(*) FROM reviews → 12 · CREATE TABLE → permission
denied for schema public · ALTER TABLE reviews → must be owner of table reviews
review_migrator: SELECT current_user → review_owner
```

Drift drill, same container: `RESET role`, `INHERIT`, a new migrator password,
the edge re-granted `INHERIT TRUE`, a removed default `DELETE`, a revoked
`INSERT` and an extra `TRUNCATE` were all restored by the next run; runtime
access to `schema_migrations` was revoked by it. A membership granted by
`postgres` (`GRANT review_owner TO review_runtime`) made the run exit 1 with
`permission denied to revoke privileges granted by role "postgres"`, and the
other steps still ran.

**Kind, fresh bring-up** (2026-10-15, Kubernetes 1.35.8, CNPG 1.30.1,
PostgreSQL 18.6, review `2.6.0`, branch commit `eceab9dd`, DR replica off).
Catalog read as `postgres` on the primary after the Job, the first CronJob run
and review's migrate:

```text
 rolname         | login | inherit | createrole | super | connlimit | rolconfig
 authz_admin     | f     | t       | t          | f     |        -1 |
 db_authz        | t     | t       | f          | f     |         4 |
 review_migrator | t     | f       | f          | f     |        -1 | {role=review_owner}
 review_owner    | f     | t       | f          | f     |        -1 |
 review_runtime  | t     | t       | f          | f     |        -1 |

 role            | member          | grantor     | inh | set | adm
 authz_admin     | db_authz        | postgres    | t   | t   | f
 review_migrator | authz_admin     | authz_admin | t   | t   | f
 review_migrator | authz_admin     | postgres    | f   | f   | t
 review_owner    | authz_admin     | authz_admin | t   | t   | f
 review_owner    | authz_admin     | postgres    | f   | f   | t
 review_owner    | review_migrator | authz_admin | f   | t   | f

 relname           | kind | owner        | relacl
 reviews           | r    | review_owner | {review_owner=arwdDxtm/review_owner,review_runtime=arwd/review_owner}
 reviews_id_seq    | S    | review_owner | {review_owner=rwU/review_owner,review_runtime=rU/review_owner}
 schema_migrations | r    | review_owner | {review_owner=arwdDxtm/review_owner}

 default ACL (review_owner) | S public {review_runtime=rU/review_owner}
                            | f -      {review_owner=X/review_owner}
                            | r public {review_runtime=arwd/review_owner}

 pg_hba_file_rules | 25 host {postgres} {db_authz} scram-sha-256
                   | 26 host {review}   {db_authz} scram-sha-256
```

`schema_migrations` has a lower oid (16667) than `reviews_id_seq` (20553): the
Job created it ten minutes before review's migrate. Gate output on the same
cluster: `db-authz-check.sh` 12/12 PASS, `db-isolation-sweep.sh` 99/99 PASS
(`db_authz` allowed only to `postgres` and `review`), `make e2e GATE=kind`
saga 9/9, smoke 55/55 (K3.7 5/5), staff 59/59, operator 26/26.

Drift drill, same cluster, as `postgres`:

| Injected | Guard / alert | Repair |
|---|---|---|
| `GRANT TRUNCATE ON reviews TO review_runtime` | — (not a default ACL) | revoked by the next run |
| `REVOKE DELETE` from the owner's table defaults | `cnpg_pg_default_privileges_drift` 1, `CNPGDefaultPrivilegesDrift` pending | restored |
| `ALTER ROLE review_migrator RESET role` | `cnpg_pg_role_config_drift` 1, `CNPGRoleConfigDrift` pending | `{role=review_owner}` restored |
| migrator → owner re-granted `t/t/f` by `authz_admin` | `cnpg_pg_role_membership_drift` 1, `CNPGRoleMembershipDrift` pending | back to `f/t/f` |
| `GRANT review_owner TO review_runtime` (grantor `postgres`) | the run and the next scheduled run exit 1 (`permission denied to revoke privileges granted by role "postgres"`), grants still applied; `KubeJobFailed` firing after 5 min | revoked by hand, next run Complete |

All three guard metrics read 1 within a minute of the injection and 0 within
a minute of the repair run; `db-authz-check.sh` passed again afterwards.

The first bring-up of this gate failed K3.8: review's migrate ran four
seconds after a CronJob run and the owner's defaults handed the new
`schema_migrations` to the runtime. That is why the Job now creates the table.

**Kind, fresh bring-up for D2** (2026-10-15, same versions, branch commit
`bb3a3010`, DR replica off). `user`, `shipping` and `notification` on the Job
for roles and pgroles for grants; catalog read as `postgres` after migrate and
seed:

```text
 rolname               | login | inherit | createrole | connlimit | rolconfig
 db_authz              | t     | t       | f          |        10 |
 notification_migrator | t     | f       | f          |        -1 | {role=notification_owner}
 notification_owner    | f     | t       | f          |        -1 |
 notification_runtime  | t     | t       | f          |        -1 |
 vault_rotator         | t     | f       | t          |        -1 |
 (user_* and shipping_* match notification_*)

 role                  | member                | grantor     | inh | set | adm
 notification_owner    | notification_migrator | authz_admin | f   | t   | f
 notification_runtime  | vault_rotator         | postgres    | f   | f   | t
 (plus authz_admin's t/t/f and f/f/t edges on every owner and migrator)

 datname      | owner              | datacl
 platform     | platform           |
 notification | notification_owner | {=Tc/…,notification_owner=CTc/…,notification_migrator=c/…,notification_runtime=c/…}

 relname              | owner              | relacl
 notifications        | notification_owner | {notification_runtime=arwd/…,notification_owner=arwdDxtm/…}
 notifications_id_seq | notification_owner | {notification_runtime=rU/…,notification_owner=rwU/…}
 schema_migrations    | notification_owner | {notification_runtime=arwd/…,notification_owner=arwdDxtm/…}

 default ACL (notification_owner) | S public {notification_runtime=rU/notification_owner}
                                  | f -      {notification_owner=X/notification_owner}
                                  | r public {notification_runtime=arwd/notification_owner}
```

The runtime's CRUD on `schema_migrations` is the accepted PGR-10 gap. OpenBAO's
`openbao-db-config` Job wrote static role `notification-runtime`, which set the
runtime's password through `vault_rotator`; notification served on it. Gate
output: `db-authz-check.sh` 48/48, `db-isolation-sweep.sh` platform-db 105/105
and product-db 36/36, three `PostgresPolicy` Ready with no drift,
`authz applied: roles [review user shipping notification] grants [review]`,
`make e2e GATE=kind` green.

Drift drill, same cluster, as `postgres`:

| Injected | Guard / alert | Repair |
|---|---|---|
| `REVOKE SELECT ON user_profiles FROM user_runtime` | — | pgroles, 16 s later |
| `GRANT TRUNCATE ON shipments TO shipping_runtime` | — | pgroles, within one 5 min interval |
| `REVOKE DELETE` from `shipping_owner`'s table defaults | `cnpg_pg_default_privileges_drift` 1, `CNPGDefaultPrivilegesDrift` pending | pgroles, same reconcile; guard 0 half a minute later |
| `ALTER ROLE shipping_migrator RESET role` | `cnpg_pg_role_config_drift` 1, `CNPGRoleConfigDrift` pending | the 07:10 CronJob run |
| `GRANT shipping_owner TO shipping_runtime` (grantor `postgres`) | runs exit 1 on `roles/shipping` only (`permission denied to revoke privileges granted by role "postgres"`), the other services still applied; `KubeJobFailed` firing after 5 min | revoked by hand, next run Complete |

## Operations

### Re-run the catalog now

```bash
kubectl -n platform create job --from=cronjob/platform-db-authz authz-manual-$(date +%s)
kubectl -n platform logs -f job/authz-manual-<suffix>
```

### Effective access for one role

Run on the primary as `postgres`:

```sql
-- Who owns what in this database
SELECT n.nspname, c.relname, c.relkind, pg_get_userbyid(c.relowner) AS owner
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND c.relkind IN ('r','S','v','m','f','p')
 ORDER BY owner, 1, 2;

-- What the runtime role can do on each table
SELECT c.relname,
       has_table_privilege('<svc>_runtime', c.oid, 'SELECT') AS sel,
       has_table_privilege('<svc>_runtime', c.oid, 'INSERT') AS ins,
       has_table_privilege('<svc>_runtime', c.oid, 'UPDATE') AS upd,
       has_table_privilege('<svc>_runtime', c.oid, 'DELETE') AS del
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r';

-- Default privileges and the migrator's session defaults
SELECT pg_get_userbyid(defaclrole) AS owner, defaclnamespace::regnamespace AS schema,
       defaclobjtype, defaclacl
  FROM pg_default_acl;
SELECT rolname, rolinherit, rolconfig FROM pg_roles WHERE rolname LIKE '%\_migrator';

-- Membership options, every grantor (the guard reads the same catalog)
SELECT pg_get_userbyid(member) AS member, pg_get_userbyid(roleid) AS parent,
       pg_get_userbyid(grantor) AS grantor, admin_option, inherit_option, set_option
  FROM pg_auth_members
 WHERE pg_get_userbyid(roleid) ~ '_(owner|migrator)$' OR pg_get_userbyid(roleid) = 'authz_admin';
```

Expected for a converted service: every object owned by `<svc>_owner`, except
the views extensions install (`pg_stat_statements`), which CNPG creates as
`postgres`; the runtime has the four table rights and nothing else;
`pg_default_acl` has the owner's three rows; the migrator is `rolinherit f` with
`{role=<svc>_owner}`; `<svc>_migrator → <svc>_owner` is `f / f / t`; the only
other members of the owner and migrator are `authz_admin`'s creator edges.

### The lab

`scripts/pg-authz-lab/run.sh` re-runs the experiments this design rests on.
Run it after every PostgreSQL major and every CNPG minor or major upgrade, and
before changing a convention on this page.

```bash
scripts/pg-authz-lab/run.sh pg     # throwaway postgres:18 container, no cluster
scripts/pg-authz-lab/run.sh cnpg   # Kind platform-db; lab_* objects only, removed afterwards
```

| Experiment | Proves | Mode |
|---|---|---|
| PG-01 | Each missing layer (database, schema, table, sequence) refuses at that layer | pg |
| PG-02 | `INHERIT`, `SET` and `ADMIN` behave as the catalog says | pg |
| PG-03 | The owner's default privileges reach objects created after `SET ROLE`; runtime gets CRUD only | pg |
| PG-04 | A NOINHERIT migrator that skips `SET ROLE` creates nothing | pg |
| PG-05 | Only the **global** `REVOKE EXECUTE … FROM PUBLIC` default works | pg |
| PG-06 | Defaults do not reach existing objects; a backfill does (reference only here) | pg |
| PG-07 | RLS `USING` / `WITH CHECK`, owner bypass, `FORCE` (Phase 4 material) | pg |
| PG-08 | A `SECURITY DEFINER` function without a fixed `search_path` can be hijacked | pg |
| CNPG-01 | Adoption resets attributes the spec leaves out | cnpg |
| CNPG-02 | A Secret change reaches the role's password | cnpg |
| CNPG-03 | `spec.name` is immutable | cnpg |
| CNPG-04 | CNPG ignores membership options and recreates an edge with defaults | cnpg |
| CNPG-05 | `retain` keeps the role; `delete` waits while the role owns objects | cnpg |
| CNPG-06 | Manual drift survives until a spec change triggers a reconcile | cnpg |
| CNPG-07 | With `inherit: false` on the member, CNPG creates and recreates the owner edge as `f/f/t` | cnpg |

The ADR-088 lab (2026-10-12, Kind `platform-db`, CNPG 1.30.1, PostgreSQL 18.6,
pgroles 0.13.0) added the rows that chose the executor shape and the
Job / pgroles split; they are recorded in
[ADR-088](../proposals/adr/ADR-088-platform-owns-database-authorization/#evidence)
and were run by hand, not by `run.sh`.

The `pg` mode switches identity with `SET SESSION AUTHORIZATION`, which checks
privileges exactly as a login would but not authentication or `pg_hba`; those
are the Kind gate's job (K3.4, K3.8, K3.9), which connects as the real logins.
PG-04 still holds for a migrator without `role=`; the platform now sets it.
