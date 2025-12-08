# Setup Guide - Kubernetes Monitoring

Complete guide to deploy Go REST API monitoring on Kind (Kubernetes in Docker).

---

## Quick Start (5 Minutes)

### One-Command Deployment

```bash
cd project-monitoring-golang
chmod +x scripts/*.sh

# Step 1: Create Kind cluster
./scripts/01-create-kind-cluster.sh

# Step 2: Install metrics infrastructure
./scripts/02-install-metrics.sh

# Step 3: Deploy monitoring stack (Prometheus Operator + Grafana Operator)
./scripts/03-deploy-monitoring.sh

# Step 4: Deploy APM stack (BEFORE apps to collect traces/logs/profiles immediately)
./scripts/04-deploy-apm.sh

# Step 5: Build all microservices
./scripts/05-build-microservices.sh

# Step 6: Deploy all microservices
./scripts/06-deploy-microservices.sh

# Step 7: Deploy k6 load testing (AFTER apps to test them)
./scripts/07-deploy-k6.sh

# Step 8: Deploy SLO system (Required for SRE practices)
./scripts/08-deploy-slo.sh

# Step 9: Setup port forwarding
./scripts/09-setup-access.sh
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

### Step 2: Install Metrics Infrastructure

```bash
./scripts/02-install-metrics.sh
```

**What it does:**
- Installs `kube-state-metrics` (via `prometheus-community/kube-state-metrics` Helm chart) to expose Kubernetes object metrics
- Installs `metrics-server` (via `metrics-server/metrics-server` Helm chart) with `--kubelet-insecure-tls` for Kind clusters
- Ensures both components run in the `kube-system` namespace

**Verify:**
```bash
kubectl get pods -n kube-system | grep -E "(kube-state|metrics-server)"
# Expected: 2 pods running
```

---

### Step 3: Deploy Monitoring Stack

```bash
./scripts/03-deploy-monitoring.sh
```

**What it does:**
- Deploys Prometheus (RBAC + scrape configs)
- Installs the Grafana Operator and reconciles Grafana (anonymous auth, dark theme) plus the Prometheus datasource
- Auto-provisions the microservices + Sloth SLO dashboards via `GrafanaDashboard` CRs (no manual imports)

**Why before apps:** Prometheus needs to be ready to collect metrics immediately when apps start.

**Verify:**
```bash
kubectl get pods -n monitoring | grep -E "(prometheus|grafana)"
# Expected: prometheus and grafana pods running

curl http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

curl http://localhost:3000/api/health
# Expected: {"database":"ok"}
```

---

### Step 4: Deploy APM Stack

```bash
./scripts/04-deploy-apm.sh
```

**What it does:**
- Deploys Grafana Tempo (distributed tracing)
- Deploys Pyroscope (continuous profiling)
- Deploys Loki + Vector (log aggregation)
- Creates Grafana Operator datasources (Tempo, Loki, Pyroscope)

**Why before apps:** APM components need to be ready BEFORE apps start to:
- Receive traces from Tempo endpoint (`http://tempo.monitoring.svc.cluster.local:4318`)
- Receive profiles from Pyroscope endpoint (`http://pyroscope.monitoring.svc.cluster.local:4040`)
- Vector collects logs from pods immediately when apps start

**Verify:**
```bash
kubectl get pods -n monitoring | grep -E "(tempo|pyroscope|loki)"
kubectl get pods -n kube-system -l app=vector
# Expected: All APM components running
```

---

### Step 5: Build All Microservices

```bash
./scripts/05-build-microservices.sh
```

**What it does:**
- Builds Docker images for all 9 microservices using unified Dockerfile
- Loads images into Kind cluster nodes
- Verifies image availability

**Services built:**
- auth, user, product
- cart, order, review
- notification, shipping, shipping-v2

**Verify:**
```bash
docker images | grep -E "(auth|user|product)"
# Expected: 9 service images
```

---

### Step 6: Deploy All Microservices

```bash
# Deploy using local Helm chart (default)
./scripts/06-deploy-microservices.sh --local

# Or deploy from OCI registry (if chart is published)
./scripts/06-deploy-microservices.sh --registry
```

**What it does:**
- Creates all service namespaces (auth, user, product, cart, order, review, notification, shipping) and `monitoring` namespace
- Deploys all 9 microservices using Helm chart with per-service values
- Creates Services for each microservice
- Sets up proper labels for Prometheus discovery

**Deployment modes:**
- `--local` (default): Uses local `charts/` directory
- `--registry`: Uses `oci://ghcr.io/duynhne/charts/microservice`

**Verify:**
```bash
# Check Helm releases
helm list -A

kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product
# Expected: 9 microservice pods running

kubectl get svc -n auth
kubectl get svc -n user
kubectl get svc -n product
# Expected: 9 services
```

---

### Step 7: Deploy k6 Load Testing

```bash
# Deploy all k6 variants (default)
./scripts/07-deploy-k6.sh

# Or deploy specific variant:
# ./scripts/07-deploy-k6.sh legacy
# ./scripts/07-deploy-k6.sh scenarios
```

**What it does:**
- Deploys k6 load generators via Helm (k6-legacy, k6-scenarios)
- Creates `k6` namespace
- Generates continuous load on all services

**Why after apps:** k6 needs applications to exist before it can generate load.

**Verify:**
```bash
kubectl get pods -n k6
kubectl logs -n k6 -l app=k6-legacy -f
kubectl logs -n k6 -l app=k6-scenarios -f
```

---

### Step 8: Deploy SLO System

```bash
./scripts/08-deploy-slo.sh
```

**What it does:**
- Installs Sloth Operator via Helm (`sloth/sloth` chart v0.15.0)
- Applies PrometheusServiceLevel CRDs (9 services)
- Automatically generates Prometheus recording rules
- Sets up error budget tracking via Kubernetes-native SLO management

**Why after monitoring and apps:** SLO system needs Prometheus and metrics data to work.

**Verify:**
```bash
# Check Sloth Operator
kubectl get pods -n monitoring -l app.kubernetes.io/name=sloth

# Check PrometheusServiceLevel CRDs
kubectl get prometheusservicelevels -n monitoring

# Check generated PrometheusRules
kubectl get prometheusrules -n monitoring

# Check Prometheus rules
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl http://localhost:9090/api/v1/rules
# Expected: SLO rules visible
```

---

### Step 9: Setup Port Forwarding

```bash
./scripts/09-setup-access.sh
```

**What it does:**
- Sets up port-forwarding for Grafana (3000)
- Sets up port-forwarding for Prometheus (9090)
- Sets up port-forwarding for API services (8080)
- Sets up port-forwarding for APM services (Tempo: 3200, Pyroscope: 4040, Loki: 3100)

**Note:** Script runs port-forwarding in background. Access services via localhost.

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

### Check Pod Status

```bash
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
auth-xxx                                1/1     Running   0          2m
user-xxx                                1/1     Running   0          2m
product-xxx                             1/1     Running   0          2m
cart-xxx                                1/1     Running   0          2m
order-xxx                               1/1     Running   0          2m
review-xxx                              1/1     Running   0          2m
notification-xxx                        1/1     Running   0          2m
shipping-xxx                            1/1     Running   0          2m
shipping-v2-xxx                         1/1     Running   0          2m
prometheus-xxx                          1/1     Running   0          2m
grafana-xxx                             1/1     Running   0          2m
k6-load-generator-xxx                   1/1     Running   0          2m
```

### Check Prometheus Targets

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
# Open http://localhost:9090/targets
```

All microservices should show as "UP" in Prometheus targets.

### Test APIs

```bash
# Test User Service
curl http://localhost:8080/api/v1/users

# Test Product Service
curl http://localhost:8080/api/v1/products

# Test Health Endpoint
curl http://localhost:8080/health
```

---

## Useful Commands

### Cluster Management

```bash
# List clusters
kind get clusters

# Cluster info
kubectl cluster-info

# All resources in namespace
kubectl get all -n auth
kubectl get all -n monitoring

# Delete cluster
kind delete cluster --name <cluster-name>
```

### Pod Management

```bash
# Watch pods
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product -w

# Pod logs (follow)
kubectl logs -f deployment/auth -n auth

# Exec into pod
kubectl exec -it <pod-name> -n <namespace> -- sh

# Scale application
kubectl scale deployment auth --replicas=3 -n auth
```

### Port Forwarding

If NodePort doesn't work (WSL2/Windows issues):

```bash
# Forward Grafana
kubectl port-forward svc/grafana-service 3000:3000 -n monitoring &

# Forward Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring &

# Forward Go API (example: auth)
kubectl port-forward svc/auth 8080:8080 -n auth &
```

---

## Troubleshooting

### Pods Not Starting

**Issue:** ImagePullBackOff

```bash
# Rebuild and reload images
./scripts/05-build-microservices.sh

# Force recreation
kubectl delete pods -l app=auth -n auth
```

### Dashboard No Data

**Issue:** Metrics not collected

```bash
# 1. Check Prometheus targets
open http://localhost:9090/targets
# All services should be UP

# 2. Run query
open http://localhost:9090/graph
# Query: request_duration_seconds_count{job=~"microservices"}

# 3. Check Prometheus logs
kubectl logs deployment/prometheus -n monitoring
```

### Grafana Dashboard Empty

**Issue:** Dashboard not provisioned

```bash
# Check ConfigMaps
kubectl get configmap -n monitoring | grep grafana

# Reload dashboard
./scripts/10-reload-dashboard.sh

# Restart Grafana
kubectl rollout restart deployment grafana -n monitoring
```

### Services Not Accessible

**Issue:** NodePort not working (WSL2)

```bash
# Use port-forwarding instead
./scripts/09-setup-access.sh
```

---

## Load Testing

### Automatic (k6 Deployment)

k6 load generators run continuously in the `k6` namespace:

```bash
# Check k6 pods
kubectl get pods -n k6

# View logs
kubectl logs -n k6 -l app=k6-legacy -f
kubectl logs -n k6 -l app=k6-scenarios -f
```

### Manual Testing

```bash
# Test endpoints
for i in {1..100}; do curl -s http://localhost:8080/api/v1/users & done
for i in {1..50}; do curl -s http://localhost:8080/api/v1/products & done
wait
```

---

## Resource Usage

### Expected Resources

```
Total Requirements:
- RAM: ~5-6 GB
- CPU: ~2-3 cores
- Disk: ~5 GB

Breakdown:
- Kind cluster: ~4 GB RAM
- Application pods (9x): ~600 MB RAM
- Monitoring stack: ~1 GB RAM
```

### Performance

With k6 load test:
- **P50**: ~50-100ms
- **P95**: ~100-200ms  
- **P99**: ~200-400ms
- **Error Rate**: 3-5% (simulated)
- **Throughput**: ~45-50 req/s actual

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
For API reference, see [API_REFERENCE.md](../api/API_REFERENCE.md).

