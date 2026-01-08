# API Reference

> **Document Status:** Production Contract  
> **Last Updated:** 2026-01-07  
> **Architecture:** 3-Layer (Web / Logic / Core)

---

## Master API Overview

This is the **single source of truth** for all API endpoints. The Frontend team MUST use these endpoints exactly as documented. No client-side orchestration allowed for aggregation endpoints.

### API Stability Levels

| Phase | Status | Meaning |
|-------|--------|---------|
| Phase 1 | ✅ STABLE | Production-ready, no breaking changes |
| Phase 2 | ⏳ PLANNED | Approved, implementation pending |
| Phase 3 | 🧪 OPTIONAL | Under consideration |

### Master Endpoint Table

| Service | Endpoint | Method | Purpose | Phase | Status | Used By |
|---------|----------|--------|---------|-------|--------|---------|
| **Product** | `/api/v1/products` | GET | List all products with filtering | 1 | ✅ STABLE | Frontend |
| **Product** | `/api/v1/products/:id` | GET | Get single product | 1 | ✅ STABLE | Frontend |
| **Product** | `/api/v1/products/:id/details` | GET | **Aggregated product details** | 1 | ✅ STABLE | Frontend |
| **Product** | `/api/v1/products` | POST | Create new product | 1 | ✅ STABLE | Internal |
| **Product** | `/api/v2/catalog/items` | GET | Get all catalog items (v2) | 1 | ✅ STABLE | Frontend |
| **Product** | `/api/v2/catalog/items/:itemId` | GET | Get catalog item by ID (v2) | 1 | ✅ STABLE | Frontend |
| **Product** | `/api/v2/catalog/items` | POST | Create catalog item (v2) | 1 | ✅ STABLE | Internal |
| **Cart** | `/api/v1/cart` | GET | Get user cart | 1 | ✅ STABLE | Frontend |
| **Cart** | `/api/v1/cart` | POST | Add item to cart | 1 | ✅ STABLE | Frontend |
| **Cart** | `/api/v1/cart/count` | GET | **Get cart item count** | 1 | ✅ STABLE | Frontend |
| **Cart** | `/api/v1/cart/items/:itemId` | PATCH | **Update cart item quantity** | 1 | ✅ STABLE | Frontend |
| **Cart** | `/api/v1/cart/items/:itemId` | DELETE | **Remove cart item** | 1 | ✅ STABLE | Frontend |
| **Cart** | `/api/v2/carts/:cartId` | GET | Get cart by ID (v2) | 1 | ✅ STABLE | Frontend |
| **Cart** | `/api/v2/carts/:cartId/items` | POST | Add item to cart (v2) | 1 | ✅ STABLE | Frontend |
| **Order** | `/api/v1/orders` | GET | List user orders | 1 | ✅ STABLE | Frontend |
| **Order** | `/api/v1/orders/:id` | GET | Get order by ID | 1 | ✅ STABLE | Frontend |
| **Order** | `/api/v1/orders` | POST | Create new order | 1 | ✅ STABLE | Frontend |
| **Order** | `/api/v2/orders` | GET | List orders (v2) | 1 | ✅ STABLE | Frontend |
| **Order** | `/api/v2/orders/:orderId/status` | GET | Get order status (v2) | 1 | ✅ STABLE | Frontend |
| **Order** | `/api/v2/orders` | POST | Create order (v2) | 1 | ✅ STABLE | Frontend |
| **Auth** | `/api/v1/auth/login` | POST | User login | 1 | ✅ STABLE | Frontend |
| **Auth** | `/api/v1/auth/register` | POST | User registration | 1 | ✅ STABLE | Frontend |
| **Auth** | `/api/v2/auth/login` | POST | User login (v2) | 1 | ✅ STABLE | Frontend |
| **Auth** | `/api/v2/auth/register` | POST | User registration (v2) | 1 | ✅ STABLE | Frontend |
| **User** | `/api/v1/users/:id` | GET | Get user by ID | 1 | ✅ STABLE | Frontend |
| **User** | `/api/v1/users/profile` | GET | Get user profile | 1 | ✅ STABLE | Frontend |
| **User** | `/api/v1/users` | POST | Create new user | 1 | ✅ STABLE | Internal |
| **User** | `/api/v2/users/:id` | GET | Get user by ID (v2) | 1 | ✅ STABLE | Frontend |
| **User** | `/api/v2/users/profile` | GET | Get user profile (v2) | 1 | ✅ STABLE | Frontend |
| **User** | `/api/v2/users` | POST | Create new user (v2) | 1 | ✅ STABLE | Internal |
| **Review** | `/api/v1/reviews` | GET | Get all reviews | 1 | ✅ STABLE | Frontend |
| **Review** | `/api/v1/reviews` | POST | Create new review | 1 | ✅ STABLE | Frontend |
| **Review** | `/api/v2/reviews/:reviewId` | GET | Get review by ID (v2) | 1 | ✅ STABLE | Frontend |
| **Review** | `/api/v2/reviews` | POST | Create review (v2) | 1 | ✅ STABLE | Frontend |
| **Notification** | `/api/v1/notify/email` | POST | Send email notification | 1 | ✅ STABLE | Internal |
| **Notification** | `/api/v1/notify/sms` | POST | Send SMS notification | 1 | ✅ STABLE | Internal |
| **Notification** | `/api/v2/notifications` | GET | Get all notifications | 1 | ✅ STABLE | Frontend |
| **Notification** | `/api/v2/notifications/:id` | GET | Get notification by ID | 1 | ✅ STABLE | Frontend |
| **Shipping** | `/api/v1/shipping/track` | GET | Track shipment | 1 | ✅ STABLE | Frontend |
| **Shipping-v2** | `/api/v2/shipments/estimate` | GET | Estimate shipment cost | 1 | ✅ STABLE | Frontend |

**Legend:**
- **Bold endpoints** = Phase 1 aggregation APIs (Frontend-critical)
- Frontend = Called directly by frontend application
- Internal = Backend-to-backend or admin only

---

## 3-Layer Architecture Responsibility

All backend services follow a strict 3-layer architecture. Understanding these layers is essential for both frontend and backend engineers.

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND (React SPA)                      │
│                  Calls ONLY Web Layer endpoints                  │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼ HTTP
┌─────────────────────────────────────────────────────────────────┐
│                         WEB LAYER                                │
│  • HTTP request/response handling                                │
│  • Request validation (JSON binding)                             │
│  • Authentication/Authorization                                  │
│  • DTO mapping (request → domain, domain → response)             │
│  • Aggregation of multiple Logic services                        │
│  • Error translation (domain errors → HTTP status codes)         │
│                                                                  │
│  Location: services/{service}/internal/web/v1/handler.go         │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼ Function calls
┌─────────────────────────────────────────────────────────────────┐
│                        LOGIC LAYER                               │
│  • Business rules and validation                                 │
│  • Transaction orchestration                                     │
│  • Repository interface usage (NO direct DB access)              │
│  • Cross-service coordination                                    │
│  • Domain error definitions                                      │
│                                                                  │
│  Location: services/{service}/internal/logic/v1/service.go       │
│                                                                  │
│  ❌ NO SQL queries                                               │
│  ❌ NO database.GetDB() calls                                    │
│  ❌ NO HTTP handling                                             │
└─────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼ Repository interface
┌─────────────────────────────────────────────────────────────────┐
│                         CORE LAYER                               │
│  • Domain models (entities, value objects)                       │
│  • Repository interfaces (contracts)                             │
│  • Repository implementations (PostgreSQL)                       │
│  • Database connection management                                │
│  • Transaction implementation                                    │
│                                                                  │
│  Location:                                                       │
│    - services/{service}/internal/core/domain/          (models)  │
│    - services/{service}/internal/core/repository/      (impl)    │
│    - services/{service}/internal/core/database.go      (conn)    │
└─────────────────────────────────────────────────────────────────┘
```

### Key Rules

| Rule | Applies To | Description |
|------|------------|-------------|
| Frontend calls Web only | Frontend | Never call Logic or Core directly |
| Web aggregates | Web Layer | Combine multiple Logic calls in Web handlers |
| Logic uses repositories | Logic Layer | Access data via repository interfaces only |
| Core owns SQL | Core Layer | All database queries live in repository implementations |
| Dependency injection | All | Services receive dependencies via constructors |

### Service Isolation (Refactored 2026-01-08)

**Each service is completely independent:**

```
services/{service}/
├── go.mod                    # Independent module
├── cmd/main.go              # Entry point
├── internal/
│   ├── web/v1/handler.go    # HTTP handlers
│   ├── logic/v1/service.go  # Business logic
│   └── core/
│       ├── domain/          # Domain models
│       └── repository/      # DB access
├── middleware/              # Duplicated (not shared)
└── config/                  # Duplicated (not shared)
```

**Key Changes:**
- ❌ **No shared `services/go.mod`** - Each service has own module
- ❌ **No shared `services/pkg/`** - Middleware/config duplicated per service
- ✅ **Complete independence** - Each service ready for separate repo

**Why Duplication?**
Maximum service independence. Each service can be moved to a separate repository without any shared dependencies.

---

## Phase 1 Aggregation APIs (Frontend-Critical)

These endpoints were added in Phase 1 to support frontend needs. **Frontend MUST use these endpoints. No client-side orchestration allowed.**

---

### GET /api/v1/products/:id/details

**Purpose:** Aggregated product details for Product Detail Page

> **Frontend MUST call this endpoint. No orchestration in FE.**

**Aggregates:**
- Product details (ProductService.GetProduct)
- Related products (ProductService.GetRelatedProducts)
- Stock information (mock data, pending inventory service)
- Reviews (empty array, pending review service integration)

**Logic Services Involved:**
- `ProductService.GetProduct(ctx, id)`
- `ProductService.GetRelatedProducts(ctx, id, limit)`

#### Request

```
GET /api/v1/products/:id/details
```

**Headers:**
```
Content-Type: application/json
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Product ID |

#### Response

**200 OK**
```json
{
  "product": {
    "id": "1",
    "name": "Wireless Mouse",
    "description": "Ergonomic wireless mouse with long battery life",
    "price": 29.99,
    "category": "Electronics"
  },
  "stock": {
    "available": true,
    "quantity": 50
  },
  "reviews": [],
  "reviews_summary": {
    "total": 0,
    "average_rating": 0.0
  },
  "related_products": [
    {
      "id": "2",
      "name": "Wireless Keyboard",
      "price": 49.99
    },
    {
      "id": "3",
      "name": "USB Hub",
      "price": 19.99
    }
  ]
}
```

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 404 | `{"error": "Product not found"}` | Product ID does not exist |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### DELETE /api/v1/cart/items/:itemId

**Purpose:** Remove a single item from the cart

> **Frontend MUST call this endpoint. No orchestration in FE.**

**Logic Services Involved:**
- `CartService.RemoveItem(ctx, userID, itemID)`
- `CartService.GetCart(ctx, userID)` (for updated totals)

#### Request

```
DELETE /api/v1/cart/items/:itemId
```

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <jwt_token>
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `itemId` | string | Yes | Cart item ID |

#### Response

**200 OK**
```json
{
  "success": true,
  "cart_total": 49.98,
  "cart_count": 2
}
```

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 404 | `{"error": "Cart item not found"}` | Item ID does not exist |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### PATCH /api/v1/cart/items/:itemId

**Purpose:** Update the quantity of a cart item

> **Frontend MUST call this endpoint. No orchestration in FE.**

**Logic Services Involved:**
- `CartService.UpdateItemQuantity(ctx, userID, itemID, quantity)`
- `CartService.GetCart(ctx, userID)` (for updated totals)

#### Request

```
PATCH /api/v1/cart/items/:itemId
```

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <jwt_token>
```

**Path Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `itemId` | string | Yes | Cart item ID |

**Request Body:**
```json
{
  "quantity": 3
}
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `quantity` | integer | Yes | min=1 (must be positive) |

#### Response

**200 OK**
```json
{
  "success": true,
  "cart_total": 89.97,
  "cart_count": 5
}
```

**Validation Rules:**
- `quantity` must be >= 1 (positive integer)

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 400 | `{"error": "<validation_error>"}` | Invalid request body |
| 400 | `{"error": "Invalid quantity"}` | Quantity validation failed |
| 404 | `{"error": "Cart item not found"}` | Item ID does not exist |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### GET /api/v1/cart/count

**Purpose:** Lightweight endpoint for cart badge count

> **Frontend MUST call this endpoint. No orchestration in FE.**

**Logic Services Involved:**
- `CartService.GetCartCount(ctx, userID)`

#### Request

```
GET /api/v1/cart/count
```

**Headers:**
```
Content-Type: application/json
Authorization: Bearer <jwt_token>
```

#### Response

**200 OK**
```json
{
  "count": 3
}
```

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 500 | `{"error": "Internal server error"}` | Server error |

---

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
| shipping | shipping | 8080 | `/api/v1` only |
| shipping-v2 | shipping | 8080 | `/api/v2` only |

---

## Product Service

### Endpoints (v1)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v1/products` | List all products with filtering | ✅ STABLE |
| `GET` | `/api/v1/products/:id` | Get product by ID | ✅ STABLE |
| `GET` | `/api/v1/products/:id/details` | **Aggregated product details** | ✅ STABLE |
| `POST` | `/api/v1/products` | Create new product | ✅ STABLE |

### GET /api/v1/products

List all products with optional filtering.

#### Request

```
GET /api/v1/products?category=Electronics&search=mouse&sort=price&order=asc
```

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `category` | string | No | Filter by category |
| `search` | string | No | Search by product name (ILIKE) |
| `sort` | string | No | Sort field (`price`, `created_at`, `name`) |
| `order` | string | No | Sort order (`asc`, `desc`) |

#### Response

**200 OK**
```json
[
  {
    "id": "1",
    "name": "Wireless Mouse",
    "description": "Ergonomic wireless mouse",
    "price": 29.99,
    "category": "Electronics"
  },
  {
    "id": "2",
    "name": "USB Keyboard",
    "description": "Mechanical keyboard",
    "price": 79.99,
    "category": "Electronics"
  }
]
```

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 500 | `{"error": "Internal server error"}` | Server error |

---

### GET /api/v1/products/:id

Get a single product by ID.

#### Request

```
GET /api/v1/products/123
```

#### Response

**200 OK**
```json
{
  "id": "123",
  "name": "Wireless Mouse",
  "description": "Ergonomic wireless mouse with long battery life",
  "price": 29.99,
  "category": "Electronics"
}
```

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 404 | `{"error": "Product not found"}` | Product ID does not exist |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### POST /api/v1/products

Create a new product.

#### Request

```
POST /api/v1/products
Content-Type: application/json

{
  "name": "New Product",
  "description": "Product description",
  "price": 49.99,
  "category": "Electronics"
}
```

#### Response

**201 Created**
```json
{
  "id": "456",
  "name": "New Product",
  "description": "Product description",
  "price": 49.99,
  "category": "Electronics"
}
```

**Validation Rules:**
- `price` must be >= 0 (non-negative)

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 400 | `{"error": "<validation_error>"}` | Invalid request body |
| 400 | `{"error": "Invalid price"}` | Price < 0 |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### Endpoints (v2)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/catalog/items` | Get all catalog items | ✅ STABLE |
| `GET` | `/api/v2/catalog/items/:itemId` | Get catalog item by ID | ✅ STABLE |
| `POST` | `/api/v2/catalog/items` | Create new catalog item | ✅ STABLE |

---

## Cart Service

### Endpoints (v1)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v1/cart` | Get user cart | ✅ STABLE |
| `POST` | `/api/v1/cart` | Add item to cart | ✅ STABLE |
| `GET` | `/api/v1/cart/count` | **Get cart item count** | ✅ STABLE |
| `PATCH` | `/api/v1/cart/items/:itemId` | **Update cart item quantity** | ✅ STABLE |
| `DELETE` | `/api/v1/cart/items/:itemId` | **Remove cart item** | ✅ STABLE |

### GET /api/v1/cart

Get the current user's cart.

#### Request

```
GET /api/v1/cart
Authorization: Bearer <jwt_token>
```

#### Response

**200 OK**
```json
{
  "id": "1",
  "user_id": "1",
  "items": [
    {
      "id": "item1",
      "product_id": "prod123",
      "product_name": "Wireless Mouse",
      "product_price": 29.99,
      "quantity": 2,
      "subtotal": 59.98
    }
  ],
  "subtotal": 59.98,
  "shipping": 5.00,
  "total": 64.98,
  "item_count": 2
}
```

---

### POST /api/v1/cart

Add an item to the cart.

#### Request

```
POST /api/v1/cart
Content-Type: application/json
Authorization: Bearer <jwt_token>

{
  "product_id": "prod123",
  "quantity": 2
}
```

#### Response

**201 Created**
```json
{
  "product_id": "prod123",
  "quantity": 2
}
```

**Validation Rules:**
- `quantity` must be > 0 (positive integer)

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 400 | `{"error": "Invalid quantity"}` | Quantity <= 0 |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### Endpoints (v2)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/carts/:cartId` | Get cart by ID | ✅ STABLE |
| `POST` | `/api/v2/carts/:cartId/items` | Add item to cart | ✅ STABLE |

---

## Order Service

### Endpoints (v1)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v1/orders` | Get all user orders | ✅ STABLE |
| `GET` | `/api/v1/orders/:id` | Get order by ID | ✅ STABLE |
| `POST` | `/api/v1/orders` | Create new order | ✅ STABLE |

### GET /api/v1/orders

List all orders for the current user.

#### Request

```
GET /api/v1/orders
Authorization: Bearer <jwt_token>
```

#### Response

**200 OK**
```json
[
  {
    "id": "ord123",
    "user_id": "1",
    "status": "pending",
    "subtotal": 59.98,
    "shipping": 5.00,
    "total": 64.98,
    "created_at": "2026-01-07T08:00:00Z"
  }
]
```

---

### GET /api/v1/orders/:id

Get a specific order by ID.

#### Request

```
GET /api/v1/orders/ord123
Authorization: Bearer <jwt_token>
```

#### Response

**200 OK**
```json
{
  "id": "ord123",
  "user_id": "1",
  "status": "pending",
  "items": [
    {
      "product_id": "prod123",
      "product_name": "Wireless Mouse",
      "quantity": 2,
      "price": 29.99,
      "subtotal": 59.98
    }
  ],
  "subtotal": 59.98,
  "shipping": 5.00,
  "total": 64.98,
  "created_at": "2026-01-07T08:00:00Z"
}
```

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 404 | Order not found | Order ID does not exist |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### POST /api/v1/orders

Create a new order.

#### Request

```
POST /api/v1/orders
Content-Type: application/json
Authorization: Bearer <jwt_token>

{
  "user_id": "user123",
  "items": [
    {
      "product_id": "prod1",
      "quantity": 2,
      "price": 29.99
    }
  ]
}
```

#### Response

**201 Created**
```json
{
  "id": "ord456",
  "user_id": "user123",
  "status": "pending",
  "subtotal": 59.98,
  "shipping": 5.00,
  "total": 64.98, 
  "created_at": "2026-01-07T08:00:00Z"
}
```

**Validation Rules:**
- `subtotal` must be >= 0
- `shipping` defaults to $5.00 (fixed cost)
- `total` must equal `subtotal + shipping`
- Item `subtotal` must equal `quantity × price`

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 400 | `{"error": "Invalid order"}` | Items array empty or validation failed |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### Endpoints (v2)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/orders` | Get all orders (v2) | ✅ STABLE |
| `GET` | `/api/v2/orders/:orderId/status` | Get order status | ✅ STABLE |
| `POST` | `/api/v2/orders` | Create new order (v2) | ✅ STABLE |

---

## Auth Service

### Endpoints

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `POST` | `/api/v1/auth/login` | User login | ✅ STABLE |
| `POST` | `/api/v1/auth/register` | User registration | ✅ STABLE |
| `POST` | `/api/v2/auth/login` | User login (v2) | ✅ STABLE |
| `POST` | `/api/v2/auth/register` | User registration (v2) | ✅ STABLE |

### POST /api/v1/auth/login

#### Request

```
POST /api/v1/auth/login
Content-Type: application/json

{
  "username": "user1",
  "password": "pass123"
}
```

#### Response

**200 OK**
```json
{
  "token": "eyJhbG...",
  "user": {
    "id": "1",
    "username": "user1"
  }
}
```

---

### POST /api/v1/auth/register

#### Request

```
POST /api/v1/auth/register
Content-Type: application/json

{
  "username": "newuser",
  "email": "new@example.com",
  "password": "pass123"
}
```

#### Response

**201 Created**
```json
{
  "id": "123",
  "username": "newuser",
  "email": "new@example.com"
}
```

---

## User Service

### Endpoints (v1)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v1/users/:id` | Get user by ID | ✅ STABLE |
| `GET` | `/api/v1/users/profile` | Get user profile | ✅ STABLE |
| `POST` | `/api/v1/users` | Create new user | ✅ STABLE |

### Endpoints (v2)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/users/:id` | Get user by ID (v2) | ✅ STABLE |
| `GET` | `/api/v2/users/profile` | Get user profile (v2) | ✅ STABLE |
| `POST` | `/api/v2/users` | Create new user (v2) | ✅ STABLE |

---

## Review Service

### Endpoints (v1)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v1/reviews` | Get all reviews | ✅ STABLE |
| `POST` | `/api/v1/reviews` | Create new review | ✅ STABLE |

### Endpoints (v2)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/reviews/:reviewId` | Get review by ID | ✅ STABLE |
| `POST` | `/api/v2/reviews` | Create new review (v2) | ✅ STABLE |

---

## Notification Service

### Endpoints (v1)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `POST` | `/api/v1/notify/email` | Send email notification | ✅ STABLE |
| `POST` | `/api/v1/notify/sms` | Send SMS notification | ✅ STABLE |

### Endpoints (v2)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/notifications` | Get all notifications | ✅ STABLE |
| `GET` | `/api/v2/notifications/:id` | Get notification by ID | ✅ STABLE |

---

## Shipping Service

### Endpoints (v1 only)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v1/shipping/track` | Track shipment | ✅ STABLE |

#### Request

```
GET /api/v1/shipping/track?tracking_number=TRACK123
```

---

## Shipping-v2 Service

### Endpoints (v2 only)

| Method | Endpoint | Description | Phase |
|--------|----------|-------------|-------|
| `GET` | `/api/v2/shipments/estimate` | Estimate shipment cost | ✅ STABLE |

#### Request

```
GET /api/v2/shipments/estimate?weight=2.5&destination=US
```

---

## Common Response Patterns

### Error Response Format

All error responses follow this format:

```json
{
  "error": "<error_message>"
}
```

### HTTP Status Codes

| Status | Meaning | When Used |
|--------|---------|-----------|
| 200 | OK | Successful GET, PATCH, DELETE |
| 201 | Created | Successful POST (resource created) |
| 400 | Bad Request | Validation error, invalid input |
| 404 | Not Found | Resource does not exist |
| 500 | Internal Server Error | Unexpected server error |

---

## Conventions and Standards

### File Organization Patterns

#### Services
- Service code: `services/cmd/{service}/main.go` + `services/internal/{service}/{web,logic,core}/`
- Helm values: `charts/values/{service}.yaml`
- SLO CRD: `k8s/sloth/crds/{service}-slo.yaml`
- Migration: `services/migrations/{service}/Dockerfile` + `sql/001__init_schema.sql`

**Example Structure:**
```
services/
├── cmd/
│   └── product/
│       └── main.go
├── internal/
│   └── product/
│       ├── web/
│       │   ├── v1/
│       │   │   └── handler.go
│       │   └── v2/
│       ├── logic/
│       │   ├── v1/
│       │   │   └── service.go
│       │   └── v2/
│       └── core/
│           ├── domain/
│           │   ├── product.go
│           │   ├── repository.go
│           │   └── errors.go
│           ├── repository/
│           │   └── postgres_product_repository.go
│           └── database.go
└── migrations/
    └── product/
```

### Local Build Verification

**Before pushing code, run:**
```bash
./scripts/00-verify-build.sh
```

#### What It Checks

1. Go module synchronization (`go.mod`/`go.sum`)
2. Code formatting (`gofmt`)
3. Static analysis (`go vet`)
4. Build all 9 services
5. Tests (optional - use `--skip-tests` to skip)

---

## API Versioning

### Version Strategy

- **v1**: Original API, maintained for backward compatibility
- **v2**: Enhanced API with improved patterns

### URL Pattern

```
/api/v1/{resource}     # Version 1
/api/v2/{resource}     # Version 2
```

### Deprecation Policy

- v1 endpoints remain stable indefinitely
- New features may only be added to v2
- Breaking changes require new version

---

**Document End**
