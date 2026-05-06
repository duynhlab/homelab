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
git clone https://github.com/duynhlab/monitoring.git
git clone https://github.com/duyhenryer/shared-workflows.git
git clone https://github.com/duynhlab/pkg.git

# Microservices Repositories
for service in auth user product cart order review notification shipping; do
  git clone https://github.com/duynhlab/${service}-service.git
done

# Frontend Repository
git clone https://github.com/duynhlab/frontend.git
```

This creates a structured local environment with all necessary source code.

---

## Deployment Workflow

### Prerequisites

Before the first `make up`, two host-side prerequisites must be in place:

1. **`/etc/hosts` entries for `*.duynh.me`** — Kong runs as NodePort and Kind maps host ports 80/443. Use the helper:
   ```bash
   sudo ./scripts/setup-hosts.sh           # adds the marker block
   sudo ./scripts/setup-hosts.sh remove    # cleans it up
   ```
2. **Cloudflare API token in OpenBAO** — the `letsencrypt-prod` ClusterIssuer uses Cloudflare DNS-01 to issue the wildcard `*.duynh.me` cert that Kong terminates. The token is **bootstrap-only** (not in Git) and must be re-seeded after every fresh cluster:
   ```bash
   ROOT=$(kubectl get secret -n openbao openbao-init-keys -o jsonpath='{.data.root_token}' | base64 -d)
   kubectl exec -n openbao openbao-0 -- sh -c \
     "BAO_TOKEN=$ROOT bao kv put secret/local/infra/cloudflare/api-token api_token=cfut_..."
   flux reconcile ks secrets-local --with-source
   flux reconcile ks cert-manager-local --with-source
   ```
   ESO syncs the token to `Secret/cloudflare-api-token` in the `cert-manager` namespace via `kubernetes/infra/configs/secrets/cluster-external-secrets/cloudflare.yaml`.

Without step 2, `cert-manager-local` reconciles but `kong-proxy-tls` stays NotReady and Kong cannot terminate HTTPS.

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
- Validates Kind cluster status.
- Ensures the local OCI registry Is operational.
- Installs the Flux Operator via Helm.
- Provisions the `FluxInstance` resource.
- Awaits readiness of Flux controllers.

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
- Namespaces for every domain provisioned (auth, user, product, cart, order, review, notification, shipping, frontend, kong, cert-manager, openbao, external-secrets-system, monitoring, apm, databases-cnpg-system, databases-zalando, kyverno, flux-system, …).
- 5 ResourceSets (`rs-identity`, `rs-catalog`, `rs-checkout`, `rs-comms`, `rs-frontend`) successfully reconciled.
- HelmReleases for the 8 microservices + frontend in `Ready` state.
- 3 PostgreSQL clusters (`auth-db`, `supporting-shared-db`, `cnpg-db`) + 1 DR replica (`cnpg-db-replica`) operational.
- ClusterIssuers `selfsigned-bootstrap`, `homelab-ca`, `letsencrypt-staging`, `letsencrypt-prod` Ready; `kong-proxy-tls` Certificate Ready and signed by `letsencrypt-prod`.

---

## Accessing Services

All user-facing endpoints go through Kong on `*.duynh.me` (terminated with the Let's Encrypt wildcard cert). Make sure `scripts/setup-hosts.sh` has been run.

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

## Project Architecture

```
monitoring/
├── kubernetes/
│   ├── infra/                          # Core infrastructure definitions
│   │   ├── controllers/                # Operators and CRD definitions
│   │   │   ├── namespaces.yaml         # Cluster-wide namespace definitions
│   │   │   ├── monitoring/             # Prometheus and Grafana operators
│   │   │   ├── databases/              # Database orchestration operators
│   │   │   └── slo/                    # Service Level Objective operator
│   │   ├── configs/                    # Component instances and configurations
│   │   │   ├── monitoring/             # Grafana resources and ServiceMonitors
│   │   │   ├── apm/                    # APM stack (Loki, Tempo, Pyroscope)
│   │   │   ├── databases/              # PostgreSQL clusters and poolers
│   │   │   └── slo/                    # SLO definitions (PrometheusServiceLevel)
│   │   └── kustomization.yaml
│   ├── apps/                           # Application definitions (Hybrid ResourceSet)
│   │   ├── domains/                    # Domain ResourceSets (template + inputsFrom selector)
│   │   │   ├── identity-rs.yaml        # rs-identity: auth, user
│   │   │   ├── catalog-rs.yaml         # rs-catalog: product, review
│   │   │   ├── checkout-rs.yaml        # rs-checkout: cart, order
│   │   │   └── comms-rs.yaml           # rs-comms: notification, shipping
│   │   ├── services/                   # Per-service InputProviders (Static)
│   │   │   ├── auth.yaml               # domain=identity
│   │   │   ├── user.yaml               # domain=identity
│   │   │   ├── product.yaml            # domain=catalog
│   │   │   ├── review.yaml             # domain=catalog
│   │   │   ├── cart.yaml               # domain=checkout
│   │   │   ├── order.yaml              # domain=checkout
│   │   │   ├── notification.yaml       # domain=comms
│   │   │   └── shipping.yaml           # domain=comms
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
7. `cnpg-barman-plugin-local`: Installs the CNPG Barman Cloud Plugin and `ObjectStore` CRD (Depends on `controllers-local`, `cert-manager-local`).
8. `databases-local`: Provisions persistence layer (Depends on `secrets-local`, `monitoring-local`, `cnpg-barman-plugin-local`).
9. `databases-cnpg-dr-local`: CNPG DR replica (Depends on `databases-local`, `secrets-local`).
10. `kyverno-policies-local`: Admission policies (Depends on `controllers-local`, `monitoring-local`). See [kyverno.md](kyverno.md).
11. `apps-local`: Deploys business logic (Depends on `databases-local`, `monitoring-local`).

---

For detailed API specifications, refer to [api.md](../api/api.md).  
For persistence layer details, refer to [database.md](../databases/002-database-integration.md).