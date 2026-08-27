# Add Or Write A KV Secret On A Live Cluster

The bootstrap Job **revokes the root token** at the end of its first run
(RFC-0008), and the `root_token` field left in `openbao-init-keys` is an
**inert copy** — it authenticates nothing. Every ESO role is read-only.
Re-running the bootstrap Job seeds nothing (it detects the revoked root and
exits "already bootstrapped. Done." — learned live at the RFC-0021 W8
canary-salt seed).

Since [ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/) the normal
write path is a **staff OIDC login**: the `infra-team` policy is `path "*"`
with `sudo`, so it writes KV.

| | |
|---|---|
| **Needs** | membership in the Keycloak `infra-team` group (staff realm) |
| **Leaves behind** | an OIDC token that expires with its TTL (revoke-self for hygiene) |
| **Fresh clusters** | Do NOT need this — `make up` runs bootstrap with a live root and seeds every `bao kv put` in the script |

## Procedure

```bash
# 1. Log in as an infra-team member (opens a browser to Keycloak)
export BAO_ADDR=https://openbao.duynh.me   # or a port-forward to :8200
bao login -method=oidc

# 2. Write, verify, clean up
bao kv put secret/local/<category>/<service>/<name> key="value"
bao kv get secret/local/<category>/<service>/<name>
bao token revoke -self
```

Then force the ExternalSecret to pick it up:

```bash
kubectl annotate externalsecret <name> -n <ns> force-sync="$(date +%s)" --overwrite
```

## Fallback — recovery-key ceremony (issuer down)

If Keycloak or the edge is down, the designed break-glass is minting a
temporary root from the **recovery key** (`openbao-init-keys`, field
`recovery_key` — full-admin material, treat accordingly). **Known gap:** on
this platform the ceremony has answered the attempt endpoint with **403**
(recorded in [RFC-0008](../../proposals/rfc/RFC-0008/), re-verified
2026-08-25) — if it does, restore Keycloak first (it is GitOps: one
`flux reconcile` away) and use the OIDC path above.

All inside `openbao-0` (`kubectl -n openbao exec -it openbao-0 -- sh`,
`export BAO_ADDR=http://127.0.0.1:8200`):

```bash
# 1. Start a root-generation ceremony: prints a NONCE and an OTP
bao operator generate-root -init

# 2. Feed the recovery key (from the openbao-init-keys Secret, field
#    recovery_key) with the nonce; prints an ENCODED token
echo "<recovery_key>" | bao operator generate-root -nonce=<nonce> -

# 3. Decode with the OTP from step 1 → the temporary root token
bao operator generate-root -decode=<encoded_token> -otp=<otp>

# 4. Write, verify, and revoke the temporary root
export BAO_TOKEN=<token>
bao kv put secret/local/<category>/<service>/<name> key="value"
bao kv get secret/local/<category>/<service>/<name>
bao token revoke -self
```

Then force the ExternalSecret to pick it up:

```bash
kubectl annotate externalsecret <name> -n <ns> force-sync="$(date +%s)" --overwrite
```

## If the secret is also seeded by the bootstrap script

Add the `bao kv put` line to
`kubernetes/infra/configs/secrets/openbao-bootstrap/configmap.yaml` **as well**
(fresh clusters seed from there), and do the break-glass write for the cluster
already running. One without the other leaves either the live cluster or the
next `make up` without the value.

## The proper fix (planned)

A scoped **AppRole/Kubernetes-auth role with write on `secret/data/local/*`**
for operator seeding would retire this ceremony — tracked as an RFC-0008
follow-up. Until then the trade-off is deliberate: no standing write
credential exists to steal.

---
_Last updated: 2026-08-27 — OIDC infra-team login is the normal write path (ADR-062); recovery-key ceremony demoted to issuer-down fallback with its RFC-0008 403 gap stated. 2026-07-31: first version._
