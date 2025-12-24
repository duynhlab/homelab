# Research: PostgreSQL Database Integration for k6 Load Testing

> **Research ID**: postgres-database-integration  
> **Created**: December 14, 2025  
> **Last Updated**: December 14, 2025  
> **Focus**: Đánh giá API docs và nghiên cứu PostgreSQL tools/operators để tích hợp database cho k6 load testing thực tế

> **Related Research**: [Flyway Migration Integration](./research-flyway-migration.md) - Research về Flyway tool để thay thế init container SQL approach

---

## Architecture Pattern Verification

### ✅ 3-Layer Architecture Confirmed

**Current Architecture Pattern (Before Database):**

```mermaid
flowchart TD
    subgraph "Layer 1: Web/Presentation"
        WEB[web/v1/, web/v2/<br/>HTTP Handlers - Gin<br/>- Request validation<br/>- Response formatting]
    end
    
    subgraph "Layer 2: Business Logic"
        LOGIC[logic/v1/, logic/v2/<br/>Business Logic Services<br/>- Business rules<br/>- Validation<br/>- Orchestration]
    end
    
    subgraph "Layer 3: Core/Domain"
        DOMAIN[core/domain/<br/>Domain Models<br/>- Data structures<br/>- Entities]
    end
    
    WEB -->|calls| LOGIC
    LOGIC -->|uses| DOMAIN
    LOGIC -->|returns| WEB
    
    style WEB fill:#e1f5ff
    style LOGIC fill:#fff4e1
    style DOMAIN fill:#e8f5e9
```

**Architecture Pattern (After Database Integration):**

```mermaid
flowchart TD
    subgraph "Layer 1: Web/Presentation"
        WEB[web/v1/, web/v2/<br/>HTTP Handlers - Gin<br/>- Request validation<br/>- Response formatting<br/>✅ UNCHANGED]
    end
    
    subgraph "Layer 2: Business Logic"
        LOGIC[logic/v1/, logic/v2/<br/>Business Logic Services<br/>- Business rules<br/>- Validation<br/>- Orchestration<br/>✅ UPDATED: Calls database]
    end
    
    subgraph "Layer 3: Core/Domain"
        DOMAIN[core/domain/<br/>Domain Models<br/>- Data structures<br/>- Entities<br/>✅ UNCHANGED]
        DB_CORE[core/database.go<br/>Database Connection<br/>- Connection pool<br/>- DSN building<br/>✨ NEW]
    end
    
    subgraph "Layer 4: Data/Persistence"
        POOLER[Connection Poolers<br/>PgBouncer / PgCat<br/>✨ NEW]
        POSTGRES[(PostgreSQL Databases<br/>5 Clusters<br/>✨ NEW)]
    end
    
    WEB -->|calls| LOGIC
    LOGIC -->|uses| DOMAIN
    LOGIC -->|queries| DB_CORE
    DB_CORE -->|connects via| POOLER
    POOLER -->|routes to| POSTGRES
    POSTGRES -->|returns data| DB_CORE
    DB_CORE -->|returns| LOGIC
    LOGIC -->|returns| WEB
    
    style WEB fill:#e1f5ff
    style LOGIC fill:#fff4e1
    style DOMAIN fill:#e8f5e9
    style DB_CORE fill:#f3e5f5
    style POOLER fill:#fff9c4
    style POSTGRES fill:#ffebee
```

**Key Points:**
- ✅ **3-Layer Architecture is PRESERVED**: web → logic → core
- ✅ **Database is added to core layer**: `core/database.go` (not a new layer)
- ✅ **Logic layer calls database**: Through core/database.go
- ✅ **Web layer unchanged**: Still calls logic layer only
- ✅ **Domain models unchanged**: Still in core/domain/

**Code Flow Example (Current - Without Database):**
```go
// web/v1/handler.go
func Login(c *gin.Context) {
    var req domain.LoginRequest
    c.ShouldBindJSON(&req)
    
    // Call logic layer
    response, err := authService.Login(ctx, req)
    c.JSON(http.StatusOK, response)
}

// logic/v1/service.go
func (s *AuthService) Login(ctx context.Context, req domain.LoginRequest) (*domain.AuthResponse, error) {
    // Business logic (currently mock)
    user := domain.User{...}
    return &domain.AuthResponse{Token: "...", User: user}, nil
}

// core/domain/user.go
type User struct {
    ID       string
    Username string
    Email    string
}
```

**Code Flow Example (After Database Integration):**
```go
// web/v1/handler.go (UNCHANGED - still calls logic layer)
func Login(c *gin.Context) {
    var req domain.LoginRequest
    c.ShouldBindJSON(&req)
    
    // Call logic layer (same as before)
    response, err := authService.Login(ctx, req)
    c.JSON(http.StatusOK, response)
}

// logic/v1/service.go (UPDATED - calls database via core layer)
func (s *AuthService) Login(ctx context.Context, req domain.LoginRequest) (*domain.AuthResponse, error) {
    // Get database connection from core layer
    db := database.GetDB() // from core/database.go
    
    // Query database
    var user domain.User
    err := db.QueryRow("SELECT id, username, email FROM users WHERE username = $1", req.Username).Scan(&user.ID, &user.Username, &user.Email)
    
    // Business logic (validate password, generate token)
    return &domain.AuthResponse{Token: "...", User: user}, nil
}

// core/database.go (NEW - database connection)
func Connect() (*sql.DB, error) {
    cfg := config.Load().Database
    dsn := cfg.BuildDSN()
    return sql.Open("postgres", dsn)
}

// core/domain/user.go (UNCHANGED - domain models)
type User struct {
    ID       string
    Username string
    Email    string
}
```

**Key Points:**
- ✅ **3-Layer Architecture is PRESERVED**: web → logic → core
- ✅ **Database is added to core layer**: `core/database.go` (not a new layer)
- ✅ **Logic layer calls database**: Through core/database.go
- ✅ **Web layer unchanged**: Still calls logic layer only
- ✅ **Domain models unchanged**: Still in core/domain/

### ✅ k6 Load Testing Pattern Confirmed

**Current k6 Test Flow (Without Database):**

```mermaid
sequenceDiagram
    participant K6 as k6 Load Test
    participant WEB as Web Layer<br/>(web/v1/handler.go)
    participant LOGIC as Logic Layer<br/>(logic/v1/service.go)
    participant DOMAIN as Core/Domain<br/>(core/domain/)
    
    K6->>WEB: HTTP POST /api/v1/auth/login
    WEB->>LOGIC: Login(ctx, req)
    LOGIC->>DOMAIN: Create User domain model
    DOMAIN-->>LOGIC: User{ID, Username, Email}
    LOGIC-->>WEB: AuthResponse (mock data)
    WEB-->>K6: HTTP 200 OK (mock token)
    
    Note over K6,DOMAIN: ❌ No data persistence<br/>❌ Mock data only
```

**k6 Test Flow (After Database Integration):**

```mermaid
sequenceDiagram
    participant K6 as k6 Load Test
    participant WEB as Web Layer<br/>(web/v1/handler.go)
    participant LOGIC as Logic Layer<br/>(logic/v1/service.go)
    participant DB as Core/Database<br/>(core/database.go)
    participant POOLER as Connection Pooler<br/>(PgBouncer/PgCat)
    participant PG as PostgreSQL Database
    
    K6->>WEB: HTTP POST /api/v1/auth/login
    Note over WEB: ✅ UNCHANGED<br/>Still calls logic layer
    WEB->>LOGIC: Login(ctx, req)
    Note over LOGIC: ✅ UPDATED<br/>Calls database
    LOGIC->>DB: Query user by username
    DB->>POOLER: Connect via pooler
    POOLER->>PG: SELECT * FROM users WHERE username = $1
    PG-->>POOLER: User data
    POOLER-->>DB: Query result
    DB-->>LOGIC: User domain model
    LOGIC->>LOGIC: Validate password<br/>Generate token
    LOGIC-->>WEB: AuthResponse (real data)
    WEB-->>K6: HTTP 200 OK (real token)
    
    Note over K6,PG: ✅ Data persistence<br/>✅ Real database queries<br/>✅ Full 3-layer coverage
```

**k6 Test Coverage:**

```mermaid
flowchart LR
    subgraph "k6 Load Test"
        K6[k6 Script<br/>load-test-multiple-scenarios.js]
    end
    
    subgraph "Layer 1: Web"
        WEB1[Auth Handler<br/>POST /api/v1/auth/login]
        WEB2[User Handler<br/>GET /api/v1/users/:id]
        WEB3[Product Handler<br/>GET /api/v1/products]
        WEB4[Cart Handler<br/>POST /api/v1/cart/items]
        WEB5[Order Handler<br/>POST /api/v1/orders]
    end
    
    subgraph "Layer 2: Logic"
        LOGIC1[AuthService.Login]
        LOGIC2[UserService.GetUser]
        LOGIC3[ProductService.ListProducts]
        LOGIC4[CartService.AddItem]
        LOGIC5[OrderService.CreateOrder]
    end
    
    subgraph "Layer 3: Core"
        DB[Database Connection<br/>core/database.go]
    end
    
    subgraph "Layer 4: Data"
        PG[(PostgreSQL<br/>5 Clusters)]
    end
    
    K6 -->|HTTP Request| WEB1
    K6 -->|HTTP Request| WEB2
    K6 -->|HTTP Request| WEB3
    K6 -->|HTTP Request| WEB4
    K6 -->|HTTP Request| WEB5
    
    WEB1 --> LOGIC1
    WEB2 --> LOGIC2
    WEB3 --> LOGIC3
    WEB4 --> LOGIC4
    WEB5 --> LOGIC5
    
    LOGIC1 --> DB
    LOGIC2 --> DB
    LOGIC3 --> DB
    LOGIC4 --> DB
    LOGIC5 --> DB
    
    DB --> PG
    
    style K6 fill:#ff9800
    style WEB1 fill:#e1f5ff
    style WEB2 fill:#e1f5ff
    style WEB3 fill:#e1f5ff
    style WEB4 fill:#e1f5ff
    style WEB5 fill:#e1f5ff
    style LOGIC1 fill:#fff4e1
    style LOGIC2 fill:#fff4e1
    style LOGIC3 fill:#fff4e1
    style LOGIC4 fill:#fff4e1
    style LOGIC5 fill:#fff4e1
    style DB fill:#f3e5f5
    style PG fill:#ffebee
```

**k6 Test Scenarios (Still Test Through HTTP):**

```mermaid
flowchart TD
    subgraph "k6 User Journey: E-commerce Shopping"
        START[Start Journey]
        STEP1[Step 1: Login<br/>POST /api/v1/auth/login<br/>✨ Creates session in DB]
        STEP2[Step 2: Get Profile<br/>GET /api/v1/users/:id<br/>✨ Reads from DB]
        STEP3[Step 3: Browse Products<br/>GET /api/v1/products<br/>✨ Reads from DB]
        STEP4[Step 4: Add to Cart<br/>POST /api/v1/cart/items<br/>✨ Writes to DB]
        STEP5[Step 5: Create Order<br/>POST /api/v1/orders<br/>✨ Transaction in DB]
        END[End Journey<br/>✅ Data persists]
    end
    
    START --> STEP1
    STEP1 -->|Session created| STEP2
    STEP2 -->|Profile loaded| STEP3
    STEP3 -->|Products listed| STEP4
    STEP4 -->|Cart updated| STEP5
    STEP5 -->|Order created| END
    
    style STEP1 fill:#c8e6c9
    style STEP2 fill:#c8e6c9
    style STEP3 fill:#c8e6c9
    style STEP4 fill:#fff9c4
    style STEP5 fill:#fff9c4
    style END fill:#4caf50,color:#fff
```

**k6 Code Example:**
```javascript
// k6/load-test-multiple-scenarios.js
// k6 vẫn test qua HTTP endpoints (web layer)
// Nhưng giờ có database persistence

// Journey 1: E-commerce Shopping
function ecommerceShoppingJourney() {
  // Step 1: Login (creates session in database)
  makeRequest('POST', `${SERVICES.auth}/api/v1/auth/login`, {...});
  
  // Step 2: Get Profile (reads from database)
  makeRequest('GET', `${SERVICES.user}/api/v2/users/${userId}`, null);
  
  // Step 3: Browse Products (reads from database)
  makeRequest('GET', `${SERVICES.product}/api/v2/catalog/items`, null);
  
  // Step 4: Add to Cart (writes to database)
  makeRequest('POST', `${SERVICES.cart}/api/v1/cart/items`, {...});
  
  // Step 5: Create Order (writes to database, transaction)
  makeRequest('POST', `${SERVICES.order}/api/v1/orders`, {...});
}
```

**Key Points:**
- ✅ **k6 still tests through HTTP**: Web layer endpoints
- ✅ **k6 tests all 3 layers**: web → logic → core → database
- ✅ **k6 tests real data flows**: Data persists in database
- ✅ **k6 tests full user journeys**: Login → Browse → Cart → Order
- ✅ **k6 validates data consistency**: Data persists across requests

### Architecture Compliance Summary

```mermaid
graph TB
    subgraph "Before Database Integration"
        B_WEB[Web Layer<br/>HTTP Handlers]
        B_LOGIC[Logic Layer<br/>Business Logic<br/>Mock Data]
        B_CORE[Core Layer<br/>Domain Models]
        
        B_WEB --> B_LOGIC
        B_LOGIC --> B_CORE
    end
    
    subgraph "After Database Integration"
        A_WEB[Web Layer<br/>HTTP Handlers<br/>✅ UNCHANGED]
        A_LOGIC[Logic Layer<br/>Business Logic<br/>✅ UPDATED: Calls DB]
        A_CORE[Core Layer<br/>Domain Models<br/>✅ UNCHANGED]
        A_DB[Database Connection<br/>core/database.go<br/>✨ NEW]
        A_PG[(PostgreSQL<br/>✨ NEW)]
        
        A_WEB --> A_LOGIC
        A_LOGIC --> A_CORE
        A_LOGIC --> A_DB
        A_DB --> A_PG
    end
    
    style B_WEB fill:#e1f5ff
    style B_LOGIC fill:#fff4e1
    style B_CORE fill:#e8f5e9
    style A_WEB fill:#e1f5ff
    style A_LOGIC fill:#fff4e1
    style A_CORE fill:#e8f5e9
    style A_DB fill:#f3e5f5
    style A_PG fill:#ffebee
```

**Compliance Matrix:**

| Aspect | Current (Mock) | After Database | Status |
|--------|---------------|----------------|--------|
| **3-Layer Architecture** | ✅ web → logic → core | ✅ web → logic → core | ✅ **PRESERVED** |
| **Web Layer** | HTTP handlers | HTTP handlers (unchanged) | ✅ **UNCHANGED** |
| **Logic Layer** | Business logic (mock) | Business logic (real DB) | ✅ **UPDATED** |
| **Core Layer** | Domain models | Domain models + Database | ✅ **EXTENDED** |
| **k6 Testing** | HTTP → mock data | HTTP → real DB data | ✅ **ENHANCED** |
| **Data Persistence** | ❌ No | ✅ Yes | ✅ **ADDED** |

**Conclusion:**
- ✅ **3-Layer Architecture is MAINTAINED** - Database is added to core layer, not a new layer
- ✅ **k6 Load Testing is CORRECT** - Tests through HTTP (web layer), covering all layers
- ✅ **No Architecture Breaking Changes** - Web layer unchanged, logic layer calls database via core layer

---

## Executive Summary

### Problem Statement

**Current State:**
- API documentation (`docs/api/API_REFERENCE.md`) đã có đầy đủ endpoints cho 9 microservices
- Microservices hiện tại **KHÔNG có database** - chỉ return mock data
- k6 load testing đang test các endpoints nhưng không thể verify data flows thực tế
- Không có data persistence → không thể test real user journeys (login → create order → track order)

**Goal:**
- Thêm PostgreSQL database để k6 có thể test full flows như production
- Học hỏi operations (DevOps/SRE focus)
- Có thể chia nhiều cluster, một số dùng connection pooling
- Full monitoring cho database
- **Không quan tâm data loss** (Kind cluster sẽ bị xóa)

### Key Findings

**1. API Documentation Analysis:**
- ✅ **API docs ĐỦ để test thực tế** - có đầy đủ endpoints cho tất cả flows
- ⚠️ **Thiếu database schema** - cần design tables cho 9 services
- ⚠️ **Thiếu migration scripts** - cần setup database schema
- ⚠️ **Thiếu connection pooling config** - cần cho high-load scenarios

**2. PostgreSQL Tools Categorization:**

| Category | Tools | Use Case |
|----------|-------|----------|
| **Kubernetes Operators** | Zalando postgres-operator, CrunchyData postgres-operator | Deploy & manage PostgreSQL in K8s |
| **Connection Poolers** | PgBouncer, PgCat | Reduce connection overhead, improve performance |
| **High Availability** | Patroni | HA PostgreSQL with automatic failover |
| **Monitoring** | postgres_exporter, pgdog | Metrics & observability |
| **Backup** | percona-xtrabackup | Database backups (not needed for this project) |

**3. Recommended Scenarios:**

**Scenario 0: Service-Specific Multi-Cluster (Advanced Learning) ⭐ RECOMMENDED**
- **5 Clusters** với setups khác nhau theo service characteristics:
  - **Cluster 1 (Product)**: CrunchyData + **PgCat** + Read replicas (high traffic, catalog browsing)
  - **Cluster 2 (Review)**: Zalando + **NO POOLER** (isolated workload, direct connection)
  - **Cluster 3 (Auth)**: Zalando + **PgBouncer** (frequent short-lived connections, transaction pooling)
  - **Cluster 4 (Cart+Order)**: CrunchyData + **PgCat** + **Patroni HA** (transaction-heavy, high availability)
  - **Cluster 5 (User+Notification)**: Zalando + **NO POOLER** (low traffic, shared database, multi-schema)
- **Learning Outcomes**: 5 different setups, 2 operators, 2 poolers + no pooler, HA, direct vs pooled connections
- **Use Case**: Học nhiều trường hợp khác nhau - mỗi service có setup riêng theo đặc điểm

**Scenario 1: Single Cluster, Simple Setup (Learning Basics)**
- **PostgreSQL**: Zalando postgres-operator (simpler than CrunchyData)
- **Pooling**: PgBouncer (industry standard)
- **Monitoring**: postgres_exporter (Prometheus metrics)
- **Use Case**: Học basics, single database cho tất cả services

**Scenario 2: Multi-Cluster, Production-Like (Advanced Learning)**
- **PostgreSQL**: CrunchyData postgres-operator (more features)
- **Pooling**: PgCat (modern, better for multi-cluster)
- **HA**: Patroni (for critical services)
- **Monitoring**: postgres_exporter + pgdog (full observability)
- **Use Case**: Simulate production, học advanced operations

**Scenario 3: High-Load Testing (k6 Focus)**
- **PostgreSQL**: Zalando postgres-operator (lightweight)
- **Pooling**: PgBouncer (proven for high concurrency)
- **Monitoring**: postgres_exporter (essential for load testing)
- **Use Case**: Optimize cho k6 load testing với 250 VUs

---

## Current State Analysis

### API Documentation Completeness

**File**: `docs/api/API_REFERENCE.md`

**Coverage Analysis:**

| Service | Endpoints | CRUD Operations | Data Flow | Status |
|---------|-----------|-----------------|-----------|--------|
| **auth** | 4 endpoints | ✅ Login, Register | ✅ Token generation | ✅ **COMPLETE** |
| **user** | 5 endpoints | ✅ Full CRUD | ✅ Profile management | ✅ **COMPLETE** |
| **product** | 5 endpoints | ✅ Full CRUD | ✅ Catalog browsing | ✅ **COMPLETE** |
| **cart** | 4 endpoints | ✅ Add, Remove, View, Clear | ✅ Shopping cart | ✅ **COMPLETE** |
| **order** | 5 endpoints | ✅ Full CRUD | ✅ Order lifecycle | ✅ **COMPLETE** |
| **review** | 5 endpoints | ✅ Full CRUD | ✅ Product reviews | ✅ **COMPLETE** |
| **notification** | 4 endpoints | ✅ Create, Read, Update | ✅ Notifications | ✅ **COMPLETE** |
| **shipping** | 4 endpoints (v1) | ✅ Track, Create | ✅ Shipping tracking | ✅ **COMPLETE** |
| **shipping-v2** | 3 endpoints (v2) | ✅ Enhanced tracking | ✅ Real-time tracking | ✅ **COMPLETE** |

**Total**: 39 endpoints across 9 services

**User Journey Coverage:**

✅ **E-commerce Shopping Flow** (9 services):
- Auth → User → Product → Cart → Shipping-v2 → Order → Notification
- **Status**: All endpoints documented

✅ **Product Review Flow** (5 services):
- Auth → User → Product → Review → Notification
- **Status**: All endpoints documented

✅ **Order Tracking Flow** (6 services):
- Auth → User → Order → Shipping → Notification
- **Status**: All endpoints documented

**Missing for Real Testing:**

1. **Database Schema Design** ❌
   - No table definitions
   - No relationships documented
   - No indexes specified

2. **Data Models** ❌
   - Request/response examples exist
   - But no database entity models

3. **Migration Scripts** ❌
   - No database setup instructions
   - No schema versioning

4. **Connection Configuration** ❌
   - No database connection strings
   - No pooling configuration

**Conclusion**: API docs **ĐỦ để test**, nhưng cần thêm database layer.

**Service-Specific Requirements:**
- **Product**: High-traffic database với read replicas + pooling
- **Review**: Isolated database, simple setup, no pooling
- **Auth**: Medium-high traffic, transaction pooling (PgBouncer)
- **Cart + Order**: Transaction-heavy, HA required, multi-service pooling
- **User + Notification**: Low traffic, can share database, no pooling

### Current Microservices Implementation

**Codebase Analysis:**

```bash
# No database libraries in go.mod
# Only commented reference in tracing.go:
# ctx, span := middleware.StartSpan(ctx, "database.query")
```

**Current Data Flow:**
```
k6 Request → Microservice → Mock Data → Response
```

**Needed Data Flow:**
```
k6 Request → Microservice → PostgreSQL → Response
```

**Services Currently Using Mock Data:**
- All 9 services return hardcoded responses
- No persistence layer
- Cannot test data consistency
- Cannot test transactions
- Cannot test real user journeys

---

## PostgreSQL Tools Research

### 1. Kubernetes Operators

#### 1.1 Zalando Postgres Operator

**GitHub**: `zalando/postgres-operator`  
**Helm Chart**: `postgres-operator/postgres-operator`

**Features:**
- ✅ Kubernetes-native PostgreSQL management
- ✅ Automatic failover with Patroni integration
- ✅ Connection pooling built-in (PgBouncer sidecar)
- ✅ Backup/restore with WAL-E
- ✅ Simple CRD-based configuration
- ✅ Good for learning (simpler than CrunchyData)

**Pros:**
- ✅ **Easier to learn** - simpler architecture
- ✅ **Good documentation** - Zalando has extensive docs
- ✅ **Production-proven** - used by Zalando at scale
- ✅ **Built-in pooling** - PgBouncer as sidecar
- ✅ **Active development** - regular updates

**Cons:**
- ⚠️ Less features than CrunchyData
- ⚠️ Smaller community than CrunchyData

**Use Case**: **RECOMMENDED for Scenario 1 & 3** (Learning + High-Load)

**Deployment:**
```bash
helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update
helm upgrade --install postgres-operator postgres-operator/postgres-operator \
  --namespace monitoring \
  --create-namespace \
  -f k8s/postgres-operator-zalando/values.yaml \
  --wait
```

**Helm Values File (`k8s/postgres-operator-zalando/values.yaml`):**
```yaml
# Zalando Postgres Operator Helm Values
# Chart: postgres-operator/postgres-operator
# Version: v1.15.0 (adjust as needed)
# Docs: https://github.com/zalando/postgres-operator

# Operator image configuration
image:
  registry: registry.opensource.zalan.do
  repository: acid/postgres-operator
  tag: v1.15.0  # ⚠️ Fix version here for stability
  pullPolicy: IfNotPresent

# Operator configuration
config:
  # Kubernetes API connection
  kubernetes:
    cluster_name: "kind-cluster"
  
  # PostgreSQL configuration
  postgresql:
    # Default parameters for all PostgreSQL instances
    parameters:
      max_connections: "100"
      shared_buffers: "128MB"
      effective_cache_size: "256MB"
      maintenance_work_mem: "64MB"
      checkpoint_completion_target: "0.9"
      wal_buffers: "16MB"
      default_statistics_target: "100"
      random_page_cost: "4.0"
      effective_io_concurrency: "2"
      work_mem: "4MB"
      min_wal_size: "1GB"
      max_wal_size: "4GB"
  
  # Connection pooler (PgBouncer) configuration
  connection_pooler:
    # Default PgBouncer settings
    default_parameters:
      pool_mode: "transaction"
      max_client_conn: "100"
      default_pool_size: "25"
      reserve_pool_size: "5"
      reserve_pool_timeout: "3"
      max_db_connections: "0"  # 0 = no limit
      max_user_connections: "0"
  
  # Backup configuration
  backup:
    # WAL-E backup settings (if enabled)
    wal_s3_bucket: ""  # Leave empty for no backup (learning project)
  
  # Monitoring
  enable_pgversion_env_var: true

# Operator resources
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"

# Service account
serviceAccount:
  create: true
  name: "postgres-operator"

# RBAC
rbac:
  create: true

# Pod security context
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

# Security context
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # Operator needs write access
  capabilities:
    drop:
      - ALL
```

**CRD Example:**
```yaml
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  name: microservices-db
spec:
  teamId: "platform"
  volume:
    size: 10Gi
  numberOfInstances: 1
  users:
    monitoring: [superuser]
  databases:
    auth: monitoring
    user: monitoring
    product: monitoring
    # ... other services
```

#### 1.2 CrunchyData Postgres Operator

**GitHub**: `CrunchyData/postgres-operator`  
**Helm Chart**: `postgres-operator/postgres-operator` (different from Zalando)

**Features:**
- ✅ Enterprise-grade PostgreSQL operator
- ✅ Advanced backup/restore (pgBackRest)
- ✅ Multi-cluster management
- ✅ Advanced monitoring (pgMonitor)
- ✅ More configuration options
- ✅ Better for complex scenarios

**Pros:**
- ✅ **More features** - enterprise-grade
- ✅ **Better multi-cluster** - designed for it
- ✅ **Advanced monitoring** - pgMonitor integration
- ✅ **Better backup** - pgBackRest (better than WAL-E)
- ✅ **Larger community** - more support

**Cons:**
- ⚠️ More complex - steeper learning curve
- ⚠️ More resource-intensive
- ⚠️ Overkill for simple learning scenarios

**Use Case**: **RECOMMENDED for Scenario 2** (Multi-Cluster, Production-Like)

**Deployment:**
```bash
helm repo add postgres-operator https://charts.crunchydata.com
helm repo update
helm upgrade --install postgres-operator postgres-operator/postgres-operator \
  --namespace monitoring \
  --create-namespace \
  -f k8s/postgres-operator-crunchydata/values.yaml \
  --wait
```

**Helm Values File (`k8s/postgres-operator-crunchydata/values.yaml`):**
```yaml
# CrunchyData Postgres Operator Helm Values
# Chart: postgres-operator/postgres-operator
# Version: v5.7.0 (adjust as needed)
# Docs: https://github.com/CrunchyData/postgres-operator

# Operator image configuration
image:
  registry: registry.developers.crunchydata.com
  repository: crunchy/postgres-operator
  tag: v5.7.0  # ⚠️ Fix version here for stability
  pullPolicy: IfNotPresent

# Operator configuration
config:
  # PGO (PostgreSQL Operator) configuration
  pgo:
    # Image prefix for PostgreSQL images
    imagePrefix: "registry.developers.crunchydata.com/crunchydata"
    
    # Default PostgreSQL version
    pgoImageTag: "ubi8-5.7.0-0"
    
    # Feature flags
    features:
      # Enable pgBackRest for backups (optional for learning)
      pgbackrest: false  # Disable for learning project
      
      # Enable pgMonitor for monitoring
      pgmonitor: true
    
    # Resource defaults
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  
  # PostgreSQL cluster defaults
  postgresql:
    # Default PostgreSQL version
    version: "15"
    
    # Default resources per instance
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
    
    # Default storage
    storage:
      size: "10Gi"
      storageClass: "standard"  # Adjust for your cluster
  
  # Patroni HA configuration
  patroni:
    # Default Patroni settings
    dynamicConfiguration:
      postgresql:
        parameters:
          max_connections: "100"
          shared_buffers: "128MB"
          effective_cache_size: "256MB"

# Operator resources
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"

# Service account
serviceAccount:
  create: true
  name: "postgres-operator"

# RBAC
rbac:
  create: true

# Security context
securityContext:
  runAsNonRoot: true
  runAsUser: 26  # PostgreSQL user ID
  fsGroup: 26
```

### 2. Connection Poolers

#### 2.1 PgBouncer

**GitHub**: `pgbouncer/pgbouncer`  
**Type**: Connection pooler

**Features:**
- ✅ Industry standard connection pooler
- ✅ Transaction pooling mode (most efficient)
- ✅ Session pooling mode
- ✅ Statement pooling mode
- ✅ Lightweight (single binary)
- ✅ Low overhead

**Pros:**
- ✅ **Proven** - used everywhere
- ✅ **Lightweight** - minimal resources
- ✅ **Flexible** - 3 pooling modes
- ✅ **Well-documented** - extensive docs
- ✅ **Kubernetes-ready** - easy to deploy

**Cons:**
- ⚠️ No advanced features (just pooling)
- ⚠️ Single point of failure (need HA setup)

**Use Case**: **RECOMMENDED for Scenario 1 & 3** (Simple + High-Load)

**Deployment Options:**

1. **Standalone via Helm** (recommended for learning):
```bash
helm repo add pgbouncer https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install pgbouncer pgbouncer/pgbouncer \
  --namespace monitoring \
  --create-namespace \
  -f k8s/pgbouncer/values.yaml \
  --wait
```

**Helm Values File (`k8s/pgbouncer/values.yaml`):**
```yaml
# PgBouncer Helm Values
# Chart: pgbouncer/pgbouncer (Bitnami)
# Version: 15.0.0 (adjust as needed)
# Docs: https://github.com/bitnami/charts/tree/main/bitnami/pgbouncer

# Image configuration
image:
  registry: docker.io
  repository: bitnami/pgbouncer
  tag: 1.22.0-debian-12-r0  # ⚠️ Fix version here
  pullPolicy: IfNotPresent

# PgBouncer configuration
configuration:
  # Pooling mode: session, transaction, statement
  poolMode: "transaction"
  
  # Connection limits
  maxClientConn: "200"
  defaultPoolSize: "25"
  reservePoolSize: "5"
  reservePoolTimeout: "3"
  
  # Database connections (configure per service)
  databases:
    # Example: Auth service
    auth: |
      host=auth-db.postgres-operator.svc.cluster.local
      port=5432
      dbname=auth
      user=auth
      password=${AUTH_DB_PASSWORD}
  
  # PgBouncer settings
  settings:
    listen_addr: "0.0.0.0"
    listen_port: "6432"
    auth_type: "md5"
    auth_file: "/opt/bitnami/pgbouncer/conf/userlist.txt"
    log_connections: "1"
    log_disconnections: "1"
    log_pooler_errors: "1"
    ignore_startup_parameters: "extra_float_digits"

# Replicas
replicaCount: 2

# Resources
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"

# Service
service:
  type: ClusterIP
  port: 6432

# Secrets for database passwords
existingSecret: ""  # Create secret separately
secretKeyRef: "password"  # Key in secret

# Health checks
livenessProbe:
  enabled: true
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  enabled: true
  initialDelaySeconds: 5
  periodSeconds: 5
```

2. **Sidecar với Zalando Operator** (automatic, no separate values file needed):
- Zalando operator tự động deploy PgBouncer as sidecar
- Configuration via PostgreSQL CRD `connectionPooler` section

2. **Sidecar** (with Zalando operator):
- Built-in as sidecar container
- Automatic configuration

**Configuration Example:**
```ini
[databases]
auth = host=postgres.auth.svc.cluster.local port=5432 dbname=auth
user = host=postgres.user.svc.cluster.local port=5432 dbname=user

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

#### 2.2 PgCat

**GitHub**: `postgresml/pgcat`  
**Type**: Modern connection pooler

**Features:**
- ✅ Modern Rust-based pooler
- ✅ Better performance than PgBouncer
- ✅ Advanced load balancing
- ✅ Query routing
- ✅ Better for multi-cluster
- ✅ Built-in sharding support

**Pros:**
- ✅ **Modern** - Rust-based, faster
- ✅ **Better multi-cluster** - designed for it
- ✅ **Advanced features** - query routing, sharding
- ✅ **Better performance** - lower latency

**Cons:**
- ⚠️ Newer - less battle-tested
- ⚠️ Smaller community
- ⚠️ More complex setup

**Use Case**: **RECOMMENDED for Scenario 2** (Multi-Cluster)

**Deployment:**

**Option 1: Helm Chart (if available):**
```bash
# Check if official Helm chart exists
helm search repo pgcat

# If available:
helm upgrade --install pgcat <chart-repo>/pgcat \
  --namespace monitoring \
  --create-namespace \
  -f k8s/pgcat/values.yaml \
  --wait
```

**Option 2: Manual Deployment with ConfigMap (recommended for learning):**

**Helm Values File (`k8s/pgcat/values.yaml`):**
```yaml
# PgCat Helm Values (Manual Deployment Template)
# Chart: Custom (no official Helm chart yet)
# Image: postgresml/pgcat
# Version: latest (adjust as needed)
# Docs: https://github.com/postgresml/pgcat

# Image configuration
image:
  registry: docker.io
  repository: postgresml/pgcat
  tag: latest  # ⚠️ Fix version here (e.g., v1.0.0)
  pullPolicy: IfNotPresent

# Replicas
replicaCount: 2

# PgCat configuration (via ConfigMap)
config:
  # Admin interface
  admin:
    host: "0.0.0.0"
    port: 9930
  
  # Pools configuration
  pools:
    # Product service pool
    product:
      host: "product-db-primary.postgres-operator.svc.cluster.local"
      port: 5432
      database: "product"
      user: "product"
      password: "${PRODUCT_DB_PASSWORD}"
      pool_size: 50
      load_balance: true
      replicas:
        - host: "product-db-replica-1.postgres-operator.svc.cluster.local"
          port: 5432
        - host: "product-db-replica-2.postgres-operator.svc.cluster.local"
          port: 5432
    
    # Cart service pool
    cart:
      host: "transaction-db-primary.postgres-operator.svc.cluster.local"
      port: 5432
      database: "cart"
      user: "cart"
      password: "${CART_DB_PASSWORD}"
      pool_size: 30
    
    # Order service pool
    order:
      host: "transaction-db-primary.postgres-operator.svc.cluster.local"
      port: 5432
      database: "order"
      user: "order"
      password: "${ORDER_DB_PASSWORD}"
      pool_size: 30

# Resources
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"

# Service
service:
  type: ClusterIP
  port: 5432  # PostgreSQL protocol port
  adminPort: 9930  # Admin interface port

# Secrets for database passwords
existingSecret: ""  # Create secret separately
secretKeyRef: "password"  # Key in secret
```

**Note**: PgCat may not have official Helm chart. Use Kubernetes manifests with ConfigMap for configuration.

### 3. High Availability

#### 3.1 Patroni

**GitHub**: `zalando/patroni`  
**Type**: HA PostgreSQL manager

**Features:**
- ✅ Automatic failover
- ✅ Leader election (etcd, Consul, Kubernetes)
- ✅ PostgreSQL cluster management
- ✅ Integrated with Zalando operator
- ✅ Production-grade HA

**Pros:**
- ✅ **Proven HA** - used in production
- ✅ **Kubernetes-native** - uses K8s API for leader election
- ✅ **Automatic failover** - < 30 seconds
- ✅ **Integrated** - works with Zalando operator

**Cons:**
- ⚠️ More complex - need to understand HA concepts
- ⚠️ Resource overhead - multiple replicas

**Use Case**: **RECOMMENDED for Scenario 2** (Production-Like, Critical Services)

**Integration with Zalando Operator:**
- Built-in - just enable in postgresql CRD:
```yaml
spec:
  numberOfInstances: 3  # HA with Patroni
  enableMasterLoadBalancer: true
```

### 4. Monitoring

#### 4.1 postgres_exporter

**GitHub**: `prometheus-community/postgres_exporter`  
**Type**: Prometheus exporter

**Features:**
- ✅ Standard PostgreSQL metrics
- ✅ Query performance metrics
- ✅ Connection pool metrics
- ✅ Replication lag metrics
- ✅ Database size metrics
- ✅ Easy Prometheus integration

**Pros:**
- ✅ **Standard** - de facto standard
- ✅ **Comprehensive** - all important metrics
- ✅ **Easy integration** - ServiceMonitor ready
- ✅ **Well-maintained** - prometheus-community

**Cons:**
- ⚠️ Basic - just metrics, no advanced analysis

**Use Case**: **REQUIRED for all scenarios** (Essential monitoring)

**Deployment:**

**Option 1: Helm Chart (recommended):**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace monitoring \
  --create-namespace \
  -f k8s/postgres-exporter/values.yaml \
  --wait
```

**Helm Values File (`k8s/postgres-exporter/values.yaml`):**
```yaml
# postgres_exporter Helm Values
# Chart: prometheus-community/prometheus-postgres-exporter
# Version: 2.8.0 (adjust as needed)
# Docs: https://github.com/prometheus-community/postgres_exporter

# Image configuration
image:
  registry: quay.io
  repository: prometheuscommunity/postgres-exporter
  tag: v0.15.0  # ⚠️ Fix version here
  pullPolicy: IfNotPresent

# Configuration
config:
  # Data source name (DSN) - use Secret for password
  datasource:
    # Option 1: Single database
    host: "postgres.postgres-operator.svc.cluster.local"
    port: 5432
    database: "postgres"
    user: "postgres"
    password: "${DB_PASSWORD}"  # From Secret
    
    # Option 2: Multiple databases (use queries.yaml)
    # Leave empty and use queries.yaml for multi-database setup
  
  # Custom queries (optional)
  queries: |
    # Custom PostgreSQL queries for monitoring
    pg_replication:
      query: "SELECT * FROM pg_stat_replication"
      master: true
      metrics:
        - lag_bytes:
            usage: "GAUGE"
            description: "Replication lag in bytes"

# Replicas (one per database cluster)
replicaCount: 1

# Resources
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

# Service
service:
  type: ClusterIP
  port: 9187  # Default postgres_exporter port

# ServiceMonitor (for Prometheus auto-discovery)
serviceMonitor:
  enabled: true
  namespace: monitoring
  labels:
    app: postgres-exporter
  interval: 15s
  scrapeTimeout: 10s

# Secrets for database passwords
existingSecret: ""  # Create secret separately
secretKeyRef: "password"  # Key in secret

# Health checks
livenessProbe:
  enabled: true
  httpGet:
    path: /metrics
    port: 9187
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  enabled: true
  httpGet:
    path: /metrics
    port: 9187
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Option 2: Sidecar với PostgreSQL Operator:**
- Zalando operator: PgBouncer sidecar có thể export metrics
- CrunchyData operator: pgMonitor integration (built-in)

**Metrics Exposed:**
- `pg_stat_database_*` - Database statistics
- `pg_stat_user_tables_*` - Table statistics
- `pg_stat_activity_*` - Active connections
- `pg_replication_*` - Replication lag
- Custom queries supported

#### 4.2 pgdog

**GitHub**: `pgdogdev/pgdog`  
**Type**: Advanced PostgreSQL observability

**Features:**
- ✅ Advanced query analysis
- ✅ Slow query detection
- ✅ Connection pool monitoring
- ✅ Query performance insights
- ✅ Better than basic exporter

**Pros:**
- ✅ **Advanced** - more than just metrics
- ✅ **Query analysis** - slow query detection
- ✅ **Better insights** - performance analysis

**Cons:**
- ⚠️ Newer - less mature
- ⚠️ More complex setup

**Use Case**: **OPTIONAL for Scenario 2** (Advanced monitoring)

### 5. Backup Tools

#### 5.1 percona-xtrabackup

**GitHub**: `percona/percona-xtrabackup`  
**Type**: Backup tool

**Features:**
- ✅ Hot backups (no downtime)
- ✅ Point-in-time recovery
- ✅ Incremental backups
- ✅ Industry standard

**Analysis:**
- ❌ **NOT NEEDED** for this project
- User explicitly said: "skip lost data", "I delete Kind clusters"
- Learning focus, not production data protection

**Use Case**: **SKIP** (Not needed for learning project)

---

## Service-Specific Database Scenarios (Advanced Learning)

### Service Characteristics Analysis

**Traffic Patterns từ k6 Load Testing:**

| Service | Traffic Level | Characteristics | Database Needs |
|---------|---------------|-----------------|----------------|
| **product** | 🔥 **HIGH** | Catalog browsing, product views (most traffic) | High connections, pooling required |
| **auth** | ⚡ **MEDIUM-HIGH** | Login/register (frequent, short-lived) | Connection pooling, fast queries |
| **cart** | ⚡ **MEDIUM** | Add/remove items (session-based) | Moderate connections |
| **order** | ⚡ **MEDIUM** | Order creation (transaction-heavy) | Transaction support, moderate connections |
| **review** | 📊 **LOW-MEDIUM** | Read/write reviews (isolated workload) | Can be separate, simple setup |
| **user** | 📊 **LOW-MEDIUM** | Profile management (read-heavy) | Read replicas beneficial |
| **notification** | 📊 **LOW** | Send notifications (write-heavy) | Simple, no pooling needed |
| **shipping** | 📊 **LOW** | Tracking queries (read-heavy) | Simple, can share cluster |

**Recommendation Strategy:**
- **High Traffic Services** → Dedicated cluster + pooling
- **Isolated Services** → Separate cluster (learning isolation)
- **Low Traffic Services** → Can share cluster or separate (flexible)

---

## Recommended Scenarios

### Scenario 0: Service-Specific Multi-Cluster Setup (Advanced Learning)

**Goal**: Học nhiều trường hợp khác nhau - mỗi service có setup riêng theo đặc điểm

**Architecture Overview:**

```mermaid
flowchart TB
    subgraph "Cluster 1: Product Service (High Traffic)"
        direction TB
        CD1[CrunchyData Operator]
        PG1[PostgreSQL<br/>2 replicas<br/>Read-optimized]
        PC1[PgCat Pooler<br/>Transaction pooling<br/>500 connections<br/>Load balancing]
        SVC1[Product Service<br/>High traffic<br/>Catalog browsing]
        
        CD1 --> PG1
        PG1 --> PC1
        PC1 --> SVC1
    end
    
    subgraph "Cluster 2: Review Service (Isolated)"
        direction TB
        ZA2[Zalando Operator]
        PG2[PostgreSQL<br/>1 instance<br/>Simple]
        NO2[NO POOLER<br/>Direct connection<br/>Low traffic]
        SVC2[Review Service<br/>Isolated workload<br/>Read/write reviews]
        
        ZA2 --> PG2
        PG2 --> NO2
        NO2 --> SVC2
    end
    
    subgraph "Cluster 3: Auth Service (Medium-High)"
        direction TB
        ZA3[Zalando Operator]
        PG3[PostgreSQL<br/>1 instance]
        PB3[PgBouncer<br/>Transaction pooling<br/>200 max connections<br/>25 pool size]
        SVC3[Auth Service<br/>Frequent connections<br/>Login/register]
        
        ZA3 --> PG3
        PG3 --> PB3
        PB3 --> SVC3
    end
    
    subgraph "Cluster 4: Cart + Order (Transaction-Heavy)"
        direction TB
        CD4[CrunchyData Operator]
        PG4[PostgreSQL<br/>2 replicas<br/>HA with Patroni]
        PC4[PgCat Pooler<br/>Multi-service routing<br/>Cart → Replica 1<br/>Order → Replica 2]
        SVC4[Cart + Order Services<br/>Transaction-heavy<br/>Need consistency]
        
        CD4 --> PG4
        PG4 --> PC4
        PC4 --> SVC4
    end
    
    subgraph "Cluster 5: User + Notification (Low Traffic)"
        direction TB
        ZA5[Zalando Operator]
        PG5[PostgreSQL<br/>1 instance<br/>Shared database]
        NO5[NO POOLER<br/>Multi-schema<br/>user schema<br/>notification schema]
        SVC5[User + Notification Services<br/>Low traffic<br/>Shared resources]
        
        ZA5 --> PG5
        PG5 --> NO5
        NO5 --> SVC5
    end
    
    subgraph "Monitoring Stack"
        direction LR
        EXP[postgres_exporter<br/>All clusters]
        PROM[Prometheus]
        GRAF[Grafana<br/>Multi-cluster Dashboard]
        
        EXP --> PROM
        PROM --> GRAF
    end
    
    PG1 -.->|Metrics| EXP
    PG2 -.->|Metrics| EXP
    PG3 -.->|Metrics| EXP
    PG4 -.->|Metrics| EXP
    PG5 -.->|Metrics| EXP
```

**Detailed Service Configurations:**

#### Cluster 1: Product Service (High Traffic + PgCat)

**Why PgCat?**
- Product service có traffic cao nhất (catalog browsing)
- Cần load balancing across replicas
- PgCat tốt hơn cho multi-replica scenarios

**Configuration:**
```yaml
# CrunchyData PostgreSQL
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: product-db
spec:
  instances:
    - name: instance1
      replicas: 2
      resources:
        requests:
          memory: 2Gi
          cpu: 1000m
  postgresVersion: 15
  backups:
    pgbackrest:
      repos:
        - name: repo1
          volume:
            volumeClaimSpec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 20Gi
```

```yaml
# PgCat Configuration
databases:
  product:
    host: product-db-primary.postgres-operator.svc.cluster.local
    port: 5432
    database: product
    pool_size: 50
    load_balance: true
    replicas:
      - host: product-db-replica-1.postgres-operator.svc.cluster.local
      - host: product-db-replica-2.postgres-operator.svc.cluster.local
```

**Service Connection (via PgCat - via Separate Environment Variables):**

**Go Code (`services/internal/product/core/database.go`):**
```go
package database

import (
    "database/sql"
    "fmt"
    "os"
    "strconv"
    _ "github.com/lib/pq" // PostgreSQL driver
)

// DatabaseConfig holds database connection configuration
type DatabaseConfig struct {
    Host           string
    Port           string
    Name           string
    User           string
    Password       string
    SSLMode        string
    MaxConnections int
    PoolerType     string
}

// LoadConfig loads database configuration from separate environment variables
func LoadConfig() (*DatabaseConfig, error) {
    cfg := &DatabaseConfig{
        Host:           getEnv("DB_HOST", ""),
        Port:           getEnv("DB_PORT", "5432"),
        Name:           getEnv("DB_NAME", ""),
        User:           getEnv("DB_USER", ""),
        Password:       getEnv("DB_PASSWORD", ""),
        SSLMode:        getEnv("DB_SSLMODE", "disable"),
        MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 50),
        PoolerType:     getEnv("DB_POOLER_TYPE", "pgcat"),
    }
    
    // Validate required fields
    if cfg.Host == "" {
        return nil, fmt.Errorf("DB_HOST environment variable is required")
    }
    if cfg.Name == "" {
        return nil, fmt.Errorf("DB_NAME environment variable is required")
    }
    if cfg.User == "" {
        return nil, fmt.Errorf("DB_USER environment variable is required")
    }
    if cfg.Password == "" {
        return nil, fmt.Errorf("DB_PASSWORD environment variable is required")
    }
    
    return cfg, nil
}

// BuildDSN constructs PostgreSQL connection string from config
func (c *DatabaseConfig) BuildDSN() string {
    // Format: postgresql://user:password@host:port/dbname?sslmode=disable
    // Note: Connect to PgCat pooler (DB_HOST points to PgCat), routes to appropriate replica
    return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
        c.User,
        c.Password,
        c.Host,  // e.g., pgcat.product.svc.cluster.local
        c.Port,
        c.Name,
        c.SSLMode,
    )
}

// Connect establishes database connection using separate environment variables
func Connect() (*sql.DB, error) {
    // ⚠️ CRITICAL: Load config from separate env vars, NOT DATABASE_URL string
    cfg, err := LoadConfig()
    if err != nil {
        return nil, fmt.Errorf("failed to load database config: %w", err)
    }
    
    // Build DSN from individual env vars
    dsn := cfg.BuildDSN()
    
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }
    
    // Configure connection pool (higher for high traffic)
    db.SetMaxOpenConns(cfg.MaxConnections)
    db.SetMaxIdleConns(cfg.MaxConnections / 2)
    
    // Test connection
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}

// Helper functions
func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
    if val := os.Getenv(key); val != "" {
        if intVal, err := strconv.Atoi(val); err == nil {
            return intVal
        }
    }
    return defaultValue
}
```

**Helm Chart Configuration (`charts/values/product.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "product"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars, KHÔNG dùng DATABASE_URL string
extraEnv:
  - name: DB_HOST
    value: "pgcat.product.svc.cluster.local"  # PgCat pooler endpoint
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "product"
  - name: DB_USER
    value: "product"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: product-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "50"  # Higher for high traffic
  - name: DB_POOLER_TYPE
    value: "pgcat"  # Indicates PgCat pooler (for logging/monitoring)
```

**Learning Points:**
- ✅ High-traffic database optimization
- ✅ Read replica load balancing
- ✅ PgCat multi-replica routing
- ✅ Connection pool tuning for high load
- ✅ Environment variable configuration pattern

#### Cluster 2: Review Service (Isolated + No Pooler)

**Why No Pooler?**
- Review service có traffic thấp-trung bình
- Workload isolated (không ảnh hưởng services khác)
- Học direct database connection (không qua pooler)
- Simple setup để học basics

**Configuration:**
```yaml
# Zalando PostgreSQL (Simple)
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  name: review-db
spec:
  teamId: "platform"
  volume:
    size: 5Gi
  numberOfInstances: 1
  users:
    review: [createdb]
  databases:
    review: review
```

**Service Connection (Direct - via Separate Environment Variables):**

**Go Code (`services/internal/review/core/database.go`):**
```go
package database

import (
    "database/sql"
    "fmt"
    "os"
    "strconv"
    _ "github.com/lib/pq" // PostgreSQL driver
)

// DatabaseConfig holds database connection configuration
type DatabaseConfig struct {
    Host           string
    Port           string
    Name           string
    User           string
    Password       string
    SSLMode        string
    MaxConnections int
}

// LoadConfig loads database configuration from separate environment variables
func LoadConfig() (*DatabaseConfig, error) {
    cfg := &DatabaseConfig{
        Host:           getEnv("DB_HOST", ""),
        Port:           getEnv("DB_PORT", "5432"),
        Name:           getEnv("DB_NAME", ""),
        User:           getEnv("DB_USER", ""),
        Password:       getEnv("DB_PASSWORD", ""),
        SSLMode:        getEnv("DB_SSLMODE", "disable"),
        MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 10),
    }
    
    // Validate required fields
    if cfg.Host == "" {
        return nil, fmt.Errorf("DB_HOST environment variable is required")
    }
    if cfg.Name == "" {
        return nil, fmt.Errorf("DB_NAME environment variable is required")
    }
    if cfg.User == "" {
        return nil, fmt.Errorf("DB_USER environment variable is required")
    }
    if cfg.Password == "" {
        return nil, fmt.Errorf("DB_PASSWORD environment variable is required")
    }
    
    return cfg, nil
}

// BuildDSN constructs PostgreSQL connection string from config
func (c *DatabaseConfig) BuildDSN() string {
    // Format: postgresql://user:password@host:port/dbname?sslmode=disable
    return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
        c.User,
        c.Password,
        c.Host,
        c.Port,
        c.Name,
        c.SSLMode,
    )
}

// Connect establishes database connection using separate environment variables
func Connect() (*sql.DB, error) {
    // ⚠️ CRITICAL: Load config from separate env vars, NOT DATABASE_URL string
    cfg, err := LoadConfig()
    if err != nil {
        return nil, fmt.Errorf("failed to load database config: %w", err)
    }
    
    // Build DSN from individual env vars
    dsn := cfg.BuildDSN()
    
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }
    
    // Configure connection pool (smaller for direct connection)
    db.SetMaxOpenConns(cfg.MaxConnections)
    db.SetMaxIdleConns(cfg.MaxConnections / 2)
    
    // Test connection
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}

// Helper functions
func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
    if val := os.Getenv(key); val != "" {
        if intVal, err := strconv.Atoi(val); err == nil {
            return intVal
        }
    }
    return defaultValue
}
```

**Helm Chart Configuration (`charts/values/review.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "review"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars, KHÔNG dùng DATABASE_URL string
extraEnv:
  - name: DB_HOST
    value: "review-db.postgres-operator.svc.cluster.local"  # Direct connection, no pooler
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "review"
  - name: DB_USER
    value: "review"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: review-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "10"  # Direct connection, no pooler - smaller pool
```

**Learning Points:**
- ✅ Direct database connection
- ✅ Service isolation
- ✅ Simple single-instance setup
- ✅ When NOT to use pooling

#### Cluster 3: Auth Service (Medium-High + PgBouncer)

**Why PgBouncer?**
- Auth service có frequent, short-lived connections
- Login/register operations cần fast response
- PgBouncer transaction pooling perfect cho use case này
- Industry standard, dễ học

**Configuration:**
```yaml
# Zalando PostgreSQL with PgBouncer sidecar
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  name: auth-db
spec:
  teamId: "platform"
  volume:
    size: 5Gi
  numberOfInstances: 1
  enableMasterLoadBalancer: false
  # PgBouncer enabled by default in Zalando operator
  connectionPooler:
    numberOfInstances: 2
    schema: pooler
    user: pooler
    mode: transaction
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

**PgBouncer Config (Auto-generated):**
```ini
[databases]
auth = host=auth-db.postgres-operator.svc.cluster.local port=5432 dbname=auth

[pgbouncer]
pool_mode = transaction
max_client_conn = 200
default_pool_size = 25
```

**Service Connection (via PgBouncer - via Separate Environment Variables):**

**Go Code (`services/internal/auth/core/database.go`):**
```go
package database

import (
    "database/sql"
    "fmt"
    "os"
    "strconv"
    _ "github.com/lib/pq" // PostgreSQL driver
)

// DatabaseConfig holds database connection configuration
type DatabaseConfig struct {
    Host           string
    Port           string
    Name           string
    User           string
    Password       string
    SSLMode        string
    MaxConnections int
    PoolMode       string
}

// LoadConfig loads database configuration from separate environment variables
func LoadConfig() (*DatabaseConfig, error) {
    cfg := &DatabaseConfig{
        Host:           getEnv("DB_HOST", ""),
        Port:           getEnv("DB_PORT", "5432"),
        Name:           getEnv("DB_NAME", ""),
        User:           getEnv("DB_USER", ""),
        Password:       getEnv("DB_PASSWORD", ""),
        SSLMode:        getEnv("DB_SSLMODE", "disable"),
        MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 25),
        PoolMode:       getEnv("DB_POOL_MODE", "transaction"),
    }
    
    // Validate required fields
    if cfg.Host == "" {
        return nil, fmt.Errorf("DB_HOST environment variable is required")
    }
    if cfg.Name == "" {
        return nil, fmt.Errorf("DB_NAME environment variable is required")
    }
    if cfg.User == "" {
        return nil, fmt.Errorf("DB_USER environment variable is required")
    }
    if cfg.Password == "" {
        return nil, fmt.Errorf("DB_PASSWORD environment variable is required")
    }
    
    return cfg, nil
}

// BuildDSN constructs PostgreSQL connection string from config
func (c *DatabaseConfig) BuildDSN() string {
    // Format: postgresql://user:password@host:port/dbname?sslmode=disable
    // Note: Connect to pooler service (DB_HOST points to pooler), not direct database
    return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
        c.User,
        c.Password,
        c.Host,  // e.g., auth-db-pooler.postgres-operator.svc.cluster.local
        c.Port,
        c.Name,
        c.SSLMode,
    )
}

// Connect establishes database connection using separate environment variables
func Connect() (*sql.DB, error) {
    // ⚠️ CRITICAL: Load config from separate env vars, NOT DATABASE_URL string
    cfg, err := LoadConfig()
    if err != nil {
        return nil, fmt.Errorf("failed to load database config: %w", err)
    }
    
    // Build DSN from individual env vars
    dsn := cfg.BuildDSN()
    
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }
    
    // Configure connection pool (PgBouncer handles pooling, but app still needs limits)
    db.SetMaxOpenConns(cfg.MaxConnections)
    db.SetMaxIdleConns(cfg.MaxConnections / 2)
    
    // Test connection
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}

// Helper functions
func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
    if val := os.Getenv(key); val != "" {
        if intVal, err := strconv.Atoi(val); err == nil {
            return intVal
        }
    }
    return defaultValue
}
```

**Helm Chart Configuration (`charts/values/auth.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "auth"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars, KHÔNG dùng DATABASE_URL string
extraEnv:
  - name: DB_HOST
    value: "auth-db-pooler.postgres-operator.svc.cluster.local"  # PgBouncer pooler endpoint
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "auth"
  - name: DB_USER
    value: "auth"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: auth-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "25"  # PgBouncer pool size
  - name: DB_POOL_MODE
    value: "transaction"  # PgBouncer transaction pooling
```

**Learning Points:**
- ✅ PgBouncer transaction pooling
- ✅ Connection pool optimization
- ✅ Short-lived connection handling
- ✅ Zalando operator PgBouncer integration

#### Cluster 4: Transaction Services (Cart + Order + PgCat + HA)

**Why PgCat + HA?**
- Cart và Order là transaction-heavy
- Cần consistency và reliability
- HA với Patroni cho automatic failover
- PgCat để route traffic giữa 2 services

**Configuration:**
```yaml
# CrunchyData PostgreSQL with HA
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: transaction-db
spec:
  instances:
    - name: instance1
      replicas: 2
      dataVolumeClaimSpec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
  postgresVersion: 15
  patroni:
    dynamicConfiguration:
      postgresql:
        parameters:
          max_connections: 200
          shared_buffers: 256MB
```

```yaml
# PgCat Configuration (Multi-service routing)
databases:
  cart:
    host: transaction-db-primary.postgres-operator.svc.cluster.local
    port: 5432
    database: cart
    pool_size: 30
  order:
    host: transaction-db-primary.postgres-operator.svc.cluster.local
    port: 5432
    database: order
    pool_size: 30
```

**Service Connections (via PgCat - via Environment Variables):**

**Cart Service (`charts/values/cart.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "cart"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars
extraEnv:
  - name: DB_HOST
    value: "pgcat.transaction.svc.cluster.local"  # PgCat pooler endpoint
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "cart"
  - name: DB_USER
    value: "cart"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: transaction-db-secret
        key: cart-password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "30"
  - name: DB_POOLER_TYPE
    value: "pgcat"
```

**Order Service (`charts/values/order.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "order"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars
extraEnv:
  - name: DB_HOST
    value: "pgcat.transaction.svc.cluster.local"  # PgCat pooler endpoint
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "order"
  - name: DB_USER
    value: "order"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: transaction-db-secret
        key: order-password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "30"
  - name: DB_POOLER_TYPE
    value: "pgcat"
```

**Go Code (Same pattern for both services - reuse database.go):**
```go
// Use same database.Connect() function
// Builds DSN from separate env vars: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
```

**Learning Points:**
- ✅ High availability với Patroni
- ✅ Multi-service database sharing
- ✅ Transaction consistency
- ✅ PgCat multi-database routing
- ✅ Automatic failover

#### Cluster 5: Supporting Services (User + Notification + Shared DB)

**Why Shared Database?**
- User và Notification có traffic thấp
- Có thể share resources để tiết kiệm
- Học multi-schema database design
- Simple setup, no pooling needed

**Configuration:**
```yaml
# Zalando PostgreSQL (Shared)
apiVersion: acid.zalan.do/v1
kind: postgresql
metadata:
  name: supporting-db
spec:
  teamId: "platform"
  volume:
    size: 5Gi
  numberOfInstances: 1
  users:
    user: [createdb]
    notification: [createdb]
  databases:
    user: user
    notification: notification
```

**Service Connections (Direct, different schemas - via Environment Variables):**

**User Service (`charts/values/user.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "user"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars
extraEnv:
  - name: DB_HOST
    value: "supporting-db.postgres-operator.svc.cluster.local"  # Shared database
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "user"  # Different schema/database
  - name: DB_USER
    value: "user"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: supporting-db-secret
        key: user-password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "10"  # Low traffic, smaller pool
```

**Notification Service (`charts/values/notification.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "notification"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars
extraEnv:
  - name: DB_HOST
    value: "supporting-db.postgres-operator.svc.cluster.local"  # Shared database
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "notification"  # Different schema/database
  - name: DB_USER
    value: "notification"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: supporting-db-secret
        key: notification-password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "10"  # Low traffic, smaller pool
```

**Go Code (Same pattern for both services - reuse database.go):**
```go
// Use same database.Connect() function
// Builds DSN from separate env vars: DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD
// Same database host, different database names (user vs notification)
```

**Learning Points:**
- ✅ Multi-schema database design
- ✅ Resource sharing
- ✅ Service isolation via schemas
- ✅ When to share vs separate

**Summary Table:**

| Cluster | Services | Operator | Pooler | HA | Learning Focus |
|---------|----------|----------|--------|----|----------------|
| **1** | product | CrunchyData | PgCat | No | High-traffic, read replicas, load balancing |
| **2** | review | Zalando | **None** | No | Direct connection, service isolation |
| **3** | auth | Zalando | **PgBouncer** | No | Transaction pooling, frequent connections |
| **4** | cart, order | CrunchyData | PgCat | **Yes (Patroni)** | HA, transactions, multi-service |
| **5** | user, notification | Zalando | **None** | No | Shared database, multi-schema |

**Total Learning Outcomes:**
- ✅ 5 different database setups
- ✅ 2 operators (Zalando, CrunchyData)
- ✅ 2 poolers (PgBouncer, PgCat) + No pooler
- ✅ HA setup với Patroni
- ✅ Direct connections vs Pooled connections
- ✅ Single instance vs Multi-replica
- ✅ Shared database vs Dedicated database

---

### Scenario 1: Single Cluster, Simple Setup (Learning Basics)

**Goal**: Học PostgreSQL operations cơ bản

**Stack:**
- **PostgreSQL**: Zalando postgres-operator (1 instance)
- **Pooling**: PgBouncer (sidecar với Zalando operator)
- **Monitoring**: postgres_exporter (Prometheus metrics)
- **HA**: None (single instance)

**Architecture:**

```mermaid
flowchart TB
    subgraph "Kubernetes Cluster (Kind)"
        direction TB
        ZA[Zalando Postgres Operator]
        PG[PostgreSQL<br/>1 instance<br/>+ PgBouncer sidecar]
        EXP[postgres_exporter]
        PROM[Prometheus]
        
        ZA --> PG
        PG --> EXP
        EXP --> PROM
    end
```

**Pros:**
- ✅ Simple - dễ học
- ✅ Low resource usage
- ✅ Good for understanding basics
- ✅ Built-in pooling (no extra setup)

**Cons:**
- ⚠️ No HA (single point of failure)
- ⚠️ Limited scalability

**When to Use:**
- Learning PostgreSQL basics
- First-time setup
- Resource-constrained environment

### Scenario 2: Multi-Cluster, Production-Like (Advanced Learning)

**Goal**: Simulate production environment, học advanced operations

**Stack:**
- **PostgreSQL**: CrunchyData postgres-operator (multiple clusters)
- **Pooling**: PgCat (multi-cluster aware)
- **HA**: Patroni (for critical services)
- **Monitoring**: postgres_exporter + pgdog (full observability)

**Architecture:**

```mermaid
flowchart TB
    subgraph "Cluster 1: Core Services"
        CD1[CrunchyData Operator]
        PG1[PostgreSQL<br/>3 replicas<br/>Patroni HA]
        PC1[PgCat Pooler<br/>Routes to all clusters]
        SVC1[Auth, User, Product Services]
        
        CD1 --> PG1
        PG1 --> PC1
        PC1 --> SVC1
    end
    
    subgraph "Cluster 2: Transaction Services"
        CD2[CrunchyData Operator]
        PG2[PostgreSQL<br/>2 replicas<br/>Patroni HA]
        SVC2[Cart, Order Services]
        
        CD2 --> PG2
        PG2 --> SVC2
    end
    
    subgraph "Cluster 3: Supporting Services"
        CD3[CrunchyData Operator]
        PG3[PostgreSQL<br/>1 instance<br/>No HA]
        SVC3[Review, Notification Services]
        
        CD3 --> PG3
        PG3 --> SVC3
    end
    
    subgraph "Monitoring Stack"
        EXP[postgres_exporter<br/>All clusters]
        PGD[pgdog<br/>Advanced analysis]
        PROM[Prometheus]
        
        EXP --> PROM
        PGD --> PROM
    end
    
    PG1 -.->|Metrics| EXP
    PG2 -.->|Metrics| EXP
    PG3 -.->|Metrics| EXP
```

**Pros:**
- ✅ Production-like - real-world scenario
- ✅ Multi-cluster - học distributed systems
- ✅ HA - học high availability
- ✅ Advanced monitoring - full observability

**Cons:**
- ⚠️ Complex - nhiều components
- ⚠️ High resource usage
- ⚠️ Steeper learning curve

**When to Use:**
- Advanced learning
- Simulating production
- Testing multi-cluster scenarios

### Scenario 3: High-Load Testing (k6 Focus)

**Goal**: Optimize cho k6 load testing với 250 VUs

**Stack:**
- **PostgreSQL**: Zalando postgres-operator (optimized config)
- **Pooling**: PgBouncer (transaction mode, high connections)
- **Monitoring**: postgres_exporter (essential metrics)

**Architecture:**

```mermaid
flowchart TB
    subgraph "High-Load PostgreSQL Setup"
        direction TB
        ZA[Zalando Operator]
        PG[PostgreSQL<br/>Optimized for<br/>high connections]
        PB[PgBouncer<br/>Transaction Pooling<br/>max_client_conn: 2000<br/>pool_size: 50]
        
        subgraph "9 Microservices (250 VUs)"
            AUTH[auth: 50 conn]
            USER[user: 50 conn]
            PROD[product: 100 conn<br/>High traffic]
            CART[cart: 30 conn]
            ORDER[order: 30 conn]
            OTHER[... other services]
        end
        
        EXP[postgres_exporter]
        PROM[Prometheus<br/>Connection pool monitoring]
        
        ZA --> PG
        PG --> PB
        PB --> AUTH
        PB --> USER
        PB --> PROD
        PB --> CART
        PB --> ORDER
        PB --> OTHER
        PG -.->|Metrics| EXP
        EXP --> PROM
    end
```

**Optimization Tips:**
- **Connection Pooling**: Transaction mode (most efficient)
- **Pool Size**: 25-50 per service (adjust based on load)
- **Max Connections**: PostgreSQL: 200, PgBouncer: 2000
- **Monitoring**: Track `pg_stat_activity`, connection pool metrics

**Pros:**
- ✅ Optimized for high load
- ✅ Efficient connection usage
- ✅ Good monitoring

**Cons:**
- ⚠️ Single cluster (no HA)
- ⚠️ Focused on performance, not learning HA

**When to Use:**
- k6 load testing optimization
- Performance testing
- Connection pool tuning

---

## Implementation Recommendations

### Phase 1: Start Simple (Scenario 1)

**Steps:**
1. Deploy Zalando postgres-operator
2. Create PostgreSQL instance with PgBouncer sidecar
3. Add postgres_exporter for monitoring
4. Update microservices to use database
5. Test with k6

**Learning Outcomes:**
- PostgreSQL basics in Kubernetes
- Connection pooling concepts
- Basic monitoring

### Phase 2: Add Complexity (Scenario 3)

**Steps:**
1. Optimize PgBouncer for high load
2. Tune PostgreSQL for high connections
3. Monitor connection pool metrics
4. Test with 250 VUs

**Learning Outcomes:**
- Performance optimization
- Connection pool tuning
- High-load scenarios

### Phase 3: Advanced (Scenario 2)

**Steps:**
1. Deploy CrunchyData operator
2. Setup multiple clusters
3. Add PgCat for multi-cluster routing
4. Add Patroni for HA
5. Add pgdog for advanced monitoring

**Learning Outcomes:**
- Multi-cluster management
- High availability
- Advanced monitoring

---

## Helm Values Files Structure

### ⚠️ CRITICAL: All Operators Need Values Files

**Rule**: **ALWAYS create `k8s/{operator-name}/values.yaml` files** để:
- Fix version cho stability
- Centralize configuration
- Easy to adjust settings
- Version control cho config changes

### Directory Structure

```
k8s/
├── postgres-operator-zalando/
│   └── values.yaml          # Zalando operator config
├── postgres-operator-crunchydata/
│   └── values.yaml          # CrunchyData operator config
├── pgbouncer/
│   └── values.yaml          # PgBouncer standalone config
├── pgcat/
│   └── values.yaml          # PgCat config (if Helm chart exists)
└── postgres-exporter/
    └── values.yaml          # postgres_exporter config
```

### Values File Pattern

**Template Structure:**
```yaml
# {Operator Name} Helm Values
# Chart: {chart-repo}/{chart-name}
# Version: {version} (adjust as needed)
# Docs: {documentation-url}

# Image configuration (ALWAYS fix version)
image:
  registry: {registry}
  repository: {repository}
  tag: {version}  # ⚠️ Fix version here
  pullPolicy: IfNotPresent

# Operator-specific configuration
config:
  # ... operator settings

# Resources
resources:
  requests:
    memory: "XXXMi"
    cpu: "XXXm"
  limits:
    memory: "XXXMi"
    cpu: "XXXm"

# Service account
serviceAccount:
  create: true
  name: "{operator-name}"

# RBAC
rbac:
  create: true

# Security context
securityContext:
  # ... security settings
```

### Deployment Script Pattern

**Example (`scripts/XX-deploy-postgres-operators.sh`):**
```bash
#!/bin/bash
set -e

echo "=== Deploying PostgreSQL Operators ==="

NAMESPACE="monitoring"

# 1. Zalando Postgres Operator
echo "1. Deploying Zalando Postgres Operator..."
helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update
helm upgrade --install postgres-operator-zalando postgres-operator/postgres-operator \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f k8s/postgres-operator-zalando/values.yaml \
  --wait --timeout 300s

# 2. CrunchyData Postgres Operator (if needed)
echo "2. Deploying CrunchyData Postgres Operator..."
helm repo add postgres-operator-crunchy https://charts.crunchydata.com
helm repo update
helm upgrade --install postgres-operator-crunchy postgres-operator-crunchy/postgres-operator \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f k8s/postgres-operator-crunchydata/values.yaml \
  --wait --timeout 300s

# 3. PgBouncer (standalone, if needed)
echo "3. Deploying PgBouncer..."
helm repo add pgbouncer https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install pgbouncer pgbouncer/pgbouncer \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f k8s/pgbouncer/values.yaml \
  --wait --timeout 300s

# 4. postgres_exporter
echo "4. Deploying postgres_exporter..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f k8s/postgres-exporter/values.yaml \
  --wait --timeout 300s

echo "✅ PostgreSQL operators deployed successfully!"
```

### Version Management

**Best Practices:**
- ✅ **Fix version in values.yaml** - không dùng `latest`
- ✅ **Document version** - comment trong values file
- ✅ **Test version upgrades** - update version và test
- ✅ **Version control** - commit values.yaml changes

**Example:**
```yaml
# Version: v1.15.0 (adjust as needed)
image:
  tag: v1.15.0  # ⚠️ Fix version here for stability
```

---

## Environment Variables Configuration Pattern

### ⚠️ CRITICAL: Tách riêng các Environment Variables

**Rule**: **KHÔNG dùng DATABASE_URL string**. Tách riêng thành: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`.

**Lý do:**
- ✅ **Dễ config**: Override từng phần (host, port) mà không cần rebuild string
- ✅ **Dễ debug**: Xem từng giá trị riêng trong logs/env
- ✅ **Security tốt hơn**: Password riêng, dễ quản lý Secret
- ✅ **Consistent**: Theo pattern hiện tại (`OTEL_COLLECTOR_ENDPOINT`, `PYROSCOPE_ENDPOINT`)
- ✅ **Dễ validate**: Validate từng field riêng
- ✅ **Flexible**: Có thể thêm SSL config, timeout riêng

### Current Helm Chart Pattern

**From `charts/values.yaml`:**

```yaml
# Core application configuration (chart-managed)
# Use for: SERVICE_NAME, PORT, ENV, OTEL_COLLECTOR_ENDPOINT, etc.
env: []
# Example:
# - name: SERVICE_NAME
#   value: "auth"
# - name: OTEL_COLLECTOR_ENDPOINT
#   value: "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"

# Service-specific configuration (ad-hoc variables)
# Use for: Database connections, feature flags, secrets
extraEnv: []
# Example:
# - name: DB_HOST
    #   value: "host.postgres-operator.svc.cluster.local"
    # - name: DB_PORT
    #   value: "5432"
    # - name: DB_NAME
    #   value: "dbname"
    # - name: DB_USER
    #   value: "user"
    # - name: DB_PASSWORD
    #   valueFrom:
    #     secretKeyRef:
    #       name: db-secret
    #       key: password
# - name: DB_PASSWORD
#   valueFrom:
#     secretKeyRef:
#       name: db-secret
#       key: password
```

### Database Connection Environment Variables

**⚠️ CRITICAL: Tách riêng các env vars, KHÔNG dùng DATABASE_URL string**

**Lý do tách riêng:**
- ✅ Dễ config từng phần (override host mà không cần rebuild string)
- ✅ Dễ debug (xem từng giá trị riêng)
- ✅ Security tốt hơn (password riêng, dễ quản lý Secret)
- ✅ Consistent với pattern hiện tại (OTEL_COLLECTOR_ENDPOINT, PYROSCOPE_ENDPOINT)
- ✅ Dễ validate từng field
- ✅ Flexible (có thể thêm SSL config riêng)

**Standard Variables (All Services):**

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `DB_HOST` | Database host (pooler or direct) | `auth-db-pooler.postgres-operator.svc.cluster.local` | ✅ Yes |
| `DB_PORT` | Database port | `5432` | ✅ Yes |
| `DB_NAME` | Database name | `auth` | ✅ Yes |
| `DB_USER` | Database user | `auth` | ✅ Yes |
| `DB_PASSWORD` | Database password (use Secret) | - | ✅ Yes |
| `DB_SSLMODE` | SSL mode | `disable` (for Kind cluster) | ⚠️ Optional (default: disable) |
| `DB_POOL_MAX_CONNECTIONS` | Max connections in pool | `25` | ⚠️ Optional (default: 25) |
| `DB_POOL_MODE` | Pooling mode (if using pooler) | `transaction` | ⚠️ Optional |

**Pooling Configuration (If using pooler):**

| Variable | Description | Example | Service |
|----------|-------------|---------|---------|
| `DB_POOL_MAX_CONNECTIONS` | Max connections in pool | `25` | auth (PgBouncer) |
| `DB_POOL_MODE` | Pooling mode | `transaction` | auth (PgBouncer) |
| `DB_POOLER_ENABLED` | Enable connection pooling | `true` | auth, product |

### Service-Specific Examples

#### Example 1: Auth Service (PgBouncer)

**Helm Values (`charts/values/auth.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "auth"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars, không dùng DATABASE_URL string
extraEnv:
  - name: DB_HOST
    value: "auth-db-pooler.postgres-operator.svc.cluster.local"  # PgBouncer pooler endpoint
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "auth"
  - name: DB_USER
    value: "auth"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: auth-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"  # Kind cluster doesn't use SSL
  - name: DB_POOL_MAX_CONNECTIONS
    value: "25"  # PgBouncer pool size
  - name: DB_POOL_MODE
    value: "transaction"  # PgBouncer transaction pooling
```

**Go Code (`services/internal/auth/core/database.go`):**
```go
package database

import (
    "database/sql"
    "fmt"
    "os"
    "strconv"
    _ "github.com/lib/pq" // PostgreSQL driver
)

// DatabaseConfig holds database connection configuration
type DatabaseConfig struct {
    Host            string
    Port            string
    Name            string
    User            string
    Password        string
    SSLMode         string
    MaxConnections  int
    PoolMode        string
}

// LoadConfig loads database configuration from environment variables
func LoadConfig() (*DatabaseConfig, error) {
    cfg := &DatabaseConfig{
        Host:           getEnv("DB_HOST", ""),
        Port:           getEnv("DB_PORT", "5432"),
        Name:           getEnv("DB_NAME", ""),
        User:           getEnv("DB_USER", ""),
        Password:       getEnv("DB_PASSWORD", ""),
        SSLMode:        getEnv("DB_SSLMODE", "disable"),
        MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 25),
        PoolMode:       getEnv("DB_POOL_MODE", "transaction"),
    }
    
    // Validate required fields
    if cfg.Host == "" {
        return nil, fmt.Errorf("DB_HOST environment variable is required")
    }
    if cfg.Name == "" {
        return nil, fmt.Errorf("DB_NAME environment variable is required")
    }
    if cfg.User == "" {
        return nil, fmt.Errorf("DB_USER environment variable is required")
    }
    if cfg.Password == "" {
        return nil, fmt.Errorf("DB_PASSWORD environment variable is required")
    }
    
    return cfg, nil
}

// BuildDSN constructs PostgreSQL connection string from config
func (c *DatabaseConfig) BuildDSN() string {
    // Format: postgresql://user:password@host:port/dbname?sslmode=disable
    return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
        c.User,
        c.Password,
        c.Host,
        c.Port,
        c.Name,
        c.SSLMode,
    )
}

// Connect establishes database connection using environment variables
func Connect() (*sql.DB, error) {
    // ⚠️ CRITICAL: Load config from separate env vars, not DATABASE_URL
    cfg, err := LoadConfig()
    if err != nil {
        return nil, fmt.Errorf("failed to load database config: %w", err)
    }
    
    // Build DSN from individual env vars
    dsn := cfg.BuildDSN()
    
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }
    
    // Configure connection pool
    db.SetMaxOpenConns(cfg.MaxConnections)
    db.SetMaxIdleConns(cfg.MaxConnections / 2)
    
    // Test connection
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}

// Helper functions
func getEnv(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
    if val := os.Getenv(key); val != "" {
        if intVal, err := strconv.Atoi(val); err == nil {
            return intVal
        }
    }
    return defaultValue
}
```

### Integration với `services/pkg/config/config.go` Pattern

**Recommended Approach**: Thêm `DatabaseConfig` vào existing config pattern để consistent với codebase.

**Update `services/pkg/config/config.go`:**
```go
// Add DatabaseConfig to Config struct
type Config struct {
    Service   ServiceConfig
    Tracing   TracingConfig
    Profiling ProfilingConfig
    Logging   LoggingConfig
    Metrics   MetricsConfig
    Database  DatabaseConfig  // ✨ NEW: Database configuration
}

// DatabaseConfig defines PostgreSQL database configuration
type DatabaseConfig struct {
    Host           string  // Database host - from DB_HOST env
    Port           string  // Database port - from DB_PORT env (default: "5432")
    Name           string  // Database name - from DB_NAME env
    User           string  // Database user - from DB_USER env
    Password       string  // Database password - from DB_PASSWORD env
    SSLMode        string  // SSL mode - from DB_SSLMODE env (default: "disable")
    MaxConnections int     // Max connections - from DB_POOL_MAX_CONNECTIONS env (default: 25)
    PoolMode       string  // Pool mode - from DB_POOL_MODE env (optional)
    PoolerType     string  // Pooler type - from DB_POOLER_TYPE env (optional)
}

// BuildDSN constructs PostgreSQL connection string from config
func (c *DatabaseConfig) BuildDSN() string {
    return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
        c.User, c.Password, c.Host, c.Port, c.Name, c.SSLMode)
}

// Update Load() function:
func Load() *Config {
    _ = godotenv.Load()
    
    return &Config{
        Service: ServiceConfig{
            Name:    getEnv("SERVICE_NAME", "unknown"),
            Port:    getEnv("PORT", "8080"),
            Version: getEnv("VERSION", "dev"),
            Env:     getEnv("ENV", "development"),
        },
        Tracing: TracingConfig{
            Enabled:            getEnvBool("TRACING_ENABLED", true),
            Endpoint:           getEnv("OTEL_COLLECTOR_ENDPOINT", "otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4318"),
            SampleRate:         getEnvFloat("OTEL_SAMPLE_RATE", 0.1),
            ServiceName:        getEnv("SERVICE_NAME", "unknown"),
            MaxExportBatchSize: getEnvInt("OTEL_BATCH_SIZE", 512),
        },
        Profiling: ProfilingConfig{
            Enabled:     getEnvBool("PROFILING_ENABLED", true),
            Endpoint:    getEnv("PYROSCOPE_ENDPOINT", "http://pyroscope.monitoring.svc.cluster.local:4040"),
            ServiceName: getEnv("SERVICE_NAME", "unknown"),
        },
        Logging: LoggingConfig{
            Level:  getEnv("LOG_LEVEL", "info"),
            Format: getEnv("LOG_FORMAT", "json"),
        },
        Metrics: MetricsConfig{
            Enabled: getEnvBool("METRICS_ENABLED", true),
            Path:    getEnv("METRICS_PATH", "/metrics"),
        },
        // ✨ NEW: Database configuration
        Database: DatabaseConfig{
            Host:           getEnv("DB_HOST", ""),
            Port:           getEnv("DB_PORT", "5432"),
            Name:           getEnv("DB_NAME", ""),
            User:           getEnv("DB_USER", ""),
            Password:       getEnv("DB_PASSWORD", ""),
            SSLMode:        getEnv("DB_SSLMODE", "disable"),
            MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 25),
            PoolMode:       getEnv("DB_POOL_MODE", ""),
            PoolerType:     getEnv("DB_POOLER_TYPE", ""),
        },
    }
}

// Update Validate() function:
func (c *Config) Validate() error {
    var errors []string
    
    // ... existing validations ...
    
    // ✨ NEW: Database validation
    if c.Database.Host == "" {
        errors = append(errors, "DB_HOST is required for database connection")
    }
    if c.Database.Name == "" {
        errors = append(errors, "DB_NAME is required for database connection")
    }
    if c.Database.User == "" {
        errors = append(errors, "DB_USER is required for database connection")
    }
    if c.Database.Password == "" {
        errors = append(errors, "DB_PASSWORD is required for database connection")
    }
    // Validate port is a valid number
    if c.Database.Port != "" {
        if _, err := strconv.Atoi(c.Database.Port); err != nil {
            errors = append(errors, fmt.Sprintf("DB_PORT must be a valid number, got: %s", c.Database.Port))
        }
    }
    
    if len(errors) > 0 {
        return fmt.Errorf("configuration validation failed:\n  - %s", strings.Join(errors, "\n  - "))
    }
    
    return nil
}
```

**Usage trong service code:**
```go
package main

import (
    "database/sql"
    "github.com/duynhne/monitoring/pkg/config"
    _ "github.com/lib/pq"
)

func main() {
    cfg := config.Load()
    if err := cfg.Validate(); err != nil {
        log.Fatal(err)
    }
    
    // Connect to database using config
    db, err := connectDatabase(cfg.Database)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()
    
    // ... rest of service code
}

func connectDatabase(cfg config.DatabaseConfig) (*sql.DB, error) {
    dsn := cfg.BuildDSN()
    
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, fmt.Errorf("failed to open database: %w", err)
    }
    
    db.SetMaxOpenConns(cfg.MaxConnections)
    db.SetMaxIdleConns(cfg.MaxConnections / 2)
    
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("failed to ping database: %w", err)
    }
    
    return db, nil
}
```

**Benefits:**
- ✅ Consistent với existing config pattern
- ✅ Centralized configuration management
- ✅ Type-safe configuration
- ✅ Built-in validation
- ✅ Easy to test (mock config)
- ✅ Clear documentation

---

**Alternative: Standalone database package (if not using config.go):**

```go
// Add to services/pkg/config/config.go

// DatabaseConfig defines PostgreSQL database configuration
type DatabaseConfig struct {
    Host           string  // Database host - from DB_HOST env
    Port           string  // Database port - from DB_PORT env (default: "5432")
    Name           string  // Database name - from DB_NAME env
    User           string  // Database user - from DB_USER env
    Password       string  // Database password - from DB_PASSWORD env
    SSLMode        string  // SSL mode - from DB_SSLMODE env (default: "disable")
    MaxConnections int     // Max connections - from DB_POOL_MAX_CONNECTIONS env (default: 25)
    PoolMode       string  // Pool mode - from DB_POOL_MODE env
}

// BuildDSN constructs PostgreSQL connection string
func (c *DatabaseConfig) BuildDSN() string {
    return fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
        c.User, c.Password, c.Host, c.Port, c.Name, c.SSLMode)
}

// Update Load() function:
func Load() *Config {
    _ = godotenv.Load()
    
    return &Config{
        // ... existing configs ...
        Database: DatabaseConfig{
            Host:           getEnv("DB_HOST", ""),
            Port:           getEnv("DB_PORT", "5432"),
            Name:           getEnv("DB_NAME", ""),
            User:           getEnv("DB_USER", ""),
            Password:       getEnv("DB_PASSWORD", ""),
            SSLMode:        getEnv("DB_SSLMODE", "disable"),
            MaxConnections: getEnvInt("DB_POOL_MAX_CONNECTIONS", 25),
            PoolMode:       getEnv("DB_POOL_MODE", ""),
        },
    }
}
```

#### Example 2: Review Service (Direct Connection, No Pooler)

**Helm Values (`charts/values/review.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "review"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars
extraEnv:
  - name: DB_HOST
    value: "review-db.postgres-operator.svc.cluster.local"  # Direct connection, no pooler
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "review"
  - name: DB_USER
    value: "review"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: review-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "10"  # Direct connection, smaller pool
```

**Go Code (Same pattern, reuse database.go):**
```go
// Use same database.Connect() function from services/internal/review/core/database.go
// DB_POOL_MAX_CONNECTIONS=10 will be used automatically
```

#### Example 3: Product Service (PgCat, Multiple Replicas)

**Helm Values (`charts/values/product.yaml`):**
```yaml
# Core configuration (chart-managed via env)
env:
  - name: SERVICE_NAME
    value: "product"
  - name: PORT
    value: "8080"
  # ... other core env vars

# Service-specific database configuration (via extraEnv)
# ⚠️ IMPORTANT: Tách riêng các env vars
extraEnv:
  - name: DB_HOST
    value: "pgcat.product.svc.cluster.local"  # PgCat pooler endpoint
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "product"
  - name: DB_USER
    value: "product"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: product-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "50"  # Higher for high traffic
  - name: DB_POOLER_TYPE
    value: "pgcat"  # Indicates PgCat pooler (for logging/monitoring)
```

### Best Practices

**✅ DO:**
- **Tách riêng các env vars**: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- Store passwords in Kubernetes Secrets
- Use `valueFrom.secretKeyRef` for sensitive data
- Configure connection pool size via env vars
- Build DSN string từ các env vars riêng trong code
- Validate từng field riêng

**❌ DON'T:**
- **KHÔNG dùng `DATABASE_URL` string** - khó config, khó debug
- Hardcode connection strings in code
- Commit passwords to git
- Use `value:` for passwords (use Secrets)
- Assume connection string format
- Mix pooler and direct connections without env var distinction

### Connection String Patterns (Built from Env Vars)

**Pattern trong Code:**
```go
// Build DSN from separate env vars
dsn := fmt.Sprintf("postgresql://%s:%s@%s:%s/%s?sslmode=%s",
    os.Getenv("DB_USER"),
    os.Getenv("DB_PASSWORD"),
    os.Getenv("DB_HOST"),
    os.Getenv("DB_PORT"),
    os.Getenv("DB_NAME"),
    os.Getenv("DB_SSLMODE"),
)
```

**Direct Connection (No Pooler):**
- `DB_HOST`: `review-db.postgres-operator.svc.cluster.local`
- `DB_PORT`: `5432`
- `DB_NAME`: `review`
- `DB_USER`: `review`
- `DB_PASSWORD`: (from Secret)
- `DB_SSLMODE`: `disable`

**Via PgBouncer:**
- `DB_HOST`: `auth-db-pooler.postgres-operator.svc.cluster.local` (pooler service)
- `DB_PORT`: `5432`
- `DB_NAME`: `auth`
- `DB_USER`: `auth`
- `DB_PASSWORD`: (from Secret)
- `DB_SSLMODE`: `disable`
- `DB_POOL_MODE`: `transaction`

**Via PgCat:**
- `DB_HOST`: `pgcat.product.svc.cluster.local` (PgCat service)
- `DB_PORT`: `5432`
- `DB_NAME`: `product`
- `DB_USER`: `product`
- `DB_PASSWORD`: (from Secret)
- `DB_SSLMODE`: `disable`
- `DB_POOLER_TYPE`: `pgcat`

---

## Database Schema Design Considerations

### Service-to-Database Mapping

**Option 1: Single Database, Multiple Schemas**
```
postgresql://postgres:pass@pgbouncer:5432/microservices
├── schema: auth
├── schema: user
├── schema: product
├── schema: cart
├── schema: order
├── schema: review
├── schema: notification
└── schema: shipping
```

**Pros:**
- ✅ Simple - one database
- ✅ Easy connection string
- ✅ Good for learning

**Cons:**
- ⚠️ No isolation between services
- ⚠️ Single point of failure

**Use Case**: Scenario 1 (Learning)

**Option 2: Multiple Databases, One Cluster**
```
postgresql://postgres:pass@pgbouncer:5432/auth
postgresql://postgres:pass@pgbouncer:5432/user
postgresql://postgres:pass@pgbouncer:5432/product
...
```

**Pros:**
- ✅ Service isolation
- ✅ Better for multi-cluster later
- ✅ More realistic

**Cons:**
- ⚠️ More complex connection management

**Use Case**: Scenario 2 & 3 (Production-like, High-Load)

**Option 3: Multiple Clusters (Advanced)**
```
Cluster 1: auth, user, product
Cluster 2: cart, order
Cluster 3: review, notification, shipping
```

**Pros:**
- ✅ True multi-cluster
- ✅ Best isolation
- ✅ Production-like

**Cons:**
- ⚠️ Most complex
- ⚠️ High resource usage

**Use Case**: Scenario 2 (Advanced Learning)

---

## Monitoring Integration for Service-Specific Scenarios

### Monitoring Strategy per Cluster

**Cluster 1 (Product - High Traffic):**
- **postgres_exporter**: Essential metrics (connections, queries, replication lag)
- **PgCat metrics**: Connection pool utilization, routing stats
- **Custom queries**: Slow query detection, catalog access patterns
- **Grafana panels**: High-traffic database dashboard

**Cluster 2 (Review - Isolated):**
- **postgres_exporter**: Basic metrics (simpler setup)
- **Custom queries**: Review read/write patterns
- **Grafana panels**: Simple single-instance dashboard

**Cluster 3 (Auth - PgBouncer):**
- **postgres_exporter**: Database metrics
- **PgBouncer metrics**: Connection pool stats (via postgres_exporter custom queries)
- **Custom queries**: Login/register query performance
- **Grafana panels**: PgBouncer pool monitoring

**Cluster 4 (Cart + Order - HA):**
- **postgres_exporter**: All replicas
- **Patroni metrics**: HA status, leader election
- **PgCat metrics**: Multi-service routing
- **Custom queries**: Transaction performance, consistency checks
- **Grafana panels**: HA cluster dashboard

**Cluster 5 (User + Notification - Shared):**
- **postgres_exporter**: Shared database metrics
- **Custom queries**: Per-schema statistics
- **Grafana panels**: Multi-schema dashboard

### Unified Monitoring Dashboard

**Grafana Dashboard Structure:**
```
PostgreSQL Multi-Cluster Monitoring
├── Overview Row
│   ├── Total Clusters (5)
│   ├── Total Databases (7)
│   ├── Total Connections
│   └── Health Status
├── Cluster 1: Product (High Traffic)
│   ├── Connection Pool (PgCat)
│   ├── Query Performance
│   ├── Replica Lag
│   └── Load Balancing Stats
├── Cluster 2: Review (Isolated)
│   ├── Direct Connections
│   ├── Query Performance
│   └── Database Size
├── Cluster 3: Auth (PgBouncer)
│   ├── PgBouncer Pool Stats
│   ├── Transaction Pooling Metrics
│   ├── Connection Wait Time
│   └── Query Performance
├── Cluster 4: Cart + Order (HA)
│   ├── Patroni HA Status
│   ├── Primary/Replica Health
│   ├── Transaction Rate
│   └── Consistency Metrics
└── Cluster 5: User + Notification (Shared)
    ├── Per-Schema Stats
    ├── Shared Resource Usage
    └── Schema Isolation Metrics
```

---

## Monitoring Integration

### Essential Metrics (All Scenarios)

**From postgres_exporter:**
- `pg_stat_database_*` - Database stats
- `pg_stat_user_tables_*` - Table performance
- `pg_stat_activity_*` - Active connections
- `pg_stat_statements_*` - Query performance

**Custom Metrics Needed:**
- Connection pool utilization (PgBouncer)
- Query latency per service
- Transaction rate per service
- Database size growth

### Grafana Dashboard

**Panels Needed:**
1. **Connection Pool**:
   - Active connections
   - Pool utilization
   - Connection wait time

2. **Query Performance**:
   - Query latency (P50, P95, P99)
   - Slow queries
   - Query rate per service

3. **Database Health**:
   - Database size
   - Table sizes
   - Index usage

4. **Replication** (if HA):
   - Replication lag
   - Replica status

---

## Next Steps for Specification

### Questions to Answer:

1. **Which scenario to start with?**
   - **Recommendation**: Start with **Scenario 0 (Service-Specific)** - học nhiều trường hợp khác nhau
   - **Alternative**: Start with Scenario 1 (Simple) nếu muốn học từng bước
   - **Progressive**: Scenario 1 → Scenario 0 → Scenario 3 (High-Load)

2. **Database schema design?**
   - Need to design tables for 9 services
   - Consider relationships between services
   - Indexes for performance

3. **Migration strategy?**
   - How to setup initial schema?
   - Version control for migrations?
   - Rollback strategy?

4. **Service integration?**
   - Which Go database library? (gorm, sqlx, pgx)
   - Connection string configuration
   - Error handling

5. **k6 test updates?**
   - How to verify data persistence?
   - How to test transactions?
   - How to test data consistency?

---

## References

### PostgreSQL Operators
- [Zalando Postgres Operator](https://github.com/zalando/postgres-operator)
- [CrunchyData Postgres Operator](https://github.com/CrunchyData/postgres-operator)

### Connection Poolers
- [PgBouncer](https://www.pgbouncer.org/)
- [PgCat](https://github.com/postgresml/pgcat)

### High Availability
- [Patroni](https://github.com/zalando/patroni)

### Monitoring
- [postgres_exporter](https://github.com/prometheus-community/postgres_exporter)
- [pgdog](https://github.com/pgdogdev/pgdog)

### Go Database Libraries
- [GORM](https://gorm.io/) - ORM
- [sqlx](https://github.com/jmoiron/sqlx) - SQL extensions
- [pgx](https://github.com/jackc/pgx) - PostgreSQL driver

---

**Research Status**: ✅ Complete  
**Next Phase**: `/specify` - Create detailed specification for database integration
