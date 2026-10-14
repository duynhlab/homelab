# Runbook: Add a Service Database on product-db

Give a new service its own database, role, and credentials on the shared
`product-db` cluster — a service triplet, client/pooler registrations, and an
HBA allow rule in `instance.yaml` before its terminal reject.

| | |
|---|---|
| **Pattern** | Per-service triplet: ExternalSecret + DatabaseRole + Database ([ADR-013](../../proposals/adr/ADR-013-per-service-db-triplet/)) |
| **Time** | ~15 minutes + one PR |
| **Reference triplet** | `kubernetes/infra/configs/databases/clusters/product-db/services/payment.yaml` |
| **Concepts** | [012 — Declarative Role & Database Management](../declarative-role-management.md) |
| **Three-role services** | On `platform-db`, a service on owner + migrator + runtime roles ([ADR-088](../../proposals/adr/ADR-088-platform-owns-database-authorization/)) follows [Three-role service on platform-db](#three-role-service-on-platform-db) below; product-db services move in a later wave |

## Steps

`<svc>` is the new service name throughout.

1. **Seed the credential in OpenBAO** at
   `secret/local/databases/product-db/<svc>` with `username` and `password`.
   For an existing cluster, follow [Add a secret to a live cluster](../../secrets/runbooks/add-secret-live-cluster.md)
   using an authorized session. Do not commit the password or embed it in a
   client DSN. Fresh-cluster provisioning belongs in the bootstrap workflow,
   with runtime-generated credentials rather than a new committed literal.

   Re-running `openbao-bootstrap` does not seed a live cluster: it has already
   revoked its root token and exits as already bootstrapped. Use the day-2
   procedure, then sync ESO.

2. **Create the triplet** —
   `kubernetes/infra/configs/databases/clusters/product-db/services/<svc>.yaml`,
   copied from `payment.yaml`, in this order:
   1. `ExternalSecret product-db-<svc>-secret` (namespace `product`) —
      `template.type: kubernetes.io/basic-auth`, label `cnpg.io/reload: "true"`,
      OpenBAO path from step 1.
   2. `DatabaseRole product-db-role-<svc>` — **every attribute explicit** (adoption
      semantics; see the concept doc), `login: true`, all privilege flags
      `false`, `databaseRoleReclaimPolicy: retain`.
   3. `Database <svc>-database` — `owner: <svc>`, baseline extensions
      (`pgaudit`, `pg_stat_statements`) plus service-specific ones,
      `databaseReclaimPolicy: retain`.

   Register the file in `services/kustomization.yaml`.

3. **App-namespace secret copy** — the service's pods read credentials from
   their own namespace: add
   `clusters/product-db/secrets/product-db-<svc>-secret-<svc>-ns.yaml` (clone the
   cart/order/payment `-ns` copies; plain Opaque is fine for app env use) and
   register it in the cluster `kustomization.yaml`.

4. **Pooler entry** (skip if the service connects direct like payment) — in
   `clusters/product-db/poolers/helmrelease.yaml`:
   - **Append** to `values.databases` and `values.users` (name + database
     only, no password).
   - **Append** a `valuesFrom` entry pointing at the new Secret with
     `targetPath: "users[<N>].password"` where `<N>` is the new **last**
     index. Indices are positional — always append at the end, never insert
     mid-list ([ADR-014](../../proposals/adr/ADR-014-pooler-credentials-valuesfrom/)).

5. **pg_hba (connection isolation is live — RFC-0012 P4):** add the service's `pg_hba`
   allow rule in `instance.yaml` above the trailing reject — the one
   exception to "never touch instance.yaml", because HBA is cluster
   infrastructure, not a service definition.

6. **Validate and ship** — `make validate`, PR, merge. Flux converges:
   ESO renders the Secret → `DatabaseRole` creates the role →
   `Database` creates the database owned by it.

7. **Verify:**

   ```bash
   kubectl get databaserole,database -n product | grep <svc>   # applied: true
   kubectl run psql-check --rm -it --restart=Never -n product \
     --image=ghcr.io/cloudnative-pg/postgresql:18.6-system-trixie -- \
     psql -W "host=product-db-rw.product user=<svc> dbname=<svc>" -c 'select 1'
   ```

## Three-role service on platform-db

The platform creates the owner and migrator and applies the grants; the service
repo gets two credentials. One PR, no manual SQL ([Database
authorization](../authorization.md)):

1. **OpenBAO:** seed `secret/local/databases/platform-db/<svc>-runtime` and
   `…/<svc>-migrator` (`username` = `<svc>_runtime` / `<svc>_migrator`, random
   passwords; fresh clusters: the `openbao-bootstrap` loop).
2. **`services/<svc>.yaml`** (copy `review.yaml`): runtime and migrator
   ExternalSecrets, the runtime `DatabaseRole`, and `Database` with
   `owner: <svc>_owner`. No owner or migrator `DatabaseRole`: the catalog
   creates them, and CNPG retries the `Database` until the owner exists.
3. **App-namespace copies** of both Secrets (`secrets/…-<svc>-ns.yaml`).
4. **`pg_hba`:** `host <svc> <svc>_runtime`, `host <svc> <svc>_migrator`,
   `host <svc> db_authz`, above the reject.
5. **Role catalog** (`authz/job.yaml`, both the Job and the CronJob): add `<svc>`
   to `ROLE_SERVICES`, add the `<SVC>_MIGRATOR_PASSWORD` env from the migrator
   Secret, and either add `<svc>` to `GRANT_SERVICES` or give it a pgroles
   policy (planned, D2).
6. **Guards:** the migrator edge in `pg_role_membership`, the migrator in
   `pg_role_config`, the database in `pg_default_privileges` (Job-owned), the
   `absent()` selectors and `smoke.js`.
7. **InputProvider:** `db_runtime_secret`, `db_migrator_secret`,
   `db_migration_host` (the primary).
8. **Verify:** `kubectl -n platform logs job/platform-db-authz` ends with
   `authz applied`, then `./scripts/db-authz-check.sh <svc>` after adding the
   service to its table.

## What you never do

- Edit `bootstrap.initdb` or add `postInitSQL` — dead on a running cluster,
  divergent on restore; RFC-0012 removed that generation.
- Add an inline `managed.roles` entry — it would take precedence over the
  `DatabaseRole` and flip it to `applied: false` (that's the rollback lever,
  not the pattern).
- Put a password in any manifest or Helm value.
