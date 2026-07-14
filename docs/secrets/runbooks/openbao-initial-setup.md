# OpenBAO Initial Setup

Use this after a fresh local Kind deployment or when verifying that OpenBAO, ESO, and seeded KV paths are ready.

| Scope | Current local Kind behavior |
|---|---|
| OpenBAO init | Bootstrap Job initializes and stores keys in `openbao-init-keys` |
| Secret seeding | Bootstrap Job seeds local learning values into KV v2 |
| Production warning | Do not keep root tokens or unseal keys in Kubernetes Secrets in production |

```bash
# 1. Check cluster status after deployment
kubectl get pods -n openbao

# 2. Initialize (first time only — saves keys)
kubectl exec -n openbao openbao-0 -- bao operator init \
  -key-shares=1 -key-threshold=1 -format=json > /tmp/openbao-init.json

# 3. Unseal all nodes (Shamir / local Kind)
UNSEAL_KEY=$(cat /tmp/openbao-init.json | jq -r '.unseal_keys_b64[0]')
kubectl exec -n openbao openbao-0 -- bao operator unseal $UNSEAL_KEY
kubectl exec -n openbao openbao-1 -- bao operator unseal $UNSEAL_KEY
kubectl exec -n openbao openbao-2 -- bao operator unseal $UNSEAL_KEY

# 4. Login with root token (one time only)
ROOT_TOKEN=$(cat /tmp/openbao-init.json | jq -r '.root_token')
kubectl exec -n openbao openbao-0 -- bao login $ROOT_TOKEN

# 5. Run bootstrap job (engines, auth, policies, namespaces, DB config)
kubectl create job --from=cronjob/openbao-bootstrap openbao-bootstrap-manual -n openbao

# 6. Revoke root token after bootstrap is verified
kubectl exec -n openbao openbao-0 -- bao token revoke $ROOT_TOKEN
```

## Step 7 — Seed bootstrap-only Cloudflare token (operator)

**Local Kind:** nothing to do — `openbao-bootstrap` seeds a **dev placeholder** (`api_token="dev-cloudflare-placeholder"`) so the ExternalSecret syncs. Local `kong-proxy-tls` is `homelab-ca`-issued, so the (failing) DNS-01 challenge is irrelevant.

**Prod:** the real Cloudflare API token used by cert-manager DNS-01 is **operator-supplied** — **not** in Git. Override the placeholder with the real token after every fresh cluster, then trigger downstream reconciles:

```bash
# Re-fetch root token from K8s Secret (kept across pod restarts via PVC)
ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)

kubectl exec -n openbao openbao-0 -- sh -c \
  "BAO_TOKEN=$ROOT bao kv put secret/local/infra/cloudflare/api-token api_token=cfut_..."

# Force ESO to re-sync the per-namespace ExternalSecret in cert-manager
kubectl annotate clustersecretstore openbao force-sync=$(date +%s) --overwrite

# Make Flux re-evaluate cert-manager (will issue letsencrypt-prod cert once the Secret lands)
flux reconcile ks secrets-local --with-source
flux reconcile ks cert-manager-local --with-source
```

Verify: `kubectl get secret cloudflare-api-token -n cert-manager` should exist with key `api-token`. The `kong-proxy-tls` Certificate then transitions to `Ready=True`.

## Check Status

```bash
# OpenBAO cluster health
kubectl exec -n openbao openbao-0 -- bao status

# Raft peers
kubectl exec -n openbao openbao-0 -- bao operator raft list-peers

# Active leases (count)
kubectl exec -n openbao openbao-0 -- bao list sys/leases/lookup/database/creds/

# ESO sync status
kubectl get externalsecret -A
kubectl get clustersecretstore openbao

# Specific ExternalSecret state
kubectl describe externalsecret product-db-secret -n product
```

---

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
