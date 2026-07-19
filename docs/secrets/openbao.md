# OpenBAO Architecture

> **Status**: Migration target — replacing HashiCorp Vault (Dev Mode) with OpenBAO HA
>
> **Scope**: OpenBAO internals, current local Kind behavior, and production-target learning notes.

> ### ⚠ Current deployment state vs. planned
>
> Much of this guide describes the **production target**. What the local Kind
> cluster **actually runs today**:
>
> | Capability | Deployed now (local Kind) | Planned for prod |
> |---|---|---|
> | Storage / HA | ✅ OpenBAO HA, 3-node Raft, PVC | same |
> | App secret delivery | ✅ ESO + **KV v2 static** secrets (`refreshInterval: 1h`) | + dynamic DB creds |
> | Auth (ESO) | ✅ Kubernetes auth, least-privilege `eso-read` policy | + OIDC for humans |
> | Audit | ⚠ `file → stdout` **best-effort** (enablement is not fail-closed; `auditStorage` off) | durable, fail-closed |
> | **Database secrets engine / dynamic creds** | ❌ **not enabled** — §5.2, §6, §10, §14 describe the *planned* design | enable DB engine |
> | Unseal | ❌ **Shamir key + root token in a K8s Secret** (`openbao-init-keys`), re-read by a 60s unsealer CronJob | KMS / Transit auto-unseal |
> | TLS | ❌ disabled (`tlsDisable: true`; plaintext HTTP in-cluster) | TLS via cert-manager |
> | Credentials | ❌ dev passwords **seeded from Git** (e.g. `*-K1nd-2026!`) | generated / dynamic, none in Git |
> | Root token | ❌ persisted, **not revoked** after bootstrap | revoked; OIDC / AppRole |
>
> **These local-only choices are unsafe for production.** The hardening path and a
> local-vs-prod parity/testing matrix live in [RFC-0008](../proposals/rfc/RFC-0008/).
> Any section below describing dynamic credentials, leases, OIDC, or auto-unseal is
> **planned**, not deployed.

---

## 1. What Is OpenBAO?

**OpenBAO** is an open-source fork of HashiCorp Vault, created after the BSL license change in 2023. It is:

- **Apache 2.0 licensed** — truly open-source, no enterprise licensing concerns
- **API-compatible with Vault** — ESO, Kubernetes auth, all existing patterns carry over unchanged
- **CNCF Sandbox project** under the OpenSSF
- **Drop-in replacement** — rename `vault` CLI to `bao`, same REST API paths (`/v1/...`)
- **Actively maintained** — this repo currently deploys OpenBAO 2.5.x via the OpenBAO Helm chart

### Why Migrate from Vault Dev Mode

| Problem | Vault Dev Mode | OpenBAO Production |
|---------|---------------|-------------------|
| Data persistence | ❌ In-memory, lost on restart | ✅ Raft PVC, survives reboots |
| Unseal | ❌ Always unsealed with root token | ✅ Auto-unseal via KMS / Transit |
| TLS | ❌ HTTP only | ✅ TLS everywhere |
| High availability | ❌ Single node | ✅ 3-node Raft cluster |
| Root token | ❌ Static `root` in Git | ✅ Revoked after init, operator access via OIDC |
| DB credentials | ❌ Static `postgres/postgres` | ✅ Dynamic, TTL-based, per-service |
| Multi-environment | ❌ One flat namespace | ✅ Namespaces: `local/`, `staging/`, `prod/` |
| License | ❌ BSL (non-OSS) | ✅ Apache 2.0 |

> This table is the canonical **Vault → OpenBAO** comparison (the legacy
> `vault.md` dev-mode doc has been retired). The decision and the rejected
> alternatives are recorded in
> [ADR-005](../proposals/adr/ADR-005-openbao-ha-raft/); the dev-vs-prod
> seal/TLS/credential tradeoffs and how to close them are in
> [RFC-0008](../proposals/rfc/RFC-0008/) and the current-state banner above.

---

## 2. OpenBAO Runtime Architecture

The diagram below summarizes the **logical** HA stack: traffic enters via the
in-cluster service, three Raft peers form the quorum, each peer persists Raft
state to PVCs, and ESO syncs OpenBAO-backed values into Kubernetes Secrets.

### High-Level Overview

```mermaid
flowchart TD
    subgraph external["External Access"]
        devteam["Dev Team\n(OIDC: GitHub / Google)"]
        datateam["Data Team\n(OIDC: GitHub / Google)"]
        cicd["CI/CD\n(GitHub Actions AppRole)"]
    end

    subgraph k8s["Kubernetes Cluster"]
        subgraph openbao_ns["Namespace: openbao"]
            subgraph raft["OpenBAO HA — Raft Cluster (3 nodes)"]
                bao0["openbao-0\nActive / Leader"]
                bao1["openbao-1\nStandby"]
                bao2["openbao-2\nStandby"]
                bao0 <-->|"Raft replication\nport 8201 (TLS planned)"| bao1
                bao0 <-->|"Raft replication\nport 8201 (TLS planned)"| bao2
            end

            subgraph engines["Secret Engines"]
                kv["KV v2: secret/\nInfra, backup, pooler creds"]
                db["Database: database/\nDynamic PostgreSQL creds"]
                transit["Transit: transit/\nEncryption + auto-unseal"]
                audit["Audit: file → stdout\nVector → VictoriaLogs"]
            end

            subgraph authmethods["Auth Methods"]
                k8sauth["kubernetes/\nFor ESO service accounts"]
                oidcauth["oidc/\nFor human operators"]
                approle["approle/\nFor CI/CD pipelines"]
            end
        end

        subgraph eso_ns["Namespace: external-secrets-system"]
            eso["External Secrets Operator\nv2.5.0"]
            css["ClusterSecretStore\nopenbao"]
        end

        subgraph app_ns["App Namespaces (product, cart, order, auth, ...)"]
            es["ExternalSecret\n/ ClusterExternalSecret"]
            k8ssecret["Kubernetes Secret\n(managed-by: external-secrets)"]
            appod["Application Pod\nreads env/volume"]
        end

        subgraph db_ns["Database Namespaces"]
            platformdb["platform-db\n(CloudNativePG)"]
            productdb["product-db\n(CloudNativePG)"]
        end
    end

    subgraph autounseal["Unseal"]
        kind_unseal["openbao-unsealer CronJob (local Kind)\nre-reads Shamir key from Secret, every minute"]
        eks_kms["AWS KMS\n(EKS / Production)"]
        gke_kms["GCP Cloud KMS\n(GKE / Production)"]
    end

    external --> k8sauth
    external --> oidcauth
    cicd --> approle
    raft --> engines
    raft --> authmethods
    css --> eso
    eso --> es
    es --> k8ssecret
    k8ssecret --> appod
    eso --> css
    css --> raft
    db --> platformdb
    db --> productdb
    autounseal --> raft
```

### Raft Cluster Internals

```mermaid
sequenceDiagram
    autonumber
    participant Client as Client (ESO / Human)
    participant Active as openbao-0 (Active)
    participant Standby1 as openbao-1 (Standby)
    participant Standby2 as openbao-2 (Standby)
    participant Raft as Raft Log (PVC)

    Client->>Active: HTTPS :8200 — read/write request
    Active->>Raft: Append log entry
    Active->>Standby1: Replicate (port 8201)
    Active->>Standby2: Replicate (port 8201)
    Standby1-->>Active: ACK
    Standby2-->>Active: ACK
    Active-->>Client: Response

    note over Standby1,Standby2: Reads forwarded to Active\nvia request forwarding (TLS)

    note over Active: If Active crashes:
    Standby1->>Standby2: Leader election
    Standby1->>Raft: Becomes new Active
```

---

## 3. Seal / Unseal Architecture

Unsealing is the process of decrypting the root key so OpenBAO can serve requests. OpenBAO always starts **sealed**.

### Shamir vs Auto-Unseal

```mermaid
flowchart LR
    subgraph shamir["Shamir Seal (production ceremony)"]
        sk["Unseal Key\nsplit into 5 shards\nthreshold: 3"]
        op1["Operator 1\n(holds shard 1)"]
        op2["Operator 2\n(holds shard 2)"]
        op3["Operator 3\n(holds shard 3)"]
        op1 & op2 & op3 -->|"bao operator unseal"| sk
        sk --> bao_s["OpenBAO Unsealed"]
    end

    subgraph autounseal_kms["Auto-Unseal (EKS/GKE Production)"]
        kms["AWS KMS / GCP KMS\n(key never leaves KMS)"]
        env["IRSA / Workload Identity\n(no static credentials)"]
        kms --> env --> bao_a["OpenBAO Auto-Unseals\non pod start"]
    end

    subgraph autounseal_local["Automated Unseal (local Kind)"]
        unseal_secret["Shamir key: 1 share, threshold 1\nin K8s Secret openbao-init-keys"]
        unsealer_cron["openbao-unsealer CronJob\n(runs every minute)"]
        unseal_secret --> unsealer_cron --> bao_t["HA Cluster re-unsealed\nafter any restart"]
    end
```

### Unseal Key Management (Init Ceremony)

On first initialization, unseal keys should be split with PGP to prevent any single operator knowing the full key:

```bash
# Production ceremony: 5 shares, threshold 3, each encrypted to a different operator's PGP key
bao operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -pgp-keys="keybase:devops1,keybase:devops2,keybase:devops3,keybase:devops4,keybase:devops5" \
  -root-token-pgp-key="keybase:devops-lead"

# Local Kind (learning): 1 share, 1 threshold, store in 1Password
bao operator init -key-shares=1 -key-threshold=1
```

> **Critical**: After bootstrap is complete, revoke the root token. Operators use OIDC for day-to-day access.

---

## 4. Authentication Methods

### Overview

```mermaid
flowchart TD
    subgraph consumers["Consumers"]
        eso_sa["ESO ServiceAccount\nexternal-secrets/external-secrets-system"]
        dev["Developer\n(GitHub / Google SSO)"]
        data["Data Analyst\n(GitHub / Google SSO)"]
        devops["DevOps Engineer\n(GitHub / Google SSO — admin)"]
        gha["GitHub Actions\n(CI/CD pipeline)"]
    end

    subgraph authmethods["OpenBAO Auth Methods"]
        k8sauth["Kubernetes Auth\nauth/kubernetes/\nValidates K8s SA tokens\nvia TokenReview API"]
        oidcauth["OIDC Auth\nauth/oidc/\nGitHub OAuth / Google Workspace\nGroup claims → policies"]
        approlauth["AppRole Auth\nauth/approle/\nrole_id + secret_id\nfor CI/CD automation"]
    end

    subgraph policies["Policies Issued"]
        p_eso["eso-read\nread secret/{data,metadata}/local/{databases,infra,services,auth}/*\nread database/creds/*"]
        p_dev_rw["dev-team-rw\nread/write dev KV\ndynamic DB creds (rw)"]
        p_data_ro["data-team-ro\ndynamic DB creds (ro only)"]
        p_admin["devops-admin\nfull access"]
        p_cicd["cicd-deploy\nwrite deploy artifacts\nno DB access"]
    end

    eso_sa --> k8sauth --> p_eso
    dev --> oidcauth --> p_dev_rw
    data --> oidcauth --> p_data_ro
    devops --> oidcauth --> p_admin
    gha --> approlauth --> p_cicd
```

### Kubernetes Auth — ESO Integration

ESO authenticates to OpenBAO using its Kubernetes ServiceAccount token. OpenBAO validates the token against the Kubernetes TokenReview API.

```mermaid
sequenceDiagram
    autonumber
    participant ESO as ESO Pod
    participant K8s as Kubernetes API (TokenReview)
    participant BAO as OpenBAO

    ESO->>ESO: Read own SA token\n/var/run/secrets/kubernetes.io/serviceaccount/token
    ESO->>BAO: POST /v1/auth/kubernetes/login\n{role: "eso-reader", jwt: "<SA token>"}
    BAO->>K8s: POST /apis/authentication.k8s.io/v1/tokenreviews\n{token: "<SA token>"}
    K8s-->>BAO: TokenReview response\n{authenticated: true, serviceaccount: "external-secrets"}
    BAO->>BAO: Verify bound_service_account_names\nVerify bound_service_account_namespaces
    BAO-->>ESO: Vault token\n{policies: ["eso-read"], ttl: "1h"}
    ESO->>BAO: GET /v1/secret/data/local/databases/product-db/product\nAuthorization: Bearer <token>
    BAO-->>ESO: Secret data
    ESO->>K8s: Create/Update K8s Secret
```

> ⚠️ **Reviewer-JWT pitfall (commit `fb14349`)** — When configuring `auth/kubernetes/config`, **omit** `token_reviewer_jwt` and set `disable_local_ca_jwt=false`. OpenBAO will then call `TokenReview` using its own pod's auto-rotated SA token (long-lived projected token, refreshed by kubelet).
>
> If you instead pass `token_reviewer_jwt=@/var/run/secrets/.../token` from the bootstrap Job's pod, that token is bound by `BoundServiceAccountTokenVolume` to ~1 h. After it expires every login fails with `permission denied` and ESO breaks platform-wide. See [Reviewer JWT auth failure](./runbooks/reviewer-jwt-auth-failure.md) for the runtime recovery procedure.

### OIDC Auth — Developer / Data Team

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Developer (CLI)
    participant BAO as OpenBAO
    participant GitHub as GitHub OIDC
    participant PG as PostgreSQL

    Dev->>BAO: bao login -method=oidc role="dev-team"
    BAO-->>Dev: Open browser: https://github.com/login/oauth/authorize?...
    Dev->>GitHub: Authorize (SSO)
    GitHub-->>BAO: ID token (claims: groups=[engineering])
    BAO->>BAO: groups claim → Identity Group "dev-team"\nAssign policy: dev-team-rw
    BAO-->>Dev: Vault token (TTL: 8h, policy: dev-team-rw)
    Dev->>BAO: bao read database/creds/product-app-rw
    BAO->>PG: CREATE ROLE "v-k8s-product-app-rw-1711584000"\nWITH LOGIN PASSWORD '...' VALID UNTIL '...'
    BAO-->>Dev: {username: "v-k8s-product-app-rw-...", password: "Xk9mN3..."}
    Dev->>PG: psql -U v-k8s-product-app-rw-1711584000 -d product
    note over Dev,PG: Credentials auto-expire after 8h\nAudit log tracks every access
```

---

## 5. Secret Engines

### 5.1 KV v2 — Static Secrets

Used for infrastructure credentials that cannot be dynamic (S3 backup keys, pooler admin users).

**Path structure** (unchanged from current Vault convention):

```
secret/{environment}/{category}/{service}/{resource}
```

| Environment | KV path prefix | Use |
|-------------|----------------|-----|
| `local` | `secret/local/` | Kind cluster |
| `staging` | `secret/staging/` | Staging environment |
| `prod` | `secret/prod/` | EKS / GKE production |

**Current KV paths** (seeded at bootstrap):

| Path | Keys | Consumer |
|------|------|---------|
| `secret/local/databases/auth-db/auth` | `username`, `password` | platform-db auth owner (compat path) |
| `secret/local/databases/shared-db/user` | `username`, `password` | platform-db user owner (compat path) |
| `secret/local/databases/shared-db/notification` | `username`, `password` | platform-db notification owner (compat path) |
| `secret/local/databases/shared-db/shipping` | `username`, `password` | platform-db shipping owner (compat path) |
| `secret/local/databases/shared-db/review` | `username`, `password` | platform-db review owner (compat path) |
| `secret/local/databases/platform-db/temporal` | `username`, `password` | platform-db temporal owner (Temporal server) |
| `secret/local/databases/product-db/product` | `username`, `password` | CNPG bootstrap owner |
| `secret/local/databases/product-db/cart` | `username`, `password` | CNPG cart owner |
| `secret/local/databases/product-db/order` | `username`, `password` | CNPG order owner |
| `secret/local/databases/product-db/payment` | `username`, `password` | CNPG payment owner (consumed in `product` + `payment` ns) |
| `secret/local/databases/pgdog-cnpg/credentials` | `username`, `password` | PgDog pooler admin |
| `secret/local/services/payment/webhook-hmac` | `secret` | payment ↔ mockpay webhook HMAC (shared signing key) |
| `secret/local/auth/jwt-signing` | `private_key`, `public_key` | RS256 access-token keypair — auth signer (private → ns `auth`) + Kong edge JWT (public → ns `kong`); see [JWT signing key](#jwt-signing-key-auth--kong) |
| `secret/local/infra/rustfs/backup-cnpg` | `access_key_id`, `secret_access_key` | Barman S3 (all CloudNativePG clusters — bucket `pg-backups-cnpg`) |
| `secret/local/infra/cloudflare/api-token` ⚠️ | `api_token` | cert-manager `letsencrypt-{staging,prod}` ClusterIssuers (DNS-01 solver) — **prod only**; on local Kind `kong-proxy-tls` is `homelab-ca`-issued |

> **Note — `secret/local/services/payment/webhook-hmac`**: follows the standard 4-level `secret/{env}/{category}/{service}/{resource}` structure and is covered by the existing `eso-read` `local/services/*` grant. (It was briefly seeded at the 3-level `secret/local/payment/webhook-hmac`, which sat outside every `eso-read` prefix; renaming it into `local/services/*` fixed both the convention and the RBAC scope.)

> ⚠️ **Local vs prod**: on **local Kind** `openbao-bootstrap` **now seeds a dev placeholder** (`dev-cloudflare-placeholder`) so the `cloudflare-api-token` ExternalSecret syncs and doesn't block `secrets-local` (DNS-01 fails locally, which is fine — `kong-proxy-tls` is `homelab-ca`-issued). On **prod** the real token is **operator-supplied** and **not** in Git — re-seed after every fresh cluster — see [OpenBAO initial setup](./runbooks/openbao-initial-setup.md#step-7--seed-bootstrap-only-cloudflare-token-operator).

#### JWT signing key (auth + Kong)

The RS256 access-token keypair is a single OpenBAO secret,
`secret/local/auth/jwt-signing` (`private_key` + `public_key`), that **ESO fans out
to two consumers** — the private half signs, the public half verifies at the edge:

```mermaid
flowchart LR
  KV[("OpenBAO<br/>secret/local/auth/jwt-signing<br/>private_key + public_key")]
  ES1["ExternalSecret auth-jwt-signing<br/>(ns auth · private_key)"]
  ES2["ExternalSecret auth-issuer-jwt<br/>(ns kong · public_key)"]
  AUTH["auth<br/>JWT_PRIVATE_KEY_PEM<br/>signs iss/aud/kid"]
  KONG["Kong jwt-edge<br/>auth-issuer consumer cred<br/>verify RS256 by iss"]
  KV --> ES1 --> AUTH
  KV --> ES2 --> KONG

  classDef external fill:#64748b,color:#fff,stroke:#334155;
  classDef service fill:#06b6d4,color:#082f49,stroke:#0e7490;
  classDef edge fill:#2563eb,color:#fff,stroke:#1e3a8a;
  class KV external; class ES1,ES2,AUTH service; class KONG edge;
```

| ExternalSecret | Namespace | Property | Consumer |
|---|---|---|---|
| `auth-jwt-signing` | `auth` | `private_key` | auth env `JWT_PRIVATE_KEY_PEM` — signs access tokens (`iss=https://gateway.duynh.me`, `aud=duynhlab-platform`, `kid`) |
| `auth-issuer-jwt` | `kong` | `public_key` | rendered as a Kong `jwt` credential (`key=https://gateway.duynh.me`, `algorithm=RS256`, `rsa_public_key`) on the `auth-issuer` `KongConsumer` |

**Verification is two-layer.** Kong's `jwt-edge` plugin (on `/private/` routes) looks
up the credential **by the token's `iss` claim** (`key_claim_name: iss`) and checks the
RS256 signature + `exp` — Kong holds only the public key. Each service's `pkg/authmw`
then re-verifies the full token (audience, `nbf`, …) against auth's cached JWKS
(`/auth/v1/public/auth/jwks`) and is authoritative. Contract detail:
[auth service API](../api/auth.md); edge detail: [Kong gateway](../platform/kong-gateway.md).

**Rotation.** Because Kong verifies against the statically provisioned public key (Kong
OSS `jwt` can't fetch a JWKS), the key is dual-target — rotate **both** ExternalSecrets:

1. Write a new keypair to `secret/local/auth/jwt-signing` (both `private_key` + `public_key`).
2. Both ExternalSecrets re-sync (`refreshInterval`); force with `kubectl annotate externalsecret … force-sync=$(date +%s)` if needed.
3. **Restart auth** so it loads the new `JWT_PRIVATE_KEY_PEM`; Kong reloads the new `auth-issuer-jwt` credential automatically.
4. Overlap window: tokens signed by the old key keep validating until their `exp` — keep the old public key alongside the new one until the longest-lived token expires, or accept a short reject window. A JWKS refresh alone only covers the services, **not** Kong's edge credential.

> Path note: this ships at `secret/local/auth/jwt-signing`; [RFC-0009](../proposals/rfc/RFC-0009/) references a pre-implementation `secret/data/<env>/apps/auth/jwt-signing` — the deployed path is the one above.

### 5.2 Database Secrets Engine — Dynamic Credentials

> **⚠ Planned — not yet deployed.** The bootstrap enables only KV v2, Kubernetes
> auth, and audit; the database secrets engine is **not** enabled. Application
> credentials today are **static KV v2** values. This section describes the
> production design (tracked in [RFC-0008](../proposals/rfc/RFC-0008/)).

The **database secrets engine** would generate short-lived, unique PostgreSQL credentials on demand, so no static application passwords need exist.

#### How It Works

```mermaid
sequenceDiagram
    autonumber
    participant ESO as External Secrets Operator
    participant BAO as OpenBAO (Database Engine)
    participant PG as PostgreSQL (product-db)
    participant App as Application Pod

    note over ESO,App: Every 1h refresh (before the lease expires)

    ESO->>BAO: GET /v1/database/creds/product-app-rw\n(using K8s auth token)
    BAO->>PG: CREATE ROLE "v-k8s-product-app-rw-1711584000"\nWITH LOGIN PASSWORD 'Xk9mN3pQ...'\nVALID UNTIL '2026-03-27T15:00:00Z'
    BAO->>BAO: Record lease_id (TTL: 1h)\nSchedule revocation at expiry
    BAO-->>ESO: {username: "...", password: "...", lease_id: "...", ttl: "1h"}
    ESO->>K8s: Update K8s Secret product-db-product-creds
    App->>K8s: Mount secret (env/volume)
    App->>PG: Connect with new credentials

    note over BAO,PG: On previous lease expiry:
    BAO->>PG: DROP ROLE "v-k8s-product-app-rw-<old-ts>"
    note over PG: Old user automatically removed
```

#### Database Connection Configuration

```mermaid
flowchart LR
    subgraph cnpg_setup["product-db Connection Setup (one-time)"]
        vault_admin["vault_admin user\n(created in PG with CREATEROLE)\nstored as static role\nin OpenBAO"]
        db_engine["OpenBAO Database Engine\ndatabase/config/product-db\nconnection_url: postgres://...\nallowed_roles: *-app-rw, *-readonly"]
        vault_admin --> db_engine
    end

    subgraph roles["Dynamic Roles (per database)"]
        r1["product-app-rw\nCREATE, SELECT, INSERT,\nUPDATE, DELETE\nTTL: 1h / max: 24h"]
        r2["product-readonly\nSELECT only\nTTL: 8h / max: 24h"]
        r3["cart-app-rw\nTTL: 1h"]
        r4["order-app-rw\nTTL: 1h"]
    end

    subgraph consumers2["Consumers"]
        eso2["ESO → App Pods\n(via ExternalSecret)"]
        dev2["Developers\n(bao read database/creds/...)"]
        data2["Data Team\n(bao read database/creds/*-readonly)"]
    end

    db_engine --> r1 & r2 & r3 & r4
    r1 & r3 & r4 --> eso2
    r1 & r2 & r3 & r4 --> dev2
    r2 --> data2
```

#### Role SQL Templates

**Read-Write role** (application service):
```sql
-- Creation statement (executed by OpenBAO when credential requested)
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
GRANT CONNECT ON DATABASE product TO "{{name}}";
GRANT USAGE ON SCHEMA public TO "{{name}}";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "{{name}}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "{{name}}";

-- Revocation statement (executed by OpenBAO on lease expiry)
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM "{{name}}";
DROP ROLE IF EXISTS "{{name}}";
```

**Read-only role** (data team / analytics):
```sql
-- Creation statement
CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
GRANT CONNECT ON DATABASE product TO "{{name}}";
GRANT USAGE ON SCHEMA public TO "{{name}}";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "{{name}}";

-- Revocation statement
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM "{{name}}";
DROP ROLE IF EXISTS "{{name}}";
```

---

## 6. Database Credential Workflows

> **⚠ Mixed state.** The `cart`/`order` owners are still created with hardcoded
> passwords in CNPG `postInitSQL` (`instance.yaml`). An ExternalSecret for those
> creds exists but is effectively **bypassed** — the same password is duplicated in
> Git, so it is not a single source of truth and rotating it in OpenBAO would not
> change the DB user. The "OpenBAO Solution" column below is the **planned** target;
> dynamic application users are not yet enabled.

### 6.1 Current State Problems

```mermaid
flowchart TD
    subgraph problem["Current Issues"]
        p1["❌ cart + order users\ncreated with hardcoded\nPASSWORD 'postgres'\nin postInitSQL"]
        p2["❌ All passwords = 'postgres'\nNo differentiation"]
        p3["❌ No rotation\nPasswords never change"]
        p4["❌ No team access\nDevs need DBA access\nto connect to DB"]
    end

    subgraph solution["OpenBAO Solution"]
        s1["✅ cart + order owners\nbacked by ExternalSecret\n(KV v2 static)"]
        s2["✅ Application users\nare dynamic (1h TTL)\nv-k8s-{role}-{ts}"]
        s3["✅ Auto-rotation\nESO refreshes (1h)\nOld user dropped"]
        s4["✅ Team access\nDev team gets 8h creds\nData team gets read-only"]
    end

    p1 -->|"Fix: CNPG managed.roles"| s1
    p2 -->|"Fix: DB Engine + password policy"| s2
    p3 -->|"Fix: Lease TTL + static role rotation"| s3
    p4 -->|"Fix: OIDC + dynamic roles"| s4
```

### 6.2 Database User Architecture

```mermaid
erDiagram
    POSTGRESQL_CLUSTER {
        string name
        string operator
        string version
    }

    DB_OWNER {
        string username
        string purpose "DDL + golang-migrate migrations"
        string managed_by "KV v2 static (ESO)"
        string rotation "90 days static role"
    }

    APP_USER {
        string username "v-k8s-{svc}-app-rw-{ts}"
        string purpose "Application read/write"
        string managed_by "DB Engine dynamic"
        string ttl "1h / max 24h"
    }

    READONLY_USER {
        string username "v-k8s-{svc}-readonly-{ts}"
        string purpose "Data team / analytics"
        string managed_by "DB Engine dynamic"
        string ttl "8h / max 24h"
    }

    MONITOR_USER {
        string username "{svc}_monitor"
        string purpose "pg_stat metrics only"
        string managed_by "KV v2 static"
        string rotation "manual"
    }

    POSTGRESQL_CLUSTER ||--o{ DB_OWNER : "1 per database"
    POSTGRESQL_CLUSTER ||--o{ APP_USER : "1 per service pod"
    POSTGRESQL_CLUSTER ||--o{ READONLY_USER : "per team member session"
    POSTGRESQL_CLUSTER ||--o{ MONITOR_USER : "1 per exporter"
```

### 6.3 CloudNativePG (product-db) — Credential Flow

```mermaid
sequenceDiagram
    autonumber
    participant Flux as Flux (GitOps)
    participant BAO as OpenBAO
    participant ESO as ESO
    participant CNPG as CloudNativePG Operator
    participant PG as PostgreSQL

    note over Flux,PG: Bootstrap Phase (cluster creation)

    Flux->>ESO: Apply ExternalSecret product-db-secret\n(namespace: product)
    ESO->>BAO: Read secret/local/databases/product-db/product\n{username: product_owner, password: <strong>}
    ESO->>K8s: Create K8s Secret product-db-secret
    Flux->>CNPG: Apply Cluster product-db\nbootstrap.initdb.secret: product-db-secret
    CNPG->>PG: CREATE DATABASE product OWNER product_owner
    CNPG->>PG: CREATE DATABASE cart OWNER cart_owner  (via managed.roles)
    CNPG->>PG: CREATE DATABASE "order" OWNER order_owner (via managed.roles)

    note over Flux,PG: Runtime Phase (ESO → dynamic creds)

    ESO->>BAO: GET /v1/database/creds/product-app-rw
    BAO->>PG: CREATE ROLE "v-k8s-product-app-rw-{ts}" ...
    BAO-->>ESO: {username, password, lease_id, ttl: 1h}
    ESO->>K8s: Update Secret product-db-product-app-creds

    note over Flux,PG: Rotation (every 1h refresh)

    ESO->>BAO: GET /v1/database/creds/product-app-rw  (fresh)
    BAO->>PG: CREATE ROLE "v-k8s-product-app-rw-{new_ts}"
    BAO-->>ESO: New credentials
    ESO->>K8s: Update Secret
    BAO->>PG: DROP ROLE "v-k8s-product-app-rw-{old_ts}"  (on old lease expiry)
```

### 6.4 CloudNativePG (`platform-db`, `product-db`) — Credential Strategy

Every cluster now runs on **CloudNativePG**, so credentials follow the same ESO-first
pattern everywhere: owner/role passwords come from OpenBAO KV v2, synced by ESO, and
each service's role + database are declared with the **RFC-0012 triplet** (`ExternalSecret`
+ `DatabaseRole` + `Database`) that the operator applies. There are no operator-generated
credential secrets to reconcile against.

> **Historical:** the retired Zalando operator managed its own K8s secrets
> (`{user}.{cluster}.credentials.postgresql.acid.zalan.do`). The former `auth-db`,
> `shared-db`, and `temporal-db` clusters were consolidated into **`platform-db`**
> (RFC-0018). OpenBAO keeps **compat paths** `auth-db/*` and `shared-db/*` for app
> credentials; Temporal uses the new path `platform-db/temporal`.

```mermaid
flowchart LR
    subgraph cnpg_platform["platform-db (CloudNativePG)"]
        p_auth["auth owner\n(compat: auth-db/auth)"]
        p_shared["user / notification /\nshipping / review owners\n(compat: shared-db/*)"]
        p_temporal["temporal owner\n(platform-db/temporal)"]
        p_roles["service role(s)\n(RFC-0012 triplet:\nDatabaseRole + Database)"]
    end

    subgraph cnpg_product["product-db (CloudNativePG)"]
        prod_owners["product / cart / order / payment owners\n(ExternalSecret → KV v2)"]
        prod_roles["service role(s)\n(RFC-0012 triplet:\nDatabaseRole + Database)"]
    end

    subgraph management["Management"]
        eso_mgr["ESO\nsyncs owner creds from OpenBAO KV v2"]
        cnpg_op["CloudNativePG Operator\napplies Database + DatabaseRole CRDs"]
    end

    eso_mgr --> p_auth & p_shared & p_temporal & prod_owners
    cnpg_op --> p_roles & prod_roles
```

---

## 7. ESO Integration

### ClusterSecretStore (target shape — TLS is planned, RFC-0008)

> **Deployed reality:** the local store uses `server: "http://openbao.openbao.svc.cluster.local:8200"`
> with no `caBundle` (`kubernetes/infra/configs/secrets/cluster-secret-store.yaml` — OpenBAO runs
> `tlsDisable: true` locally). The `https` + `caBundle` shape below is the RFC-0008 target.
> Multi-env isolation is by **KV path prefix** (`secret/local/…`), not an OpenBAO namespace —
> OpenBAO (OSS) has no Enterprise-style namespaces feature.

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: openbao
spec:
  provider:
    vault:
      server: "https://openbao.openbao.svc.cluster.local:8200"  # planned (RFC-0008); http:// today
      path: "secret"
      version: "v2"
      caBundle: <base64-ca-cert>   # cert-manager issued CA (planned with TLS)
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-reader"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets-system
```

### ExternalSecret Pattern (Static KV)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: product-db-secret
  namespace: product
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: openbao
    kind: ClusterSecretStore
  target:
    name: product-db-secret
    creationPolicy: Owner
    deletionPolicy: Retain
    template:
      type: Opaque
      metadata:
        labels:
          cnpg.io/reload: "true"    # Triggers CNPG to reload on rotation
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/local/databases/product-db/product
        property: username
    - secretKey: password
      remoteRef:
        key: secret/data/local/databases/product-db/product
        property: password
```

### ESO Sync Flow

```mermaid
flowchart TD
    subgraph eso_flow["ESO Reconciliation Loop"]
        trigger["Timer: refreshInterval elapsed\n(default: 1h)"]
        auth["Authenticate to OpenBAO\nvia K8s SA token → Vault token"]
        read["Read secret from OpenBAO\n(KV or dynamic DB creds)"]
        compare["Compare hash with\nexisting K8s Secret"]
        update["Update K8s Secret\n(if changed)"]
        reload["Trigger reload label\n(cnpg.io/reload: true)"]
        nochange["No-op\n(secret unchanged)"]
    end

    trigger --> auth --> read --> compare
    compare -->|"Changed"| update --> reload
    compare -->|"Same"| nochange
```

---

## 8. Policies

Policies follow the principle of **least privilege**. No wildcard access in production.

### Policy Hierarchy

```mermaid
flowchart TD
    root_policy["root policy\n(initial setup only — then revoked)"]

    subgraph human["Human Access Policies"]
        devops_admin["devops-admin\nFull read/write all namespaces\nManage auth methods, policies\nUsed by: DevOps team via OIDC"]
        dev_rw["dev-team-rw\nRead/write secret/local/services/*\nRead database/creds/*-app-rw\nRead database/creds/*-readonly\nUsed by: Developers via OIDC"]
        data_ro["data-team-ro\nRead database/creds/*-readonly only\nUsed by: Data analysts via OIDC"]
    end

    subgraph service["Service Policies"]
        eso_read["eso-read\nRead secret/{data,metadata}/local/{databases,infra,services,auth}/*\nRead database/creds/*-app-rw\nUsed by: ESO K8s auth role"]
        svc_product["service-product\nRead database/creds/product-app-rw\nUsed by: product SA (future direct auth)"]
    end

    subgraph cicd["CI/CD Policies"]
        cicd_deploy["cicd-deploy\nWrite secret/local/cicd/*\nRead secret/local/infra/*\nNo database access\nUsed by: GitHub Actions AppRole"]
    end

    root_policy -.->|"revoked after bootstrap"| devops_admin
    devops_admin & dev_rw & data_ro & eso_read & svc_product & cicd_deploy
```

### Policy Syntax Example

```hcl
# eso-read: ESO service account policy (scoped paths, not wildcard)
path "secret/data/local/databases/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/local/databases/*" {
  capabilities = ["read", "list"]
}
path "secret/data/local/infra/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/local/infra/*" {
  capabilities = ["read", "list"]
}
path "secret/data/local/services/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/local/services/*" {
  capabilities = ["read", "list"]
}
# auth/* — auth JWT signing-key ExternalSecrets (RFC-0009 Phase 4 edge JWT)
path "secret/data/local/auth/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/local/auth/*" {
  capabilities = ["read", "list"]
}
# Dynamic DB credentials (planned — DB engine not yet enabled)
path "database/creds/*-app-rw" {
  capabilities = ["read"]
}

# dev-team-rw: Developer policy with identity templating
path "secret/data/local/services/{{identity.entity.name}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "database/creds/*-app-rw" {
  capabilities = ["read"]
}
path "database/creds/*-readonly" {
  capabilities = ["read"]
}
```

---

## 9. Multi-Environment (KV Path Prefixes)

OpenBAO OSS has **no namespaces** (that is an Enterprise feature — consistent with §7). Multiple environments share a single instance, isolated by **KV v2 path prefixes** under one `secret/` mount (`secret/{environment}/…`) plus scoped policies. A single ESO `ClusterSecretStore` (`openbao`) targets that mount.

```mermaid
flowchart TD
    subgraph instance["Single OpenBAO Instance — secret/ (KV v2 mount)"]
        local_p["secret/local/…\nDev secrets, local values"]
        staging_p["secret/staging/…\nStaging values (future)"]
        prod_p["secret/prod/…\nProduction secrets (future EKS/GKE)"]
    end

    subgraph auth["Auth + Policies"]
        k8s_auth["K8s Auth\n(SA tokens)"]
        policies["Scoped policies\n(per-prefix read paths)"]
    end

    subgraph eso_store["ESO ClusterSecretStore"]
        css["ClusterSecretStore: openbao\n(single store, all prefixes)"]
    end

    k8s_auth --> policies --> instance
    instance --> css
```

---

## 10. Lease, Renewal, and Revocation

Every dynamic credential in OpenBAO has a **lease** — a time-bounded grant to the secret.

```mermaid
stateDiagram-v2
    [*] --> Issued : bao read database/creds/product-app-rw
    Issued --> Active : App uses credentials
    Active --> Renewed : ESO renews each 1h refresh (before lease expiry)
    Renewed --> Active : New TTL reset to 1h
    Active --> Expired : TTL elapsed (not renewed)
    Expired --> Revoked : OpenBAO auto-revokes
    Active --> Revoked : bao lease revoke <lease-id>\n(incident response)
    Revoked --> [*] : DROP ROLE in PostgreSQL
    note right of Expired : OpenBAO drops the PG user
    note right of Revoked : Immediate — DB user gone\nwithin seconds
```

### Lease Commands

```bash
# List all active leases for a role
bao list sys/leases/lookup/database/creds/product-app-rw/

# Inspect a specific lease
bao lease lookup database/creds/product-app-rw/<lease-id>

# Renew a lease manually (normally done by ESO)
bao lease renew database/creds/product-app-rw/<lease-id>

# Revoke a single lease (compromised credential)
bao lease revoke database/creds/product-app-rw/<lease-id>

# Revoke ALL leases for a role (incident response — all apps get new creds on next refresh)
bao lease revoke -prefix database/creds/product-app-rw/
```

---

## 11. Password Policies

Custom password policies enforce strength requirements for all dynamically generated credentials.

```hcl
# Policy: db-strong (applied to all DB engine roles)
length = 32

rule "charset" {
  charset   = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 4
}
rule "charset" {
  charset   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 4
}
rule "charset" {
  charset   = "0123456789"
  min-chars = 4
}
rule "charset" {
  charset   = "!@#%^&*()-_=+"
  min-chars = 2
}
```

Apply to a database role:
```bash
bao write database/roles/product-app-rw \
  db_name=product-db \
  password_policy="db-strong" \
  creation_statements="..." \
  default_ttl="1h" \
  max_ttl="24h"
```

---

---

## Operations And Runbooks

Operational commands are kept out of this architecture document so the learning material stays readable. Use these task-focused runbooks:

| Task | Runbook |
|---|---|
| Bootstrap a fresh local OpenBAO deployment | [Initial setup](./runbooks/openbao-initial-setup.md) |
| Recover sealed OpenBAO pods or a stuck `secrets-local` reconciliation | [Unseal and stuck reconciliation](./runbooks/openbao-unseal.md) |
| Diagnose ESO sync failures | [ESO sync failure](./runbooks/eso-sync-failure.md) |
| Recover the 1-hour Kubernetes reviewer JWT failure | [Reviewer JWT auth failure](./runbooks/reviewer-jwt-auth-failure.md) |
| Save or restore a Raft snapshot | [Raft snapshot and restore](./runbooks/raft-snapshot-restore.md) |
| Rotate static KV v2 secrets | [Rotate static secret](./runbooks/rotate-static-secret.md) |
| Revoke credentials after compromise | [Revoke compromised credential](./runbooks/revoke-compromised-credential.md) |

## 16. File Reference

### Infrastructure Files

| File | Purpose |
|------|---------|
| `kubernetes/infra/controllers/secrets/openbao/helmrelease.yaml` | OpenBAO HA Helm chart |
| `kubernetes/infra/controllers/secrets/external-secrets/helmrelease.yaml` | ESO HelmRelease |
| `kubernetes/infra/configs/secrets/openbao-bootstrap/` | Init scripts (phased) |
| `kubernetes/infra/configs/secrets/cluster-secret-store.yaml` | ClusterSecretStore (openbao) |
| `kubernetes/infra/configs/secrets/cluster-external-secrets/` | ClusterExternalSecret definitions |
| `kubernetes/infra/configs/secrets/cluster-external-secrets/cloudflare.yaml` | `ExternalSecret` (per-namespace) for cert-manager DNS-01 — file lives in CES dir but is `kind: ExternalSecret` since cert-manager only needs the Secret in one namespace |
| `kubernetes/infra/configs/databases/clusters/*/secrets/` | Per-cluster ExternalSecret definitions |

### Helm Sources

| File | Purpose |
|------|---------|
| `kubernetes/clusters/local/sources/helm/openbao.yaml` | OpenBAO Helm repository |
| `kubernetes/clusters/local/sources/helm/external-secrets.yaml` | ESO Helm repository |

---

## 17. Migration from Vault Dev Mode

### Phase Checklist

```mermaid
gantt
    title Migration from Vault Dev → OpenBAO Production
    dateFormat  YYYY-MM-DD
    section Phase 0: Prep
    cert-manager ClusterIssuer        :p0a, 2026-04-01, 2d
    Design + review policies          :p0b, 2026-04-01, 3d
    section Phase 1: Deploy OpenBAO HA
    Deploy 3-node Raft cluster        :p1a, after p0b, 2d
    Initialize + unseal               :p1b, after p1a, 1d
    Run bootstrap scripts             :p1c, after p1b, 1d
    section Phase 2: Migrate ESO
    Create ClusterSecretStore openbao :p2a, after p1c, 1d
    Migrate ClusterExternalSecrets    :p2b, after p2a, 1d
    Migrate DB ExternalSecrets        :p2c, after p2b, 2d
    section Phase 3: Dynamic Creds
    Configure DB engine + roles       :p3a, after p2c, 3d
    Fix CNPG postInitSQL passwords    :p3b, after p3a, 2d
    Update ExternalSecrets → dynamic  :p3c, after p3b, 2d
    section Phase 4: Team Access
    OIDC auth + Identity groups       :p4a, after p3c, 2d
    Dev + data team workflows         :p4b, after p4a, 1d
    section Phase 5: Decommission
    Remove vault-dev ClusterSecretStore :p5a, after p4b, 1d
    Delete Vault HelmRelease          :p5b, after p5a, 1d
```

---

## 18. Related Documentation

- [RFC-0008 — Production secrets hardening](../proposals/rfc/RFC-0008/) (+ [implementation.md](../proposals/rfc/RFC-0008/implementation.md) — feature selection, architecture, DB redesign, install phases)
- [Secrets Management](./secrets-management.md) — ESO patterns, path conventions, operations
- [cert-manager](./cert-manager.md) — Certificate issuers and `kong-proxy-tls` wildcard pipeline
- [Trust Distribution](./trust-distribution.md) — trust-manager `homelab-ca-bundle` distribution
- [Secrets proposals](../proposals/) — ADR-004/005 (audit, HA) + RFC backlog (rotation, PushSecret, hardening)
- [OpenBAO Documentation](https://openbao.org/docs)
- [OpenBAO Helm Chart](https://openbao.org/docs/platform/k8s/helm)
- [External Secrets Operator](https://external-secrets.io/)
- [CloudNativePG External Secrets Integration](https://cloudnative-pg.io/docs/1.28/cncf-projects/external-secrets)

---

_Last updated: 2026-07-17 — Split from `docs/secrets/README.md`; RFC-0018 platform-db paths and compat OpenBAO layout._