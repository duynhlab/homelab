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
mkdir -p ~/Working/duynhne
cd ~/Working/duynhne
```

### 2. Clone Repositories

Execute the following script to clone all required components:

```bash
# Infrastructure Repositories
git clone https://github.com/duynhne/monitoring.git
git clone https://github.com/duyhenryer/shared-workflows.git
git clone https://github.com/duynhne/pkg.git

# Microservices Repositories
for service in auth user product cart order review notification shipping; do
  git clone https://github.com/duynhne/${service}-service.git
done

# Frontend Repository
git clone https://github.com/duynhne/frontend.git
```

This creates a structured local environment with all necessary source code.

---

## Deployment Workflow

### Step 1: Provision Kind Cluster

```bash
make cluster-up
```

**Actions Performed:**
- Initializes a local OCI registry (`localhost:5050`).
- Provisions a 4-node Kubernetes cluster named `mop`.
- Establishes network connectivity between the registry and the Kind cluster.

**Verification:**
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
  - **Phase 2: Security & Monitoring** - Vault/ESO, Grafana/Prometheus.
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
- 14 Namespaces provisioned.
- 7 Helm Repositories configured.
- 5 ResourceSets (`rs-identity`, `rs-catalog`, `rs-checkout`, `rs-comms`, `rs-frontend`) successfully reconciled.
- 9 HelmReleases automatically generated and in `Ready` state.
- 4 PostgreSQL clusters operational.

---

## Accessing Services

### Integrated Port-Forwarding

```bash
make flux-ui  # Automatically configures all required port-forwards
```

**Actions Performed:**
- Terminates legacy port-forwarding processes.
- Initializes background port-forwards for all platform services.
- Displays centralized access URLs.

**To terminate all sessions:**
```bash
pkill -f 'kubectl port-forward'
```

### Centralized Service URLs

| Service | Local URL | Credentials |
|---------|-----------|-------------|
| Flux Web UI | http://localhost:9080 | - |
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger UI | http://localhost:16686 | - |
| Tempo | http://localhost:3200 | - |
| Pyroscope | http://localhost:4040 | - |
| Loki | http://localhost:3100 | - |
| Postgres Operator UI | http://localhost:8082 | - |
| Frontend Application | http://localhost:3001 | - |

---

## Project Architecture

```
monitoring/
├── kubernetes/
│   ├── infra/                          # Core infrastructure definitions
│   │   ├── namespaces.yaml             # Cluster-wide namespace definitions
│   │   ├── controllers/                # Operators and CRD definitions
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
│   │   └── frontend-rs.yaml            # rs-frontend (standalone)
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
1. `controllers-local`: Provisions namespaces and core operators.
2. `secrets-local`: Deploys Vault/ESO (Depends on `controllers-local`).
3. `monitoring-local`: Deploys observability stack (Depends on `controllers-local`).
4. `databases-local`: Provisions persistence layer (Depends on `secrets-local`, `monitoring-local`).
5. `apps-local`: Deploys business logic (Depends on `databases-local`, `monitoring-local`).

---

For detailed API specifications, refer to [api.md](../api/api.md).  
For persistence layer details, refer to [database.md](../databases/database.md).