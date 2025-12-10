# 08. Development Workflow

> **Purpose**: Step-by-step guide for local development, deployment, testing, and debugging.

---

## Table of Contents

- [Local Development Setup](#local-development-setup)
- [Build & Deploy Process](#build--deploy-process)
- [Testing & Validation](#testing--validation)
- [Debugging Workflows](#debugging-workflows)
- [Common Operations](#common-operations)

---

## Local Development Setup

### Prerequisites

**Required Software:**
| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| Docker Desktop | 20.10+ | Container runtime | https://www.docker.com/products/docker-desktop |
| kubectl | 1.25+ | Kubernetes CLI | https://kubernetes.io/docs/tasks/tools/ |
| Helm | 3.x | Package manager | https://helm.sh/docs/intro/install/ |
| Kind | 0.20+ | Local Kubernetes | `brew install kind` or `go install sigs.k8s.io/kind@latest` |
| Go | 1.23.0 | Development | https://go.dev/dl/ |

**System Requirements:**
- **CPU**: 8 cores minimum (12 cores recommended)
- **RAM**: 16GB minimum (32GB recommended)
- **Disk**: 50GB free space minimum
- **OS**: macOS, Linux, or Windows (with WSL2)

### Initial Setup (First Time Only)

**Step 1: Clone Repository**
```bash
git clone <repo-url>
cd monitoring
```

**Step 2: Verify Tools**
```bash
# Check Docker
docker --version
# Docker version 20.10.x

# Check kubectl
kubectl version --client
# Client Version: v1.33.0

# Check Helm
helm version --short
# v3.16.0

# Check Kind
kind version
# kind v0.20.0

# Check Go
go version
# go version go1.23.0
```

**Step 3: Create Kind Cluster**
```bash
./scripts/01-create-kind-cluster.sh
```

**Expected output:**
```
=== Creating Kind Cluster ===
Creating cluster "monitoring-cluster" ...
 ✓ Ensuring node image (kindest/node:v1.33.0)
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-monitoring-cluster"
✅ Kind cluster created successfully!
```

**Step 4: Install Metrics Infrastructure**
```bash
./scripts/02-install-metrics.sh
```

---

## Build & Deploy Process

### Full Deployment (Complete Stack)

**Execute deployment order:**

```bash
# Phase 1: Infrastructure (Steps 1-2) - Already done in setup
# ./scripts/01-create-kind-cluster.sh  # ✅ Done
# ./scripts/02-install-metrics.sh      # ✅ Done

# Phase 2: Monitoring Stack (Step 3) - BEFORE apps
./scripts/03-deploy-monitoring.sh

# Phase 3: APM Stack (Step 4) - BEFORE apps
./scripts/04-deploy-apm.sh

# Phase 4: Build & Deploy Applications (Steps 5-6)
./scripts/05-build-microservices.sh    # Build Docker images
./scripts/06-deploy-microservices.sh   # Deploy via Helm

# Phase 5: Load Testing (Step 7) - AFTER apps
./scripts/07-deploy-k6.sh

# Phase 6: SLO System (Step 8)
./scripts/08-deploy-slo.sh

# Phase 7: Access Setup (Step 9)
./scripts/09-setup-access.sh
```

**Total time**: 10-15 minutes (depending on internet speed)

### Build Docker Images

**Script**: `scripts/05-build-microservices.sh`

```bash
./scripts/05-build-microservices.sh
```

**What it does:**
1. Builds 9 service images using multi-stage Dockerfile
2. Tags images: `ghcr.io/duynhne/<service>:v5`
3. Optionally pushes to registry (commented out)

**Manual build (single service):**
```bash
docker build \
  --build-arg SERVICE_NAME=auth \
  -t ghcr.io/duynhne/auth:v5 \
  -f services/Dockerfile services/
```

### Deploy Microservices

**Script**: `scripts/06-deploy-microservices.sh`

**Deploy from local chart:**
```bash
./scripts/06-deploy-microservices.sh --local
```

**Deploy from OCI registry:**
```bash
./scripts/06-deploy-microservices.sh --registry
```

**What it does:**
1. Detects chart version from `charts/Chart.yaml`
2. Deploys all 9 services via Helm
3. Creates namespaces if not exist
4. Waits for pods to be ready

**Manual deploy (single service):**
```bash
helm upgrade --install auth charts/ \
  -f charts/values/auth.yaml \
  -n auth \
  --create-namespace \
  --wait --timeout 120s
```

### Verify Deployment

**Check all pods:**
```bash
kubectl get pods -A | grep -E 'auth|user|product|cart|order|review|notification|shipping'
```

**Expected output:**
```
auth            auth-deployment-xxx-yyy           1/1     Running   0          2m
user            user-deployment-xxx-yyy           1/1     Running   0          2m
product         product-deployment-xxx-yyy        1/1     Running   0          2m
cart            cart-deployment-xxx-yyy           1/1     Running   0          2m
order           order-deployment-xxx-yyy          1/1     Running   0          2m
review          review-deployment-xxx-yyy         1/1     Running   0          2m
notification    notification-deployment-xxx-yyy   1/1     Running   0          2m
shipping        shipping-deployment-xxx-yyy       1/1     Running   0          2m
shipping        shipping-v2-deployment-xxx-yyy    1/1     Running   0          2m
```

**Check services:**
```bash
kubectl get svc -A | grep -E 'auth|user|product|cart|order|review|notification|shipping'
```

---

## Testing & Validation

### Manual API Testing

**Port-forward a service:**
```bash
kubectl port-forward -n auth svc/auth 8080:8080
```

**Test endpoints:**
```bash
# Health check
curl http://localhost:8080/health
# {"status":"ok"}

# Metrics
curl http://localhost:8080/metrics | head -20

# v1 API
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}'

# v2 API
curl -X POST http://localhost:8080/api/v2/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}'
```

### Load Testing with K6

**Deploy K6:**
```bash
./scripts/07-deploy-k6.sh
```

**Check K6 logs:**
```bash
kubectl logs -n k6 -l app=k6-scenarios -f
```

**Expected output:**
```
🚀 k6 Professional High-Volume Load Test Starting...
=====================================================
📊 Configuration:
  - Duration: 6.5 hours (390 minutes)
  - Peak VUs: 250 (100 browser + 75 shopping + ...)
  - Estimated RPS: 250-1000 (avg ~400 RPS)
  - Estimated Total Requests: 3-4 million
...
```

**Test results:**
- Check Grafana dashboards for metrics
- Check Tempo for distributed traces
- Check Loki for logs

### Grafana Dashboard Access

**Port-forward Grafana:**
```bash
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
```

**Access dashboards:**
- **URL**: http://localhost:3000
- **Credentials**: admin/admin

**Dashboards to check:**
1. **Microservices Monitoring** (UID: microservices-monitoring-001)
   - 32 panels: Response time, RPS, Error rate, Go runtime, Resources
2. **SLO Overview** (ID: 14643)
   - SLO compliance, Error budget remaining
3. **SLO Detailed** (ID: 14348)
   - Burn rates, Alert history
4. **Tempo Observability**
   - Trace search, Service graphs
5. **Vector Monitoring** (ID: 21954)
   - Vector self-monitoring

### Prometheus Queries

**Port-forward Prometheus:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

**Test queries:**
- **URL**: http://localhost:9090
- **Query**: `rate(requests_total{job="microservices"}[5m])`
- **Expected**: See metrics for all 9 services

**Key queries:**
```promql
# Request rate per service
rate(requests_total{job="microservices"}[5m])

# P95 latency
histogram_quantile(0.95, rate(request_duration_seconds_bucket[5m]))

# Error rate
sum(rate(requests_total{code=~"5.."}[5m])) / sum(rate(requests_total[5m]))

# Goroutines (memory leak detection)
go_goroutines{job="microservices"}
```

---

## Debugging Workflows

### Debug Pod Not Starting

**Check pod status:**
```bash
kubectl get pods -n <namespace>
```

**Common issues:**

**Issue 1: ImagePullBackOff**
```bash
kubectl describe pod <pod-name> -n <namespace>
# Events: Failed to pull image "ghcr.io/duynhne/auth:v5"
```

**Solution**:
```bash
# Build image locally
./scripts/05-build-microservices.sh

# Load image into Kind cluster
kind load docker-image ghcr.io/duynhne/auth:v5 --name monitoring-cluster
```

**Issue 2: CrashLoopBackOff**
```bash
kubectl logs <pod-name> -n <namespace>
# Check application logs for errors
```

**Solution**:
- Fix application error in code
- Rebuild image
- Redeploy service

### Debug Metrics Not Appearing

**Step 1: Check pod has `/metrics` endpoint**
```bash
kubectl port-forward -n auth <pod-name> 8080:8080
curl http://localhost:8080/metrics | grep requests_total
```

**Expected**: See `requests_total` metric

**Step 2: Check ServiceMonitor**
```bash
kubectl get servicemonitor -n monitoring
# Should see: microservices
```

**Step 3: Check Prometheus targets**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/targets
# Search for: microservices
```

**Expected**: All 9 services with state "UP"

**Step 4: Check namespace labels**
```bash
kubectl get ns --show-labels | grep monitoring
# auth namespace should have: monitoring=enabled
```

**Fix**:
```bash
kubectl label namespace auth monitoring=enabled
```

### Debug Traces Not Appearing

**Step 1: Check Tempo is running**
```bash
kubectl get pods -n monitoring -l app=tempo
# Should be: Running
```

**Step 2: Check microservice logs**
```bash
kubectl logs -n auth -l app=auth --tail=10 | grep -i tracing
# Should see: "OpenTelemetry tracing initialized"
```

**Step 3: Check Tempo endpoint**
```bash
kubectl port-forward -n monitoring svc/tempo 4318:4318
# Tempo OTLP HTTP endpoint should be reachable
```

**Step 4: Check trace sampling rate**
```bash
kubectl get deployment auth -n auth -o yaml | grep OTEL_SAMPLE_RATE
# Should see: OTEL_SAMPLE_RATE: "0.1" (10% sampling)
```

**Increase sampling for debugging:**
```bash
# Edit deployment
kubectl edit deployment auth -n auth

# Change OTEL_SAMPLE_RATE to "1.0" (100% sampling)
# Save and exit
```

### Debug SLO Metrics Missing

**Step 1: Check PrometheusServiceLevels**
```bash
kubectl get prometheusservicelevels -n monitoring
```

**Expected**: 9 SLOs with `GEN OK = true`

**If `GEN OK = false`:**
```bash
# Check Sloth logs
kubectl logs -n monitoring -l app=sloth --tail=50

# Common issue: Prometheus Operator webhook rejection
# Solution: Delete webhook
kubectl delete validatingwebhookconfigurations kube-prometheus-stack-admission

# Restart Sloth
kubectl delete pod -n monitoring -l app=sloth
```

**Step 2: Check PrometheusRules**
```bash
kubectl get prometheusrules -n monitoring | grep slo
```

**Expected**: 9 PrometheusRules (one per service)

**Step 3: Check Prometheus loaded rules**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/rules
# Search for: sloth_service
```

**Step 4: Check base metrics exist**
```promql
requests_total{job="microservices", app="auth"}
```

**If no results**: Microservices not exposing metrics (see "Debug Metrics Not Appearing")

---

## Common Operations

### Add a New Microservice

**Step 1: Create service code**
```bash
mkdir -p services/cmd/newservice
mkdir -p services/internal/newservice/web/{v1,v2}
mkdir -p services/internal/newservice/logic/{v1,v2}
mkdir -p services/internal/newservice/core/domain
```

**Step 2: Implement service**
- Copy structure from existing service (e.g., auth)
- Update package names
- Implement handlers, logic, domain models

**Step 3: Create Helm values**
```bash
cp charts/values/auth.yaml charts/values/newservice.yaml
```

**Edit `charts/values/newservice.yaml`:**
```yaml
name: newservice
namespace: newservice
image:
  name: newservice
  tag: v5
```

**Step 4: Create SLO definition**
```bash
cp k8s/sloth/crds/auth-slo.yaml k8s/sloth/crds/newservice-slo.yaml
```

**Edit `k8s/sloth/crds/newservice-slo.yaml`:**
```yaml
metadata:
  name: newservice-slo
spec:
  service: newservice
  ...
```

**Step 5: Build and deploy**
```bash
# Add to build script
# Edit scripts/05-build-microservices.sh
# Add "newservice" to SERVICES array

# Build
./scripts/05-build-microservices.sh

# Add to deploy script
# Edit scripts/06-deploy-microservices.sh
# Add "newservice" to SERVICES array

# Deploy
./scripts/06-deploy-microservices.sh --local

# Apply SLO
kubectl apply -f k8s/sloth/crds/newservice-slo.yaml
```

**Step 6: Verify**
```bash
kubectl get pods -n newservice
kubectl get svc -n newservice
kubectl get prometheusservicelevels -n monitoring | grep newservice
```

### Update Grafana Dashboard

**Step 1: Edit dashboard JSON**
```bash
# Edit file
vi k8s/grafana-operator/dashboards/microservices-dashboard.json

# Add new panel, modify queries, etc.
```

**Step 2: Reload dashboard**
```bash
./scripts/10-reload-dashboard.sh
```

**Step 3: Verify**
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana-service 3000:3000

# Open dashboard
open http://localhost:3000/d/microservices-monitoring-001/
```

### Update Service Code

**Step 1: Modify code**
```bash
vi services/internal/auth/web/v1/handler.go
# Make changes
```

**Step 2: Rebuild image**
```bash
docker build \
  --build-arg SERVICE_NAME=auth \
  -t ghcr.io/duynhne/auth:v5 \
  -f services/Dockerfile services/

# Load into Kind
kind load docker-image ghcr.io/duynhne/auth:v5 --name monitoring-cluster
```

**Step 3: Restart deployment**
```bash
kubectl rollout restart deployment auth -n auth

# Watch rollout
kubectl rollout status deployment auth -n auth
```

**Step 4: Verify**
```bash
kubectl logs -n auth -l app=auth --tail=20
```

### Clean Up Cluster

**Delete everything:**
```bash
./scripts/cleanup.sh
```

**Or manual cleanup:**
```bash
# Delete Kind cluster
kind delete cluster --name monitoring-cluster

# Verify
kind get clusters
# (empty)
```

### Troubleshoot Latency Issues

**Run diagnostic script:**
```bash
./scripts/11-diagnose-latency.sh <service-name>
```

**Example:**
```bash
./scripts/11-diagnose-latency.sh auth
```

**What it checks:**
1. P95 latency from Prometheus
2. Recent deployment history
3. Goroutine count (memory leak?)
4. Error logs
5. Slow traces in Tempo
6. CPU/heap profile

### Respond to Error Budget Alert

**Run runbook script:**
```bash
./scripts/12-error-budget-alert.sh <service-name> <burn-rate>
```

**Example:**
```bash
./scripts/12-error-budget-alert.sh auth 5.2
```

**What it does:**
1. Check current error rate
2. Check recent deployments
3. Check error logs
4. Suggest actions based on burn rate

---

## Best Practices

### Development

1. **Always test locally first** before pushing
2. **Use structured logging** with trace-id
3. **Add metrics** for important operations
4. **Create spans** for database calls, external APIs
5. **Handle errors gracefully** with proper status codes

### Deployment

1. **Deploy monitoring BEFORE apps** (03, 04 before 05-06)
2. **Verify health checks** before declaring success
3. **Check logs** after deployment
4. **Monitor dashboards** for 5 minutes after deploy
5. **Keep rollback plan ready** (kubectl rollout undo)

### Testing

1. **Run load tests** in dedicated namespace (k6)
2. **Monitor SLO metrics** during tests
3. **Check all 4 pillars** (metrics, traces, logs, profiles)
4. **Validate error budget** consumption is acceptable
5. **Test edge cases** with k6 edge journeys

### Debugging

1. **Start with dashboards** (high-level view)
2. **Drill down to traces** (request-level view)
3. **Correlate with logs** (detailed context)
4. **Check profiles** if CPU/memory issue
5. **Use runbook scripts** for common issues

---

## Useful Commands Reference

### kubectl

```bash
# Get all pods in all namespaces
kubectl get pods -A

# Get pods for specific service
kubectl get pods -n auth -l app=auth

# Logs (follow)
kubectl logs -n auth -l app=auth -f

# Logs (last 100 lines)
kubectl logs -n auth -l app=auth --tail=100

# Describe pod (events)
kubectl describe pod <pod-name> -n <namespace>

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Port-forward service
kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<remote-port>

# Restart deployment
kubectl rollout restart deployment <name> -n <namespace>

# Rollback deployment
kubectl rollout undo deployment <name> -n <namespace>

# Get events (recent)
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

### Helm

```bash
# List releases
helm list -A

# Get values
helm get values <release-name> -n <namespace>

# Upgrade release
helm upgrade <release-name> <chart> -f <values.yaml> -n <namespace>

# Uninstall release
helm uninstall <release-name> -n <namespace>

# Show chart values
helm show values <chart>
```

### Docker

```bash
# Build image
docker build -t <image-name>:<tag> -f <dockerfile> <context>

# List images
docker images

# Load image into Kind
kind load docker-image <image-name>:<tag> --name <cluster-name>

# Remove image
docker rmi <image-name>:<tag>
```

---

**End of System Context Documentation** 🎉

Return to [README](README.md) for navigation.

