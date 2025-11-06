# /deploy Command

## Purpose
Deploy changes to Kubernetes cluster

## Instructions
1. Build Docker images if needed using unified Dockerfile
2. Load images to Kind cluster (if using Kind)
3. Apply Kubernetes manifests using numbered scripts
4. Verify pod status and logs
5. Restart deployments if ConfigMaps changed
6. Provide port-forward commands for access

## Deployment Steps

### Build and Load Images

**Option 1: Use Build Script (Recommended)**
```bash
./scripts/03-build-microservices.sh
```

**Option 2: Manual Build**
Build individual service using unified Dockerfile:
```bash
# Build auth-service
docker build --build-arg SERVICE_NAME=auth-service -t auth-service:latest .

# Build other services similarly
docker build --build-arg SERVICE_NAME=user-service -t user-service:latest .
docker build --build-arg SERVICE_NAME=product-service -t product-service:latest .
# ... etc for all 9 services
```

**Load to Kind (if using Kind)**
```bash
# Load all images at once
kind load docker-image auth-service:latest user-service:latest product-service:latest --name <cluster-name>

# Or load individually
kind load docker-image auth-service:latest --name <cluster-name>
```

### Apply Kubernetes Manifests

**Option 1: Use Deployment Scripts (Recommended)**
```bash
# Step 1: Create Kind cluster
./scripts/01-create-kind-cluster.sh

# Step 2: Install metrics infrastructure
./scripts/02-install-metrics.sh

# Step 3: Build microservices (already done above)
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

**Option 2: Manual Deployment**
```bash
# Apply namespaces
kubectl apply -f k8s/namespaces.yaml

# Deploy services (each in its own namespace)
kubectl apply -f k8s/auth-service/
kubectl apply -f k8s/user-service/
kubectl apply -f k8s/product-service/
kubectl apply -f k8s/cart-service/
kubectl apply -f k8s/order-service/
kubectl apply -f k8s/review-service/
kubectl apply -f k8s/notification-service/
kubectl apply -f k8s/shipping-service/
kubectl apply -f k8s/shipping-service-v2/

# Deploy monitoring components
kubectl apply -f k8s/prometheus/
kubectl apply -f k8s/grafana/
kubectl apply -f k8s/k6/
```

### Deploy SLO Components
```bash
# Use SLO deployment script (validates, generates, deploys)
./scripts/11-deploy-slo.sh
```

### Verify Deployment

**Check Pod Status by Namespace**
```bash
# Service namespaces
kubectl get pods -n auth
kubectl get pods -n user
kubectl get pods -n product
kubectl get pods -n cart
kubectl get pods -n order
kubectl get pods -n review
kubectl get pods -n notification
kubectl get pods -n shipping

# Monitoring namespace
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

**Check Logs**
```bash
# Service logs (example: auth-service)
kubectl logs -l app=auth-service -n auth

# Monitoring logs
kubectl logs -l app=prometheus -n monitoring
kubectl logs -l app=grafana -n monitoring
kubectl logs -l app=k6-load-generator -n monitoring
```

### Port Forwarding

**Grafana**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

**Prometheus**
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

**API Services (example: auth-service)**
```bash
kubectl port-forward -n auth svc/auth-service 8080:8080
```

### Restart Deployments (if ConfigMaps changed)

**Dashboard Changes**
```bash
./scripts/08-reload-dashboard.sh
```

**Prometheus Config Changes**
```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

**Service Restart (example: auth-service)**
```bash
kubectl rollout restart deployment/auth-service -n auth
```
