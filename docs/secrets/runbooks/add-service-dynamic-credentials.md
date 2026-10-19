# Add Service Dynamic Credentials

Use this to put a service runtime login under OpenBAO-managed rotation
(ADR-025 pattern A, ADR-089: one writer per password). Deployed today for all
ten runtimes: four on `platform-db` and six on `product-db`, rotated every
720h. Copy any of them; `user` (platform-db) is the reference below, and
`<cluster>` is `platform-db` or `product-db`.

| Status | Meaning |
|---|---|
| Deployed pattern (static role) | OpenBAO rotates the password of an **existing** PostgreSQL role; ESO syncs `database/static-creds/<svc>-runtime` through ClusterSecretStore `openbao-db`; the pod reads it from a mounted file |
| Planned | Dynamic `database/creds/*` roles (per-lease `CREATE ROLE`, TTLs) — **not deployed**; do not follow that pattern yet |

The service image must read `DB_PASSWORD_FILE` (pkg/dbx `WithPasswordFile`);
every service from the 2026-10-18 release does.

## 1. Let vault_rotator administer the role

`kubernetes/infra/configs/databases/clusters/<cluster>/`:

- `instance.yaml` `postInitSQL`: `CREATE ROLE <svc>_runtime WITH LOGIN` and
  `GRANT <svc>_runtime TO vault_rotator WITH INHERIT FALSE, SET FALSE, ADMIN TRUE`.
  This runs on a new cluster only; on a running one, run the grant by hand
  ([rotator credential runbook](../../databases/runbooks/rotate-vault-rotator-credential.md), step 5).
- `vault-rotator.yaml`: add `<svc>_runtime` to `inRoles`, or CNPG revokes the
  membership. (On product-db `vault_rotator` logs in through
  `hostssl product vault_rotator`; the same line sits on `product-db-replica`.)
- Drift guard: one row in `configmaps/monitoring-queries.yaml`
  (`('vault_rotator', '<svc>_runtime', true, false, false)`) and one `absent(...)`
  line in [bundles/postgres/role-membership-alerts.yaml](https://github.com/duynhlab/helm-charts/blob/main/charts/vm-rules/bundles/postgres/role-membership-alerts.yaml).

## 2. Add the static role to the engine-config Job

The cluster's `openbao-db-config.yaml`: add `<svc>-runtime` to `allowed_roles`
and `<svc>` to the static-role loop. The connection already reaches PostgreSQL
as `vault_rotator`; `ALTER ROLE` is cluster-wide, so no new `pg_hba` line is
needed. A new cluster needs its own Job and ServiceAccount in its namespace,
plus that namespace in the bootstrap's `db-configurator` auth role
(`bound_service_account_namespaces`).

## 3. Grant ESO read on the static-creds path

`kubernetes/infra/configs/secrets/openbao-bootstrap/configmap.yaml`, policy
`eso-read`:

```text
path "database/static-creds/<svc>-runtime" { capabilities = ["read"] }
```

Remove `<svc>/runtime` from the KV seed loop in the same file; the static role
is now the only source.

**Live cluster:** the bootstrap Job cannot re-apply policies (root is revoked).
Apply the updated policy by hand with an `infra-team` OIDC token
(`bao login -method=oidc`, then `bao policy write eso-read <file>` —
[ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/)); the
[generate-root ceremony](./add-secret-live-cluster.md) is the issuer-down
fallback.

## 4. Point both ExternalSecrets at the engine

`services/<svc>.yaml` (the cluster's namespace) and
`secrets/<cluster>-<svc>-runtime-secret-<svc>-ns.yaml` (service ns):
`secretStoreRef.name: openbao-db`, `remoteRef.key: database/static-creds/<svc>-runtime`
(properties `username`, `password`), `refreshInterval: 15s`, and no
`cnpg.io/reload` label. In the same file, delete the runtime `DatabaseRole`'s
`passwordSecret`.

## 5. Mount the file in the pod

`kubernetes/apps/services/<svc>.yaml`: `db_password_file: "/etc/db/secret/password"`.
The domain template mounts the runtime Secret as a directory, sets
`DB_PASSWORD_FILE` and stops setting `DB_PASSWORD` on the service container
(the `migrate` init container keeps its migrator password).

## 6. Deploy and verify

```bash
make validate
# after merge, on a running cluster: let Flux re-create the completed Job
kubectl delete job openbao-db-config -n <platform|product>
flux reconcile kustomization databases-local -n flux-system --with-source
kubectl logs -n <platform|product> job/openbao-db-config
kubectl get externalsecret -A | grep <svc>-runtime
```

Force one rotation and confirm the pod follows it without a restart (commands in
[Dynamic credentials debug](./dynamic-credentials-debug.md)). A new connection
fails authentication for up to ESO refresh + kubelet sync after a rotation;
open connections are unaffected.
