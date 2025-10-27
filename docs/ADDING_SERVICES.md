# Adding New Microservices

## Overview

This monitoring platform automatically discovers and monitors any microservice that follows the established conventions. No dashboard changes are needed when adding new services.

## Requirements

Your service will automatically appear in monitoring if it meets these requirements:

### 1. Expose Metrics Endpoint
- Service must expose `/metrics` endpoint with Prometheus format
- Port should be 8080 (or update ServiceMonitor if different)

### 2. Kubernetes Labels
Your service deployment and service must have these labels:

```yaml
metadata:
  labels:
    app: your-service-name        # Service name without version
    version: v1                   # Version tag (v1, v2, v3, etc.)
    component: api                # Always 'api' for API services
```

### 3. Service Configuration
Your Kubernetes Service must have the same labels:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: your-service-v1
  namespace: your-namespace
  labels:
    app: your-service-name
    version: v1
    component: api
spec:
  selector:
    app: your-service-name
    version: v1
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
```

### 4. Namespace Inclusion
Your service's namespace must be included in the ServiceMonitor's `namespaceSelector`:

```yaml
# In k8s/monitoring/servicemonitors.yaml
spec:
  namespaceSelector:
    matchNames:
    - user
    - product
    - checkout
    - order
    - unified
    - your-new-namespace  # Add your namespace here
```

## Example: Adding Payment Service

### Step 1: Create Namespace
```bash
kubectl create namespace payment
```

### Step 2: Deploy Service
```yaml
# k8s/payment-service-v1/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service-v1
  namespace: payment
  labels:
    app: payment-service
    version: v1
    component: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-service
      version: v1
  template:
    metadata:
      labels:
        app: payment-service
        version: v1
        component: api
    spec:
      containers:
      - name: payment-service
        image: payment-service-v1:latest
        ports:
        - containerPort: 8080
        # ... rest of container config
```

### Step 3: Create Service
```yaml
# k8s/payment-service-v1/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: payment-service-v1
  namespace: payment
  labels:
    app: payment-service
    version: v1
    component: api
spec:
  selector:
    app: payment-service
    version: v1
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
  type: ClusterIP
```

### Step 4: Update ServiceMonitor
Add your namespace to the ServiceMonitor:

```yaml
# k8s/monitoring/servicemonitors.yaml
spec:
  namespaceSelector:
    matchNames:
    - user
    - product
    - checkout
    - order
    - unified
    - payment  # Add this line
```

### Step 5: Apply Changes
```bash
kubectl apply -f k8s/payment-service-v1/
kubectl apply -f k8s/monitoring/servicemonitors.yaml
```

## Automatic Discovery

Once deployed, your service will automatically:

✅ **Appear in Grafana dashboard** - No dashboard changes needed
✅ **Show in app dropdown** - Service name appears in filter
✅ **Display metrics** - All 32 panels show data for your service
✅ **Support filtering** - Filter by service, namespace, version
✅ **Scale monitoring** - Works with any number of replicas

## Dashboard Features

Your new service will have access to all monitoring features:

- **Response Time Metrics** - p50, p95, p99 percentiles
- **RPS Monitoring** - Requests per second tracking
- **Error Rate Tracking** - 4xx/5xx error monitoring
- **Resource Usage** - CPU, memory, network
- **Go Runtime Health** - GC, goroutines, memory leak detection
- **SLO Tracking** - Service level objective monitoring

## Troubleshooting

### Service Not Appearing in Dashboard

1. **Check labels**: Ensure `component: api` label is present
2. **Verify namespace**: Check if namespace is in ServiceMonitor
3. **Check metrics endpoint**: Test `/metrics` endpoint manually
4. **Prometheus targets**: Check http://localhost:9090/targets

### No Data in Panels

1. **Wait for scrape**: Prometheus scrapes every 30 seconds
2. **Check time range**: Ensure dashboard time range includes current time
3. **Verify app filter**: Check if correct service is selected
4. **Check metrics format**: Ensure metrics follow Prometheus format

### Adding Custom Metrics

Your service can expose any custom metrics. They will automatically appear in Grafana if they follow Prometheus naming conventions:

```go
// Example custom metric
var customCounter = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "custom_operations_total",
        Help: "Total number of custom operations",
    },
    []string{"app", "namespace", "operation"},
)
```

## Best Practices

1. **Consistent Naming**: Use `service-name-v1` pattern
2. **Namespace per Service**: One namespace per service type
3. **Label Consistency**: Always include required labels
4. **Metrics Quality**: Use meaningful metric names and labels
5. **Documentation**: Document your service's metrics

## Support

For questions or issues:
1. Check this documentation
2. Review existing service examples
3. Check Prometheus targets page
4. Verify Grafana dashboard configuration
