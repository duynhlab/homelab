# Refactor to Production Microservices Architecture

## Goals

1. **API Versioning**: v1/v2 trong cùng 1 service (URL-based versioning)
2. **Consistent Naming**: Deployment name = Pod label = Service name = APP_NAME
3. **Scalable**: Ready cho 1000+ pods
4. **Real-world APIs**: 9 microservices với endpoints thực tế

## Architecture Decision

### Service Structure

```
auth-service (1 deployment, handles /api/v1 & /api/v2)
user-service (1 deployment, handles /api/v1 & /api/v2)
product-service (1 deployment, handles /api/v1 & /api/v2)
cart-service (1 deployment, handles /api/v1 & /api/v2)
order-service (1 deployment, handles /api/v1 & /api/v2)
review-service (1 deployment, handles /api/v1 & /api/v2)
notification-service (1 deployment, handles /api/v1 & /api/v2)
shipping-service (1 deployment, handles /api/v1 only)
shipping-service-v2 (separate deployment, handles /api/v2 only - breaking changes)
```

**Why separate shipping-service-v2?**

- v2 có breaking changes lớn (track → shipments/estimate)
- Cần rollout strategy riêng
- Example cho trường hợp cần tách service

## New Project Structure

```
project-monitoring-golang/
├── cmd/
│   ├── auth-service/main.go
│   ├── user-service/main.go
│   ├── product-service/main.go
│   ├── cart-service/main.go
│   ├── order-service/main.go
│   ├── review-service/main.go
│   ├── notification-service/main.go
│   ├── shipping-service/main.go
│   └── shipping-service-v2/main.go
├── internal/
│   ├── auth/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/user.go
│   ├── user/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/user.go
│   ├── product/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/product.go
│   ├── cart/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/cart.go
│   ├── order/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/order.go
│   ├── review/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/review.go
│   ├── notification/
│   │   ├── v1/handler.go
│   │   ├── v2/handler.go
│   │   └── domain/notification.go
│   └── shipping/
│       ├── v1/handler.go
│       ├── v2/handler.go (for shipping-service-v2)
│       └── domain/shipment.go
├── pkg/
│   └── middleware/prometheus.go (keep as-is)
├── k8s/
│   ├── namespaces.yaml (update)
│   ├── auth-service/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── user-service/
│   ├── product-service/
│   ├── cart-service/
│   ├── order-service/
│   ├── review-service/
│   ├── notification-service/
│   ├── shipping-service/
│   ├── shipping-service-v2/
│   └── monitoring/
│       └── servicemonitors.yaml (update namespaces)
├── Dockerfile                       # Unified Dockerfile for all services
└── k6/
    └── load-test.js (update endpoints)
```

## API Endpoints Mapping

### 1. auth-service

```
POST /api/v1/auth/login
POST /api/v1/auth/register
POST /api/v2/auth/login (same behavior)
POST /api/v2/auth/register (same behavior)
GET  /health
GET  /metrics
```

### 2. user-service

```
GET    /api/v1/users/{id}
GET    /api/v1/users/profile
PUT    /api/v1/users/{id}
GET    /api/v2/users/{id}
GET    /api/v2/users/profile
PATCH  /api/v2/users/{id} (v2 uses PATCH instead of PUT)
GET    /health
GET    /metrics
```

### 3. product-service

```
# v1 - simple REST
GET  /api/v1/products
GET  /api/v1/products/{id}
POST /api/v1/products

# v2 - renamed to catalog
GET  /api/v2/catalog/items
GET  /api/v2/catalog/items/{itemId}
POST /api/v2/catalog/items
GET  /health
GET  /metrics
```

### 4. cart-service

```
# v1
GET    /api/v1/cart
POST   /api/v1/cart/items
DELETE /api/v1/cart/items/{itemId}

# v2 - RESTful with cartId
GET    /api/v2/carts/{cartId}
POST   /api/v2/carts/{cartId}/items
DELETE /api/v2/carts/{cartId}/items/{itemId}
GET    /health
GET    /metrics
```

### 5. order-service

```
# v1
GET  /api/v1/orders
POST /api/v1/orders
GET  /api/v1/orders/{id}

# v2 - enhanced with status endpoint
GET  /api/v2/orders
POST /api/v2/orders
GET  /api/v2/orders/{orderId}/status
PUT  /api/v2/orders/{orderId}/status
GET  /health
GET  /metrics
```

### 6. review-service

```
# v1
POST /api/v1/reviews
GET  /api/v1/reviews/product/{productId}

# v2 - RESTful
GET    /api/v2/reviews/{reviewId}
POST   /api/v2/reviews
PUT    /api/v2/reviews/{reviewId}
DELETE /api/v2/reviews/{reviewId}
GET    /health
GET    /metrics
```

### 7. notification-service

```
# v1 - action-based
POST /api/v1/notify/email
POST /api/v1/notify/sms

# v2 - resource-based
POST   /api/v2/notifications
GET    /api/v2/notifications/{id}
DELETE /api/v2/notifications/{id}
GET    /health
GET    /metrics
```

### 8. shipping-service (v1 only)

```
GET /api/v1/shipping/track?trackingId={id}
GET /health
GET /metrics
```

### 9. shipping-service-v2 (v2 only - separate deployment)

```
POST /api/v2/shipments/estimate
GET  /api/v2/shipments/{shipmentId}
PUT  /api/v2/shipments/{shipmentId}/status
GET  /health
GET  /metrics
```

## Kubernetes Deployment Strategy

### Consistent Naming Convention

**Pattern**: `{service-name}` (no version suffix unless separate deployment)

```yaml
# Example: auth-service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service  # ← Consistent
  namespace: auth
  labels:
    app: auth-service  # ← Consistent
    component: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: auth-service  # ← Consistent
  template:
    metadata:
      labels:
        app: auth-service  # ← Consistent
        component: api
    spec:
      containers:
      - name: auth-service
        image: auth-service:latest
        env:
        - name: APP_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['app']  # → "auth-service"
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service  # ← Consistent
  namespace: auth
  labels:
    app: auth-service  # ← Consistent
    component: api
spec:
  selector:
    app: auth-service  # ← Consistent
  ports:
  - port: 8080
    targetPort: 8080
```

### Namespaces

```yaml
# k8s/namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: auth
---
apiVersion: v1
kind: Namespace
metadata:
  name: user
---
apiVersion: v1
kind: Namespace
metadata:
  name: product
---
apiVersion: v1
kind: Namespace
metadata:
  name: cart
---
apiVersion: v1
kind: Namespace
metadata:
  name: order
---
apiVersion: v1
kind: Namespace
metadata:
  name: review
---
apiVersion: v1
kind: Namespace
metadata:
  name: notification
---
apiVersion: v1
kind: Namespace
metadata:
  name: shipping
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

## Go Code Structure

### Example: product-service

**cmd/product-service/main.go**:

```go
package main

import (
    "log"
    "net/http"
    "os"

    "github.com/gin-gonic/gin"
    "github.com/prometheus/client_golang/prometheus/promhttp"

    v1 "project/internal/product/v1"
    v2 "project/internal/product/v2"
    "project/pkg/middleware"
)

func main() {
    r := gin.Default()
    
    // Prometheus middleware
    r.Use(middleware.PrometheusMiddleware)
    
    // Health check
    r.GET("/health", func(c *gin.Context) {
        c.JSON(200, gin.H{"status": "ok"})
    })
    
    // Metrics endpoint
    r.GET("/metrics", gin.WrapH(promhttp.Handler()))
    
    // API v1
    apiV1 := r.Group("/api/v1")
    {
        apiV1.GET("/products", v1.ListProducts)
        apiV1.GET("/products/:id", v1.GetProduct)
        apiV1.POST("/products", v1.CreateProduct)
    }
    
    // API v2
    apiV2 := r.Group("/api/v2")
    {
        apiV2.GET("/catalog/items", v2.ListItems)
        apiV2.GET("/catalog/items/:itemId", v2.GetItem)
        apiV2.POST("/catalog/items", v2.CreateItem)
    }
    
    port := os.Getenv("PORT")
    if port == "" {
        port = "8080"
    }
    
    log.Printf("Starting product-service on :%s", port)
    log.Fatal(r.Run(":" + port))
}
```

**internal/product/v1/handler.go**:

```go
package v1

import (
    "github.com/gin-gonic/gin"
    "project/internal/product/domain"
)

func ListProducts(c *gin.Context) {
    products := []domain.Product{
        {ID: "1", Name: "Product 1", Price: 100},
        {ID: "2", Name: "Product 2", Price: 200},
    }
    c.JSON(200, products)
}

func GetProduct(c *gin.Context) {
    id := c.Param("id")
    product := domain.Product{ID: id, Name: "Product " + id, Price: 100}
    c.JSON(200, product)
}

func CreateProduct(c *gin.Context) {
    var product domain.Product
    if err := c.ShouldBindJSON(&product); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    c.JSON(201, product)
}
```

**internal/product/v2/handler.go**:

```go
package v2

import (
    "github.com/gin-gonic/gin"
    "project/internal/product/domain"
)

type Item struct {
    ItemID      string  `json:"itemId"`
    Name        string  `json:"name"`
    Price       float64 `json:"price"`
    Description string  `json:"description"`
}

func ListItems(c *gin.Context) {
    items := []Item{
        {ItemID: "item-1", Name: "Item 1", Price: 100, Description: "Desc 1"},
        {ItemID: "item-2", Name: "Item 2", Price: 200, Description: "Desc 2"},
    }
    c.JSON(200, items)
}

func GetItem(c *gin.Context) {
    itemId := c.Param("itemId")
    item := Item{ItemID: itemId, Name: "Item " + itemId, Price: 100}
    c.JSON(200, item)
}

func CreateItem(c *gin.Context) {
    var item Item
    if err := c.ShouldBindJSON(&item); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    c.JSON(201, item)
}
```

## ServiceMonitor Update

```yaml
# k8s/monitoring/servicemonitors.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: microservices-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      component: api
  namespaceSelector:
    matchNames:
    - auth
    - user
    - product
    - cart
    - order
    - review
    - notification
    - shipping
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    metricRelabelings:
    - sourceLabels: [__meta_kubernetes_service_label_app]
      targetLabel: app
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
```

## k6 Load Test Update

```javascript
// k8s/k6/load-test.js
import http from "k6/http";
import { check } from "k6";

export let options = {
  vus: 20,
  duration: "30s",
};

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

const services = [
  { name: "auth-service", endpoints: [
    "POST /api/v1/auth/login",
    "POST /api/v2/auth/register"
  ]},
  { name: "user-service", endpoints: [
    "GET /api/v1/users/profile",
    "GET /api/v2/users/profile"
  ]},
  { name: "product-service", endpoints: [
    "GET /api/v1/products",
    "GET /api/v2/catalog/items"
  ]},
  { name: "cart-service", endpoints: [
    "GET /api/v1/cart",
    "GET /api/v2/carts/cart-123"
  ]},
  { name: "order-service", endpoints: [
    "GET /api/v1/orders",
    "GET /api/v2/orders"
  ]},
  { name: "review-service", endpoints: [
    "GET /api/v1/reviews/product/prod-1",
    "GET /api/v2/reviews/review-1"
  ]},
  { name: "notification-service", endpoints: [
    "POST /api/v1/notify/email",
    "GET /api/v2/notifications/notif-1"
  ]},
  { name: "shipping-service", endpoints: [
    "GET /api/v1/shipping/track?trackingId=123"
  ]},
  { name: "shipping-service-v2", endpoints: [
    "GET /api/v2/shipments/ship-123"
  ]},
];

export default function() {
  services.forEach(service => {
    const ns = service.name.replace(/-service.*/, "");
    const svcName = service.name;
    const baseUrl = `http://${svcName}.${ns}.svc.cluster.local:8080`;
    
    service.endpoints.forEach(endpoint => {
      const [method, path] = endpoint.split(" ");
      let response;
      
      if (method === "GET") {
        response = http.get(baseUrl + path);
      } else if (method === "POST") {
        response = http.post(baseUrl + path, JSON.stringify({}), {
          headers: { "Content-Type": "application/json" },
        });
      }
      
      check(response, {
        [`${service.name} ${endpoint} status is 200`]: (r) => r.status === 200,
      });
    });
  });
}
```

## Migration Steps

### Phase 1: Cleanup Old Resources

1. Delete old deployments (user-service-v1, product-service-v1, etc.)
2. Delete old services
3. Delete old namespaces
4. Clean up old code

### Phase 2: Create New Structure

1. Create new Go code structure (9 services)
2. Create new Dockerfiles (9 files)
3. Create new K8s manifests (9 services)
4. Update namespaces.yaml

### Phase 3: Build & Deploy

1. Build all Docker images
2. Load images into Kind
3. Apply namespaces
4. Deploy all services
5. Update ServiceMonitor
6. Deploy k6 load generator

### Phase 4: Verify

1. Check all pods running
2. Verify Prometheus targets
3. Test dashboard shows data
4. Run k6 load tests

## Files to Delete

```
# Old structure - DELETE
k8s/user-service-v1/
k8s/product-service-v1/
k8s/checkout-service-v1/
k8s/order-service-v2/
k8s/unified-service-v3/

# Old code - DELETE
cmd/user-service-v1/
cmd/product-service-v1/
cmd/checkout-service-v1/
cmd/order-service-v2/
cmd/unified-service-v3/

# Old dockerfiles - DELETE
docker build --build-arg SERVICE_NAME=user-service -f Dockerfile -t user-service:latest .
docker build --build-arg SERVICE_NAME=product-service -f Dockerfile -t product-service:latest .
docker build --build-arg SERVICE_NAME=cart-service -f Dockerfile -t cart-service:latest .
docker build --build-arg SERVICE_NAME=order-service -f Dockerfile -t order-service:latest .
docker build --build-arg SERVICE_NAME=review-service -f Dockerfile -t review-service:latest .
```

## Benefits

✅ **Production-ready**: Real API structure

✅ **Scalable**: 1 deployment handles multiple API versions

✅ **Consistent**: Names match across all resources

✅ **Maintainable**: Clear separation v1/v2

✅ **Flexible**: Can split services when needed (shipping-service-v2)

✅ **Monitoring-ready**: All services auto-discovered

## Rollout Strategy

1. **Blue-Green**: Deploy new services alongside old
2. **Test**: Verify all endpoints work
3. **Cutover**: Update Ingress/Service mesh
4. **Cleanup**: Delete old resources

This architecture supports 1000+ pods easily!