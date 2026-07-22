# Setup Guide - GitOps with Flux Operator

Comprehensive guide to deploying the microservices platform using **GitOps**, **Flux Operator**, and **Kustomize** on Kind (Kubernetes in Docker).

---

## Command Reference

### Quick Start (Makefile)

- **Bootstrap Environment**: `make up` (cluster-up + flux-push + flux-up — the OCI registry is pushed **before** the Flux bootstrap so the first reconcile finds the manifests)
- **Synchronize Changes**: `make sync` (flux-push + flux-sync)
- **Tear Down Environment**: `make down` (cluster-down)
- **Validate Manifests**: `make validate`

### Detailed Commands (Makefile)

- **Cluster Management**: `make cluster-up`, `make cluster-down`
- **Flux Operations**: `make flux-up`, `make flux-push`, `make flux-sync`, `make flux-status`, `make flux-logs`, `make flux-ui`
- **OpenTofu (Flux bootstrap)**: `make tf-init`, `make tf-plan`, `make tf-apply`, `make tf-destroy`
- **Utilities**: `make prereqs`, `make help`

---

## Workspace Configuration (Polyrepo)

Since the project utilizes a polyrepo architecture, you must clone all component repositories to facilitate local development.

### 1. Initialize Workspace Directory

```bash
mkdir -p ~/Working/duynhlab
cd ~/Working/duynhlab
```

### 2. Clone Repositories

Execute the following script to clone all required components:

```bash
# Infrastructure Repositories
git clone https://github.com/duynhlab/homelab.git
git clone https://github.com/duynhlab/gha-workflows.git
git clone https://github.com/duynhlab/pkg.git

# Microservices Repositories
for service in auth user product cart order review notification shipping payment checkout; do
  git clone https://github.com/duynhlab/${service}-service.git
done

# Frontend Repository
git clone https://github.com/duynhlab/frontend.git
git clone https://github.com/duynhlab/helm-charts.git
```

This creates a structured local environment with all necessary source code.

---

## Deployment Workflow

### Prerequisites

Before the first `make up`, one host-side prerequisite must be in place:

1. **`/etc/hosts` entries for `*.duynh.me`** — Kong runs as NodePort and Kind maps host ports 80/443. Use the helper:
   ```bash
   sudo ./scripts/setup-hosts.sh           # adds the marker block
   sudo ./scripts/setup-hosts.sh remove    # cleans it up
   ```

On **local Kind** that is enough: the `clusters/local` overlay patches the `kong-proxy-tls` Certificate to the self-signed **`homelab-ca`** issuer, so Kong terminates HTTPS with a self-signed wildcard (expect a browser warning unless `homelab-ca` is trusted). **No Cloudflare token or Let's Encrypt is needed locally.**

**Prod only — Cloudflare API token in OpenBAO:** on prod the `letsencrypt-prod` ClusterIssuer uses Cloudflare DNS-01 to issue a publicly-trusted wildcard `*.duynh.me` cert. That token is **bootstrap-only** (not in Git) and must be re-seeded after every fresh cluster:
   ```bash
   ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)
   kubectl exec -n openbao openbao-0 -- sh -c \
     "BAO_TOKEN=$ROOT bao kv put secret/local/infra/cloudflare/api-token api_token=cfut_..."
   flux reconcile ks secrets-local --with-source
   flux reconcile ks cert-manager-local --with-source
   ```
   ESO syncs the token to `Secret/cloudflare-api-token` in the `cert-manager` namespace via `kubernetes/infra/configs/secrets/cluster-external-secrets/cloudflare.yaml`. Without it, the `letsencrypt-*` issuers stay NotReady on prod — but this is **not** a local bring-up blocker (`homelab-ca` issues `kong-proxy-tls` locally).

---

### Step 1: Provision Kind Cluster

```bash
make cluster-up
```

**Actions Performed:**
- Initializes a local OCI registry (`localhost:5050`).
- Provisions a 4-node Kubernetes cluster named `homelab`.
- Establishes network connectivity between the registry and the Kind cluster.

**Verification:**
```bash
kubectl cluster-info
kubectl get nodes
docker ps | grep homelab-registry
```

---

### Step 2: Publish Manifests to the OCI Registry

```bash
make flux-push
```

**Actions Performed:**
- Publishes three OCI artifacts to the local registry:
  - `flux-cluster-sync:local` (Source: `kubernetes/clusters/local/`)
  - `flux-infra-sync:local` (Source: `kubernetes/infra/`)
  - `flux-apps-sync:local` (Source: `kubernetes/apps/`)

**Verification:**
```bash
docker ps | grep homelab-registry   # registry serving the pushed artifacts
```

---

### Step 3: Bootstrap Flux Operator

```bash
make flux-up
```

**Actions Performed:**
- Runs `tofu init` + `tofu apply` in `terraform/` (the
  `controlplaneio-fluxcd/flux-operator-bootstrap` module).
- A bootstrap `Job` installs the Flux Operator and applies the `FluxInstance`
  from `kubernetes/clusters/local/flux-system/instance.yaml`.
- Flux then adopts those resources and reconciles steady-state.
- Awaits readiness of the `FluxInstance` / Flux controllers.
- Flux then reconciles the pushed artifacts in dependency order:
  - **Phase 1: Foundation** — `controllers-local`: namespaces + operators (cert-manager, CNPG, VictoriaMetrics/Grafana operators, OpenBAO + ESO, Kyverno, temporal-operator, ClickHouse operator).
  - **Phase 2: Security & configs** — `secrets-local` (bootstrap Job + ClusterSecretStore + ExternalSecrets), `cert-manager-local`, `monitoring-local` (observability configs + Sloth SLO CRs).
  - **Phase 3: Platform services** — Kong, Valkey, RustFS, tracing/profiling, ClickHouse, databases, Temporal.
  - **Phase 4: Applications** — `apps-local`: ResourceSets + standalone workers (`order-worker`, `checkout-worker`, `mockpay`).

> OpenTofu owns only the ephemeral bootstrap mechanism; re-running `make flux-up`
> with unchanged manifests is a no-op (`make tf-plan` shows zero diff). See
> [`terraform/README.md`](../../terraform/README.md).

**Verification:**
```bash
kubectl get pods -n flux-system
make flux-status
flux get kustomizations --watch
```

**Estimated Duration:** 5-10 minutes.

---

### Step 4: Validate Deployment

```bash
make flux-status
```

**Resource Inspection:**
```bash
# Verify ResourceSet Status
kubectl get resourcesets -A

# Inspect auto-generated HelmReleases
kubectl get helmrelease -A

# Verify SLO configuration
kubectl get prometheusservicelevel -n monitoring
```

**Expected State:**
- Namespaces for every domain provisioned (auth, user, product, cart, **checkout**, order, review, notification, shipping, payment, frontend, **platform**, **product**, **cache-system**, **rustfs**, kong, cert-manager, openbao, external-secrets-system, monitoring, cloudnative-pg, database, kyverno, flux-system, **temporal**, …).
- 5 ResourceSets (`rs-identity`, `rs-catalog`, `rs-checkout`, `rs-comms`, `rs-frontend`) successfully reconciled.
- HelmReleases for the **10 microservices** + frontend, plus **`mockpay`**, **`order-worker`**, and **`checkout-worker`** (in the `payment` / `order` / `checkout` namespaces), in `Ready` state.
- 3 CloudNativePG clusters (`platform-db`, `product-db`, `product-db-replica`) operational.
- ClusterIssuers `selfsigned-bootstrap`, `homelab-ca`, `letsencrypt-staging`, `letsencrypt-prod` Ready; `kong-proxy-tls` Certificate Ready — signed by `homelab-ca` on local Kind (`letsencrypt-prod` on prod).

---

## Accessing Services

All user-facing endpoints go through Kong on `*.duynh.me` (on local Kind, terminated with the self-signed `homelab-ca` wildcard — expect a browser warning; prod uses the Let's Encrypt wildcard). Make sure `scripts/setup-hosts.sh` has been run.

| Service | URL | Credentials |
|---------|-----|-------------|
| Frontend (React SPA) | https://local.duynh.me | alice / password123 |
| API Gateway | https://gateway.duynh.me | JWT from `/auth/v1/public/auth/login` |
| Grafana | https://grafana.duynh.me | admin / admin |
| VictoriaMetrics UI | https://vmui.duynh.me | - |
| Jaeger UI | https://jaeger.duynh.me | - |
| VictoriaTraces UI | https://victoriatraces.duynh.me | - |
| VictoriaLogs UI | https://logs.duynh.me | - |
| Flux UI | https://ui.duynh.me | - |
| OpenBAO UI | https://openbao.duynh.me | root token from `openbao-init-keys` secret |

The full host inventory lives in `scripts/setup-hosts.sh` and `docs/platform/kong-gateway.md`.

---

## Seed Data & Demo Accounts

### Overview

All services include seed data via golang-migrate `000002_*.up.sql` migrations for immediate demo/local/dev functionality. Seed data is automatically loaded during database initialization.

### Demo Users

5 test users are available for authentication:

| User | Email | Password | Purpose |
|------|-------|----------|---------|
| Alice Johnson | `alice@example.com` | `password123` | Active shopper (2 orders, cart items) |
| Bob Smith | `bob@example.com` | `password123` | Cart only, no orders yet |
| Carol White | `carol@example.com` | `password123` | Frequent reviewer |
| David Brown | `david@example.com` | `password123` | Recent order with tracking |
| Eve Davis | `eve@example.com` | `password123` | Inactive user |

**Login Example** (login binds `username`, not `email`):
```bash
curl -X POST http://localhost:8080/auth/v1/public/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "password123"}'
```

### Seeded Data Summary

| Service | Table | Records | Description |
|---------|-------|---------|-------------|
| **Product** | `products` | 8 | Electronics, peripherals, accessories |
| **Product** | `categories` | 4 | Electronics, Computers, Accessories, Peripherals |
| **Auth** | `users` | 5 | Demo users with bcrypt-hashed passwords |
| **User** | `user_profiles` | 5 | Complete profiles with addresses |
| **Cart** | `cart_items` | 5 | Alice (3 items), Bob (2 items) |
| **Order** | `orders` | 5 | Mix of pending/completed/shipped |
| **Order** | `order_items` | 8 | Order line items |
| **Review** | `reviews` | 12 | Product reviews (3-5 stars) |
| **Notification** | `notifications` | 8 | Order/shipping/promo notifications |
| **Shipping** | `shipments` | 3 | USPS, FedEx, UPS tracking |

### Data Relationships

Cross-service references use fixed IDs for consistency:

```mermaid
flowchart TD
    AuthUsers["auth.users (IDs: 1-5)"]
    ProductProducts["product.products (IDs: 1-8)"]

    UserProfiles["user.user_profiles"]
    CartItems["cart.cart_items"]
    Orders["order.orders"]
    Reviews["review.reviews"]
    Notifications["notification.notifications"]

    OrderItems["order.order_items"]
    Shipments["shipping.shipments"]

    %% Top-down: sources -> consumers
    AuthUsers -->|user_id| UserProfiles
    AuthUsers -->|user_id| CartItems
    AuthUsers -->|user_id| Orders
    AuthUsers -->|user_id| Reviews
    AuthUsers -->|user_id| Notifications

    ProductProducts -->|product_id| CartItems
    ProductProducts -->|product_id| Reviews
    ProductProducts -->|product_id| OrderItems

    %% Orders -> downstream relations
    Orders -->|order_id| OrderItems
    Orders -->|order_id| Shipments
```

### Example Seeded Products

| ID | Name | Price | Category | Stock |
|----|------|-------|----------|-------|
| 1 | Wireless Mouse | $29.99 | Electronics | 50 |
| 2 | Mechanical Keyboard | $79.99 | Peripherals | 30 |
| 3 | USB-C Hub | $39.99 | Computers | 25 |
| 4 | Laptop Stand | $44.99 | Accessories | 40 |
| 5 | Webcam HD | $59.99 | Electronics | 20 |
| 6 | Monitor 24" | $149.99 | Electronics | 15 |
| 7 | Gaming Headset | $89.99 | Accessories | 35 |
| 8 | External SSD 1TB | $99.99 | Computers | 18 |

### Alice's Cart (Example)

```json
{
  "user_id": 1,
  "items": [
    {"product_id": 1, "product_name": "Wireless Mouse", "quantity": 2, "price": 29.99},
    {"product_id": 2, "product_name": "Mechanical Keyboard", "quantity": 1, "price": 79.99},
    {"product_id": 5, "product_name": "Webcam HD", "quantity": 1, "price": 59.99}
  ],
  "subtotal": 169.97,
  "shipping": 5.00,
  "total": 174.97
}
```

### Idempotency

All seed migrations use `ON CONFLICT DO NOTHING` to safely handle:
- Pod restarts
- Re-running migrations
- Multiple deployments

**Safe to restart services** - Seed data won't be inserted twice.

### Environment Configuration

**Local/Dev/Demo**: ✅ Seed data enabled (default)  
**UAT**: ⚠️ Optional (configure via golang-migrate target version)  
**Production**: ❌ Disabled (use golang-migrate target or separate migration path)

### Migration Files

Seed data located in each service:

```
{service}-service/db/migrations/sql/
├── 000001_init_schema.up.sql   # Schema creation
└── 000002_seed_{service}.up.sql # Demo data
```

**golang-migrate Execution**: 000001 → 000002 (automatic via the `migrate` subcommand, no manual intervention)

### Verification

```bash
# Check products
curl http://localhost:8080/product/v1/public/products

# Login as Alice (login binds username, not email)
TOKEN=$(curl -X POST http://localhost:8080/auth/v1/public/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "password123"}' \
  | jq -r '.access_token')

# Check Alice's cart
curl http://localhost:8080/cart/v1/private/cart \
  -H "Authorization: Bearer $TOKEN"

# Check Alice's orders
curl http://localhost:8080/order/v1/private/orders \
  -H "Authorization: Bearer $TOKEN"
```


---

## Project Architecture

```
homelab/
├── kubernetes/
│   ├── infra/                          # Core infrastructure definitions
│   │   ├── controllers/                # Operators and CRD definitions (Flux wave 1)
│   │   │   ├── namespaces.yaml         # Cluster-wide namespace definitions
│   │   │   ├── metrics/                # VictoriaMetrics + Grafana + Sloth operators
│   │   │   ├── logging/                # VictoriaLogs operator
│   │   │   ├── databases/              # CloudNativePG operator
│   │   │   ├── secrets/                # OpenBAO + External Secrets Operator HelmReleases
│   │   │   ├── cert-manager/
│   │   │   ├── clickhouse-operator/    # Altinity ClickHouse operator (CRDs)
│   │   │   ├── temporal/               # Temporal operator
│   │   │   └── kyverno/
│   │   │   # tracing/, profiling/, caching/, storage/, kong/ — separate Flux Kustomizations
│   │   ├── configs/                    # Component instances and configurations
│   │   │   ├── observability/          # Metrics, logging, tracing, Grafana, Sloth SLO CRs
│   │   │   ├── databases/              # PostgreSQL clusters and PgDog poolers
│   │   │   ├── secrets/                # Bootstrap Job, ClusterSecretStore, ExternalSecrets
│   │   │   ├── cert-manager/           # ClusterIssuers, kong-proxy-tls Certificate
│   │   │   └── kong/                   # KongClusterPlugins + Ingress routes
│   │   └── kustomization.yaml
│   ├── apps/                           # Application definitions (Hybrid ResourceSet)
│   │   ├── domains/                    # Domain ResourceSets (template + inputsFrom selector)
│   │   │   ├── identity-rs.yaml        # rs-identity: auth, user
│   │   │   ├── catalog-rs.yaml         # rs-catalog: product, review
│   │   │   ├── checkout-rs.yaml        # rs-checkout: cart, checkout, order, payment
│   │   │   └── comms-rs.yaml           # rs-comms: notification, shipping
│   │   ├── services/                   # Per-service InputProviders (Static)
│   │   │   ├── auth.yaml               # domain=identity
│   │   │   ├── user.yaml               # domain=identity
│   │   │   ├── product.yaml            # domain=catalog
│   │   │   ├── review.yaml             # domain=catalog
│   │   │   ├── cart.yaml               # domain=checkout
│   │   │   ├── checkout.yaml           # domain=checkout
│   │   │   ├── order.yaml              # domain=checkout
│   │   │   ├── payment.yaml            # domain=checkout
│   │   │   ├── notification.yaml       # domain=comms
│   │   │   └── shipping.yaml           # domain=comms
│   │   ├── mockpay.yaml                # mockpay HelmRelease (payment ns)
│   │   ├── order-worker.yaml           # order-worker HelmRelease (order ns, Temporal saga)
│   │   ├── checkout-worker.yaml        # checkout-worker HelmRelease (checkout ns)
│   │   └── frontend-rs.yaml            # rs-frontend (standalone, namespace: frontend)
│   └── clusters/                       # Environment-specific Flux configurations
│       └── local/                      # Kind local environment (20 Kustomization CRs — see kustomization.yaml)
│           ├── flux-system/            # Bootstrap FluxInstance resource
│           ├── sources/                # OCI and Helm source definitions
│           ├── controllers.yaml        # Operator orchestration
│           ├── secrets.yaml            # Secrets bootstrap configs
│           ├── cert-manager-config.yaml
│           ├── kong.yaml / kong-config.yaml
│           ├── caching.yaml / storage.yaml
│           ├── clickhouse.yaml / tracing.yaml / profiling.yaml
│           ├── databases.yaml / databases-cnpg-dr.yaml
│           ├── monitoring.yaml / kyverno.yaml / network-policies.yaml
│           ├── mcp.yaml / temporal.yaml / apps.yaml
│           └── kustomization.yaml
├── Makefile                            # Centralized automation entrypoint
└── scripts/                            # Implementation logic for automation tasks
```

**Dependency Graph:**
1. `controllers-local`: Provisions namespaces and operators (cert-manager, CNPG, VictoriaMetrics/Grafana/Sloth, OpenBAO + ESO **HelmReleases**, Kyverno, temporal-operator, ClickHouse operator). **Does not** install Kong or Tempo/Pyroscope (those are separate Kustomizations to avoid deadlocks).
2. `secrets-local`: Applies `./configs/secrets` — OpenBAO bootstrap Job, ClusterSecretStore, ExternalSecrets (depends on `controllers-local` for the OpenBAO/ESO operators).
3. `cert-manager-local`: ClusterIssuers (`selfsigned-bootstrap`, `homelab-ca`, `letsencrypt-staging`, `letsencrypt-prod`), `kong-proxy-tls` Certificate, trust-manager Bundle (depends on `controllers-local`, `secrets-local` — needs the synced `cloudflare-api-token` Secret on prod).
4. `kong-local`: Kong HelmRelease (depends on `cert-manager-local` — mounts `kong-proxy-tls` Secret as a volume).
5. `kong-config-local`: KongClusterPlugins + Ingress resources for every host (depends on `kong-local`, `cert-manager-local`).
6. `monitoring-local`: Observability **configs** — Grafana dashboards, VMAlert rules, Sloth **PrometheusServiceLevel** CRs (depends on `controllers-local`; Sloth **operator** is in `controllers-local`).
7. `storage-local`: Provisions RustFS (S3) object storage (depends on `controllers-local`, `secrets-local`).
7a. `caching-local`: Valkey (product cache-aside db 0 + Kong rate-limit counters db 1) (depends on `controllers-local`, `monitoring-local`).
8. `network-policies-local`: Per-namespace NetworkPolicies (depends on `controllers-local`).
8a. `clickhouse-local`: ClickHouse OLAP for OTel logs+traces SQL (depends on `controllers-local`, `secrets-local`).
9. `tracing-local`: Tempo + Jaeger + OTel Collector configs (depends on `secrets-local`, `storage-local`, **`clickhouse-local`** — collector `create_schema` needs ClickHouse up first).
10. `profiling-local`: Pyroscope (depends on `secrets-local`, `storage-local`).
11. `cnpg-barman-plugin-local`: CNPG Barman Cloud Plugin + `ObjectStore` CRD (depends on `controllers-local`, `cert-manager-local`).
12. `databases-local`: CNPG `platform-db` and `product-db` clusters (depends on `secrets-local`, `monitoring-local`, `cnpg-barman-plugin-local`, `storage-local`, `network-policies-local`).
13. `databases-cnpg-dr-local`: CNPG DR replica (depends on `databases-local`, `secrets-local`).
14. `temporal-local`: Temporal server (`TemporalCluster` + `TemporalNamespace`), persistence on `platform-db-rw.platform:5432` (depends on `controllers-local`, `cert-manager-local`, `databases-local`, `monitoring-local`).
15. `kyverno-policies-local`: Admission policies (depends on `controllers-local`, `monitoring-local`). See [kyverno.md](kyverno.md).
15a. `mcp-local`: MCP servers (depends on `monitoring-local`). See [mcp-servers.md](mcp-servers.md).
16. `apps-local`: Business logic — ResourceSets + workers (`dependsOn` `databases-local`, `monitoring-local`, `temporal-local`; workers dial Temporal at startup).

> **`make flux-sync` caveat:** `scripts/flux-sync.sh` reconciles only six Kustomizations
> (`flux-system`, `controllers-local`, `databases-local`, `monitoring-local`,
> `secrets-local`, `apps-local`). It does **not** force Kong, Temporal, ClickHouse,
> tracing, or cert-manager. After changes to those layers, run
> `flux reconcile kustomization <name>-local --with-source` or `make sync` after
> `make flux-push` and reconcile the specific Kustomization manually.

---

For detailed API specifications, refer to [api.md](../api/api.md).  
For persistence layer details, refer to [002-database-integration.md](../databases/002-database-integration.md).

---

_Last updated: 2026-07-22 — 10 microservices + checkout-worker; Flux graph adds clickhouse-local; secrets-local vs controllers-local split; configs/observability paths; make flux-sync caveat._