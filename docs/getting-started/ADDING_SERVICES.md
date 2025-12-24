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
  repository: ghcr.io/duynhne/payment  # Full image path
  tag: v5
  pullPolicy: IfNotPresent
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
    "net/http"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "go.uber.org/zap"

    v1 "github.com/duynhne/monitoring/internal/payment/web/v1"
    v2 "github.com/duynhne/monitoring/internal/payment/web/v2"
    "github.com/duynhne/monitoring/pkg/config"
    "github.com/duynhne/monitoring/pkg/middleware"
)

func main() {
    // Load configuration from environment variables (with .env file support for local dev)
    cfg := config.Load()
    if err := cfg.Validate(); err != nil {
        panic("Configuration validation failed: " + err.Error())
    }

    // Initialize structured logger
    logger, err := middleware.NewLogger()
    if err != nil {
        panic("Failed to initialize logger: " + err.Error())
    }
    defer logger.Sync()

    logger.Info("Service starting",
        zap.String("service", cfg.Service.Name),
        zap.String("version", cfg.Service.Version),
        zap.String("env", cfg.Service.Env),
        zap.String("port", cfg.Service.Port),
    )

    // Initialize OpenTelemetry tracing with centralized config
    var tp interface{ Shutdown(context.Context) error }
    if cfg.Tracing.Enabled {
        tp, err = middleware.InitTracing(cfg)
        if err != nil {
            logger.Warn("Failed to initialize tracing", zap.Error(err))
        } else {
            logger.Info("Tracing initialized",
                zap.String("endpoint", cfg.Tracing.Endpoint),
                zap.Float64("sample_rate", cfg.Tracing.SampleRate),
            )
        }
    }

    // Initialize Pyroscope profiling
    if cfg.Profiling.Enabled {
        if err := middleware.InitProfiling(); err != nil {
            logger.Warn("Failed to initialize profiling", zap.Error(err))
        } else {
            logger.Info("Profiling initialized",
                zap.String("endpoint", cfg.Profiling.Endpoint),
            )
            defer middleware.StopProfiling()
        }
    }

    r := gin.Default()

    // Middleware chain (order matters!)
    r.Use(middleware.TracingMiddleware())    // First: context propagation
    r.Use(middleware.LoggingMiddleware(logger)) // Second: logging with trace-id
    r.Use(middleware.PrometheusMiddleware())  // Third: metrics collection

    // Health check
    r.GET("/health", func(c *gin.Context) {
        c.JSON(200, gin.H{"status": "ok"})
    })

    // Metrics endpoint
    r.GET("/metrics", gin.WrapH(promhttp.Handler()))

    // API v1
    apiV1 := r.Group("/api/v1")
    {
        // Add your v1 routes here
        apiV1.POST("/payment", v1.ProcessPayment)
        apiV1.GET("/payment/:id", v1.GetPayment)
    }

    // API v2
    apiV2 := r.Group("/api/v2")
    {
        // Add your v2 routes here
        apiV2.POST("/payment", v2.ProcessPayment)
        apiV2.GET("/payment/:id", v2.GetPaymentStatus)
    }

    // Create HTTP server
    srv := &http.Server{
        Addr:    ":" + cfg.Service.Port,
        Handler: r,
    }

    // Start server in a goroutine
    go func() {
        logger.Info("Starting payment service", zap.String("port", cfg.Service.Port))
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            logger.Fatal("Failed to start server", zap.Error(err))
        }
    }()

    // Graceful shutdown
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    logger.Info("Shutting down server...")

    // Shutdown context with timeout
    shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    // Parallel shutdown with WaitGroup
    var wg sync.WaitGroup

    // Shutdown tracing (flush pending spans)
    if tp != nil {
        wg.Add(1)
        go func() {
            defer wg.Done()
            if err := tp.Shutdown(shutdownCtx); err != nil {
                logger.Error("Error shutting down tracer", zap.Error(err))
            } else {
                logger.Info("Tracer shutdown complete")
            }
        }()
    }

    // Shutdown HTTP server
    wg.Add(1)
    go func() {
        defer wg.Done()
        if err := srv.Shutdown(shutdownCtx); err != nil {
            logger.Error("Server forced to shutdown", zap.Error(err))
        } else {
            logger.Info("HTTP server shutdown complete")
        }
    }()

    wg.Wait()
    logger.Info("Server exited gracefully")
}
```

### Step 2: Create Helm Values

```yaml
# charts/values/payment.yaml
fullnameOverride: "payment"

env:
  - name: SERVICE_NAME
    value: "payment"
  - name: PORT
    value: "8080"
  - name: ENV
    value: "production"
  - name: OTEL_COLLECTOR_ENDPOINT
    value: "tempo.monitoring.svc.cluster.local:4318"
  - name: OTEL_SAMPLE_RATE
    value: "0.1"  # 10% sampling for production
  - name: PYROSCOPE_ENDPOINT
    value: "http://pyroscope.monitoring.svc.cluster.local:4040"
  - name: LOG_LEVEL
    value: "info"

  # Add service-specific configuration
  # Example: Payment gateway integration
  - name: STRIPE_API_ENDPOINT
    value: "https://api.stripe.com"
  - name: STRIPE_API_KEY
    valueFrom:
      secretKeyRef:
        name: payment-secrets
        key: stripe-api-key

image:
  repository: ghcr.io/duynhne/payment
  tag: "v1.0.0"
  pullPolicy: IfNotPresent

resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"
```

**Important**: See [charts/README.md](../../charts/README.md) for complete Helm chart configuration guide.

### Step 3: Update Deployment Script

Add the service to `scripts/05-deploy-microservices.sh`:

```bash
SERVICES=(
  # ... existing services ...
  "payment:payment:payment"
)
```

### Step 4: Update Build Script

Add the service to `scripts/04-build-microservices.sh`:

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
./scripts/04-build-microservices.sh

# Deploy using Helm
./scripts/05-deploy-microservices.sh --local
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
- **Show in app dropdown** - Service name appears in filter (via `$app` variable)
- **Display metrics** - All 32 panels show data for your service
- **Support filtering** - Filter by service (`$app`), namespace (`$namespace`), rate interval (`$rate`)
- **Scale monitoring** - Works with any number of replicas
- **APM Integration** - Distributed tracing (Tempo), profiling (Pyroscope), logging (Loki)

## Configuration Management

Your new service automatically benefits from centralized configuration:

### Local Development (.env file)

```bash
# Create .env file in services/ directory
cat > services/.env <<EOF
SERVICE_NAME=payment
PORT=8080
ENV=development
OTEL_SAMPLE_RATE=1.0  # 100% sampling for dev
LOG_LEVEL=debug
LOG_FORMAT=console

# Service-specific config
STRIPE_API_ENDPOINT=https://api.stripe.com/test
EOF

# Run service
go run services/cmd/payment/main.go
```

### Production (Helm Values)

Configuration is loaded from Helm values → Kubernetes environment → `config.Load()`:

```yaml
env:
  - name: SERVICE_NAME
    value: "payment"
  - name: ENV
    value: "production"
  # ... see charts/values/payment.yaml for full config
```

**See**: [docs/development/CONFIG_GUIDE.md](../development/CONFIG_GUIDE.md) for complete configuration guide.

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
