# Add Or Write A KV Secret On A Live Cluster (Break-Glass)

The bootstrap Job **revokes the root token** at the end of its first run
(RFC-0008), and the `root_token` field left in `openbao-init-keys` is an
**inert copy** — it authenticates nothing. Every ESO role is read-only. So on
an already-bootstrapped cluster there is **no standing credential that can
write KV**, and re-running the bootstrap Job seeds nothing (it detects the
revoked root and exits "already bootstrapped. Done." — learned live at the
RFC-0021 W8 canary-salt seed).

Writing therefore goes through the documented break-glass: mint a temporary
root from the **recovery key**, write, revoke again.

| | |
|---|---|
| **Needs** | `openbao-init-keys` Secret (field `recovery_key`) — full-admin material, treat accordingly |
| **Leaves behind** | Nothing: the minted root is revoked in step 4 |
| **Fresh clusters** | Do NOT need this — `make up` runs bootstrap with a live root and seeds every `bao kv put` in the script |

## Procedure

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
_Last updated: 2026-07-31_
