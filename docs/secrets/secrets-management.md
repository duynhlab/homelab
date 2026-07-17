# Secrets Management Guide

> **Scope**: How application teams add, consume, and rotate secrets in this repo.
>
> For OpenBAO architecture (HA/Raft, seal, auth methods, secret engines, lease model) read [`openbao.md`](./openbao.md). For TLS read [`cert-manager.md`](./cert-manager.md) and [`trust-distribution.md`](./trust-distribution.md).

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
| OpenBAO (HA) | Secret storage (3-node Raft) | `openbao` | 2.5.x |
| External Secrets Operator | Sync secrets to K8s | `external-secrets-system` | **v2.5.0** |
| ClusterSecretStore | OpenBAO connection config | cluster-scoped | `openbao` |
| ClusterExternalSecret | Shared secrets across namespaces | cluster-scoped | Backup creds |
| ExternalSecret | Per-secret definition | app namespaces | Creates K8s Secrets |

### OpenBAO Configuration

- **Mode**: HA with Raft integrated storage (3 replicas, 10Gi PVC per node)
- **Auth Method**: Kubernetes (ServiceAccount-based via TokenReview API)
- **Secrets Engine**: KV v2 at path `secret/`
- **Audit Logging**: Stdout audit device → Vector → VictoriaLogs. Enabled **best-effort** in the bootstrap (not fail-closed; `auditStorage` off) — durable/fail-closed audit is a production hardening item.
- **Bootstrap**: Idempotent Job — init, unseal, configure on each deploy
- **Seal**: Shamir (1-share) for Kind; AWS KMS / GCP KMS for EKS/GKE

### Secret Organization (Hybrid Strategy)

Secrets are organized using a **hybrid strategy** for maintainability and scalability:

| Category | Location | Mechanism | Rationale |
|----------|----------|-----------|-----------|
| **DB credentials** | `configs/databases/clusters/*/secrets/` | ExternalSecret | Co-located with the DB cluster they serve |
| **Pooler credentials** | `configs/databases/clusters/*/secrets/` | ExternalSecret | Co-located with the pooler they serve |
| **Backup credentials** | `configs/secrets/cluster-external-secrets/` | ClusterExternalSecret | Shared across the CloudNativePG cluster namespaces (product, auth, user) via namespace labels |
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

For the **full canonical KV catalog** (all paths currently seeded plus future-app placeholders) see [`openbao.md` §5.1 KV v2 — Static Secrets](./openbao.md#51-kv-v2--static-secrets).

> ⚠️ **`secret/local/infra/cloudflare/api-token`** (key `api_token`): on **local Kind** the `openbao-bootstrap` Job seeds a **dev placeholder** so the ExternalSecret syncs; on **prod** the real token is operator-supplied (not in Git) and re-seeded after every fresh cluster — see [Bootstrap-only secrets](#bootstrap-only-secrets) below.

---

## Kubernetes Secrets (ESO-managed)

### Naming Convention

ESO-managed secrets use the **same name** as the original secret they replace (e.g., `product-db-secret`). The `managed-by: external-secrets` label identifies OpenBAO-backed secrets. No `-vault` suffix is used.

### Database Secrets (ExternalSecret per cluster)

| K8s Secret | Namespace | Source |
|------------|-----------|--------|
| `platform-db-secret` | auth, platform | `secret/data/local/databases/auth-db/auth` (compat) |
| `platform-db-user-secret` | user, platform | `secret/data/local/databases/shared-db/user` (compat) |
| `platform-db-notification-secret` | notification, platform | `secret/data/local/databases/shared-db/notification` (compat) |
| `platform-db-shipping-secret` | shipping, platform | `secret/data/local/databases/shared-db/shipping` (compat) |
| `platform-db-review-secret` | review, platform | `secret/data/local/databases/shared-db/review` (compat) |
| `platform-db-temporal-secret` | temporal, platform | `secret/data/local/databases/platform-db/temporal` |
| `product-db-secret` | product | `secret/data/local/databases/product-db/product` |
| `product-db-cart-secret` | cart | `secret/data/local/databases/product-db/cart` |
| `product-db-order-secret` | order | `secret/data/local/databases/product-db/order` |
| `product-db-payment-secret` | product, payment | `secret/data/local/databases/product-db/payment` |

The `product-db-payment-secret` is materialised in **both** `product` (where the `payment` database/owner is created on `product-db`) and `payment` (where the payment service consumes it to connect direct-TLS to `product-db-rw`).

### Backup Secrets (ClusterExternalSecret)

Backup credentials use **ClusterExternalSecret** with namespace labels to auto-deploy to all namespaces that need them:

| ClusterExternalSecret | Label Selector | Target Namespaces | Key Format |
|----------------------|----------------|-------------------|------------|
| `pg-backup-rustfs-cnpg` | `platform.duynhlab/backup: "cnpg"` | platform, product | CNPG/Barman: `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` |

Since the Zalando→CNPG migration every cluster backs up via Barman, so `cnpg` is the
only backup label (the old WAL-G `pg-backup-rustfs-walg` / `backup: walg` mapping was removed).

**Adding backup credentials to a new namespace**: Add the label to the namespace in `kubernetes/infra/controllers/namespaces.yaml`:

```yaml
metadata:
  labels:
    platform.duynhlab/backup: "cnpg"   # CloudNativePG / Barman backup credentials
```

**ResourceSet namespaces**: Microservice namespaces are also created by Flux **ResourceSet** templates under [`kubernetes/apps/domains/`](../../kubernetes/apps/domains/). If the `Namespace` resource there omits `platform.duynhlab/backup`, app reconciliation can overwrite metadata and **drop** the label from `controllers/namespaces.yaml`, so ClusterExternalSecret **stops** matching and `pg-backup-rustfs-credentials` is not created. Keep the label in the ResourceSet `Namespace` block (now `cnpg` fleet-wide — set via `platform_backup_label` in the ResourceSetInputProvider where the domain hosts a CNPG cluster).

### Pooler Secrets

| K8s Secret | Namespace | Source | Status |
|------------|-----------|--------|--------|
| `pgdog-cnpg-credentials` | product | `secret/data/local/databases/pgdog-cnpg/credentials` | Available (not consumed) |

> **Note**: Pooler charts don't currently support `secretRef`. Secrets are created for future use.

### Infrastructure ExternalSecrets (per-namespace)

| K8s Secret | Namespace | Source path (OpenBAO) | Source key | K8s key |
|------------|-----------|-----------------------|------------|---------|
| `cloudflare-api-token` | `cert-manager` | `secret/data/local/infra/cloudflare/api-token` | `api_token` | `api-token` |
| `payment-webhook-hmac` | `payment` | `secret/data/local/services/payment/webhook-hmac` | `secret` | `secret` |

Defined at `kubernetes/infra/configs/secrets/cluster-external-secrets/cloudflare.yaml` (kind `ExternalSecret`, despite the directory name — the cert-manager ClusterIssuer only needs the Secret in one namespace). `payment-webhook-hmac` is defined at `kubernetes/infra/configs/secrets/payment-webhook-external-secrets.yaml` — the shared HMAC key mockpay signs webhooks with and payment verifies.

> **Note:** `secret/local/services/payment/webhook-hmac` follows the standard 4-level
> `secret/{env}/{category}/{service}/{resource}` hierarchy and sits inside the
> `eso-read` `local/services/*` grant. (It was briefly seeded at the 3-level
> `secret/local/payment/webhook-hmac` and renamed into convention.)

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

A few secrets are **operator-supplied on prod** — the real value is not in Git and must be re-applied after every fresh cluster. On **local Kind** the OpenBAO bootstrap script now seeds a **dev placeholder** for these so the platform comes up unattended:

| Path | Local Kind | Prod | Used by |
|---|---|---|---|
| `secret/local/infra/cloudflare/api-token` (key `api_token`) | Dev placeholder seeded by `openbao-bootstrap` (DNS-01 fails locally, which is fine — `kong-proxy-tls` is `homelab-ca`-signed) | Real token, operator-supplied, not in Git | cert-manager `letsencrypt-prod` / `letsencrypt-staging` ClusterIssuers → `kong-proxy-tls` **(prod only)** |

On local you rarely touch this. On prod, re-seed the real token with `bao kv put …` then reconcile downstream:

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

Long-term mitigation options under consideration: a local `~/.homelab/secrets.env` bootstrap script, and persisting the OpenBAO PVC across `make down` so the cluster keeps its seeded secrets.

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

Reviewer-JWT pitfall (commit `fb14349`) — root cause + runtime fix + persistent fix are documented in [Reviewer JWT auth failure](./runbooks/reviewer-jwt-auth-failure.md). General ESO sync checks live in [ESO sync failure](./runbooks/eso-sync-failure.md).

#### OpenBAO Sealed After Restart

See [OpenBAO unseal and stuck reconciliation](./runbooks/openbao-unseal.md).

---

## File Reference

See [`openbao.md` §File Reference](./openbao.md#16-file-reference) for the canonical list of OpenBAO + ESO + cert-manager files.

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

> **All phases below are planned, not deployed.** The current deployed state is in
> the [`README.md`](./README.md) current-state banner; the authoritative hardening
> scope is [RFC-0008](../proposals/rfc/RFC-0008/).

### Phase 1: Dynamic Database Secrets (planned)

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

- [OpenBAO Architecture](./openbao.md) — the canonical reference for OpenBAO internals
- [cert-manager](./cert-manager.md) — consumes the `cloudflare-api-token` Secret synced here
- [Trust Distribution](./trust-distribution.md) — distributes the homelab CA bundle
- [RFC-0008 — Production secrets hardening](../proposals/rfc/RFC-0008/) — EKS/GKE hardening + parity/testing matrix (+ [implementation.md](../proposals/rfc/RFC-0008/implementation.md))
- [Secrets proposals](../proposals/) — ADR-004/005 (audit, HA) + RFC backlog (rotation, PushSecret, hardening)
- [External Secrets Operator Docs](https://external-secrets.io/)
- [OpenBAO Docs](https://openbao.org/docs/)

---

_Last updated: 2026-07-17 — RFC-0018: platform-db secrets + backup label targets `platform` ns; product tier unchanged._
