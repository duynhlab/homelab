# API Reference

## Overview

This project provides 9 microservices with RESTful APIs. Each service exposes v1 and v2 API endpoints.

## Services

| Service | Namespace | Port | Base URL |
|---------|-----------|------|----------|
| auth | auth | 8080 | `/api/v1`, `/api/v2` |
| user | user | 8080 | `/api/v1`, `/api/v2` |
| product | product | 8080 | `/api/v1`, `/api/v2` |
| cart | cart | 8080 | `/api/v1`, `/api/v2` |
| order | order | 8080 | `/api/v1`, `/api/v2` |
| review | review | 8080 | `/api/v1`, `/api/v2` |
| notification | notification | 8080 | `/api/v1`, `/api/v2` |
| shipping | shipping | 8080 | `/api/v1` |
| shipping-v2 | shipping | 8080 | `/api/v2` |

---

## Auth Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/auth/login` | User login |
| `POST` | `/api/v1/auth/register` | User registration |
| `POST` | `/api/v2/auth/login` | User login (v2) |
| `POST` | `/api/v2/auth/register` | User registration (v2) |

### Examples

```bash
# Login
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user1","password":"pass123"}'

# Register
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"newuser","email":"new@example.com","password":"pass123"}'
```

---

## User Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/users` | Get all users |
| `GET` | `/api/v1/users/{id}` | Get user by ID |
| `POST` | `/api/v1/users` | Create new user |
| `PUT` | `/api/v1/users/{id}` | Update user |
| `DELETE` | `/api/v1/users/{id}` | Delete user |

### Examples

```bash
# Get all users
curl http://localhost:8080/api/v1/users

# Create user
curl -X POST http://localhost:8080/api/v1/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'
```

---

## Product Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/products` | Get all products |
| `GET` | `/api/v1/products/{id}` | Get product by ID |
| `POST` | `/api/v1/products` | Create new product |
| `PUT` | `/api/v1/products/{id}` | Update product |
| `DELETE` | `/api/v1/products/{id}` | Delete product |

### Examples

```bash
# Get all products
curl http://localhost:8080/api/v1/products

# Create product
curl -X POST http://localhost:8080/api/v1/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Laptop","price":999.99,"stock":10}'
```

---

## Cart Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/cart` | Get cart |
| `POST` | `/api/v1/cart/items` | Add item to cart |
| `DELETE` | `/api/v1/cart/items/{id}` | Remove item from cart |
| `DELETE` | `/api/v1/cart` | Clear cart |

### Examples

```bash
# Get cart
curl http://localhost:8080/api/v1/cart

# Add item
curl -X POST http://localhost:8080/api/v1/cart/items \
  -H "Content-Type: application/json" \
  -d '{"product_id":"prod123","quantity":2}'
```

---

## Order Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/orders` | Get all orders |
| `GET` | `/api/v1/orders/{id}` | Get order by ID |
| `POST` | `/api/v1/orders` | Create new order |
| `PUT` | `/api/v1/orders/{id}` | Update order status |
| `DELETE` | `/api/v1/orders/{id}` | Cancel order |

### Examples

```bash
# Get all orders
curl http://localhost:8080/api/v1/orders

# Create order
curl -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user123","items":[{"product_id":"prod1","quantity":2}]}'
```

---

## Review Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/reviews` | Get all reviews |
| `GET` | `/api/v1/reviews/{id}` | Get review by ID |
| `GET` | `/api/v1/products/{id}/reviews` | Get reviews for product |
| `POST` | `/api/v1/reviews` | Create new review |
| `DELETE` | `/api/v1/reviews/{id}` | Delete review |

### Examples

```bash
# Get reviews for product
curl http://localhost:8080/api/v1/products/prod123/reviews

# Create review
curl -X POST http://localhost:8080/api/v1/reviews \
  -H "Content-Type: application/json" \
  -d '{"product_id":"prod123","user_id":"user1","rating":5,"comment":"Great product!"}'
```

---

## Notification Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/notifications` | Get all notifications |
| `GET` | `/api/v1/notifications/{id}` | Get notification by ID |
| `POST` | `/api/v1/notifications` | Send notification |
| `PUT` | `/api/v1/notifications/{id}/read` | Mark as read |

### Examples

```bash
# Get notifications
curl http://localhost:8080/api/v1/notifications

# Send notification
curl -X POST http://localhost:8080/api/v1/notifications \
  -H "Content-Type: application/json" \
  -d '{"user_id":"user123","type":"email","message":"Your order has shipped!"}'
```

---

## Shipping Service

### Endpoints (v1)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/shipments` | Get all shipments |
| `GET` | `/api/v1/shipments/{id}` | Get shipment by ID |
| `POST` | `/api/v1/shipments` | Create shipment |
| `PUT` | `/api/v1/shipments/{id}` | Update shipment status |

### Endpoints (v2 - shipping-v2)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/shipments` | Get all shipments (enhanced) |
| `GET` | `/api/v2/shipments/{id}` | Get shipment with tracking |
| `POST` | `/api/v2/shipments` | Create shipment with tracking |
| `GET` | `/api/v2/shipments/{id}/track` | Real-time tracking |

### Examples

```bash
# Create shipment (v1)
curl -X POST http://localhost:8080/api/v1/shipments \
  -H "Content-Type: application/json" \
  -d '{"order_id":"ord123","address":"123 Main St"}'

# Track shipment (v2)
curl http://localhost:8080/api/v2/shipments/ship123/track
```

---

## Common Endpoints

All services provide these common endpoints:

### Health Check

```bash
curl http://localhost:8080/health
# Response: {"status":"ok"}
```

### Metrics

```bash
curl http://localhost:8080/metrics
# Response: Prometheus metrics format
```

---

## Error Handling

All services return standard HTTP status codes:

| Code | Description |
|------|-------------|
| `200 OK` | Success |
| `201 Created` | Resource created |
| `204 No Content` | Resource deleted |
| `400 Bad Request` | Invalid request data |
| `404 Not Found` | Resource not found |
| `500 Internal Server Error` | Server error |

Error response format:

```json
{
  "error": "Error message here"
}
```

---

## Accessing Services

### Via Helm Deployment

```bash
# Deploy services
./scripts/04-deploy-microservices.sh --local

# Port forward specific service
kubectl port-forward -n auth svc/auth 8080:8080
kubectl port-forward -n user svc/user 8081:8080
kubectl port-forward -n product svc/product 8082:8080
```

### Port Forwarding Guide

```bash
# Setup all port forwards
./scripts/07-setup-access.sh
```

---

## Load Testing

Use k6 to test all services:

```bash
# Deploy k6 load generators
./scripts/06-deploy-k6-testing.sh

# View k6 logs
kubectl logs -n monitoring -l app=k6-load-generator-scenarios -f
```

See [K6_LOAD_TESTING.md](../load-testing/K6_LOAD_TESTING.md) for detailed load testing documentation.
