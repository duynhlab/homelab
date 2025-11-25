# Setup Guide - Kubernetes Monitoring Demo

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

# Step 3: Build all microservices
./scripts/03-build-microservices.sh

# Step 4: Deploy all microservices
./scripts/04-deploy-microservices.sh

# Step 5: Deploy monitoring stack
./scripts/05-deploy-monitoring.sh

# Step 6: Deploy k6 load testing (optional)
./scripts/06-deploy-k6-testing.sh

# Step 7: Setup port forwarding
./scripts/07-setup-access.sh
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
- Installs `kube-state-metrics` - Exposes K8s object metrics
- Installs `metrics-server` - Provides resource usage data
- Patches metrics-server for Kind compatibility

**Verify:**
```bash
kubectl get pods -n kube-system | grep -E "(kube-state|metrics-server)"
# Expected: 2 pods running
```

---

### Step 3: Build All Microservices

```bash
./scripts/03-build-microservices.sh
```

**What it does:**
- Builds Docker images for all 9 microservices using unified Dockerfile
- Loads images into Kind cluster nodes
- Verifies image availability

**Services built:**
- auth-service, user-service, product-service
- cart-service, order-service, review-service
- notification-service, shipping-service, shipping-service-v2

**Verify:**
```bash
docker images | grep -E "(auth-service|user-service|product-service)"
# Expected: 9 service images
```

---

### Step 4: Deploy All Microservices

```bash
./scripts/04-deploy-microservices.sh
```

**What it does:**
- Creates all service namespaces (auth, user, product, cart, order, review, notification, shipping) and `monitoring` namespace
- Deploys all 9 microservices with Kubernetes Deployments
- Creates Services for each microservice
- Sets up ServiceMonitors for Prometheus discovery

**Verify:**
```bash
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product
# Expected: 9 microservice pods running

kubectl get svc -n auth
kubectl get svc -n user
kubectl get svc -n product
# Expected: 9 services + prometheus + grafana
```

---

### Step 5: Deploy Monitoring Stack

```bash
./scripts/05-deploy-monitoring.sh
```

**What it does:**
- Deploys Prometheus with RBAC permissions
- Deploys Grafana with auto-provisioning
- Creates ConfigMaps for dashboards and datasources
- Configures Prometheus scrape configs

**Verify:**
```bash
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product | grep -E "(prometheus|grafana)"
# Expected: prometheus and grafana pods running

curl http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

curl http://localhost:3000/api/health
# Expected: {"database":"ok"}
```

---

### Step 6: Deploy k6 Load Testing (Optional)

```bash
./scripts/06-deploy-k6-testing.sh
```

**What it does:**
- Deploys k6 load generators (legacy and multiple scenarios)
- Creates ConfigMap with k6 test scripts
- Generates continuous load on all services

**Verify:**
```bash
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product -l app=k6-load-generator
kubectl logs -n monitoring -l app=k6-load-generator
```

---

### Step 7: Setup Port Forwarding

```bash
./scripts/07-setup-access.sh
```

**What it does:**
- Sets up port-forwarding for Grafana (3000)
- Sets up port-forwarding for Prometheus (9090)
- Sets up port-forwarding for API services (8080)

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

- **App**: Select service (auth-service, user-service, etc.) or "All"
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
auth-service-xxx                        1/1     Running   0          2m
user-service-xxx                        1/1     Running   0          2m
product-service-xxx                     1/1     Running   0          2m
cart-service-xxx                        1/1     Running   0          2m
order-service-xxx                        1/1     Running   0          2m
review-service-xxx                      1/1     Running   0          2m
notification-service-xxx                1/1     Running   0          2m
shipping-service-xxx                    1/1     Running   0          2m
shipping-service-v2-xxx                  1/1     Running   0          2m
prometheus-xxx                          1/1     Running   0          2m
grafana-xxx                             1/1     Running   0          2m
k6-load-generator-xxx                   1/1     Running   0          2m
```

### Check Prometheus Targets

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
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
kubectl logs -f deployment/auth-service -n auth

# Exec into pod
kubectl exec -it <pod-name> -n <namespace> -- sh

# Scale application
kubectl scale deployment auth-service --replicas=3 -n auth
```

### Port Forwarding

If NodePort doesn't work (WSL2/Windows issues):

```bash
# Forward Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring &

# Forward Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring &

# Forward Go API (example: auth-service)
kubectl port-forward svc/auth-service 8080:8080 -n auth &
```

---

## Troubleshooting

### Pods Not Starting

**Issue:** ImagePullBackOff

```bash
# Rebuild and reload images
./scripts/03-build-microservices.sh

# Force recreation
kubectl delete pods -l app=auth-service -n auth
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
./scripts/08-reload-dashboard.sh

# Restart Grafana
kubectl rollout restart deployment grafana -n monitoring
```

### Services Not Accessible

**Issue:** NodePort not working (WSL2)

```bash
# Use port-forwarding instead
./scripts/07-setup-access.sh
```

---

## Load Testing

### Automatic (k6 Deployment)

k6 load generators run continuously:

```bash
# Check k6 pods
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product -l app=k6-load-generator

# View logs
kubectl logs -n monitoring -l app=k6-load-generator
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

