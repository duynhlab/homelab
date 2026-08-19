# Add Service Dynamic Credentials

Use this to put a second service's database password under OpenBAO-managed
rotation, by extending the deployed ADR-025 static-role pilot (today:
`notification` on `platform-db`, rotated every 720h).

| Status | Meaning |
|---|---|
| Deployed pattern (ADR-025 pilot) | Static role: OpenBAO rotates the password of an **existing** PostgreSQL role; ESO syncs `database/static-creds/<role>` via ClusterSecretStore `openbao-db` |
| Planned | Dynamic `database/creds/*` roles (per-lease `CREATE ROLE`, TTLs) — **not deployed**; do not follow that pattern yet |

## 1. Add the static role to the engine-config Job

Edit `kubernetes/infra/configs/databases/clusters/platform-db/openbao-db-config.yaml`:

- add the role to `allowed_roles` in the `database/config/platform-db` write
  (e.g. `allowed_roles="notification,<service>"`);
- add a static-role block after the notification one:

```bash
bao write database/static-roles/<service> \
  db_name=platform-db \
  username="<service>" \
  rotation_period="720h"
```

The `username` must be an **existing PostgreSQL role** in the target database —
static roles rotate a password, they do not create users. (A service on another
CNPG cluster needs its own `database/config/<cluster>` block and a reachable
`vault_rotator`-style login there first.)

## 2. Grant ESO read on the new static-creds path

Edit the `eso-read` policy in
`kubernetes/infra/configs/secrets/openbao-bootstrap/configmap.yaml` — add:

```text
path "database/static-creds/<service>" { capabilities = ["read"] }
```

**Live cluster:** the bootstrap Job cannot re-apply policies (root is revoked;
a re-run exits "already bootstrapped"). Apply the updated policy by hand with a
[generate-root ceremony](./add-secret-live-cluster.md) token
(`bao policy write eso-read <file>`). Fresh clusters pick it up from the
configmap automatically.

## 3. Create the ExternalSecret

Copy the shape of
`kubernetes/infra/configs/databases/clusters/platform-db/secrets/platform-db-notification-secret-notification-ns.yaml`:
`secretStoreRef.name: openbao-db`, `remoteRef.key: database/static-creds/<service>`,
properties `username` / `password`, `refreshInterval: 1m`.

## 4. Deploy and re-run the engine-config Job

```bash
make validate
make flux-push && make flux-sync

# The completed Job does not re-run on its own — delete it and let Flux re-create it:
kubectl delete job openbao-db-config -n platform
flux reconcile kustomization databases-local -n flux-system --with-source
```

## 5. Verify

```bash
kubectl logs -n platform job/openbao-db-config
kubectl get externalsecret <name> -n <namespace>
kubectl get secret <name> -n <namespace>
```

Deeper checks (engine reads, forced rotation):
[Dynamic credentials debug](./dynamic-credentials-debug.md).

---

_Last updated: 2026-08-19 — Rewritten from a planned-feature stub to the deployed ADR-025 static-role onboarding flow (extend the notification pattern); dynamic creds remain planned._
