# Adding New Microservices

## Overview

This monitoring platform automatically discovers and monitors any microservice that follows the established conventions. No dashboard changes are needed when adding new services.

## Requirements

Your service will automatically appear in monitoring if it meets these requirements:

### 1. Expose Metrics Endpoint
- Service must expose `/metrics` endpoint with Prometheus format
- Port should be 8080 (or update values.yaml if different)

### 2. Use Prometheus Middleware
Your Go service should use the shared Prometheus middleware:

```go
import "github.com/duynhne/monitoring/pkg/middleware"

func main() {
    r := gin.Default()
    r.Use(middleware.PrometheusMiddleware())
    // ... rest of setup
}
```

### 3. Create Helm Values File
Create a values file for your service in `charts/values/`:

```yaml
# charts/values/payment.yaml
name: payment
namespace: payment

replicaCount: 2

image:
  repository: ghcr.io/duynhne
  name: payment
  tag: v5
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080
  targetPort: 8080

containerPort: 8080

resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

livenessProbe:
  enabled: true
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  enabled: true
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

labels:
  component: api
```

## Example: Adding Payment Service

### Step 1: Create Service Code

```bash
mkdir -p services/cmd/payment
mkdir -p services/internal/payment/web/{v1,v2}
mkdir -p services/internal/payment/logic/{v1,v2}
mkdir -p services/internal/payment/core/domain
```

Create the main entry point:

```go
// services/cmd/payment/main.go
package main

import (
    "context"
    "os"

    "github.com/gin-gonic/gin"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "go.uber.org/zap"

    v1 "github.com/duynhne/monitoring/internal/payment/web/v1"
    v2 "github.com/duynhne/monitoring/internal/payment/web/v2"
    "github.com/duynhne/monitoring/pkg/middleware"
)

func main() {
    // Initialize structured logger
    logger, _ := middleware.NewLogger()
    defer logger.Sync()

    // Initialize OpenTelemetry tracing
    tp, _ := middleware.InitTracing()
    if tp != nil {
        defer tp.Shutdown(context.Background())
    }

    // Initialize Pyroscope profiling
    middleware.InitProfiling()
    defer middleware.StopProfiling()

    r := gin.Default()

    // Middleware chain
    r.Use(middleware.TracingMiddleware())
    r.Use(middleware.LoggingMiddleware(logger))
    r.Use(middleware.PrometheusMiddleware())

    r.GET("/health", func(c *gin.Context) {
        c.JSON(200, gin.H{"status": "ok"})
    })
    r.GET("/metrics", gin.WrapH(promhttp.Handler()))

    // API v1
    apiV1 := r.Group("/api/v1")
    {
        // Add your v1 routes here
        // apiV1.POST("/payment", v1.ProcessPayment)
    }

    // API v2
    apiV2 := r.Group("/api/v2")
    {
        // Add your v2 routes here
        // apiV2.POST("/payment", v2.ProcessPayment)
    }

    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }

    logger.Info("Starting payment service", zap.String("port", port))
    r.Run(":" + port)
}
```

### Step 2: Create Helm Values

```yaml
# charts/values/payment.yaml
name: payment
namespace: payment

image:
  repository: ghcr.io/duynhne
  name: payment
  tag: v5
```

### Step 3: Update Deployment Script

Add the service to `scripts/04-deploy-microservices.sh`:

```bash
SERVICES=(
  # ... existing services ...
  "payment:payment:payment"
)
```

### Step 4: Update Build Script

Add the service to `scripts/03-build-microservices.sh`:

```bash
SERVICES=(
  # ... existing services ...
  "payment"
)
```

### Step 5: Update Namespaces

Add the namespace to `k8s/namespaces.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: payment
```

### Step 6: Build and Deploy

```bash
# Build the new service
./scripts/03-build-microservices.sh

# Deploy using Helm
./scripts/04-deploy-microservices.sh --local
```

Or deploy manually:

```bash
helm upgrade --install payment charts/ \
  -f charts/values/payment.yaml \
  -n payment --create-namespace
```

## Automatic Discovery

Once deployed, your service will automatically:

- **Appear in Grafana dashboard** - No dashboard changes needed
- **Show in app dropdown** - Service name appears in filter
- **Display metrics** - All 32 panels show data for your service
- **Support filtering** - Filter by service, namespace, version
- **Scale monitoring** - Works with any number of replicas

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

1. **Check Helm release**: `helm list -n payment`
2. **Verify pod is running**: `kubectl get pods -n payment`
3. **Check metrics endpoint**: `kubectl port-forward -n payment svc/payment 8080:8080` then `curl localhost:8080/metrics`
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
    []string{"operation"},
)
```

## Best Practices

1. **Consistent Naming**: Use `service-name` pattern (e.g., `payment`) without `-service` suffix
2. **Namespace per Service**: One namespace per service type
3. **Use Helm Values**: Don't hardcode configuration
4. **Metrics Quality**: Use meaningful metric names and labels
5. **Documentation**: Document your service's metrics

## Support

For questions or issues:
1. Check this documentation
2. Review existing service examples in `charts/values/`
3. Check Prometheus targets page
4. Verify Grafana dashboard configuration
