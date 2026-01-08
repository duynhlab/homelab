# Setup Guide - Kubernetes Monitoring

Complete guide to deploy Go REST API monitoring on Kind (Kubernetes in Docker).

---

## Quick Start (5 Minutes)

### One-Command Deployment

```bash
cd project-monitoring-golang
chmod +x scripts/*.sh

# Step 0: Verify builds (optional but recommended)
./scripts/00-verify-build.sh

# Step 1: Create Kind cluster
./scripts/01-create-kind-cluster.sh

# Step 2: Deploy monitoring stack (creates all namespaces + Prometheus Operator + Grafana Operator + metrics)
./scripts/02-deploy-monitoring.sh

# Step 3: Deploy APM stack (BEFORE apps to collect traces/logs/profiles immediately)
./scripts/03-deploy-apm.sh

# Step 4: Deploy databases (PostgreSQL operators, clusters, poolers - BEFORE apps)
./scripts/04-deploy-databases.sh

# Step 5: Deploy all microservices (from OCI registry)
./scripts/05-deploy-microservices.sh

# Step 6: Deploy k6 load testing (AFTER apps to test them)
./scripts/06-deploy-k6.sh

# Step 7: Deploy SLO system (Required for SRE practices)
./scripts/07-deploy-slo.sh

# Step 8: Setup port forwarding
./scripts/08-setup-access.sh
```

Wait 5 minutes. Then access:

```
Go API:     http://localhost:8080
Prometheus: http://localhost:9090
Grafana:    http://localhost:3000 (admin/admin)
Dashboard:  http://localhost:3000/d/microservices-monitoring-001/
```

**Done!** Skip to [Accessing Services](#accessing-services) section.

---

## Prerequisites

### Required Software

- **Docker** - Container runtime
- **kubectl** - Kubernetes CLI
- **Helm** - Kubernetes package manager (v3.14+):
  ```bash
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ```
- **Kind** - Kubernetes in Docker (auto-installed by script or manual):
  ```bash
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  ```

### System Requirements

- **RAM**: 8GB+ recommended
- **CPU**: 4+ cores recommended
- **Disk**: 10GB+ free space

---

## Local Build Verification

Before deploying, verify your changes build correctly:

```bash
./scripts/00-verify-build.sh
```

Checks: Go modules, formatting (`gofmt`), static analysis (`go vet`), builds all 9 services, tests (optional with `--skip-tests`).

**See**: [`docs/guides/API_REFERENCE.md`](API_REFERENCE.md#local-build-verification) for detailed usage, troubleshooting, and local development setup.

---

## Step-by-Step Deployment

### Step 1: Create Kind Cluster

```bash
./scripts/01-create-kind-cluster.sh
```

**What it does:**
- Creates 3-node Kubernetes cluster (1 control-plane + 2 workers)
- Configures port mappings for services
- Sets up cluster networking

**Verify:**
```bash
kubectl cluster-info
kubectl get nodes
# Expected: 3 nodes (Ready status)
```

---

### Step 2: Deploy Monitoring Stack

```bash
./scripts/02-deploy-monitoring.sh
```

**What it does:**
- Creates all namespaces from `k8s/namespaces.yaml` (auth, user, product, cart, order, review, notification, shipping, k6, database, monitoring)
- Deploys Prometheus Operator (kube-prometheus-stack v80.0.0) with kube-state-metrics
- Deploys Grafana Operator with dashboards
- Deploys metrics-server for kubectl top / HPA

**Why namespaces are created here:**
- Ensures all namespaces exist before deployments
- Required for Zalando operator to create cross-namespace secrets (notification, shipping)
- Single source of truth for namespace management (`k8s/namespaces.yaml`)

**Verify:** `kubectl get pods -n monitoring | grep -E "(prometheus|grafana)"`

---

### Step 3: Deploy APM Stack

```bash
./scripts/03-deploy-apm.sh
```

**What it does:**
- Deploys Grafana Tempo (distributed tracing)
- Deploys Pyroscope (continuous profiling)
- Deploys Loki + Vector (log aggregation)
- Creates Grafana Operator datasources (Tempo, Loki, Pyroscope)

**Verify:** `kubectl get pods -n monitoring | grep -E "(tempo|pyroscope|loki)"`

---

### Step 4: Deploy Databases

```bash
./scripts/04-deploy-databases.sh
```

**What it does:**
- Deploys Zalando Postgres Operator (v1.15.1) for 3 clusters (Review, Auth, Supporting)
- Deploys CloudNativePG Operator (v1.28.0) for 2 clusters (Product, Transaction)
- Creates 5 PostgreSQL database clusters:
  - `review-db` (Review service)
  - `auth-db` (Auth service)
  - `supporting-db` (User, Notification, Shipping-v2 services)
  - `product-db` (Product service)
  - `transaction-db` (Cart and Order services)
- Deploys connection poolers:
  - PgBouncer for Auth database (transaction pooling)
  - PgCat for Product and Transaction databases (multi-database routing, read replica load balancing)
- Deploys `postgres_exporter` sidecars with custom queries for all clusters (Prometheus metrics: pg_stat_statements, pg_replication, pg_postmaster)
- Deploys Vector sidecars for log collection (Zalando clusters only) shipping to Loki
- Creates Kubernetes Secrets for database passwords

**Verify:** `kubectl get postgresql -A && kubectl get cluster -A` or `./scripts/04a-verify-databases.sh`

**See**: [`docs/guides/DATABASE.md`](./DATABASE.md) for architecture details.

---

### Step 5: Deploy All Microservices

```bash
./scripts/05-deploy-microservices.sh
```

**What it does:**
- Deploys all 9 microservices using Helm chart from OCI registry (`oci://ghcr.io/duynhne/charts/microservice`)
- Creates namespaces automatically via Helm's `--create-namespace` flag (or reuses existing namespaces from database deployment)
- Creates Services for each microservice
- Sets up proper labels for Prometheus discovery

**Note:** Images built by GitHub Actions, pulled from OCI registry.

**Verify:** `helm list -A && kubectl get pods -n auth -n user -n product`

---

### Step 6: Deploy k6 Load Testing

```bash
# Deploy all k6 variants (default)
./scripts/06-deploy-k6.sh

# Or deploy specific variant:
# ./scripts/06-deploy-k6.sh legacy
# ./scripts/06-deploy-k6.sh scenarios
```

**What it does:** Deploys k6 load generators via Helm, generates continuous load.

**Verify:** `kubectl get pods -n k6`

---

### Step 7: Deploy SLO System

```bash
./scripts/07-deploy-slo.sh
```

**What it does:**
- Installs Sloth Operator via Helm (`sloth/sloth` chart v0.15.0)
- Applies PrometheusServiceLevel CRDs (9 services)
- Automatically generates Prometheus recording rules
- Sets up error budget tracking via Kubernetes-native SLO management

**Verify:** `kubectl get prometheusservicelevels -n monitoring && kubectl get prometheusrules -n monitoring`

---

### Step 8: Setup Port Forwarding

```bash
./scripts/08-setup-access.sh
```

**What it does:**
- Sets up port-forwarding for Grafana (3000)
- Sets up port-forwarding for Prometheus (9090)
- Sets up port-forwarding for API services (8080)
- Sets up port-forwarding for APM services (Tempo: 3200, Pyroscope: 4040, Loki: 3100)

**Note:** Script runs port-forwarding in background. Access services via localhost.

---

## Configuration

Configuration priority (lowest to highest): Default values → `.env` file → Environment variables → Helm values (`charts/values/*.yaml`).

**See**: [`docs/guides/API_REFERENCE.md`](./API_REFERENCE.md) for environment variables and [`docs/guides/DATABASE.md`](./DATABASE.md) for database configuration.

---

## Accessing Services

### Web Interfaces

1. **Grafana**: http://localhost:3000 (admin/admin)
   - Dashboard UID: `microservices-monitoring-001`
   - Direct URL: http://localhost:3000/d/microservices-monitoring-001/

2. **Prometheus**: http://localhost:9090
   - Query interface: http://localhost:9090/graph
   - Targets: http://localhost:9090/targets
   - Rules: http://localhost:9090/rules

3. **API Services**: http://localhost:8080 (via port-forward)
   - Each service exposed on port 8080
   - Health check: `curl http://localhost:8080/health`

### Dashboard Variables

Adjust filters in Grafana dashboard header:

- **App**: Select service (auth, user, etc.) or "All"
- **Namespace**: Select service namespace (auth, user, product, etc.) or monitoring for monitoring components
- **Rate**: Query interval (1m, 5m, 10m, 30m, 1h, etc.)

---

## Verification

**Check Pods:** `kubectl get pods -n auth -n user -n product` (all 9 microservices should be Running)

**Check Prometheus Targets:** `http://localhost:9090/targets` (all services should be UP)

**Test APIs:** `curl http://localhost:8080/api/v1/users` or `curl http://localhost:8080/health`

---

## Command Reference

### Deployment Scripts

Numbered scripts (00-10) execute in order. See [Step-by-Step Deployment](#step-by-step-deployment) for detailed guide.

| Script | Command | Purpose | Order |
|--------|---------|---------|-------|
| Verify build | `./scripts/00-verify-build.sh` | Verify local builds before deployment | 0 |
| Create cluster | `./scripts/01-create-kind-cluster.sh` | Create Kind Kubernetes cluster | 1 |
| Deploy monitoring | `./scripts/02-deploy-monitoring.sh` | Create all namespaces + Deploy Prometheus, Grafana, metrics | 2 |
| Deploy APM | `./scripts/03-deploy-apm.sh` | Deploy all APM components (BEFORE apps) | 3 |
| Deploy Tempo | `./scripts/03a-deploy-tempo.sh` | Deploy Tempo (APM sub-component) | 3a |
| Deploy Pyroscope | `./scripts/03b-deploy-pyroscope.sh` | Deploy Pyroscope (APM sub-component) | 3b |
| Deploy Loki | `./scripts/03c-deploy-loki.sh` | Deploy Loki (APM sub-component) | 3c |
| Deploy Jaeger | `./scripts/03d-deploy-jaeger.sh` | Deploy Jaeger (APM sub-component) | 3d |
| Deploy databases | `./scripts/04-deploy-databases.sh` | Deploy PostgreSQL operators, clusters, poolers | 4 |
| Verify databases | `./scripts/04a-verify-databases.sh` | Verify database deployment | 4a |
| Deploy services | `./scripts/05-deploy-microservices.sh` | Deploy from OCI registry (images built by GitHub Actions) | 5 |
| Deploy k6 | `./scripts/06-deploy-k6.sh` | Deploy k6 load generators (AFTER apps) | 6 |
| Deploy SLO | `./scripts/07-deploy-slo.sh` | Deploy Sloth Operator and SLO CRDs | 7 |
| Setup access | `./scripts/08-setup-access.sh` | Setup port-forwarding | 8 |
| Reload dashboard | `./scripts/09-reload-dashboard.sh` | Reapply Grafana dashboards | 9 |
| Error budget alert | `./scripts/10-error-budget-alert.sh` | Respond to error budget alerts | 10 |
| Cleanup | `./scripts/cleanup.sh` | Complete cleanup (delete cluster, volumes, etc.) | - |

### Helm Commands

| Command | Purpose |
|---------|---------|
| `helm list -A` | List all Helm releases |
| `helm upgrade --install <name> charts/ -f charts/values/<service>.yaml -n <ns>` | Install/upgrade service |
| `helm uninstall <name> -n <namespace>` | Uninstall a service |

### kubectl Shortcuts

| Command | Purpose |
|---------|---------|
| `kubectl get pods -n {namespace}` | List pods in namespace |
| `kubectl logs -l app={service-name} -n {namespace}` | View service logs |
| `kubectl port-forward -n monitoring svc/grafana-service 3000:3000` | Port-forward Grafana |
| `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | Port-forward Prometheus |
| `kubectl rollout restart deployment/{name} -n {namespace}` | Restart deployment |

### Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| API (via port-forward) | http://localhost:8080 | - |

**Setup:** `./scripts/08-setup-access.sh` or manually port-forward services.

---

## Load Testing

k6 load generators run continuously in the `k6` namespace. Check: `kubectl get pods -n k6`. View logs: `kubectl logs -n k6 -l app=k6 -f`

**See**: [`docs/k6/K6_LOAD_TESTING.md`](../k6/K6_LOAD_TESTING.md) for detailed scenarios and manual testing.

---

## Cleanup

### Complete Cleanup

```bash
./scripts/cleanup.sh
```

**What it does:**
- Deletes Kind cluster
- Removes Docker volumes
- Cleans up test results
- Frees up ports

**Manual cleanup:**
```bash
# Delete cluster
kind delete cluster --name <cluster-name>

# Verify
kind get clusters
# Should be empty

# Clean Docker
docker system prune -f
```

---

## Next Steps

After successful deployment:

1. **Explore Dashboard** - Check all 32 panels (see [METRICS.md](../monitoring/METRICS.md))
2. **Run Load Tests** - Try different scenarios (see [K6_LOAD_TESTING.md](../load-testing/K6_LOAD_TESTING.md))
3. **Setup SLOs** - Configure SLO tracking (see [SLO Documentation](../slo/README.md))
4. **Customize Metrics** - Add your own business metrics
5. **Setup Alerts** - Configure Grafana alerting

---

## Additional Resources

- **Kind Documentation**: https://kind.sigs.k8s.io/
- **Prometheus K8s Config**: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config
- **Grafana Provisioning**: https://grafana.com/docs/grafana/latest/administration/provisioning/
- **Project Documentation**: See [docs/README.md](../README.md) for complete documentation index

---

**Ready to monitor!** 🚀

For detailed metrics explanation, see [METRICS.md](../monitoring/METRICS.md).
For API reference, see [API_REFERENCE.md](./API_REFERENCE.md).

