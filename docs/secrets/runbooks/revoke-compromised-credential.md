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

# 1a. Compromised ADR-025 static-role password (deployed pilot: notification):
#     static-creds are rotated, not lease-revoked — force an immediate rotation,
#     the old password stops working at once.
bao write -f database/rotate-role/notification
# ESO re-syncs Secret platform-db-notification-secret within refreshInterval (1m).

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

Verify from PostgreSQL that the old password no longer authenticates (the
`notification` role keeps its name — only the password rotates):

```bash
kubectl exec -n platform platform-db-1 -- psql -U postgres -c "\du" | grep notification
```

---

_Last updated: 2026-08-27 — step 0 is the ADR-062 staff OIDC login (one command beats a multi-party ceremony under incident pressure); generate-root demoted to issuer-down fallback. 2026-08-19: ceremony added, ADR-025 alignment._
