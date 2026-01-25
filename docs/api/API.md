# API Reference

> **Document Status:** Production  
> **Last Updated:** 2026-01-25  
> **Architecture:** 3-Layer (Web / Logic / Core)

---

## Master API Overview

This is the **single source of truth** for all API endpoints. The Frontend team MUST use these endpoints exactly as documented. No client-side orchestration allowed for aggregation endpoints.

### Frontend Endpoints

| Service | Endpoint | Method | Version | Purpose | Status |
|---------|----------|--------|---------|---------|--------|
| **Product** | `/api/v1/products` | GET | v1 | List all products with filtering | STABLE |
| **Product** | `/api/v1/products/:id` | GET | v1 | Get single product | STABLE |
| **Product** | `/api/v1/products/:id/details` | GET | v1 | **Aggregated product details** | STABLE |
| **Product** | `/api/v2/catalog/items` | GET | v2 | Get all catalog items | STABLE |
| **Product** | `/api/v2/catalog/items/:itemId` | GET | v2 | Get catalog item by ID | STABLE |
| **Cart** | `/api/v1/cart` | GET | v1 | Get user cart | STABLE |
| **Cart** | `/api/v1/cart` | POST | v1 | Add item to cart | STABLE |
| **Cart** | `/api/v1/cart/count` | GET | v1 | **Get cart item count** | STABLE |
| **Cart** | `/api/v1/cart/items/:itemId` | PATCH | v1 | **Update cart item quantity** | STABLE |
| **Cart** | `/api/v1/cart/items/:itemId` | DELETE | v1 | **Remove cart item** | STABLE |
| **Cart** | `/api/v2/carts/:cartId` | GET | v2 | Get cart by ID | STABLE |
| **Cart** | `/api/v2/carts/:cartId/items` | POST | v2 | Add item to cart | STABLE |
| **Order** | `/api/v1/orders` | GET | v1 | List user orders | STABLE |
| **Order** | `/api/v1/orders/:id` | GET | v1 | Get order by ID | STABLE |
| **Order** | `/api/v1/orders` | POST | v1 | Create new order | STABLE |
| **Order** | `/api/v2/orders` | GET | v2 | List orders | STABLE |
| **Order** | `/api/v2/orders/:orderId/status` | GET | v2 | Get order status | STABLE |
| **Order** | `/api/v2/orders` | POST | v2 | Create order | STABLE |
| **Auth** | `/api/v1/auth/login` | POST | v1 | User login | STABLE |
| **Auth** | `/api/v1/auth/register` | POST | v1 | User registration | STABLE |
| **Auth** | `/api/v1/auth/me` | GET | v1 | **Get current user from token** | STABLE |
| **Auth** | `/api/v2/auth/login` | POST | v2 | User login | STABLE |
| **Auth** | `/api/v2/auth/register` | POST | v2 | User registration | STABLE |
| **User** | `/api/v1/users/:id` | GET | v1 | Get user by ID | STABLE |
| **User** | `/api/v1/users/profile` | GET | v1 | Get user profile | STABLE |
| **User** | `/api/v1/users/profile` | PUT | v1 | **Update user profile** | STABLE |
| **User** | `/api/v2/users/:id` | GET | v2 | Get user by ID | STABLE |
| **User** | `/api/v2/users/profile` | GET | v2 | Get user profile | STABLE |
| **Review** | `/api/v1/reviews?product_id={id}` | GET | v1 | Get reviews for product (**product_id required**) | STABLE |
| **Review** | `/api/v1/reviews` | POST | v1 | Create review (**user_id required**, 409 if duplicate) | STABLE |
| **Review** | `/api/v2/reviews/:reviewId` | GET | v2 | Get review by ID | STABLE |
| **Review** | `/api/v2/reviews` | POST | v2 | Create review | STABLE |
| **Notification** | `/api/v1/notifications` | GET | v1 | Get all notifications | STABLE |
| **Notification** | `/api/v1/notifications/:id` | GET | v1 | Get notification by ID | STABLE |
| **Notification** | `/api/v1/notifications/:id` | PATCH | v1 | Mark notification as read | STABLE |
| **Notification** | `/api/v2/notifications` | GET | v2 | Get all notifications | STABLE |
| **Notification** | `/api/v2/notifications/:id` | GET | v2 | Get notification by ID | STABLE |
| **Shipping** | `/api/v1/shipping/track` | GET | v1 | Track shipment (query: `tracking_number`) | STABLE |
| **Shipping** | `/api/v1/shipping/estimate` | GET | v1 | **Estimate shipment cost** | STABLE |
| **Shipping-v2** | `/api/v2/shipments/estimate` | GET | v2 | Estimate shipment cost | STABLE |

### Internal Endpoints

| Service | Endpoint | Method | Version | Purpose | Status |
|---------|----------|--------|---------|---------|--------|
| **Product** | `/api/v1/products` | POST | v1 | Create new product | STABLE |
| **Product** | `/api/v2/catalog/items` | POST | v2 | Create catalog item | STABLE |
| **User** | `/api/v1/users` | POST | v1 | Create new user | STABLE |
| **User** | `/api/v2/users` | POST | v2 | Create new user | STABLE |
| **Notification** | `/api/v1/notify/email` | POST | v1 | Send email notification | STABLE |
| **Notification** | `/api/v1/notify/sms` | POST | v1 | Send SMS notification | STABLE |

**Legend:**
- **Bold endpoints** = Aggregation APIs (combine multiple data sources)
- Version = API version (v1 or v2) extracted from endpoint path
- Frontend endpoints = Called directly by frontend React application
- Internal endpoints = Backend-to-backend or admin operations only

---

## 3-Layer Architecture Responsibility

All backend services follow a strict 3-layer architecture. Understanding these layers is essential for both frontend and backend engineers.

```mermaid
flowchart TD
    Frontend["FRONTEND (React SPA)\nCalls ONLY Web Layer endpoints"]
    WebLayer["WEB LAYER\n- HTTP request/response handling\n- Request validation (JSON binding)\n- Authentication/Authorization\n- DTO mapping (request -> domain, domain -> response)\n- Aggregation of multiple Logic services\n- Error translation (domain errors -> HTTP status codes)\nLocation: services/{service}/internal/web/v1/handler.go"]
    LogicLayer["LOGIC LAYER\n- Business rules and validation\n- Transaction orchestration\n- Repository interface usage (NO direct DB access)\n- Cross-service coordination\n- Domain error definitions\nLocation: services/{service}/internal/logic/v1/service.go\nConstraints:\n- NO SQL queries\n- NO database.GetDB() calls\n- NO HTTP handling"]
    CoreLayer["CORE LAYER\n- Domain models (entities, value objects)\n- Repository interfaces (contracts)\n- Repository implementations (PostgreSQL)\n- Database connection management\n- Transaction implementation\nLocation:\n- services/{service}/internal/core/domain/ (models)\n- services/{service}/internal/core/repository/ (impl)\n- services/{service}/internal/core/database.go (conn)"]

    Frontend -->|"HTTP"| WebLayer
    WebLayer -->|"Function calls"| LogicLayer
    LogicLayer -->|"Repository interface"| CoreLayer
```

### Key Rules

| Rule | Applies To | Description |
|------|------------|-------------|
| **Frontend calls Web only** | **Frontend** | **CRITICAL: Never call Logic or Core directly. Only HTTP requests to `/api/v1/*` and `/api/v2/*` endpoints.** |
| Web aggregates | Web Layer | Combine multiple Logic calls in Web handlers |
| Logic uses repositories | Logic Layer | Access data via repository interfaces only |
| Core owns SQL | Core Layer | All database queries live in repository implementations |
| Dependency injection | All | Services receive dependencies via constructors |

**⚠️ Frontend Developers & AI Agents:**

**DO:**
- Make HTTP requests to Web Layer endpoints (`GET /api/v1/products`, `POST /api/v1/cart`, etc.)
- Use aggregation endpoints for complex operations (e.g., `GET /api/v1/products/:id/details`)
- Let Web Layer handle validation, authentication, and error translation

**DO NOT:**
- ❌ Attempt to call Logic Layer functions directly (no function imports from `logic/` packages)
- ❌ Attempt to access Core Layer or database directly (no SQL queries, no repository calls)
- ❌ Implement client-side orchestration (make multiple API calls and combine results)
- ❌ Bypass Web Layer in any way

**For AI Agents:** See [`AGENTS.md`](../../AGENTS.md#frontend-integration-rules) for explicit Frontend integration rules and restrictions.

### Service Isolation

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
├── middleware/
└── config/
```

**Key Changes:**
- ❌ **No shared `services/go.mod`** - Each service has own module
- ❌ **No shared `services/pkg/`** - Middleware/config live within each service
- **Complete independence** - Each service ready for separate repo

**Rationale:** Keep cross-service coupling minimal so each service stays portable and independently deployable.

---

## Aggregation APIs

These endpoints combine multiple data sources to provide complete responses. **Frontend MUST use these endpoints. No client-side orchestration allowed.**

---

### GET /api/v1/products/:id/details

**Purpose:** Aggregated product details for Product Detail Page

> **Frontend MUST call this endpoint. No orchestration in FE.**

**Aggregates:**
- Product details (ProductService.GetProduct)
- Related products (ProductService.GetRelatedProducts)
- Stock information (mock data, pending inventory service)
- Reviews (aggregated from review service via HTTP call; soft-fail to empty array if review service unavailable)

**Logic Services Involved:**
- `ProductService.GetProduct(ctx, id)`
- `ProductService.GetRelatedProducts(ctx, id, limit)`

**Configuration:**
- Product service uses `REVIEW_SERVICE_URL` environment variable (default: `http://review.review.svc.cluster.local:8080`) to call review service for aggregation.

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

## Go PostgreSQL Driver

All microservices use **pgx/v5** as the PostgreSQL driver.

**Driver Comparison:**

| Feature | lib/pq | pgx/v5 |
|---------|--------|--------|
| GitHub Stars | 9.8k | 13.2k |
| Maintenance | Maintenance mode (since 2023) | Actively maintained |
| Prepared Statements | Server-side (cached on PostgreSQL) | Client-side / Simple protocol |
| Connection Pooling | Manual (`sql.DB` config) | Built-in (`pgxpool`) |
| Binary Protocol | Limited | Full support |
| PostgreSQL Types | Basic | Extended (JSONB, arrays, hstore) |
| Performance | Good | Better (native binary protocol) |

**Why pgx Instead of lib/pq?**

1. **Connection Pooler Compatibility**: lib/pq uses server-side prepared statements which cause errors with transaction pooling:
   ```
   pq: bind message supplies 1 parameters, but prepared statement "" requires 2
   ```
   pgx uses client-side prepared statements / simple protocol, fully compatible with PgCat/PgBouncer.

2. **Active Development**: pgx is actively maintained with regular updates, while lib/pq is in maintenance mode since 2023.

3. **Better Performance**: pgx implements PostgreSQL's binary protocol natively.

4. **Native Connection Pool**: `pgxpool.Pool` is designed for PostgreSQL, providing better control than `sql.DB` generic pool.

**Code Example:**

```go
import (
    "context"
    "github.com/jackc/pgx/v5/pgxpool"
)

func Connect(ctx context.Context) (*pgxpool.Pool, error) {
    dsn := "postgresql://user:pass@host:5432/db?sslmode=disable&pool_max_conns=25"
    return pgxpool.New(ctx, dsn)
}
```

> [!NOTE]
> See [PGCAT_PREPARED_STATEMENT_ERROR.md](../runbooks/troubleshooting/PGCAT_PREPARED_STATEMENT_ERROR.md) for detailed troubleshooting.

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

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/products` | List all products with filtering |
| `GET` | `/api/v1/products/:id` | Get product by ID |
| `GET` | `/api/v1/products/:id/details` | **Aggregated product details** |
| `POST` | `/api/v1/products` | Create new product |

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

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/catalog/items` | Get all catalog items |
| `GET` | `/api/v2/catalog/items/:itemId` | Get catalog item by ID |
| `POST` | `/api/v2/catalog/items` | Create new catalog item |

---

## Cart Service

### Endpoints (v1)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/cart` | Get user cart |
| `POST` | `/api/v1/cart` | Add item to cart |
| `GET` | `/api/v1/cart/count` | **Get cart item count** |
| `PATCH` | `/api/v1/cart/items/:itemId` | **Update cart item quantity** |
| `DELETE` | `/api/v1/cart/items/:itemId` | **Remove cart item** |

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
  "product_name": "Wireless Mouse",
  "product_price": 29.99,
  "quantity": 2
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `product_id` | string | Yes | Product ID to add |
| `product_name` | string | Yes | Product name (stored for display) |
| `product_price` | number | Yes | Product price at time of adding |
| `quantity` | integer | Yes | Quantity to add (min=1) |

#### Response

**200 OK**
```json
{
  "message": "Item added to cart"
}
```

**Validation Rules:**
- `quantity` must be > 0 (positive integer)
- `product_price` must be >= 0

**Error Responses:**

| Status | Body | Condition |
|--------|------|-----------|
| 400 | `{"error": "<validation_error>"}` | Missing required fields |
| 400 | `{"error": "Invalid quantity"}` | Quantity <= 0 |
| 500 | `{"error": "Internal server error"}` | Server error |

---

### Endpoints (v2)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/carts/:cartId` | Get cart by ID |
| `POST` | `/api/v2/carts/:cartId/items` | Add item to cart |

---

## Order Service

### Endpoints (v1)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/orders` | Get all user orders |
| `GET` | `/api/v1/orders/:id` | Get order by ID |
| `POST` | `/api/v1/orders` | Create new order |

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

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/orders` | Get all orders (v2) |
| `GET` | `/api/v2/orders/:orderId/status` | Get order status |
| `POST` | `/api/v2/orders` | Create new order (v2) |

---

## Auth Service

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/auth/login` | User login |
| `POST` | `/api/v1/auth/register` | User registration |
| `POST` | `/api/v2/auth/login` | User login (v2) |
| `POST` | `/api/v2/auth/register` | User registration (v2) |

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

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/users/:id` | Get user by ID |
| `GET` | `/api/v1/users/profile` | Get user profile |
| `POST` | `/api/v1/users` | Create new user |

### Endpoints (v2)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/users/:id` | Get user by ID (v2) |
| `GET` | `/api/v2/users/profile` | Get user profile (v2) |
| `POST` | `/api/v2/users` | Create new user (v2) |

---

## Review Service

### Endpoints (v1)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/reviews?product_id={id}` | Get reviews for a product (**product_id required**) |
| `POST` | `/api/v1/reviews` | Create new review (**user_id required**) |

#### GET /api/v1/reviews

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `product_id` | string | **Yes** | Product ID to get reviews for |

**Response (200 OK):**
```json
[
  {
    "id": "1",
    "product_id": "5",
    "user_id": "1",
    "rating": 5,
    "title": "Great product!",
    "comment": "Highly recommend this product.",
    "created_at": "2026-01-23T10:30:00Z"
  }
]
```

**Error (400 Bad Request):** Missing `product_id`
```json
{
  "error": "product_id query parameter is required"
}
```

#### POST /api/v1/reviews

**Request Body:**
```json
{
  "product_id": "5",
  "user_id": "1",
  "rating": 5,
  "title": "Great product!",
  "comment": "Highly recommend this product."
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `product_id` | string | Yes | Product ID |
| `user_id` | string | Yes | User ID (authenticated user) |
| `rating` | int | Yes | Rating 1-5 |
| `title` | string | No | Review title |
| `comment` | string | Yes | Review comment |

**Response (201 Created):**
```json
{
  "id": "10",
  "product_id": "5",
  "user_id": "1",
  "rating": 5,
  "title": "Great product!",
  "comment": "Highly recommend this product.",
  "created_at": "2026-01-23T10:30:00Z"
}
```

**Error (409 Conflict):** User already reviewed this product
```json
{
  "error": "Review already exists"
}
```

### Endpoints (v2)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/reviews/:reviewId` | Get review by ID |
| `POST` | `/api/v2/reviews` | Create new review (v2) |

---

## Notification Service

### Endpoints (v1)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/v1/notify/email` | Send email notification |
| `POST` | `/api/v1/notify/sms` | Send SMS notification |

### Endpoints (v2)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/notifications` | Get all notifications |
| `GET` | `/api/v2/notifications/:id` | Get notification by ID |

---

## Shipping Service

### Endpoints (v1 only)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/shipping/track` | Track shipment |

#### Request

```
GET /api/v1/shipping/track?tracking_number=TRACK123
```

---

## Shipping-v2 Service

### Endpoints (v2 only)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v2/shipments/estimate` | Estimate shipment cost |

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
- Service code: `services/{service}/cmd/main.go` + `services/{service}/internal/{web,logic,core}/`
- Helm values: `charts/values/{service}.yaml`
- SLO CRD: `k8s/sloth/crds/{service}-slo.yaml`
- Migration: `services/{service}/db/migrations/Dockerfile` + `sql/V*__*.sql`

**Example Structure:**
```
services/
├── product/
│   ├── go.mod                    # Independent module
│   ├── cmd/
│   │   └── main.go              # Entry point
│   ├── internal/
│   │   ├── web/
│   │   │   ├── v1/
│   │   │   │   └── handler.go
│   │   │   └── v2/
│   │   ├── logic/
│   │   │   ├── v1/
│   │   │   │   └── service.go
│   │   │   └── v2/
│   │   └── core/
│   │       ├── domain/
│   │       │   ├── product.go
│   │       │   ├── repository.go
│   │       │   └── errors.go
│   │       ├── repository/
│   │       │   └── postgres_product_repository.go
│   │       └── database.go
│   ├── middleware/
│   ├── config/
│   └── db/
│       └── migrations/
│           ├── Dockerfile
│           └── sql/
│               ├── V1__init_schema.sql
│               └── V2__seed_products.sql
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

## Seed Data for Local Development

### Overview

All services include seed data via Flyway V2 migrations for immediate demo/local/dev functionality. Seed data is automatically loaded during database initialization.

### Demo Users

5 test users are available for authentication:

| User | Email | Password | Purpose |
|------|-------|----------|---------|
| Alice Johnson | `alice@example.com` | `password123` | Active shopper (2 orders, cart items) |
| Bob Smith | `bob@example.com` | `password123` | Cart only, no orders yet |
| Carol White | `carol@example.com` | `password123` | Frequent reviewer |
| David Brown | `david@example.com` | `password123` | Recent order with tracking |
| Eve Davis | `eve@example.com` | `password123` | Inactive user |

**Login Example**:
```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com", "password": "password123"}'
```

### Seeded Data Summary

| Service | Table | Records | Description |
|---------|-------|---------|-------------|
| **Product** | `products` | 8 | Electronics, peripherals, accessories |
| **Product** | `categories` | 4 | Electronics, Computers, Accessories, Peripherals |
| **Auth** | `users` | 5 | Demo users with bcrypt-hashed passwords |
| **Auth** | `sessions` | 2 | Active sessions for Alice and Bob |
| **User** | `user_profiles` | 5 | Complete profiles with addresses |
| **Cart** | `cart_items` | 5 | Alice (3 items), Bob (2 items) |
| **Order** | `orders` | 5 | Mix of pending/completed/shipped |
| **Order** | `order_items` | 8 | Order line items |
| **Review** | `reviews` | 12 | Product reviews (3-5 stars) |
| **Notification** | `notifications` | 8 | Order/shipping/promo notifications |
| **Shipping** | `shipments` | 3 | USPS, FedEx, UPS tracking |

### Data Relationships

Cross-service references use fixed IDs for consistency:

```mermaid
flowchart TD
    AuthUsers["auth.users (IDs: 1-5)"]
    ProductProducts["product.products (IDs: 1-8)"]

    UserProfiles["user.user_profiles"]
    CartItems["cart.cart_items"]
    Orders["order.orders"]
    Reviews["review.reviews"]
    Notifications["notification.notifications"]

    OrderItems["order.order_items"]
    Shipments["shipping.shipments"]

    %% Top-down: sources -> consumers
    AuthUsers -->|user_id| UserProfiles
    AuthUsers -->|user_id| CartItems
    AuthUsers -->|user_id| Orders
    AuthUsers -->|user_id| Reviews
    AuthUsers -->|user_id| Notifications

    ProductProducts -->|product_id| CartItems
    ProductProducts -->|product_id| Reviews
    ProductProducts -->|product_id| OrderItems

    %% Orders -> downstream relations
    Orders -->|order_id| OrderItems
    Orders -->|order_id| Shipments
```

### Example Seeded Products

| ID | Name | Price | Category | Stock |
|----|------|-------|----------|-------|
| 1 | Wireless Mouse | $29.99 | Electronics | 50 |
| 2 | Mechanical Keyboard | $79.99 | Peripherals | 30 |
| 3 | USB-C Hub | $39.99 | Computers | 25 |
| 4 | Laptop Stand | $44.99 | Accessories | 40 |
| 5 | Webcam HD | $59.99 | Electronics | 20 |
| 6 | Monitor 24" | $149.99 | Electronics | 15 |
| 7 | Gaming Headset | $89.99 | Accessories | 35 |
| 8 | External SSD 1TB | $99.99 | Computers | 18 |

### Alice's Cart (Example)

```json
{
  "user_id": 1,
  "items": [
    {"product_id": 1, "product_name": "Wireless Mouse", "quantity": 2, "price": 29.99},
    {"product_id": 2, "product_name": "Mechanical Keyboard", "quantity": 1, "price": 79.99},
    {"product_id": 5, "product_name": "Webcam HD", "quantity": 1, "price": 59.99}
  ],
  "subtotal": 169.97,
  "shipping": 5.00,
  "total": 174.97
}
```

### Idempotency

All seed migrations use `ON CONFLICT DO NOTHING` to safely handle:
- Pod restarts
- Re-running migrations
- Multiple deployments

**Safe to restart services** - Seed data won't be inserted twice.

### Environment Configuration

**Local/Dev/Demo**: ✅ Seed data enabled (default)  
**Staging**: ⚠️ Optional (configure via Flyway target version)  
**Production**: ❌ Disabled (use Flyway target or separate migration path)

### Migration Files

Seed data located in each service:

```
services/{service}/db/migrations/sql/
├── V1__init_schema.sql      # Schema creation
└── V2__seed_{service}.sql   # Demo data
```

**Flyway Execution**: V1 → V2 (automatic, no manual intervention)

### Verification

```bash
# Check products
curl http://localhost:8080/api/v1/products

# Login as Alice
TOKEN=$(curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com", "password": "password123"}' \
  | jq -r '.token')

# Check Alice's cart
curl http://localhost:8080/api/v1/cart \
  -H "Authorization: Bearer $TOKEN"

# Check Alice's orders
curl http://localhost:8080/api/v1/orders \
  -H "Authorization: Bearer $TOKEN"
```

---