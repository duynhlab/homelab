# Deployment Guide

## Prerequisites

### Required Software
- **Docker** - Container runtime
- **Kind** - Kubernetes in Docker
- **kubectl** - Kubernetes CLI
- **Go 1.22+** - For building services (optional)

### System Requirements
- **RAM**: 8GB+ recommended
- **CPU**: 4+ cores recommended
- **Disk**: 10GB+ free space

## Quick Deployment (Recommended)

### Step-by-Step Deploy
```bash
git clone <repo-url>
cd project-monitoring-golang

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
```

Each script does ONE thing:
1. **01-create-kind-cluster.sh** - Creates Kind cluster with 3 nodes
2. **02-install-metrics.sh** - Installs Prometheus/Grafana operators
3. **03-build-microservices.sh** - Builds Docker images for all 5 services
4. **04-deploy-microservices.sh** - Deploys all services to Kubernetes
5. **05-deploy-monitoring.sh** - Deploys monitoring stack and dashboards

## Manual Deployment (Step by Step)

### Step 1: Create Kind Cluster
```bash
./scripts/01-create-kind-cluster.sh
```

This creates a Kind cluster with:
- 3 worker nodes
- Ingress controller
- Load balancer support

### Step 2: Install Metrics Infrastructure
```bash
./scripts/02-install-metrics-infrastructure.sh
```

This installs:
- Prometheus Operator
- Grafana Operator
- ServiceMonitor CRDs
- RBAC permissions

### Step 3: Build All Services
```bash
./scripts/build-all-services.sh
```

This builds Docker images for:
- user-service-v1
- product-service-v1
- checkout-service-v1
- order-service-v2
- unified-service-v3

### Step 4: Deploy All Services
```bash
./scripts/deploy-all-services.sh
```

This deploys all 5 microservices with:
- Kubernetes Deployments
- Services
- ServiceMonitors for Prometheus

### Step 5: Deploy Monitoring
```bash
./scripts/05-deploy-monitoring.sh
```

This deploys:
- Prometheus instance
- Grafana instance
- Grafana dashboards
- SLO rules and alerts

## Verification

### Check Pod Status
```bash
kubectl get pods -n monitoring-demo
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
user-service-v1-xxx                     1/1     Running   0          2m
product-service-v1-xxx                  1/1     Running   0          2m
checkout-service-v1-xxx                 1/1     Running   0          2m
order-service-v2-xxx                    1/1     Running   0          2m
unified-service-v3-xxx                  1/1     Running   0          2m
prometheus-xxx                          1/1     Running   0          2m
grafana-xxx                             1/1     Running   0          2m
k6-load-generator-xxx                   1/1     Running   0          2m
```

### Check Services
```bash
kubectl get svc -n monitoring-demo
```

### Check Prometheus Targets
```bash
kubectl port-forward -n monitoring-demo svc/prometheus 9090:9090 &
# Open http://localhost:9090/targets
```

All microservices should show as "UP" in Prometheus targets.

## Access Services

### Port Forward All Services
```bash
# Microservices
kubectl port-forward -n monitoring-demo svc/user-service-v1 8081:8080 &
kubectl port-forward -n monitoring-demo svc/product-service-v1 8082:8080 &
kubectl port-forward -n monitoring-demo svc/checkout-service-v1 8083:8080 &
kubectl port-forward -n monitoring-demo svc/order-service-v2 8084:8080 &
kubectl port-forward -n monitoring-demo svc/unified-service-v3 8085:8080 &

# Monitoring
kubectl port-forward -n monitoring-demo svc/grafana 3000:3000 &
kubectl port-forward -n monitoring-demo svc/prometheus 9090:9090 &
```

### Test APIs
```bash
# Test User Service
curl http://localhost:8081/api/v1/users
curl -X POST http://localhost:8081/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com"}'

# Test Product Service
curl http://localhost:8082/api/v1/products
curl -X POST http://localhost:8082/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Product","price":99.99,"stock":10}'

# Test Unified Service
curl http://localhost:8085/api/v3/users
curl http://localhost:8085/api/v3/products
```

### Access Monitoring
- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090

## Troubleshooting

### Common Issues

#### 1. Pods Not Starting
```bash
# Check pod logs
kubectl logs -n monitoring-demo deployment/user-service-v1
kubectl describe pod -n monitoring-demo -l app=user-service
```

#### 2. Services Not Accessible
```bash
# Check service endpoints
kubectl get endpoints -n monitoring-demo
kubectl describe svc -n monitoring-demo user-service-v1
```

#### 3. Prometheus Not Scraping
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n monitoring-demo
kubectl describe servicemonitor -n monitoring-demo user-service-v1

# Check Prometheus config
kubectl exec -n monitoring-demo deployment/prometheus -- cat /etc/prometheus/prometheus.yml
```

#### 4. Grafana Dashboard Not Loading
```bash
# Check Grafana logs
kubectl logs -n monitoring-demo deployment/grafana

# Check dashboard config
kubectl get configmap -n monitoring-demo grafana-dashboard-json -o yaml
```

### Debug Commands

```bash
# Get all resources
kubectl get all -n monitoring-demo

# Check events
kubectl get events -n monitoring-demo --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n monitoring-demo
kubectl top nodes

# Check logs for all pods
kubectl logs -n monitoring-demo -l component=api --tail=50
```

## Scaling

### Scale Individual Services
```bash
# Scale user service to 3 replicas
kubectl scale deployment user-service-v1 --replicas=3 -n monitoring-demo

# Scale all services
for service in user-service-v1 product-service-v1 checkout-service-v1 order-service-v2 unified-service-v3; do
  kubectl scale deployment $service --replicas=2 -n monitoring-demo
done
```

### Resource Limits
Each service has resource limits:
- **Memory**: 256Mi (request) / 512Mi (limit)
- **CPU**: 100m (request) / 500m (limit)

To modify limits, edit the deployment files in `k8s/{service-name}/deployment.yaml`.

## Load Testing

### Run k6 Load Tests
```bash
# Check k6 pod
kubectl get pods -n monitoring-demo -l app=k6-load-generator

# Run load test
kubectl exec -n monitoring-demo deployment/k6-load-generator -- k6 run /scripts/load-test.js

# Check k6 logs
kubectl logs -n monitoring-demo deployment/k6-load-generator
```

### Custom Load Test
```bash
# Create custom k6 script
cat > custom-test.js << EOF
import http from 'k6/http';
import { check } from 'k6';

export default function() {
  let response = http.get('http://user-service-v1:8080/api/v1/users');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
}
EOF

# Run custom test
kubectl cp custom-test.js monitoring-demo/$(kubectl get pod -n monitoring-demo -l app=k6-load-generator -o jsonpath='{.items[0].metadata.name}'):/tmp/
kubectl exec -n monitoring-demo deployment/k6-load-generator -- k6 run /tmp/custom-test.js
```

## Cleanup

### Remove Everything
```bash
# Delete Kind cluster
kind delete cluster --name monitoring-demo

# Or use cleanup script
./scripts/cleanup.sh
```

### Remove Individual Services
```bash
# Remove specific service
kubectl delete -f k8s/user-service-v1/

# Remove all microservices
kubectl delete -f k8s/user-service-v1/
kubectl delete -f k8s/product-service-v1/
kubectl delete -f k8s/checkout-service-v1/
kubectl delete -f k8s/order-service-v2/
kubectl delete -f k8s/unified-service-v3/
```

## Production Considerations

### Security
- Enable RBAC (already configured)
- Use secrets for sensitive data
- Enable network policies
- Use TLS for all communications

### Monitoring
- Set up alerting rules
- Configure external Prometheus
- Use Grafana Cloud or similar
- Set up log aggregation

### High Availability
- Use multiple Kind nodes
- Configure anti-affinity rules
- Set up external load balancer
- Use persistent volumes for data

### Performance
- Tune resource limits
- Use horizontal pod autoscaling
- Configure cluster autoscaling
- Optimize container images

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review logs using kubectl commands
3. Check Prometheus targets and metrics
4. Verify Grafana dashboard configuration
5. Create an issue in the repository
