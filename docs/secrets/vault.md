
# Vault Architecture & Bootstrap Guide

> **Scope**: Understanding the ephemeral nature of Vault Dev Mode and the role of the Bootstrap Job.

---

## 1. Why Vault Dev Mode?

We are currently running **hashicorp/vault** in **Dev Mode** (`server -dev`).

### Characteristics
-   **In-Memory Storage**: All data (secrets, policies, auth methods) is stored in RAM.
-   **Zero Persistence**: Restarting the Pod **wipes everything**.
-   **Auto-Unseal**: Starts automatically unsealed with a root token.

### The "Reset" Problem
When the Vault Pod restarts (e.g., deployment, crash, node scaling):
1.  Vault starts fresh.
2.  It generates a new Root Token (or uses a fixed one if configured).
3.  **It has NO configuration.**

---

## 2. The Role of `vault-bootstrap`

Since Dev Mode wipes configuration on restart, we need an automated way to restore the desired state. This is what the **`vault-bootstrap` Job** does.

It runs essentially as a "post-start hook" for the Vault service.

```mermaid
sequenceDiagram
    autonumber
    participant K8s as Kubernetes
    participant Vault as Vault (Dev Pod)
    participant Job as Vault-Bootstrap Job
    participant ESO as External Secrets Op
    
    note over Vault: Pod Restart (Memory Wiped)
    K8s->>Vault: Start Pod
    Vault->>Vault: Init Root Token (root)
    
    K8s->>Job: Start Job
    loop Wait for Ready
        Job->>Vault: NC/HTTP Check (8200)
        Vault-->>Job: OK
    end
    
    note over Job: Configuration Phase
    Job->>Vault: Login (Root Token)
    Job->>Vault: Enable K8s Auth
    Job->>Vault: Create Policy (external-secrets-read)
    Job->>Vault: Create Role (bind to K8s SA)
    Job->>Vault: Seed Secrets (secret/...)
    
    note over ESO: Sync Phase
    ESO->>Vault: Auth (via K8s SA)
    Vault-->>ESO: Token (Policy: external-secrets-read)
    ESO->>Vault: Read Secret
    Vault-->>ESO: Secret Data
    ESO->>K8s: Create K8s Secret
```

### What happens WITHOUT `vault-bootstrap`?

If you deploy Vault (Dev Mode) but DO NOT run this bootstrap script, you have a "zombie" Vault:

| Feature | Status | Impact |
| :--- | :--- | :--- |
| **Kubernetes Auth** | ❌ **Disabled** | Application Pods (via ESO) **cannot login**. |
| **Secrets Engine** | ❌ **Disabled** | Path `secret/` (KV v2) might not exist or be v1. |
| **Policies** | ❌ **Missing** | No `external-secrets-read` policy exists. |
| **Roles** | ❌ **Missing** | No `external-secrets` role to bind K8s SA to Policy. |

**Result**: External Secrets Operator (ESO) will fail to valid secretStores, and your applications will crash waiting for secrets.

---

## 3. Bootstrap Logic

The `kubernetes/infra/configs/secrets/vault-bootstrap/job.yaml` performs these steps idempotently:

1.  **Wait for Vault**: Loops until `vault status` returns success.
2.  **Enable Auth**: Turns on `auth/kubernetes`.
3.  **Configure Auth**: Points Vault to the K8s API server (`kubernetes.default.svc`).
4.  **Create Policy**: Adds `external-secrets-read` allowing read access to `secret/*`.
5.  **Create Role**: Binds the `external-secrets` K8s ServiceAccount to the policy.
6.  **Seed Secrets**: (Optional) Puts initial development secrets into `secret/` using the [path naming convention](./secrets-management.md#path-naming-convention): `secret/{env}/{category}/{service}/{resource}`.

---

## 4. Troubleshooting

### Job Status
The Job is managed by Flux and should run automatically.
```bash
kubectl get jobs -n vault
```

### Common Issues

#### "Read-only file system"
**Symptom**: Job fails with `failed to create /root/.vault-token`.
**Cause**: The container has `readOnlyRootFilesystem: true`, but `vault login` tries to write the token file.
**Fix**: Mount an `emptyDir` volume to `/home/vault` and set `HOME=/home/vault`.

#### "Vault not ready"
**Symptom**: Init container waits forever.
**Cause**: Vault Pod is not running or not reachable via Service `vault.vault.svc.cluster.local`.

---

## 5. Production vs. Dev

| Feature | Dev Mode (Current) | Production (Recommended) |
| :--- | :--- | :--- |
| **Storage** | RAM (Ephemeral) | Persistent Volume (PVC) or Consul/Raft |
| **Unseal** | Automatic (Root Token) | Manual or Auto-Unseal (AWS KMS/GCP KMS) |
| **Bootstrap** | **Required on every start** | Run once (config persists) |
| **Security** | Root token shared | Root token revoked, specific policies used |

---

## 6. Common Questions

### "Can I use a PVC (Persistent Volume) with Dev Mode?"
**No.**
By definition, `server -dev` runs entirely in memory. It ignores storage backends.
If you attach a PVC, Dev Mode simply won't use it.

### "How do I make Vault persistent?"
You must switch from **Dev Mode** to **Standalone Mode** (or HA).

**Standalone Mode** (Simple Persistence):
1.  Disable `server.dev.enabled`.
2.  Enable `server.dataStorage.enabled` (creates a PVC).
3.  **Trade-off**:
    *   Vault starts **Sealed**.
    *   You must manually **Initialize** (`vault operator init`) and **Unseal** (`vault operator unseal`) the first time.
    *   You get root token and unseal keys *once*.
    *   Data survives restarts (no need for `vault-bootstrap` creating secrets every time, but still need it for K8s auth config if you don't use Terraform).

---

## 7. Migration to Standalone (Persistence)

To upgrade from **Dev Mode** to **Standalone (Persistent)**, follow these steps:

### 1. Update HelmRelease
Modify `kubernetes/infra/controllers/secrets/vault/helmrelease.yaml`:
```yaml
    server:
      dev:
        enabled: false  # Disable Dev Mode
      dataStorage:
        enabled: true   # Enable PVC
        size: 10Gi
        storageClass: standard # Or your storage class
      standalone:
        enabled: true
```

### 2. Apply Changes
```bash
flux reconcile kustomization infrastructure-local --with-source
```
*Note: The existing Vault Pod will be terminated. All Dev Mode data will be lost.*

### 3. Initialize Vault
The new Vault Pod will start but not be ready (it is Sealed).
```bash
kubectl exec -it vault-0 -n vault -- vault operator init
```
**SAVE THE OUTPUT!** It contains 5 Unseal Keys and the Initial Root Token.

### 4. Unseal Vault
```bash
kubectl exec -it vault-0 -n vault -- vault operator unseal <Key-1>
kubectl exec -it vault-0 -n vault -- vault operator unseal <Key-2>
kubectl exec -it vault-0 -n vault -- vault operator unseal <Key-3>
```

### 5. Login
```bash
kubectl exec -it vault-0 -n vault -- vault login <Root-Token>
```

### 6. Run Bootstrap (Optional)
You can manually trigger the bootstrap job to configure Auth Methods, or configure them manually/Terraform one time (since they will now persist).

---

## 8. HA Mode with Raft (Production Scale)

For production environments with high availability requirements, deploy Vault with integrated Raft storage.

### Configuration

```yaml
server:
  dev:
    enabled: false
  ha:
    enabled: true
    replicas: 3
    raft:
      enabled: true
      config: |
        ui = true
        listener "tcp" {
          tls_disable = 0
          address = "[::]:8200"
          cluster_address = "[::]:8201"
          tls_cert_file = "/vault/userconfig/vault-tls/tls.crt"
          tls_key_file  = "/vault/userconfig/vault-tls/tls.key"
        }
        storage "raft" {
          path = "/vault/data"
          retry_join {
            leader_api_addr = "https://vault-0.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "https://vault-1.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "https://vault-2.vault-internal:8200"
          }
        }
        service_registration "kubernetes" {}
  dataStorage:
    enabled: true
    size: 10Gi
```

### Auto-Unseal (Eliminates Manual Key Management)

```yaml
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/vault-unseal"
}
```

Alternatives: GCP Cloud KMS (`seal "gcpckms"`), Azure Key Vault (`seal "azurekeyvault"`).

---

## 9. Dynamic Database Secrets (Future Direction)

Instead of static credentials seeded by the bootstrap Job, Vault's **database secrets engine** can generate short-lived credentials on demand. This is the approach used by Spotify and other large-scale platforms.

### How It Works

1. Vault connects to PostgreSQL as a privileged user
2. When ESO (or an app) requests credentials, Vault creates a temporary DB user
3. Credentials automatically expire after the configured TTL
4. No static passwords exist anywhere

### Example Configuration

```bash
vault secrets enable database

vault write database/config/cnpg-db \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@cnpg-db-rw.product:5432/product?sslmode=require" \
  allowed_roles="product-app" \
  username="vault_admin" \
  password="<admin-password>"

vault write database/roles/product-app \
  db_name=cnpg-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

### Benefits at Scale

- No password rotation needed (credentials are ephemeral)
- Each pod gets unique credentials (audit trail per pod)
- Credential revocation is instant (Vault drops the DB user)
- Works with 2000+ microservices without managing 2000 static passwords

