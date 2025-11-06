# Plan: Execute Full Deployment from Scratch

## Overview

Chạy tất cả 6 deployment scripts theo thứ tự để deploy hoàn chỉnh hệ thống 9 microservices với Prometheus, Grafana, và k6 load testing.

## Prerequisites Check

- Verify Docker is running
- Verify kubectl is installed
- Verify Kind is accessible
- Check current directory is project root

## Deployment Steps

### Step 1: Create Kind Cluster

**Script**: `./scripts/01-create-kind-cluster.sh`

**Actions**:

- Delete existing `monitoring-local` cluster if exists
- Create new 3-node Kind cluster (1 control-plane, 2 workers)
- Configure port mappings (8080, 9090, 3000)
- Wait for nodes to be ready
- Verify cluster is accessible

**Expected Output**: 3 nodes in Ready state

---

### Step 2: Install Metrics Infrastructure

**Script**: `./scripts/02-install-metrics.sh`

**Actions**:

- Install kube-state-metrics in `kube-system` namespace
- Install metrics-server in `kube-system` namespace
- Patch metrics-server for Kind (insecure TLS)
- Wait for both services to be ready

**Expected Output**: kube-state-metrics and metrics-server pods running

---

### Step 3: Build & Load Microservices

**Script**: `./scripts/03-build-microservices.sh`

**Actions**:

- Build Docker images for 9 services:

  1. auth-service
  2. user-service
  3. product-service
  4. cart-service
  5. order-service
  6. review-service
  7. notification-service
  8. shipping-service
  9. shipping-service-v2

- Load each image into Kind cluster

**Expected Duration**: 5-10 minutes (Docker builds)

**Expected Output**: 9 Docker images loaded into Kind

---

### Step 4: Deploy Microservices

**Script**: `./scripts/04-deploy-microservices.sh`

**Actions**:

- Create 8 namespaces (auth, user, product, cart, order, review, notification, shipping)
- Deploy 9 services to respective namespaces
- Wait for all pods to be ready (timeout 60s per service)
- Display pod status for all namespaces

**Expected Output**: 18 pods running (2 replicas × 9 services)

---

### Step 5: Deploy Monitoring Stack

**Script**: `./scripts/05-deploy-monitoring.sh`

**Actions**:

- Install Prometheus Operator (CRDs + operator pod)
- Deploy Prometheus instance in `monitoring` namespace
- Deploy Grafana in `monitoring` namespace
- Deploy centralized ServiceMonitor to discover all 9 services
- Wait for Prometheus and Grafana to be ready

**Expected Output**:

- Prometheus pod running
- Grafana pod running
- ServiceMonitor created
- All 9 services discovered as Prometheus targets

---

### Step 6: Deploy k6 Load Testing

**Script**: `./scripts/06-deploy-k6-testing.sh`

**Actions**:

- Create ConfigMap from `k6/load-test.js`
- Deploy k6-load-generator pod in `monitoring` namespace
- Wait for k6 pod to be ready
- Verify k6 is running load tests

**Expected Output**: k6 pod running and generating traffic to all 9 services

---

## Post-Deployment Verification

### 1. Check All Pods

```bash
kubectl get pods --all-namespaces
```

**Expected**: ~30 pods total (18 app + metrics + monitoring + k6)

### 2. Check Prometheus Targets

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Then visit: http://localhost:9090/targets

**Expected**: 9 service targets all UP

### 3. Check Grafana Dashboard

```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

Then visit: http://localhost:3000 (admin/admin)

**Expected**: Dashboard shows metrics from all 9 services

### 4. Check k6 Load Generation

```bash
kubectl logs -n monitoring -l app=k6-load-generator -f
```

**Expected**: Load test running, requests being sent

---

## Error Handling

### If Step Fails:

1. Check logs: `kubectl logs -n <namespace> <pod-name>`
2. Check events: `kubectl get events -n <namespace>`
3. Re-run failed script after fixing issue
4. Continue from next step

### Common Issues:

- **Docker not running**: Start Docker Desktop
- **Image pull errors**: Check Docker images exist
- **Pod pending**: Check node resources
- **Prometheus targets down**: Check ServiceMonitor labels match service labels

---

## Cleanup (if needed)

```bash
./scripts/cleanup.sh
```

This will delete the entire Kind cluster and all resources.

---

## Timeline

- **Total Duration**: ~15-20 minutes
- **Build phase**: 5-10 minutes (step 3)
- **Deploy phase**: 5-10 minutes (steps 4-6)
- **Verification**: 2-3 minutes

---

## Success Criteria

✅ All 9 services deployed and running

✅ Prometheus scraping metrics from all services

✅ Grafana dashboard displaying data

✅ k6 generating realistic load across all services

✅ No pods in CrashLoopBackOff or Error state