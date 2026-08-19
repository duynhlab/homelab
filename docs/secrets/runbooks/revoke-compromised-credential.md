# Revoke Compromised Credential

Use this during incident response when a token, static secret, or database credential is suspected compromised.

Revocation commands are authenticated, and no standing admin credential exists —
the bootstrap Job revoked the root token (the `root_token` copy in
`openbao-init-keys` is inert).

```bash
# 0. Obtain a short-lived root token via the generate-root ceremony
#    (steps 1–3 of ./add-secret-live-cluster.md, inside openbao-0):
kubectl exec -it -n openbao openbao-0 -- sh
export BAO_ADDR=http://127.0.0.1:8200
export BAO_TOKEN=<generated-root-token>

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

# 3. Revoke the temporary root token when done
bao token revoke -self
```

Verify from PostgreSQL that the old password no longer authenticates (the
`notification` role keeps its name — only the password rotates):

```bash
kubectl exec -n platform platform-db-1 -- psql -U postgres -c "\du" | grep notification
```

---

_Last updated: 2026-08-19 — Added the generate-root ceremony (step 0) and final revoke; examples aligned with the deployed ADR-025 static-role pilot instead of undeployed dynamic leases._
