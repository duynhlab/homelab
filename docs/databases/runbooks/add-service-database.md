# Runbook: Add a Service Database on product-db

Give a new service its own database, role, and credentials on the shared
`product-db` cluster — one triplet file plus three registrations, and **never a
change to `instance.yaml`**.

| | |
|---|---|
| **Pattern** | Per-service triplet: ExternalSecret + DatabaseRole + Database ([ADR-013](../../proposals/adr/ADR-013-per-service-db-triplet/)) |
| **Time** | ~15 minutes + one PR |
| **Reference triplet** | `kubernetes/infra/configs/databases/clusters/product-db/services/payment.yaml` |
| **Concepts** | [012 — Declarative Role & Database Management](../012-declarative-role-management.md) |

## Steps

`<svc>` is the new service name throughout.

1. **Seed the credential in OpenBAO** — add to
   `kubernetes/infra/configs/secrets/openbao-bootstrap/configmap.yaml`:

   ```bash
   bao kv put secret/local/databases/product-db/<svc> \
     username="<svc>" \
     password="<generated>"
   ```

   On a live cluster the run-once Job must be re-run to pick it up:
   `kubectl delete job openbao-bootstrap -n openbao && flux reconcile
   kustomization secrets-local --with-source`.

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
     --image=ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie -- \
     psql "host=product-db-rw.product user=<svc> dbname=<svc> password=<from OpenBAO>" -c 'select 1'
   ```

## What you never do

- Edit `bootstrap.initdb` or add `postInitSQL` — dead on a running cluster,
  divergent on restore; RFC-0012 removed that generation.
- Add an inline `managed.roles` entry — it would take precedence over the
  `DatabaseRole` and flip it to `applied: false` (that's the rollback lever,
  not the pattern).
- Put a password in any manifest or Helm value.

---

_Last updated: 2026-07-08 (RFC-0012 P3)_
