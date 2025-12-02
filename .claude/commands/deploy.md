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
./scripts/05-build-microservices.sh
```

**Option 2: Manual Build**
Build individual service using unified Dockerfile:
```bash
# Build auth
docker build --build-arg SERVICE_NAME=auth -f services/Dockerfile -t ghcr.io/duynhne/auth:latest services/

# Build other services similarly
docker build --build-arg SERVICE_NAME=user -f services/Dockerfile -t ghcr.io/duynhne/user:latest services/
docker build --build-arg SERVICE_NAME=product -f services/Dockerfile -t ghcr.io/duynhne/product:latest services/
# ... etc for all 9 services
```

**Load to Kind (if using Kind)**
```bash
# Load all images at once
kind load docker-image ghcr.io/duynhne/auth:latest ghcr.io/duynhne/user:latest ghcr.io/duynhne/product:latest --name <cluster-name>

# Or load individually
kind load docker-image ghcr.io/duynhne/auth:latest --name <cluster-name>
```

### Apply Kubernetes Manifests

**Option 1: Use Deployment Scripts (Recommended)**
```bash
# Step 1: Create Kind cluster
./scripts/01-create-kind-cluster.sh

# Step 2: Install metrics infrastructure
./scripts/02-install-metrics.sh

# Step 3: Deploy monitoring stack (BEFORE apps to collect metrics immediately)
./scripts/03-deploy-monitoring.sh

# Step 4: Deploy APM stack (BEFORE apps to collect traces/logs/profiles immediately)
./scripts/04-deploy-apm.sh

# Step 5: Build microservices
./scripts/05-build-microservices.sh

# Step 6: Deploy all microservices
./scripts/06-deploy-microservices.sh

# Step 7: Deploy k6 load testing (AFTER apps to test them)
./scripts/07-deploy-k6-testing.sh

# Step 8: Deploy SLO system (Required for SRE practices)
./scripts/08-deploy-slo.sh

# Step 9: Setup port forwarding
./scripts/09-setup-access.sh
```

**Option 2: Manual Deployment (Helm)**
```bash
# Apply namespaces
kubectl apply -f k8s/namespaces.yaml

# Deploy services using Helm (each in its own namespace)
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace
helm upgrade --install user charts/ -f charts/values/user.yaml -n user --create-namespace
helm upgrade --install product charts/ -f charts/values/product.yaml -n product --create-namespace
helm upgrade --install cart charts/ -f charts/values/cart.yaml -n cart --create-namespace
helm upgrade --install order charts/ -f charts/values/order.yaml -n order --create-namespace
helm upgrade --install review charts/ -f charts/values/review.yaml -n review --create-namespace
helm upgrade --install notification charts/ -f charts/values/notification.yaml -n notification --create-namespace
helm upgrade --install shipping charts/ -f charts/values/shipping.yaml -n shipping --create-namespace
helm upgrade --install shipping-v2 charts/ -f charts/values/shipping-v2.yaml -n shipping --create-namespace

# Deploy monitoring components
kubectl apply -f k8s/prometheus/
kubectl apply -f k8s/grafana/
kubectl apply -f k8s/k6/
```

### Deploy SLO Components
```bash
# Use SLO deployment script (validates, generates, deploys)
./scripts/08-deploy-slo.sh
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
# Service logs (example: auth)
kubectl logs -l app=auth -n auth

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

**API Services (example: auth)**
```bash
kubectl port-forward -n auth svc/auth 8080:8080
```

### Restart Deployments (if ConfigMaps changed)

**Dashboard Changes**
```bash
./scripts/10-reload-dashboard.sh
```

**Prometheus Config Changes**
```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

**Service Restart (example: auth)**
```bash
kubectl rollout restart deployment/auth -n auth
```
