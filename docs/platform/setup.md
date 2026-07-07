# Setup Guide - GitOps with Flux Operator

Comprehensive guide to deploying the microservices platform using **GitOps**, **Flux Operator**, and **Kustomize** on Kind (Kubernetes in Docker).

---

## Command Reference

### Quick Start (Makefile)

- **Bootstrap Environment**: `make up` (cluster-up + flux-up + flux-push)
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
for service in auth user product cart order review notification shipping payment; do
  git clone https://github.com/duynhlab/${service}-service.git
done

# Frontend Repository
git clone https://github.com/duynhlab/frontend.git
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

### Step 2: Bootstrap Flux Operator

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

> OpenTofu owns only the ephemeral bootstrap mechanism; re-running `make flux-up`
> with unchanged manifests is a no-op (`make tf-plan` shows zero diff). See
> [`terraform/README.md`](../../terraform/README.md).

**Verification:**
```bash
kubectl get pods -n flux-system
```

---

### Step 3: Deploy Infrastructure and Applications

```bash
make flux-push
```

**Actions Performed:**
- Publishes three OCI artifacts to the local registry:
  - `flux-cluster-sync:local` (Source: `kubernetes/clusters/local/`)
  - `flux-infra-sync:local` (Source: `kubernetes/infra/`)
  - `flux-apps-sync:local` (Source: `kubernetes/apps/`)

- The Flux Operator reconciles resources in the following dependency order:
  - **Phase 1: Foundation** - Namespaces and Operators (Controllers).
  - **Phase 2: Security & Monitoring** - OpenBAO/ESO, Grafana/Prometheus.
  - **Phase 3: Data Layer** - PostgreSQL Clusters.
  - **Phase 4: Applications** - Microservices (managed via ResourceSet).
  - **Phase 5: Reliability** - SLO tracking via Sloth.

**Verification:**
```bash
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
- Namespaces for every domain provisioned (auth, user, product, cart, order, review, notification, shipping, payment, frontend, kong, cert-manager, openbao, external-secrets-system, monitoring, apm, databases-cnpg-system, databases-zalando, kyverno, flux-system, …).
- 5 ResourceSets (`rs-identity`, `rs-catalog`, `rs-checkout`, `rs-comms`, `rs-frontend`) successfully reconciled.
- HelmReleases for the 9 microservices + frontend, plus the `mockpay` and `order-worker` releases (in the `payment` / `order` namespaces), in `Ready` state.
- 3 PostgreSQL clusters (`auth-db`, `supporting-shared-db`, `cnpg-db`) + 1 DR replica (`cnpg-db-replica`) operational.
- ClusterIssuers `selfsigned-bootstrap`, `homelab-ca`, `letsencrypt-staging`, `letsencrypt-prod` Ready; `kong-proxy-tls` Certificate Ready — signed by `homelab-ca` on local Kind (`letsencrypt-prod` on prod).

---

## Accessing Services

All user-facing endpoints go through Kong on `*.duynh.me` (on local Kind, terminated with the self-signed `homelab-ca` wildcard — expect a browser warning; prod uses the Let's Encrypt wildcard). Make sure `scripts/setup-hosts.sh` has been run.

| Service | URL | Credentials |
|---------|-----|-------------|
| Frontend (React SPA) | https://local.duynh.me | alice / password123 |
| API Gateway | https://gateway.duynh.me | JWT from `/auth/v1/public/login` |
| Grafana | https://grafana.duynh.me | admin / admin |
| VictoriaMetrics UI | https://vmui.duynh.me | - |
| Jaeger UI | https://jaeger.duynh.me | - |
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
curl -X POST http://localhost:8080/auth/v1/public/login \
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
TOKEN=$(curl -X POST http://localhost:8080/auth/v1/public/login \
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
│   │   ├── controllers/                # Operators and CRD definitions
│   │   │   ├── namespaces.yaml         # Cluster-wide namespace definitions
│   │   │   ├── monitoring/             # Prometheus and Grafana operators
│   │   │   ├── databases/              # Database orchestration operators
│   │   │   └── slo/                    # Service Level Objective operator
│   │   ├── configs/                    # Component instances and configurations
│   │   │   ├── monitoring/             # Grafana resources and ServiceMonitors
│   │   │   ├── apm/                    # APM stack (Tempo, Pyroscope)
│   │   │   ├── databases/              # PostgreSQL clusters and poolers
│   │   │   └── slo/                    # SLO definitions (PrometheusServiceLevel)
│   │   └── kustomization.yaml
│   ├── apps/                           # Application definitions (Hybrid ResourceSet)
│   │   ├── domains/                    # Domain ResourceSets (template + inputsFrom selector)
│   │   │   ├── identity-rs.yaml        # rs-identity: auth, user
│   │   │   ├── catalog-rs.yaml         # rs-catalog: product, review
│   │   │   ├── checkout-rs.yaml        # rs-checkout: cart, order, payment
│   │   │   └── comms-rs.yaml           # rs-comms: notification, shipping
│   │   ├── services/                   # Per-service InputProviders (Static)
│   │   │   ├── auth.yaml               # domain=identity
│   │   │   ├── user.yaml               # domain=identity
│   │   │   ├── product.yaml            # domain=catalog
│   │   │   ├── review.yaml             # domain=catalog
│   │   │   ├── cart.yaml               # domain=checkout
│   │   │   ├── order.yaml              # domain=checkout
│   │   │   ├── payment.yaml            # domain=checkout
│   │   │   ├── notification.yaml       # domain=comms
│   │   │   └── shipping.yaml           # domain=comms
│   │   ├── mockpay.yaml                # mockpay HelmRelease (payment ns, same image)
│   │   ├── order-worker.yaml           # order-worker HelmRelease (order ns, Temporal saga)
│   │   └── frontend-rs.yaml            # rs-frontend (standalone, namespace: frontend)
│   └── clusters/                       # Environment-specific Flux configurations
│       └── local/                      # Kind-specific local environment
│           ├── flux-system/            # Bootstrap FluxInstance resource
│           ├── sources/                # OCI and Helm source definitions
│           ├── controllers.yaml       # Operator orchestration
│           ├── secrets.yaml            # Secrets management orchestration
│           ├── monitoring.yaml         # Observability stack orchestration
│           ├── databases.yaml          # Database layer orchestration
│           └── apps.yaml               # Application layer orchestration
├── Makefile                            # Centralized automation entrypoint
└── scripts/                            # Implementation logic for automation tasks
```

**Dependency Graph:**
1. `controllers-local`: Provisions namespaces, operators, Kong CRDs, cert-manager, secrets managers.
2. `secrets-local`: Deploys OpenBAO + ESO and runs the OpenBAO bootstrap Job (Depends on `controllers-local`).
3. `cert-manager-local`: ClusterIssuers (`selfsigned-bootstrap`, `homelab-ca`, `letsencrypt-staging`, `letsencrypt-prod`), `kong-proxy-tls` Certificate, trust-manager Bundle (Depends on `controllers-local`, `secrets-local` — needs the synced `cloudflare-api-token` Secret).
4. `kong-local`: Kong HelmRelease (Depends on `cert-manager-local` — mounts `kong-proxy-tls` Secret as a volume).
5. `kong-config-local`: KongClusterPlugins + Ingress resources for every host (Depends on `kong-local`).
6. `monitoring-local`: Deploys observability stack (Depends on `controllers-local`).
7. `storage-local`: Provisions RustFS (S3) object storage (Depends on `controllers-local`).
8. `network-policies-local`: Provisions per-namespace NetworkPolicies so operators never race an un-fenced namespace (Depends on `controllers-local`).
9. `tracing-local`: Deploys Tempo (Depends on `secrets-local`, `storage-local` — kept out of `controllers-local` to avoid a wave deadlock).
10. `profiling-local`: Deploys Pyroscope (Depends on `secrets-local`, `storage-local` — same rationale as `tracing-local`).
11. `cnpg-barman-plugin-local`: Installs the CNPG Barman Cloud Plugin via the `plugin-barman-cloud` Helm chart (from the `cnpg` HelmRepository) and its `ObjectStore` CRD (Depends on `controllers-local`, `cert-manager-local`).
12. `databases-local`: Provisions persistence layer, including the CNPG `temporal-db` (Depends on `secrets-local`, `monitoring-local`, `cnpg-barman-plugin-local`, `storage-local`, `network-policies-local`).
13. `databases-cnpg-dr-local`: CNPG DR replica (Depends on `databases-local`, `secrets-local`).
14. `temporal-local`: Temporal server via the temporal-operator (`TemporalCluster` + `TemporalNamespace`), persistence on the CNPG `temporal-db` (Depends on `controllers-local`, `cert-manager-local`, `databases-local`, `monitoring-local`). The `temporal-operator` HelmRelease itself `dependsOn` cert-manager, since its chart renders a cert-manager `Certificate`/`Issuer` for the admission webhook.
15. `kyverno-policies-local`: Admission policies (Depends on `controllers-local`, `monitoring-local`). See [kyverno.md](kyverno.md).
16. `apps-local`: Deploys business logic (the `apps-local` Kustomization `dependsOn` `databases-local`, `monitoring-local`, and `temporal-local` — the `order-worker` dials Temporal at startup, so apps must not deploy until the Temporal cluster is Ready).

---

For detailed API specifications, refer to [api.md](../api/api.md).  
For persistence layer details, refer to [database.md](../databases/002-database-integration.md).

---

_Last updated: 2026-07-07_