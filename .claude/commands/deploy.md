# /deploy Command

## Purpose
Deploy changes to Kubernetes cluster

## Instructions
1. Build Docker images if needed
2. Load images to Kind cluster
3. Apply Kubernetes manifests
4. Verify pod status and logs
5. Restart deployments if ConfigMaps changed
6. Provide port-forward commands for access

## Deployment Steps

### Build and Load Images
1. **Build Go App**
   ```bash
   docker build -t demo-go-api:latest .
   kind load docker-image demo-go-api:latest --name monitoring-demo
   ```

2. **Build k6 Image**
   ```bash
   cd k6
   docker build -t k6-prometheus:latest .
   kind load docker-image k6-prometheus:latest --name monitoring-demo
   ```

### Apply Kubernetes Manifests
1. **Apply All Components**
   ```bash
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/prometheus/
   kubectl apply -f k8s/grafana/
   kubectl apply -f k8s/go-app/
   kubectl apply -f k8s/go-app-v2/
   kubectl apply -f k8s/go-app-v3/
   kubectl apply -f k8s/k6/
   ```

2. **Apply SLO Components**
   ```bash
   ./slo/scripts/deploy-slo.sh
   ```

### Verify Deployment
1. **Check Pod Status**
   ```bash
   kubectl get pods -n monitoring-demo
   kubectl get svc -n monitoring-demo
   ```

2. **Check Logs**
   ```bash
   kubectl logs -l app=demo-go-api -n monitoring-demo
   kubectl logs -l app=prometheus -n monitoring-demo
   kubectl logs -l app=grafana -n monitoring-demo
   kubectl logs -l app=k6-load-generator -n monitoring-demo
   ```

### Port Forwarding
1. **Grafana**
   ```bash
   kubectl port-forward -n monitoring-demo svc/grafana 3000:3000
   ```

2. **Prometheus**
   ```bash
   kubectl port-forward -n monitoring-demo svc/prometheus 9090:9090
   ```

3. **API**
   ```bash
   kubectl port-forward -n monitoring-demo svc/demo-go-api 8080:8080
   ```

### Restart Deployments (if ConfigMaps changed)
```bash
kubectl rollout restart deployment/grafana -n monitoring-demo
kubectl rollout restart deployment/prometheus -n monitoring-demo
kubectl rollout restart deployment/demo-go-api -n monitoring-demo
```
