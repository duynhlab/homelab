# Revoke Compromised Credential

Use this during incident response when a token, static secret, or database credential is suspected compromised.

Revocation commands are authenticated. Root was revoked at bootstrap (the
`root_token` copy in `openbao-init-keys` is inert) — under incident pressure
the fast path is the **staff OIDC login**
([ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/)); the recovery-key
ceremony is the fallback when Keycloak itself is down.

```bash
# 0. Log in as an infra-team member (one command, opens a browser):
export BAO_ADDR=https://openbao.duynh.me   # or a port-forward to :8200
bao login -method=oidc
# Fallback (issuer down): generate-root ceremony per ./add-secret-live-cluster.md.

# 1a. Compromised service runtime password (static role, ADR-025/ADR-089):
#     static-creds are rotated, not lease-revoked. Force a rotation, then roll
#     PgDog (product-db) and end the old sessions, per the emergency rotation in
#     docs/databases/runbooks/rotate-cnpg-service-password.md.
bao write -f database/rotate-role/<svc>-runtime
# ESO re-syncs <cluster>-<svc>-runtime-secret within refreshInterval (15s).

# 1b. Compromised KV v2 static secret: overwrite it — see
#     ./rotate-static-secret.md (same ceremony token works).

# 1c. Leased credential (generic incident command — no leased engines are
#     deployed today; dynamic database/creds/* roles are planned):
bao lease revoke <mount>/creds/<role>/<lease-id>
bao lease revoke -prefix <mount>/creds/<role>/

# 2. Compromised OpenBAO token:
bao token revoke <token>

# 3. Revoke your token when done (mandatory for a ceremony root)
bao token revoke -self
```

Verify that the old password no longer authenticates (the `<svc>_runtime`
role keeps its name — only the password rotates), as in step 4 of the
[service password rotation runbook](../../databases/runbooks/rotate-cnpg-service-password.md#force-a-rotation).
The role itself is unchanged:

```bash
kubectl exec -n <platform|product> <cluster>-1 -c postgres -- psql -U postgres -c "\du <svc>_runtime"
```
