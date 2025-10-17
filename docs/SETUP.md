# Setup Guide - Kubernetes Monitoring Demo

Complete guide to deploy Go REST API monitoring on Kind (Kubernetes in Docker).

---

## Quick Start (5 Minutes)

### One-Command Deployment

```bash
cd project-monitoring-golang
./scripts/deploy-all.sh
```

Wait 5 minutes. Then access:

```
Go API:     http://localhost:8080
Prometheus: http://localhost:9090
Grafana:    http://localhost:3000 (admin/admin)
Dashboard:  http://localhost:3000/d/go-monitoring-demo/
```

**Done!** Skip to [Generating Traffic](#generating-traffic) section.

---

## Prerequisites

### Required

- **Docker** - For Kind cluster
- **kubectl** - Kubernetes CLI
- **Kind** - Auto-installed by script or manual:
  ```bash
  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
  chmod +x ./kind
  sudo mv ./kind /usr/local/bin/kind
  ```

### Optional

- None - CronJob handles load testing automatically

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
./scripts/02-install-metrics-infrastructure.sh
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

### Step 3: Build & Load Image

```bash
./scripts/03-build-and-load.sh
```

**What it does:**
- Builds Go application Docker image
- Loads image into Kind cluster nodes
- Verifies image availability

**Verify:**
```bash
docker images | grep demo-go-api
# Expected: demo-go-api:local image
```

---

### Step 4: Deploy Application

```bash
./scripts/04-deploy-app.sh
```

**What it does:**
- Creates `monitoring-demo` namespace
- Deploys 3 replicas of Go API
- Creates NodePort service (port 30080)
- Sets up ServiceMonitor for Prometheus discovery

**Verify:**
```bash
kubectl get pods -n monitoring-demo
# Expected: 3 demo-go-api pods running

curl http://localhost:8080/health
# Expected: OK
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
- Sets up services with NodePort

**Verify:**
```bash
kubectl get pods -n monitoring-demo
# Expected: prometheus and grafana pods running

curl http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

curl http://localhost:3000/api/health
# Expected: {"database":"ok"}
```

---

## Generating Traffic

### Automatic (CronJob)

A CronJob runs every 2 minutes automatically:

```bash
kubectl get cronjob -n monitoring-demo
# demo-loadtest - Runs */2 * * * *
```

**Manual trigger:**
```bash
kubectl create job --from=cronjob/demo-loadtest manual-test-$(date +%s) -n monitoring-demo
```

**Pause CronJob:**
```bash
kubectl patch cronjob demo-loadtest -n monitoring-demo -p '{"spec":{"suspend":true}}'
```

### Manual Testing

#### Simple Curl Test

```bash
# Test endpoints
for i in {1..100}; do curl -s http://localhost:8080/api/users & done
for i in {1..50}; do curl -s http://localhost:8080/api/products & done
wait
```


---

## Accessing Grafana Dashboard

### Web UI

1. Open: **http://localhost:3000**
2. Login: `admin` / `admin` (skip password change)
3. Dashboard auto-appears: **"Go REST API Monitoring - Demo"**

**Direct URL:**
```
http://localhost:3000/d/go-monitoring-demo/
```

### Dashboard Variables

Adjust filters in dashboard header:

- **App**: Select `demo-go-api`
- **Namespace**: Select `monitoring-demo`
- **Rate**: Query interval (1m, 5m, 10m...)

---

## Useful Commands

### Cluster Management

```bash
# List clusters
kind get clusters

# Cluster info
kubectl cluster-info

# All resources in namespace
kubectl get all -n monitoring-demo

# Delete cluster
kind delete cluster --name monitoring-demo
```

### Pod Management

```bash
# Watch pods
kubectl get pods -n monitoring-demo -w

# Pod logs (follow)
kubectl logs -f deployment/demo-go-api -n monitoring-demo

# Exec into pod
kubectl exec -it <pod-name> -n monitoring-demo -- sh

# Scale application
kubectl scale deployment demo-go-api --replicas=5 -n monitoring-demo
```

### Port Forwarding

If NodePort doesn't work (WSL2/Windows issues):

```bash
# Forward Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring-demo &

# Forward Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n monitoring-demo &

# Forward Go API
kubectl port-forward svc/demo-go-api 8080:8080 -n monitoring-demo &
```

### Debugging

```bash
# Check events
kubectl get events -n monitoring-demo --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod <pod-name> -n monitoring-demo

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.job'

# Restart deployment
kubectl rollout restart deployment <name> -n monitoring-demo
```

---

## Troubleshooting

### Cluster Creation Fails

**Issue:** Port already in use

```bash
# Check running containers
docker ps

# Stop conflicting services
docker stop $(docker ps -q)

# Try again
./scripts/01-create-kind-cluster.sh
```

### Pods Not Starting

**Issue:** ImagePullBackOff

```bash
# Rebuild and reload image
./scripts/03-build-and-load.sh

# Force recreation
kubectl delete pods -l app=demo-go-api -n monitoring-demo
```

### Dashboard No Data

**Issue:** Metrics not collected

```bash
# 1. Check Prometheus targets
open http://localhost:9090/targets
# demo-go-api should be UP

# 2. Run query
open http://localhost:9090/graph
# Query: request_duration_seconds_count

# 3. Trigger load test manually
kubectl create job --from=cronjob/demo-loadtest manual-test -n monitoring-demo

# 4. Check Prometheus logs
kubectl logs deployment/prometheus -n monitoring-demo
```

### Grafana Dashboard Empty

**Issue:** Dashboard not provisioned

```bash
# Check ConfigMaps
kubectl get configmap -n monitoring-demo | grep grafana

# Recreate dashboard ConfigMap
kubectl delete configmap grafana-dashboard-json -n monitoring-demo
kubectl create configmap grafana-dashboard-json \
  --from-file=go-monitoring-demo.json=grafana-dashboard.json \
  -n monitoring-demo

# Restart Grafana
kubectl rollout restart deployment grafana -n monitoring-demo
```

### Services Not Accessible

**Issue:** NodePort not working (WSL2)

```bash
# Use port-forwarding instead
kubectl port-forward svc/grafana 3000:3000 -n monitoring-demo &
kubectl port-forward svc/prometheus 9090:9090 -n monitoring-demo &
kubectl port-forward svc/demo-go-api 8080:8080 -n monitoring-demo &

# Access via localhost
curl http://localhost:3000
```

---

## Complete Cleanup

### Delete Everything

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
kind delete cluster --name monitoring-demo

# Verify
kind get clusters
# Should be empty

# Clean Docker
docker system prune -f
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
- Application pods (3x): ~400 MB RAM
- Monitoring stack: ~1 GB RAM
```

### Performance

With 50 RPS load test:
- **P50**: ~50-100ms
- **P95**: ~100-200ms  
- **P99**: ~200-400ms
- **Error Rate**: 3-5% (simulated)
- **Throughput**: ~45-50 req/s actual

---

## Next Steps

After successful deployment:

1. **Explore Dashboard** - Check all 22 panels (see [METRICS.md](./METRICS.md))
2. **Run Load Tests** - Try different scenarios
3. **Customize Metrics** - Add your own business metrics
4. **Setup Alerts** - Configure Grafana alerting
5. **Scale Application** - Test with more replicas

---

## Additional Resources

- **Kind Documentation**: https://kind.sigs.k8s.io/
- **Prometheus K8s Config**: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config
- **Grafana Provisioning**: https://grafana.com/docs/grafana/latest/administration/provisioning/

---

**Ready to monitor!** 🚀

For detailed metrics explanation, see [METRICS.md](./METRICS.md).

For quick commands reference, see [DEMO_CHEATSHEET.md](./DEMO_CHEATSHEET.md).

