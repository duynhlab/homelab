# API Reference

## Overview

This project provides 5 microservices with RESTful APIs for a complete e-commerce system.

## Services

### 1. User Service V1
**Port**: 8080  
**Base URL**: `http://localhost:8081/api/v1`

#### Endpoints

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| `GET` | `/users` | Get all users | - | `[]User` |
| `GET` | `/users/{id}` | Get user by ID | - | `User` |
| `POST` | `/users` | Create new user | `User` | `User` |
| `PUT` | `/users/{id}` | Update user | `User` | `User` |
| `DELETE` | `/users/{id}` | Delete user | - | `204 No Content` |

#### Models

```go
type User struct {
    ID    int    `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
}
```

#### Examples

```bash
# Get all users
curl http://localhost:8081/api/v1/users

# Create user
curl -X POST http://localhost:8081/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'

# Get user by ID
curl http://localhost:8081/api/v1/users/1
```

---

### 2. Product Service V1
**Port**: 8080  
**Base URL**: `http://localhost:8082/api/v1`

#### Endpoints

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| `GET` | `/products` | Get all products | - | `[]Product` |
| `GET` | `/products/{id}` | Get product by ID | - | `Product` |
| `POST` | `/products` | Create new product | `Product` | `Product` |
| `PUT` | `/products/{id}` | Update product | `Product` | `Product` |
| `DELETE` | `/products/{id}` | Delete product | - | `204 No Content` |

#### Models

```go
type Product struct {
    ID    int     `json:"id"`
    Name  string  `json:"name"`
    Price float64 `json:"price"`
    Stock int     `json:"stock"`
}
```

#### Examples

```bash
# Get all products
curl http://localhost:8082/api/v1/products

# Create product
curl -X POST http://localhost:8082/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Laptop","price":999.99,"stock":10}'

# Get product by ID
curl http://localhost:8082/api/v1/products/1
```

---

### 3. Checkout Service V1
**Port**: 8080  
**Base URL**: `http://localhost:8083/api/v1`

#### Endpoints

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| `POST` | `/checkout` | Process checkout | `CheckoutRequest` | `CheckoutResponse` |
| `GET` | `/checkout/{id}` | Get checkout status | - | `CheckoutResponse` |

#### Models

```go
type CheckoutRequest struct {
    UserID    string  `json:"user_id"`
    ProductID string  `json:"product_id"`
    Quantity  int     `json:"quantity"`
    Amount    float64 `json:"amount"`
}

type CheckoutResponse struct {
    TransactionID string  `json:"transaction_id"`
    Status        string  `json:"status"`
    Amount        float64 `json:"amount"`
    Timestamp     string  `json:"timestamp"`
}
```

#### Examples

```bash
# Process checkout
curl -X POST http://localhost:8083/api/v1/checkout \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user123","product_id":"prod456","quantity":2,"amount":199.98}'

# Get checkout status
curl http://localhost:8083/api/v1/checkout/TXN-123456
```

---

### 4. Order Service V2
**Port**: 8080  
**Base URL**: `http://localhost:8084/api/v2`

#### Endpoints

| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| `GET` | `/orders` | Get all orders | - | `[]Order` |
| `GET` | `/orders/{id}` | Get order by ID | - | `Order` |
| `POST` | `/orders` | Create new order | `CreateOrderRequest` | `Order` |
| `PUT` | `/orders/{id}` | Update order | `UpdateOrderRequest` | `Order` |
| `DELETE` | `/orders/{id}` | Delete order | - | `204 No Content` |

#### Models

```go
type Order struct {
    ID         string    `json:"id"`
    UserID     string    `json:"user_id"`
    Items      []string  `json:"items"`
    TotalPrice float64   `json:"total_price"`
    Status     string    `json:"status"`
    CreatedAt  time.Time `json:"created_at"`
}

type CreateOrderRequest struct {
    UserID     string   `json:"user_id"`
    Items      []string `json:"items"`
    TotalPrice float64  `json:"total_price"`
}

type UpdateOrderRequest struct {
    Status     string   `json:"status"`
    Items      []string `json:"items"`
    TotalPrice float64  `json:"total_price"`
}
```

#### Examples

```bash
# Get all orders
curl http://localhost:8084/api/v2/orders

# Create order
curl -X POST http://localhost:8084/api/v2/orders \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user123","items":["prod1","prod2"],"total_price":299.98}'

# Update order status
curl -X PUT http://localhost:8084/api/v2/orders/ORD-123456 \
  -H "Content-Type: application/json" \
  -d '{"status":"shipped"}'
```

---

### 5. Unified Service V3
**Port**: 8080  
**Base URL**: `http://localhost:8085/api/v3`

This service provides all endpoints from the above services under a single API.

#### Available Endpoints

**Users**: `/api/v3/users` (same as User Service V1)  
**Products**: `/api/v3/products` (same as Product Service V1)  
**Checkout**: `/api/v3/checkout` (same as Checkout Service V1)  
**Orders**: `/api/v3/orders` (same as Order Service V2)

#### Examples

```bash
# All user operations
curl http://localhost:8085/api/v3/users
curl -X POST http://localhost:8085/api/v3/users -d '{"name":"Jane","email":"jane@example.com"}'

# All product operations
curl http://localhost:8085/api/v3/products
curl -X POST http://localhost:8085/api/v3/products -d '{"name":"Phone","price":599.99,"stock":5}'

# All checkout operations
curl -X POST http://localhost:8085/api/v3/checkout -d '{"user_id":"u1","product_id":"p1","quantity":1,"amount":99.99}'

# All order operations
curl http://localhost:8085/api/v3/orders
curl -X POST http://localhost:8085/api/v3/orders -d '{"user_id":"u1","items":["p1"],"total_price":99.99}'
```

---

## Health Checks

All services provide a health check endpoint:

```bash
# Health check for any service
curl http://localhost:8081/health  # User Service
curl http://localhost:8082/health  # Product Service
curl http://localhost:8083/health  # Checkout Service
curl http://localhost:8084/health  # Order Service
curl http://localhost:8085/health  # Unified Service
```

Response: `200 OK` with body `"OK"`

## Metrics

All services expose Prometheus metrics at `/metrics`:

```bash
# Metrics for any service
curl http://localhost:8081/metrics  # User Service
curl http://localhost:8082/metrics  # Product Service
curl http://localhost:8083/metrics  # Checkout Service
curl http://localhost:8084/metrics  # Order Service
curl http://localhost:8085/metrics  # Unified Service
```

## Error Handling

All services return standard HTTP status codes:

- `200 OK` - Success
- `201 Created` - Resource created
- `204 No Content` - Resource deleted
- `400 Bad Request` - Invalid request data
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error

Error responses include a JSON body with error details:

```json
{
  "error": "User not found"
}
```

## Rate Limiting & Performance

- All services include realistic processing delays (50-800ms)
- Random error simulation (2-5% failure rate)
- Prometheus metrics for monitoring performance
- Health checks for Kubernetes readiness/liveness probes

## Load Testing

Use k6 to test all services:

```bash
# Run load tests
kubectl exec -n monitoring-demo deployment/k6-load-generator -- k6 run /scripts/load-test.js
```

The load test covers all services with realistic scenarios and performance thresholds.
