# Setup Guide - GitOps with Flux Operator

Complete guide to deploy microservices platform using **GitOps**, **Flux Operator**, and **Kustomize** on Kind (Kubernetes in Docker).

---

## All Commands

### Quick Commands (Makefile)

- **Bootstrap everything**: `make up` (cluster-up + flux-up + flux-push)
- **Reconcile**: `make sync` (flux-push + flux-sync)
- **Tear down local env**: `make down` (cluster-down)
- **Validate manifests**: `make validate`

### Detailed Commands (Makefile)

- **Cluster**: `make cluster-up`, `make cluster-down`
- **Flux**: `make flux-up`, `make flux-push`, `make flux-sync`, `make flux-status`, `make flux-logs`, `make flux-ui`
- **Utilities**: `make prereqs`, `make help`

---

## Workspace Setup (Polyrepo)

Since the project is split into multiple repositories, you need to clone all service repositories to work on the code locally.

### 1. Create Workspace Directory

```bash
mkdir -p ~/Working/duynhne
cd ~/Working/duynhne
```

### 2. Clone Repositories

Run this snippet to clone all required repositories:

```bash
# Infrastructure
git clone https://github.com/duynhne/monitoring.git
git clone https://github.com/duyhenryer/shared-workflows.git
git clone https://github.com/duynhne/pkg.git

# Microservices
for service in auth user product cart order review notification shipping; do
  git clone https://github.com/duynhne/${service}-service.git
done

# Frontend
git clone https://github.com/duynhne/frontend.git
```

This will create a structured workspace with all components.

---

## Step-by-Step Deployment

### Step 1: Create Kind Cluster

```bash
make cluster-up
```

**What it does:**
- Starts local OCI registry (`localhost:5050`)
- Creates 4-node Kubernetes cluster (`mop`)
- Connects registry to Kind network

**Verify:**
```bash
kubectl cluster-info
kubectl get nodes
docker ps | grep mop-registry
```

---

### Step 2: Bootstrap Flux Operator

```bash
make flux-up
```

**What it does:**
- Checks if Kind cluster is running
- Starts local OCI registry
- Installs Flux Operator via Helm
- Applies FluxInstance CRD
- Waits for Flux controllers to be ready

**Verify:**
```bash
kubectl get pods -n flux-system
```

---

### Step 3: Deploy All Infrastructure and Applications

```bash
make flux-push
```

**What it does:**
- Pushes 3 OCI artifacts to `localhost:5050`:
  - `flux-cluster-sync:local` (from `kubernetes/clusters/local/`)
  - `flux-infra-sync:local` (from `kubernetes/infra/`)
  - `flux-apps-sync:local` (from `kubernetes/apps/`)

- Flux Operator reconciles in dependency order:
  - **Phase 1: Infrastructure** - Namespaces, Controllers (operators), Configs (instances)
  - **Phase 2: Applications** - 9 backend + 1 frontend + 1 k6 (waits for all infrastructure)
  - **Phase 3: SLO** - Sloth Operator + 9 PrometheusServiceLevel CRDs

**Verify:**
```bash
make flux-status
flux get kustomizations --watch
```

**Timeline:** 5-10 minutes total

---

### Step 4: Verify Deployment

```bash
make flux-status
```

**Check components:**
```bash
# Flux system
kubectl get pods -n flux-system

# Infrastructure
kubectl get helmrelease -n monitoring
kubectl get helmrelease -n apm
kubectl get postgresql -A
kubectl get cluster -A

# Applications
kubectl get pods -A | grep -E "(auth|user|product|cart|order|review|notification|shipping)"
kubectl get helmrelease -A

# SLO
kubectl get prometheusservicelevel -n monitoring
```

**Expected:**
- 14 namespaces created
- 7 Helm repositories configured
- 20+ HelmReleases reconciled
- 5 PostgreSQL clusters running
- 9 PrometheusServiceLevel CRDs applied

---

## Access Services

### Port-Forward Setup

```bash
make flux-ui  # Sets up all port-forwards automatically
```

**What it does:**
- Stops existing port-forwards
- Starts port-forwards for all services in background
- Displays access URLs

**To stop all port-forwards:**
```bash
pkill -f 'kubectl port-forward'
```

### Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Flux Web UI | http://localhost:9080 | - |
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger | http://localhost:16686 | - |
| Tempo | http://localhost:3200 | - |
| Pyroscope | http://localhost:4040 | - |
| Loki | http://localhost:3100 | - |
| Postgres Operator UI | http://localhost:8082 | - |
| Frontend | http://localhost:3001 | - |

---

## Project Structure

```
monitoring/
├── kubernetes/
│   ├── infra/                          # Infrastructure manifests
│   │   ├── namespaces.yaml             # All namespaces
│   │   ├── controllers/                # Operators + CRDs
│   │   │   ├── monitoring/             # Prometheus Operator, Grafana Operator
│   │   │   ├── databases/              # Zalando + CloudNativePG operators
│   │   │   └── slo/                    # Sloth operator
│   │   ├── configs/                    # Instances + configs
│   │   │   ├── monitoring/             # Grafana CR + ServiceMonitors
│   │   │   ├── apm/                    # Loki/Tempo/Pyroscope + HelmReleases
│   │   │   ├── databases/              # DB instances, secrets, poolers
│   │   │   └── slo/                    # PrometheusServiceLevel CRs
│   │   └── kustomization.yaml
│   ├── apps/                           # Application manifests
│   │   ├── auth.yaml                   # HelmRelease with local config
│   │   ├── user.yaml
│   │   ├── product.yaml
│   │   ├── cart.yaml
│   │   ├── order.yaml
│   │   ├── review.yaml
│   │   ├── notification.yaml
│   │   ├── shipping.yaml
│   │   ├── shipping-v2.yaml          # Suspended (v1 API only)
│   │   ├── k6.yaml
│   │   └── frontend.yaml               # ResourceSet
│   └── clusters/                       # Flux cluster configurations
│       └── local/                      # Local Kind cluster
│           ├── flux-system/            # FluxInstance CRD
│           ├── sources/                # OCI & Helm repositories
│           ├── controllers.yaml       # Controllers Kustomization
│           ├── configs.yaml            # Configs Kustomization
│           └── apps.yaml               # Apps Kustomization
├── Makefile                            # GitOps automation
├── charts/mop/                         # Helm chart for all services
└── scripts/                            # Kind/Flux helper scripts (invoked by Makefile targets)
```

**Dependency Chain:**
- `controllers-local` → Creates namespaces + deploys all operators
- `configs-local` → Depends on `controllers-local` → Deploys all configs
- `apps-local` → Depends on `configs-local` → Waits for all infrastructure

---

---

For detailed API documentation, see [api.md](./api/api.md).  
For database architecture, see [database.md](./database/database.md).