# Secrets Management Guide

> **Status**: Local/Dev environment using **OpenBAO (HA)** + External Secrets Operator (ESO)
>
> **Target**: Standardized secret management across all microservices and infrastructure

---

## Overview

This project uses **OpenBAO** (Apache 2.0 fork of HashiCorp Vault) as the source of truth for secrets, with **External Secrets Operator (ESO)** syncing secrets to Kubernetes. This approach:

- Centralizes secret management in OpenBAO
- Eliminates plaintext secrets in Git (eventual goal)
- Provides audit trails for secret access
- Enables secret rotation without redeployment
- Production-ready HA cluster (3-node Raft) — not dev mode

```mermaid
flowchart LR
    subgraph OpenBAOBox["OpenBAO (HA Raft)"]
        KV["KV v2 Secrets Engine"]
    end

    subgraph K8s["Kubernetes"]
        ESO["External Secrets Operator"]
        CSS["ClusterSecretStore"]
        CES["ClusterExternalSecret"]
        ES["ExternalSecret"]
        Secret["Kubernetes Secret"]
        App["Application Pod"]
    end

    KV --> CSS
    CSS --> ESO
    ESO --> CES
    ESO --> ES
    CES --> ES
    ES --> Secret
    Secret --> App
```

---

## Architecture

### Components

| Component | Purpose | Namespace | Version |
|-----------|---------|-----------|---------|
| OpenBAO (HA) | Secret storage (3-node Raft) | `openbao` | 2.5.2 (Chart 0.26.2) |
| External Secrets Operator | Sync secrets to K8s | `external-secrets-system` | **v2.1.0** |
| ClusterSecretStore | OpenBAO connection config | cluster-scoped | `openbao` |
| ClusterExternalSecret | Shared secrets across namespaces | cluster-scoped | Backup creds |
| ExternalSecret | Per-secret definition | app namespaces | Creates K8s Secrets |

### OpenBAO Configuration

- **Mode**: HA with Raft integrated storage (3 replicas, 10Gi PVC per node)
- **Auth Method**: Kubernetes (ServiceAccount-based via TokenReview API)
- **Secrets Engine**: KV v2 at path `secret/`
- **Audit Logging**: Stdout audit device (collected by Vector -> Loki)
- **Bootstrap**: Idempotent Job — init, unseal, configure on each deploy
- **Seal**: Shamir (1-share) for Kind; AWS KMS / GCP KMS for EKS/GKE

### Secret Organization (Hybrid Strategy)

Secrets are organized using a **hybrid strategy** for maintainability and scalability:

| Category | Location | Mechanism | Rationale |
|----------|----------|-----------|-----------|
| **DB credentials** | `configs/databases/clusters/*/secrets/` | ExternalSecret | Co-located with the DB cluster they serve |
| **Pooler credentials** | `configs/databases/clusters/*/secrets/` | ExternalSecret | Co-located with the pooler they serve |
| **Backup credentials** | `configs/secrets/cluster-external-secrets/` | ClusterExternalSecret | Shared across 5 namespaces via namespace labels |
| **Future shared secrets** | `configs/secrets/cluster-external-secrets/` | ClusterExternalSecret | Any secret needed by multiple namespaces |

---

## Path Naming Convention

All secret paths follow a standardized 4-level hierarchy:

```
secret/{environment}/{category}/{service-or-component}/{resource}
```

| Level | Values | Purpose |
|-------|--------|---------|
| `{environment}` | `local`, `staging`, `prod` | Environment isolation; same paths across envs |
| `{category}` | `databases`, `services`, `infra` | Top-level grouping; maps to policy templates |
| `{service-or-component}` | `auth`, `product`, `pgdog-cnpg`, `rustfs` | Specific service or infra component |
| `{resource}` | `credentials`, `jwt-signing-key`, `api-keys`, `backup-credentials` | Type of secret |

This convention enables:

- **Granular policies** per category (e.g., `secret/data/+/databases/*`)
- **Multi-environment** with the same paths (just swap `local` for `prod`)
- **Scalable onboarding** -- new services follow the same pattern
- **Self-documenting** -- the path tells you what, where, and why

## Secret Paths

All secrets are stored in OpenBAO's KV v2 secrets engine under the `secret/` path.

### Database Credentials

| Path | Description | Consumer |
|------|-------------|----------|
| `secret/local/databases/product/credentials` | Product DB credentials | product service |
| `secret/local/databases/cart/credentials` | Cart DB credentials (cnpg-db) | cart service |
| `secret/local/databases/order/credentials` | Order DB credentials (cnpg-db) | order service |

**Keys**: `username`, `password`

### Infrastructure Credentials

| Path | Description | Consumer |
|------|-------------|----------|
| `secret/local/infra/rustfs/backup-zalando` | RustFS S3 credentials (bucket: pg-backups-zalando) | Zalando clusters (auth-db, supporting-shared-db) |
| `secret/local/infra/rustfs/backup-cnpg` | RustFS S3 credentials (bucket: pg-backups-cnpg) | CNPG clusters (cnpg-db, cnpg-db-replica) |
| `secret/local/infra/cloudflare/api-token` | Cloudflare API token (Zone\:Read + DNS\:Edit on `duynh.me`) | cert-manager `letsencrypt-{staging,prod}` ClusterIssuers (DNS-01 solver) |

**Keys**: `access_key_id`, `secret_access_key` for RustFS rows; `api_token` for Cloudflare.

> ⚠️ **Bootstrap-only secret**: the Cloudflare token is **not** seeded by the OpenBAO bootstrap script (it is operator-supplied) and **not** in Git. Re-seed it after every fresh cluster — see [Bootstrap-only secrets](#bootstrap-only-secrets) below.

### Pooler Credentials

| Path | Description | Consumer |
|------|-------------|----------|
| `secret/local/databases/pgdog-cnpg/credentials` | PgDog (cnpg-db) credentials | pgdog-cnpg pooler |

**Keys (pgdog)**: `username`, `password`

### Future App Secrets (Ready for Onboarding)

| Path | Use Case |
|------|----------|
| `secret/local/services/auth/jwt-signing-key` | JWT signing key for auth service |
| `secret/local/services/notification/smtp-credentials` | Email provider credentials |
| `secret/local/services/product/stripe-api-key` | Payment integration |
| `secret/local/infra/otel-collector/api-token` | Observability infra |
| `secret/prod/services/auth/jwt-signing-key` | Same secret, production env |

---

## Kubernetes Secrets (ESO-managed)

### Naming Convention

ESO-managed secrets use the **same name** as the original secret they replace (e.g., `cnpg-db-secret`). The `managed-by: external-secrets` label identifies OpenBAO-backed secrets. No `-vault` suffix is used.

### Database Secrets (ExternalSecret per cluster)

| K8s Secret | Namespace | Source |
|------------|-----------|--------|
| `cnpg-db-secret` | product | `secret/data/local/databases/product/credentials` |
| `cnpg-db-cart-secret` | cart | `secret/data/local/databases/cart/credentials` |
| `cnpg-db-order-secret` | order | `secret/data/local/databases/order/credentials` |

### Backup Secrets (ClusterExternalSecret)

Backup credentials use **ClusterExternalSecret** with namespace labels to auto-deploy to all namespaces that need them:

| ClusterExternalSecret | Label Selector | Target Namespaces | Key Format |
|----------------------|----------------|-------------------|------------|
| `pg-backup-rustfs-cnpg` | `platform.duynhlab/backup: "cnpg"` | product, cart | CNPG/Barman: `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` |
| `pg-backup-rustfs-walg` | `platform.duynhlab/backup: "walg"` | auth, user, review | WAL-G: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |

**Adding backup credentials to a new namespace**: Add the appropriate label to the namespace in `kubernetes/infra/controllers/namespaces.yaml`:

```yaml
metadata:
  labels:
    platform.duynhlab/backup: "cnpg"   # For CloudNativePG clusters
    # or
    platform.duynhlab/backup: "walg"   # For Zalando/WAL-G clusters
```

**ResourceSet namespaces**: Microservice namespaces are also created by Flux **ResourceSet** templates under [`kubernetes/apps/domains/`](kubernetes/apps/domains/). If the `Namespace` resource there omits `platform.duynhlab/backup`, app reconciliation can overwrite metadata and **drop** the label from `controllers/namespaces.yaml`, so ClusterExternalSecret **stops** matching and `pg-backup-rustfs-credentials` is not created. Keep the label in the ResourceSet `Namespace` block (identity: fixed `walg`; catalog/checkout/comms: optional `platform_backup_label` in the ResourceSetInputProvider for `cnpg` where needed).

### Pooler Secrets

| K8s Secret | Namespace | Source | Status |
|------------|-----------|--------|--------|
| `pgdog-cnpg-credentials` | product | `secret/data/local/databases/pgdog-cnpg/credentials` | Available (not consumed) |

> **Note**: Pooler charts don't currently support `secretRef`. Secrets are created for future use.

### Infrastructure ExternalSecrets (per-namespace)

| K8s Secret | Namespace | Source path (OpenBAO) | Source key | K8s key |
|------------|-----------|-----------------------|------------|---------|
| `cloudflare-api-token` | `cert-manager` | `secret/data/local/infra/cloudflare/api-token` | `api_token` | `api-token` |

Defined at `kubernetes/infra/configs/secrets/cluster-external-secrets/cloudflare.yaml` (kind `ExternalSecret`, despite the directory name — the cert-manager ClusterIssuer only needs the Secret in one namespace).

---

## Monitoring

### ESO Metrics

External Secrets Operator exposes Prometheus metrics, scraped by the `external-secrets` ServiceMonitor in the `monitoring` namespace.

**Key metrics to monitor:**

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `externalsecret_sync_calls_error_total` | Total sync failures | Any increase |
| `externalsecret_status_condition{condition="Ready",status="False"}` | Unhealthy ExternalSecrets | Any value > 0 |
| `externalsecret_reconcile_duration` | Reconcile latency | p99 > 30s |

**Verify ESO sync status:**

```bash
kubectl get externalsecret -A
kubectl get clusterexternalsecret
kubectl get clustersecretstore
```

---

## Operations Guide

### Adding a New Secret

1. **Add to OpenBAO bootstrap script** (`openbao-bootstrap/configmap.yaml`):

```bash
# Follow path convention: secret/{env}/{category}/{service}/{resource}
bao kv put secret/local/services/my-service/credentials key1="value1" key2="value2"
```

2. **Create ExternalSecret** (for namespace-specific secrets):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <secret-name>
  namespace: <namespace>
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: openbao
    kind: ClusterSecretStore
  target:
    name: <secret-name>
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: <k8s-key>
      remoteRef:
        key: secret/data/local/<category>/<service>/<resource>
        property: <openbao-key>
```

3. **Or use ClusterExternalSecret** (for secrets shared across namespaces):

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: <secret-name>
spec:
  namespaceSelector:
    matchLabels:
      <label-key>: <label-value>
  refreshTime: 1h
  externalSecretSpec:
    refreshInterval: 1h
    secretStoreRef:
      name: openbao
      kind: ClusterSecretStore
    target:
      name: <secret-name>
    data:
      - secretKey: <k8s-key>
        remoteRef:
          key: secret/data/local/<category>/<component>/<resource>
          property: <openbao-key>
```

4. **Deploy**: `make flux-push && make flux-sync`

### Bootstrap-only secrets

A few secrets are **operator-supplied** — they are not in Git and not seeded by the OpenBAO bootstrap script, so they must be re-applied after every fresh cluster:

| Path | Why | Used by |
|---|---|---|
| `secret/local/infra/cloudflare/api-token` (key `api_token`) | API tokens are personal credentials, must not be committed | cert-manager `letsencrypt-prod` / `letsencrypt-staging` ClusterIssuers → `kong-proxy-tls` |

```bash
ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)
kubectl exec -n openbao openbao-0 -- sh -c \
  "BAO_TOKEN=$ROOT bao kv put secret/local/infra/cloudflare/api-token api_token=cfut_..."
flux reconcile ks secrets-local --with-source
flux reconcile ks cert-manager-local --with-source
```

If cert-manager already failed waiting for the Secret, also force ESO to re-sync immediately:

```bash
kubectl annotate clustersecretstore openbao force-sync=$(date +%s) --overwrite
kubectl rollout restart deploy/cert-manager -n cert-manager
```

Long-term mitigation options are tracked in [`tamsu.md`](../../tamsu.md) (combination of a local `~/.homelab/secrets.env` bootstrap script + persisting the OpenBAO PVC across `make down`).

### Rotating a Secret

1. **Update in OpenBAO**:

```bash
kubectl port-forward svc/openbao -n openbao 8200:8200
export BAO_ADDR=http://localhost:8200
export BAO_TOKEN=$(kubectl get secret openbao-init-keys -n openbao -o jsonpath='{.data.root_token}' | base64 -d)
bao kv put secret/local/<category>/<service>/<resource> key="new-value"
```

2. **Wait for ESO sync** (default: 1 hour) or force refresh:

```bash
kubectl annotate es <name> -n <namespace> force-sync=$(date +%s) --overwrite
```

3. **Restart affected pods**:

```bash
kubectl rollout restart deployment/<name> -n <namespace>
```

### Troubleshooting

#### ExternalSecret Not Syncing

```bash
kubectl get externalsecret -n <namespace> -o yaml
kubectl describe externalsecret <name> -n <namespace>
kubectl get clustersecretstore openbao
```

#### OpenBAO Authentication Failing (`permission denied` from ESO ~1h after bootstrap)

**Symptom**: every ExternalSecret reports `ClusterSecretStore "openbao" is not ready`; ESO logs show `Code: 403. Errors: * permission denied` on `/v1/auth/kubernetes/login`. Often appears 1–2 hours after `make up`, not at start.

**Root cause** (commit `fb14349`): the bootstrap Job used to write `auth/kubernetes/config` with `token_reviewer_jwt` set to its own projected SA token, which expires after 1h (BoundServiceAccountTokenVolume). Once expired, every Kubernetes-auth login fails. Fix is to omit `token_reviewer_jwt` and set `disable_local_ca_jwt=false` so OpenBAO uses its own pod's auto-rotated SA token to call `TokenReview`.

**Verify**:

```bash
kubectl logs job/openbao-bootstrap -n openbao
ROOT=$(kubectl get secret openbao-init-keys -n openbao -o jsonpath='{.data.root_token}' | base64 -d)
kubectl exec -n openbao openbao-0 -- sh -c "BAO_TOKEN=$ROOT bao read auth/kubernetes/config"
# Expect: token_reviewer_jwt_set=false, disable_local_ca_jwt=false
```

**Runtime fix** (deadlocked because `secrets-local` is what installs the fix — break the loop manually):

```bash
kubectl exec -n openbao openbao-0 -- sh -c \
  "BAO_TOKEN=$ROOT bao write auth/kubernetes/config \
    kubernetes_host=https://10.96.0.1:443 \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    disable_local_ca_jwt=false token_reviewer_jwt=''"
kubectl annotate clustersecretstore openbao force-sync=$(date +%s) --overwrite
```

**Persistent fix**: re-run the bootstrap Job (it now ships the corrected script):

```bash
kubectl delete job -n openbao openbao-bootstrap
flux reconcile ks secrets-local --with-source
```

#### OpenBAO Authentication Failing (general)

```bash
kubectl logs job/openbao-bootstrap -n openbao
kubectl port-forward svc/openbao -n openbao 8200:8200
export BAO_ADDR=http://localhost:8200
export BAO_TOKEN=$(kubectl get secret openbao-init-keys -n openbao -o jsonpath='{.data.root_token}' | base64 -d)
bao auth list
bao read auth/kubernetes/config
```

#### OpenBAO Sealed After Restart

```bash
# Check seal status
kubectl exec openbao-0 -n openbao -- bao status

# Get unseal key and unseal all nodes
UNSEAL_KEY=$(kubectl get secret openbao-init-keys -n openbao -o jsonpath='{.data.unseal_key}' | base64 -d)
for i in 0 1 2; do
  kubectl exec openbao-$i -n openbao -- bao operator unseal "$UNSEAL_KEY"
done
```

---

## File Reference

### Infrastructure Files

| File | Purpose |
|------|---------|
| `kubernetes/infra/controllers/secrets/openbao/helmrelease.yaml` | OpenBAO HelmRelease (HA Raft) |
| `kubernetes/infra/controllers/secrets/external-secrets/helmrelease.yaml` | ESO HelmRelease (v2.1.0) |
| `kubernetes/infra/configs/secrets/openbao-bootstrap/` | OpenBAO bootstrap (Job, ConfigMap, SA, RBAC) |
| `kubernetes/infra/configs/secrets/cluster-secret-store.yaml` | ClusterSecretStore |
| `kubernetes/infra/configs/secrets/cluster-external-secrets/` | ClusterExternalSecret definitions |
| `kubernetes/infra/configs/databases/clusters/*/secrets/` | Per-cluster ExternalSecret definitions |
| `kubernetes/infra/configs/monitoring/servicemonitors/external-secrets.yaml` | ESO metrics ServiceMonitor |

### Helm Sources

| File | Purpose |
|------|---------|
| `kubernetes/clusters/local/sources/helm/openbao.yaml` | OpenBAO Helm repo |
| `kubernetes/clusters/local/sources/helm/external-secrets.yaml` | ESO Helm repo |

---

## Known Limitations

### Pooler Inline Passwords

**Issue**: PgDog and PgCat don't support `secretRef` in their Helm charts.

**Current State**: Inline passwords in HelmRelease/ConfigMap (dev-only, documented).

**OpenBAO Secrets Available**:
- `pgdog-cnpg-credentials` (product namespace)

**Future Solutions**:
1. Request upstream chart support for `secretRef`
2. Implement initContainer-based config rendering
3. Switch to pooler that supports secrets (CNPG built-in PgBouncer)

---

## Production Roadmap

### Phase 1: Dynamic Database Secrets

Use OpenBAO's database secrets engine to generate short-lived PostgreSQL credentials on demand (eliminates static passwords entirely).

### Phase 2: Auto-Unseal (EKS/GKE)

Replace Shamir with cloud KMS for automatic unseal:
- AWS KMS for EKS
- GCP Cloud KMS for GKE

### Phase 3: Advanced Patterns

- **PushSecret**: Push operator-generated secrets back to OpenBAO for centralized visibility
- **Secret scanning**: Pre-commit hooks (`gitleaks`, `trufflehog`) in CI pipeline
- **Namespace-scoped SecretStore**: Replace ClusterSecretStore with per-namespace SecretStore for team isolation
- **OIDC Auth + Identity Groups**: Dev/data team access patterns with 90-day rotation

---

## Security Considerations

### Local/Dev Environment

- OpenBAO runs in HA mode with Shamir seal (1 share, stored in K8s Secret)
- Secrets are seeded from bootstrap script (values in Git for local dev)
- Unseal key in `openbao-init-keys` Secret — for Kind only

### Production Recommendations

1. Use auto-unseal (AWS KMS, GCP KMS) — never store unseal keys in K8s
2. Enable TLS via cert-manager
3. Restrict root token access; use AppRole or Kubernetes auth
4. Enable audit logging to SIEM
5. Rotate secrets regularly (90-day policy for service credentials)
6. Remove plaintext secrets from Git after migration

---

## Related Documentation

- [OpenBAO Architecture & Operations](./openbao.md)
- [OpenBAO Production Plan](./openbao-production-plan.md)
- [Secrets Backlog (P1/P2)](./backlog.md) - Detailed specs for pending improvements
- [External Secrets Operator Docs](https://external-secrets.io/)
- [OpenBAO Docs](https://openbao.org/docs/)
