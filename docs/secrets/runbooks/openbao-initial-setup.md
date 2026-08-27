# OpenBAO Initial Setup

Use this after a fresh local Kind deployment or when verifying that OpenBAO, ESO, and seeded KV paths are ready.

| Scope | Current local Kind behavior |
|---|---|
| Init / unseal | Automatic — the `openbao-bootstrap` Job inits with a recovery key; pods auto-unseal via the floci KMS (`awskms` seal, ADR-024) |
| Configuration | Automatic — the same Job enables KV v2, Kubernetes auth, policies, and seeds KV secrets |
| Root token | Revoked by the Job at the end of its first run; the `root_token` copy left in `openbao-init-keys` is **inert** |
| Day-2 admin access | staff OIDC login — `bao login -method=oidc`, `infra-team` policy ([ADR-062](../../proposals/adr/ADR-062-staff-groups-sso/)); configured post-bootstrap by the `openbao-oidc-config` Job |
| Break-glass (issuer down) | `recovery_key` in Secret `openbao/openbao-init-keys` → [generate-root ceremony](./add-secret-live-cluster.md) |

Everything below is **verification** — there is nothing to init, unseal, or
configure by hand (human login exists, but it is SSO — nothing to set up).

```bash
# 1. Check cluster status after deployment
kubectl get pods -n openbao

# 2. Watch the bootstrap Job (init + auto-unseal wait + config + root revoke)
kubectl get job -n openbao openbao-bootstrap
kubectl logs -n openbao job/openbao-bootstrap -f
# Expect the log to end with "Bootstrap Complete!" and "Root ... revoked".

# 3. Verify seal state: awskms auto-unseal, recovery seal shamir, unsealed
kubectl exec -n openbao openbao-0 -- bao status
# Expect: Seal Type awskms / Recovery Seal Type shamir / Initialized true / Sealed false

# 4. Verify where the break-glass material landed
kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data}' | tr ',' '\n'
# Expect keys: recovery_key (break-glass) and root_token (inert — revoked, authenticates nothing)

# 5. Verify the root token is really revoked (must FAIL with 403/permission denied)
ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)
kubectl exec -n openbao openbao-0 -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="$ROOT" \
  bao token lookup -self
```

## Re-running the bootstrap Job

The bootstrap is a **Job** delivered by the Flux Kustomization `secrets-local`
(`kubernetes/infra/configs/secrets/openbao-bootstrap/job.yaml`). To re-run it
after a script/config change, delete the completed Job and let Flux re-create
it:

```bash
kubectl delete job openbao-bootstrap -n openbao
flux reconcile kustomization secrets-local -n flux-system --with-source
```

**A re-run seeds nothing on an already-bootstrapped cluster** — the script's
`bao kv put` lines need root, which was revoked at the end of the first run;
the re-run prints "already bootstrapped (revoked). Done." and exits 0. To add
a secret to a live cluster use an `infra-team` OIDC login — or the break-glass
ceremony if the issuer is down — per
[add-secret-live-cluster.md](./add-secret-live-cluster.md). Only a
fresh cluster (`make up`) seeds the full script.

## Step 6 — Seed bootstrap-only Cloudflare token (operator)

**Local Kind:** nothing to do — `openbao-bootstrap` seeds a **dev placeholder** (`api_token="dev-cloudflare-placeholder"`) so the ExternalSecret syncs. Local `platform-edge-tls` is `homelab-ca`-issued (reconciled on Kind with the RFC-0024 bring-up), so the (failing) DNS-01 challenge is irrelevant.

**Prod:** the real Cloudflare API token used by cert-manager DNS-01 is **operator-supplied** — **not** in Git. The stored `root_token` is inert; log in
with the staff OIDC method (`bao login -method=oidc`, `infra-team`) — or the
[generate-root ceremony](./add-secret-live-cluster.md) if the issuer is
down — then:

```bash
# With $BAO_TOKEN from the OIDC login (or the ceremony):
bao kv put secret/local/infra/cloudflare/api-token api_token=cfut_...
bao token revoke -self   # revoke the temporary root when done

# Force ESO to re-sync the per-namespace ExternalSecret in cert-manager
kubectl annotate clustersecretstore openbao force-sync=$(date +%s) --overwrite

# Make Flux re-evaluate cert-manager (will issue letsencrypt-prod cert once the Secret lands)
flux reconcile ks secrets-local --with-source
flux reconcile ks cert-manager-local --with-source
```

Verify: `kubectl get secret cloudflare-api-token -n cert-manager` should exist with key `api-token`. The `platform-edge-tls` Certificate then transitions to `Ready=True`.

## Check Status

```bash
# OpenBAO cluster health
kubectl exec -n openbao openbao-0 -- bao status

# Raft peers (authenticated call — infra-team OIDC token, see add-secret runbook)
kubectl exec -n openbao openbao-0 -- bao operator raft list-peers

# ESO sync status
kubectl get externalsecret -A
kubectl get clustersecretstore openbao
kubectl get clustersecretstore openbao-db   # ADR-025 database static-role pilot

# Specific ExternalSecret state
kubectl describe externalsecret product-db-secret -n product
```

---

_Last updated: 2026-08-27 — day-2 admin access is the ADR-062 staff OIDC login; ceremony demoted to issuer-down fallback throughout. 2026-08-19: rewritten for the automated bootstrap Job._
