# Runbook: Add a Service Database on product-db

Give a new service its own database, roles, and credentials on the shared
`product-db` cluster — a service triplet, client/pooler registrations, and an
HBA allow rule in `instance.yaml` before its terminal reject.

| | |
|---|---|
| **Pattern** | Per-service triplet ([ADR-013](../../proposals/adr/ADR-013-per-service-db-triplet/)) on the owner / migrator / runtime split ([ADR-084](../../proposals/adr/ADR-084-split-service-database-roles/), [ADR-088](../../proposals/adr/ADR-088-platform-owns-database-authorization/)) |
| **Time** | ~15 minutes + one PR |
| **Reference service** | `kubernetes/infra/configs/databases/clusters/product-db/services/cart.yaml` |
| **Concepts** | [012 — Declarative Role & Database Management](../declarative-role-management.md) |
| **Three-role services** | Every service on both clusters (RFC-0029) — see [Three-role service](#three-role-service) |

## Steps

`<svc>` is the new service name throughout. Every product-db service uses the
owner / migrator / runtime split (RFC-0029), so a new one follows the same
shape as `cart` or `inventory`:

1. **Roles, Secrets, Database, catalog, guards, gates** — follow
   [Three-role service](#three-role-service) below with `<cluster>` =
   `product-db`: copy `services/cart.yaml` and `authz/policies/cart.yaml`;
   the catalog Job and CronJob are `product-db-authz` in namespace `product`.

2. **Pooler entry** — in `clusters/product-db/poolers/helmrelease.yaml`:
   - **Append** to `values.databases` and `values.users` (`<svc>_runtime` +
     database only, no password). The migrator never goes through PgDog.
   - **Append** a `valuesFrom` entry pointing at
     `product-db-<svc>-runtime-secret` with
     `targetPath: "users[<N>].password"` where `<N>` is the new **last**
     index. Indices are positional — always append at the end, never insert
     mid-list ([ADR-014](../../proposals/adr/ADR-014-pooler-credentials-valuesfrom/)).
   - A service that requires TLS to its database connects to PgDog with
     `sslmode=require` (PgDog's client certificate,
     [poolers](../poolers.md#tls)) and gets `hostssl` lines in step 3, like
     payment.

3. **pg_hba (connection isolation is live — RFC-0012 P4):** add the service's
   runtime, migrator and `db_authz` allow rules in `instance.yaml` above the
   trailing reject — the one exception to "never touch instance.yaml",
   because HBA is cluster infrastructure, not a service definition.

4. **Validate and ship** — `make validate`, PR, merge. Flux converges:
   ESO renders the Secrets → the catalog Job creates the owner and migrator →
   `DatabaseRole` creates the runtime → `Database` creates the database owned
   by `<svc>_owner` → pgroles applies the grants.

5. **Verify:**

   ```bash
   kubectl get databaserole,database,postgrespolicy -n product | grep <svc>   # applied / Ready
   kubectl -n product logs job/product-db-authz | tail -1                    # authz applied
   ./scripts/db-authz-check.sh <svc>
   ```

## Three-role service

The platform creates the owner and migrator and applies the grants; the service
repo gets two credentials. One PR, no manual SQL ([Database
authorization](../authorization.md)):

`<cluster>` is `platform-db` or `product-db`.

1. **OpenBAO:** seed `secret/local/databases/<cluster>/<svc>-runtime` and
   `…/<svc>-migrator` (`username` = `<svc>_runtime` / `<svc>_migrator`, random
   passwords; fresh clusters: the `openbao-bootstrap` loop).
2. **`services/<svc>.yaml`** (copy `review.yaml` or `cart.yaml`): runtime and migrator
   ExternalSecrets, the runtime `DatabaseRole`, and `Database` with
   `owner: <svc>_owner`. No owner or migrator `DatabaseRole`: the catalog
   creates them, and CNPG retries the `Database` until the owner exists.
3. **App-namespace copies** of both Secrets (`secrets/…-<svc>-ns.yaml`).
4. **`pg_hba`:** `host <svc> <svc>_runtime`, `host <svc> <svc>_migrator`,
   `host <svc> db_authz`, above the reject.
5. **Role catalog** (`authz/job.yaml`, both the Job and the CronJob): add `<svc>`
   to `ROLE_SERVICES`, add the `<SVC>_MIGRATOR_PASSWORD` env from the migrator
   Secret, and either add `<svc>` to `GRANT_SERVICES` or give it a pgroles
   policy: copy `authz/policies/user.yaml` (product-db: `cart.yaml`), rename, and list it in
   `authz/kustomization.yaml`. A pgroles-owned runtime holds
   `schema_migrations` (PGR-10); choose the Job if that is not acceptable.
6. **Guards:** the migrator edge in `pg_role_membership`, the migrator in
   `pg_role_config`, the database in `pg_default_privileges`, the `absent()`
   selectors and `smoke.js` (`CONVERTED_SERVICES`).
7. **Gate scripts:** `scripts/db-authz-check.sh` (`declare_service`: a table
   and `denied`/`ok` for `schema_migrations`) and the cluster's matrix in
   `scripts/db-isolation-sweep.sh`.
8. **InputProvider:** `db_runtime_secret`, `db_migrator_secret`,
   `db_migration_host` (the primary).
9. **Verify:** `kubectl -n <namespace> logs job/<cluster>-authz` (`platform` or `product`) ends with
   `authz applied`, the policy (if any) is `Ready`, then
   `./scripts/db-authz-check.sh <svc>`.

## What you never do

- Edit `bootstrap.initdb` or add `postInitSQL` — dead on a running cluster,
  divergent on restore; RFC-0012 removed that generation.
- Add an inline `managed.roles` entry — it would take precedence over the
  `DatabaseRole` and flip it to `applied: false` (that's the rollback lever,
  not the pattern).
- Put a password in any manifest or Helm value.
