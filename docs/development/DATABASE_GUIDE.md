# Database Integration Guide

## Quick Summary

**What is Database Integration?**
PostgreSQL database integration enables microservices to persist data, execute real database queries, and support realistic k6 load testing with data consistency. This implementation uses multiple PostgreSQL operators, connection poolers, and HA patterns as a comprehensive learning platform.

**Key Capabilities:**
- ✅ 5 PostgreSQL clusters with different configurations (operators, poolers, HA patterns)
- ✅ Multiple connection patterns (direct, PgBouncer sidecar, PgCat standalone)
- ✅ High availability with Patroni (all operators use Patroni internally)
- ✅ Connection pooling for performance optimization
- ✅ Separate environment variables (DB_HOST, DB_PORT, etc.) for flexible configuration
- ✅ Full monitoring integration (postgres_exporter, Prometheus, Grafana)

**Technologies:**
- **Zalando Postgres Operator**: PostgreSQL management powered by Patroni for 3 clusters (Review, Auth, Supporting)
- **CloudNativePG Operator**: Kubernetes-native PostgreSQL with Patroni for 2 clusters (Product, Cart+Order)
- **PgBouncer**: Transaction pooling for Auth service (Zalando built-in sidecar)
- **PgCat**: Modern connection pooler for Product and Cart+Order (standalone)
- **Patroni**: High availability manager (used by both Zalando and CloudNativePG operators via Kubernetes API)
- **Flyway**: Database migrations (8 migration images)

**Note on Patroni:**
- Both Zalando and CloudNativePG operators use **Patroni internally** for HA and leader election
- Patroni uses **Kubernetes API** as the Distributed Configuration Store (DCS) by default
- No separate etcd cluster needed - Kubernetes API serves as the coordination layer

---

## Table of Contents

1. [Database Architecture](#database-architecture) - 5 clusters overview
2. [Connection Patterns](#connection-patterns) - Direct, PgBouncer, PgCat
3. [Environment Variables](#environment-variables) - DB_* configuration
4. [Helm Chart Configuration](#helm-chart-configuration) - Kubernetes deployment
5. [Local Development](#local-development) - .env setup and testing
6. [Troubleshooting](#troubleshooting) - Common issues and solutions
7. [Monitoring](#monitoring) - postgres_exporter and Grafana integration

---

## Database Architecture

### Overview

The system uses **5 PostgreSQL clusters** distributed across different operators and connection patterns to demonstrate various database management approaches:

```mermaid
flowchart TD
    subgraph Services[Microservices]
        Auth[Auth Service]
        Product[Product Service]
        Cart[Cart Service]
        Order[Order Service]
        Review[Review Service]
        User[User Service]
        Notification[Notification Service]
        Shipping[Shipping-v2 Service]
    end
    
    subgraph Poolers[Connection Poolers]
        PgBouncer[PgBouncer<br/>Auth - Sidecar]
        PgCatProduct[PgCat<br/>Product - Standalone]
        PgCatTransaction[PgCat<br/>Cart+Order - Standalone]
    end
    
    subgraph Databases[PostgreSQL Clusters]
        AuthDB[(Auth DB<br/>Zalando<br/>Single Instance)]
        ProductDB[(Product DB<br/>CloudNativePG<br/>Read Replicas)]
        TransactionDB[(Transaction DB<br/>CloudNativePG<br/>Patroni HA)]
        ReviewDB[(Review DB<br/>Zalando<br/>Single Instance)]
        SupportingDB[(Supporting DB<br/>Zalando<br/>Shared Database)]
    end
    
    Auth -->|via| PgBouncer
    PgBouncer --> AuthDB
    Product -->|via| PgCatProduct
    PgCatProduct --> ProductDB
    Cart -->|via| PgCatTransaction
    Order -->|via| PgCatTransaction
    PgCatTransaction --> TransactionDB
    Review -->|direct| ReviewDB
    User -->|direct| SupportingDB
    Notification -->|direct| SupportingDB
    Shipping -->|direct| SupportingDB
```

### Operator Distribution

| Cluster | Services | Operator | Pooler | HA Pattern | Learning Focus |
|---------|----------|----------|--------|------------|----------------|
| **Product** | Product | **CloudNativePG** | **PgCat** (standalone) | **Patroni HA** (2 instances) | Read scaling, PgCat routing, Patroni failover |
| **Review** | Review | **Zalando** | **None** (direct) | **Patroni** (single instance) | Simple setup, direct connection, Patroni basics |
| **Auth** | Auth | **Zalando** | **PgBouncer** (sidecar) | **Patroni** (single instance) | Transaction pooling, Zalando built-in pooler, Patroni basics |
| **Cart+Order** | Cart, Order | **CloudNativePG** | **PgCat** (standalone) | **Patroni HA** (2 instances) | **Multi-database routing, Patroni failover** |
| **Supporting** | User, Notification, Shipping-v2 | **Zalando** | **None** (direct) | **Patroni** (single instance) | **Shared database pattern, Patroni basics** |

### Cluster Details

#### 1. Product Database (CloudNativePG + PgCat)

- **Operator**: CloudNativePG (v1.28.0) - uses Patroni internally
- **Instances**: 2 (1 primary + 1 replica)
- **HA**: Patroni via Kubernetes API (automatic failover)
- **Pooler**: PgCat standalone v1.2.0 (`ghcr.io/postgresml/pgcat:v1.2.0`)
- **Namespace**: `product`
- **CRD**: `k8s/postgres-operator-cloudnativepg/crds/product-db.yaml`
- **Pooler Config**: `k8s/pgcat/product/configmap.yaml`
- **Pooler Deployment**: `k8s/pgcat/product/deployment.yaml`

**Features:**
- Patroni HA with automatic failover (< 30 seconds)
- Read replica load balancing via PgCat (primary configured, replicas can be added)
- Async replication (no sync constraints)
- Pool size: 50 connections
- CloudNativePG services: `product-db-rw` (read-write), `product-db-r` (read-only)

#### 2. Review Database (Zalando + Direct)

- **Operator**: Zalando Postgres Operator (v1.15.0) - powered by Patroni
- **Instances**: 1 (single instance, no HA)
- **HA**: Patroni via Kubernetes API (single instance, no failover needed)
- **Pooler**: None (direct connection)
- **Namespace**: `review`
- **CRD**: `k8s/postgres-operator-zalando/crds/review-db.yaml`

**Features:**
- Patroni-based management (even for single instance)
- Simple setup for low-traffic service
- Direct PostgreSQL connection (no pooler overhead)
- PostgreSQL 15

#### 3. Auth Database (Zalando + PgBouncer)

- **Operator**: Zalando Postgres Operator (v1.15.0) - powered by Patroni
- **Instances**: 1 (single instance, no HA)
- **HA**: Patroni via Kubernetes API (single instance, no failover needed)
- **Pooler**: PgBouncer sidecar (2 instances, transaction mode)
- **Namespace**: `auth`
- **CRD**: `k8s/postgres-operator-zalando/crds/auth-db.yaml`

**Features:**
- Patroni-based management (even for single instance)
- Built-in PgBouncer sidecar (Zalando operator feature)
- Transaction pooling for short-lived connections
- Pool size: 25 connections
- Service endpoint: `auth-db-pooler.postgres-operator.svc.cluster.local`

#### 4. Transaction Database (CloudNativePG + PgCat + Patroni)

- **Operator**: CloudNativePG (v1.28.0) - uses Patroni internally
- **Instances**: 2 (1 primary + 1 replica)
- **HA**: Patroni via Kubernetes API (automatic failover)
- **Pooler**: PgCat standalone v1.2.0 (`ghcr.io/postgresml/pgcat:v1.2.0`)
- **Namespace**: `cart`
- **CRD**: `k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml`
- **Pooler Config**: `k8s/pgcat/transaction/configmap.yaml`
- **Pooler Deployment**: `k8s/pgcat/transaction/deployment.yaml`

**Features:**
- Patroni HA with automatic failover (< 30 seconds)
- Multi-database routing (cart + order databases on same cluster)
- Leader election via Kubernetes API (no separate etcd needed)
- Pool size: 30 connections per database
- CloudNativePG service: `transaction-db-rw.cart.svc.cluster.local` (read-write)

**Note on Patroni:**
- CloudNativePG uses Patroni internally for HA management
- Patroni uses Kubernetes API as Distributed Configuration Store (DCS)
- No separate etcd cluster required - Kubernetes serves as coordination layer
- For learning purposes, CRD includes commented examples of etcd integration (not implemented)

#### 5. Supporting Database (Zalando + Direct + Shared)

- **Operator**: Zalando Postgres Operator (v1.15.0) - powered by Patroni
- **Instances**: 1 (single instance, no HA)
- **HA**: Patroni via Kubernetes API (single instance, no failover needed)
- **Pooler**: None (direct connection)
- **Namespace**: `user`
- **CRD**: `k8s/postgres-operator-zalando/crds/supporting-db.yaml`

**Features:**
- Patroni-based management (even for single instance)
- Shared database pattern (3 databases: user, notification, shipping)
- Direct connection for low-traffic services
- PostgreSQL 15

---

## Connection Patterns

### Connection Flow

```mermaid
sequenceDiagram
    participant Service as Microservice
    participant Pooler as Connection Pooler<br/>(Optional)
    participant DB as PostgreSQL Cluster
    
    Note over Service,DB: Pattern 1: Via Pooler<br/>(Auth, Product, Cart+Order)
    Service->>Pooler: Connect (DB_HOST=pooler-endpoint)
    Pooler->>DB: Route query
    DB-->>Pooler: Result
    Pooler-->>Service: Return data
    
    Note over Service,DB: Pattern 2: Direct Connection<br/>(Review, Supporting)
    Service->>DB: Connect directly (DB_HOST=db-endpoint)
    DB-->>Service: Return data
```

### Pattern 1: Direct Connection (Review, Supporting)

**When to use**: Low-traffic services, simple setup, no connection pooling needed.

**Configuration**:
```yaml
# Helm values (charts/values/review.yaml)
env:
  - name: DB_HOST
    value: "review-db.postgres-operator.svc.cluster.local"
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
```

**Go Code** (`services/internal/review/core/database.go`):
```go
// Direct connection - no pooler
cfg := &DatabaseConfig{
    Host:     getEnv("DB_HOST", ""),  // review-db.postgres-operator.svc.cluster.local
    Port:     getEnv("DB_PORT", "5432"),
    Name:     getEnv("DB_NAME", ""),  // review
    User:     getEnv("DB_USER", ""),  // review
    Password: getEnv("DB_PASSWORD", ""),
}
```

### Pattern 2: PgBouncer Sidecar (Auth)

**When to use**: High connection churn, transaction pooling needed, Zalando operator built-in.

**Configuration**:
```yaml
# Helm values (charts/values/auth.yaml)
env:
  - name: DB_HOST
    value: "auth-db-pooler.postgres-operator.svc.cluster.local"  # PgBouncer endpoint
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
  - name: DB_POOL_MODE
    value: "transaction"  # PgBouncer transaction pooling
```

**CRD Configuration** (`k8s/postgres-operator-zalando/crds/auth-db.yaml`):
```yaml
connectionPooler:
  numberOfInstances: 2
  schema: pooler
  user: pooler
  mode: transaction  # Transaction pooling
```

**Go Code**: Same as direct connection (service doesn't know about pooler).

### Pattern 3: PgCat Standalone (Product, Cart+Order)

**When to use**: Read replica routing, multi-database routing, advanced load balancing.

**Configuration**:
```yaml
# Helm values (charts/values/product.yaml)
env:
  - name: DB_HOST
    value: "pgcat-product.product.svc.cluster.local"  # PgCat service
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
```

**PgCat Configuration** (`k8s/pgcat/product/configmap.yaml`):
```toml
# PgCat Configuration for Product Database
[general]
host = "0.0.0.0"
port = 5432
pool_mode = "transaction"
log_level = "info"
admin_username = "admin"
admin_password = "admin"

[admin]
host = "0.0.0.0"
port = 9930

# Product database pool
[pools.product]
pool_size = 50

[pools.product.users]
product = { username = "product", password = "postgres", pool_size = 50 }

# Primary shard (numbered starting at 0)
[pools.product.shards.0]
database = "product"

[[pools.product.shards.0.servers]]
host = "product-db-rw.product.svc.cluster.local"
port = 5432
user = "product"
password = "postgres"
role = "primary"
```

**Notes**:
- **Image**: `ghcr.io/postgresml/pgcat:v1.2.0` (fixed version, not `latest`)
- **CloudNativePG Services**: CloudNativePG automatically creates services:
  - `{cluster-name}-rw` (read-write endpoint) → `product-db-rw.product.svc.cluster.local`
  - `{cluster-name}-r` (read-only endpoint) → `product-db-r.product.svc.cluster.local` (for future replica routing)
- **Deployment**: `k8s/pgcat/product/deployment.yaml` with 2 replicas
- Currently configured with primary server only; replicas can be added later for read balancing

**Transaction Database PgCat Configuration** (`k8s/pgcat/transaction/configmap.yaml`):
```toml
# PgCat Configuration for Transaction Databases (Cart + Order)
[general]
host = "0.0.0.0"
port = 5432
pool_mode = "transaction"
log_level = "info"
admin_username = "admin"
admin_password = "admin"

[admin]
host = "0.0.0.0"
port = 9930

# Cart database pool
[pools.cart]
pool_size = 30

[pools.cart.users]
cart = { username = "cart", password = "postgres", pool_size = 30 }

[pools.cart.shards.0]
database = "cart"

[[pools.cart.shards.0.servers]]
host = "transaction-db-rw.cart.svc.cluster.local"
port = 5432
user = "cart"
password = "postgres"
role = "primary"

# Order database pool (same server, different database)
[pools.order]
pool_size = 30

[pools.order.users]
cart = { username = "cart", password = "postgres", pool_size = 30 }

[pools.order.shards.0]
database = "order"

[[pools.order.shards.0.servers]]
host = "transaction-db-rw.cart.svc.cluster.local"
port = 5432
user = "cart"
password = "postgres"
role = "primary"
```

**Go Code**: Same as direct connection (PgCat transparent).

---

## Environment Variables

### Database Configuration Variables

All database connections use **separate environment variables** (NOT a single `DATABASE_URL` string) for flexibility and debugging.

| Variable | Type | Default | Description | Required |
|----------|------|---------|-------------|----------|
| `DB_HOST` | string | - | Database host (pooler or direct endpoint) | ✅ Yes |
| `DB_PORT` | string | `"5432"` | Database port | ❌ No |
| `DB_NAME` | string | - | Database name | ✅ Yes |
| `DB_USER` | string | - | Database user | ✅ Yes |
| `DB_PASSWORD` | string | - | Database password (from Secret) | ✅ Yes |
| `DB_SSLMODE` | string | `"disable"` | SSL mode (disable for Kind cluster) | ❌ No |
| `DB_POOL_MAX_CONNECTIONS` | int | `25` | Max connections in pool | ❌ No |
| `DB_POOL_MODE` | string | `"transaction"` | Pool mode (for PgBouncer) | ❌ No |

### Per-Service Configuration Examples

#### Auth Service (PgBouncer)
```bash
DB_HOST=auth-db-pooler.postgres-operator.svc.cluster.local
DB_PORT=5432
DB_NAME=auth
DB_USER=auth
DB_PASSWORD=<from-secret>
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
DB_POOL_MODE=transaction
```

#### Product Service (PgCat)
```bash
DB_HOST=pgcat-product.product.svc.cluster.local
DB_PORT=5432
DB_NAME=product
DB_USER=product
DB_PASSWORD=<from-secret>
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=50
```

#### Review Service (Direct)
```bash
DB_HOST=review-db.postgres-operator.svc.cluster.local
DB_PORT=5432
DB_NAME=review
DB_USER=review
DB_PASSWORD=<from-secret>
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
```

### Configuration Validation

Database configuration is validated on service startup. Missing required variables cause the service to fail with a clear error:

```go
// services/internal/{service}/core/database.go
func LoadConfig() (*DatabaseConfig, error) {
    cfg := &DatabaseConfig{
        Host:     getEnv("DB_HOST", ""),
        Port:     getEnv("DB_PORT", "5432"),
        Name:     getEnv("DB_NAME", ""),
        User:     getEnv("DB_USER", ""),
        Password: getEnv("DB_PASSWORD", ""),
        SSLMode:  getEnv("DB_SSLMODE", "disable"),
    }

    // Validate required fields
    if cfg.Host == "" {
        return nil, fmt.Errorf("DB_HOST environment variable is required")
    }
    if cfg.Name == "" {
        return nil, fmt.Errorf("DB_NAME environment variable is required")
    }
    // ... more validation
}
```

---

## Helm Chart Configuration

### Database Environment Variables in Helm

Database configuration is included in the `env` section along with other environment variables.

**Pattern**:
```yaml
# charts/values/{service}.yaml
env:
  - name: DB_HOST
    value: "<pooler-or-direct-endpoint>"
  - name: DB_PORT
    value: "5432"
  - name: DB_NAME
    value: "<database-name>"
  - name: DB_USER
    value: "<database-user>"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: <service>-db-secret
        key: password
  - name: DB_SSLMODE
    value: "disable"
  - name: DB_POOL_MAX_CONNECTIONS
    value: "<pool-size>"
```

### Secret References

**Never hardcode passwords**. Always use `valueFrom.secretKeyRef`:

```yaml
# ✅ CORRECT: Use Secret reference
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: auth-db-secret
      key: password

# ❌ WRONG: Hardcoded password
- name: DB_PASSWORD
  value: "postgres"  # NEVER DO THIS
```

### Service-Specific Examples

#### Auth Service (PgBouncer)
```yaml
# charts/values/auth.yaml
env:
  - name: DB_HOST
    value: "auth-db-pooler.postgres-operator.svc.cluster.local"
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
    value: "25"
  - name: DB_POOL_MODE
    value: "transaction"
```

#### Product Service (PgCat)
```yaml
# charts/values/product.yaml
env:
  - name: DB_HOST
    value: "pgcat-product.product.svc.cluster.local"
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
    value: "50"
```

#### Review Service (Direct)
```yaml
# charts/values/review.yaml
env:
  - name: DB_HOST
    value: "review-db.postgres-operator.svc.cluster.local"
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
    value: "25"
```

---

## Local Development

### .env File Setup

Create a `.env` file in `services/` directory for local development:

```bash
# services/.env
SERVICE_NAME=auth
PORT=8080
ENV=development
LOG_LEVEL=debug
LOG_FORMAT=console

# Database configuration (local PostgreSQL or port-forward)
DB_HOST=localhost
DB_PORT=5432
DB_NAME=auth
DB_USER=auth
DB_PASSWORD=postgres
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25
DB_POOL_MODE=transaction
```

### Port-Forwarding Database

To connect to a database in Kubernetes from local machine:

```bash
# Port-forward Auth database (via PgBouncer)
kubectl port-forward -n auth svc/auth-db-pooler 5432:5432

# Port-forward Product database (via PgCat)
kubectl port-forward -n product svc/pgcat-product 5432:5432

# Port-forward Transaction database (via PgCat for Cart+Order)
kubectl port-forward -n cart svc/pgcat 5432:5432

# Port-forward Review database (direct)
kubectl port-forward -n review svc/review-db 5432:5432
```

### Testing Connection

Test database connection from Go code:

```bash
cd services
go run cmd/auth/main.go
```

Expected output:
```
INFO    Database connection successful    {"host": "localhost:5432", "database": "auth"}
```

### Connection Testing Script

Test database connection manually:

```bash
# Using psql (if installed)
psql -h localhost -p 5432 -U auth -d auth

# Using kubectl exec (from within cluster)
kubectl exec -it -n auth deployment/auth -- psql -h auth-db-pooler.postgres-operator.svc.cluster.local -U auth -d auth
```

---

## Troubleshooting

### Connection Failures

#### Error: "Failed to connect to database"

**Symptoms**:
```
ERROR   Failed to connect to database    {"error": "dial tcp: lookup auth-db-pooler.postgres-operator.svc.cluster.local: no such host"}
```

**Diagnosis**:
```bash
# Check if database pod is running
kubectl get pods -n auth -l app=postgres

# Check database service
kubectl get svc -n auth auth-db-pooler

# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup auth-db-pooler.postgres-operator.svc.cluster.local
```

**Solutions**:
1. Verify database cluster is ready: `kubectl get postgresql auth-db -n auth`
2. Check service endpoints: `kubectl get endpoints -n auth auth-db-pooler`
3. Verify namespace: Ensure service is in correct namespace

#### Error: "Database authentication failed"

**Symptoms**:
```
ERROR   Database authentication failed    {"error": "password authentication failed for user \"auth\""}
```

**Diagnosis**:
```bash
# Check Secret exists
kubectl get secret auth-db-secret -n auth

# Check Secret content (base64 decoded)
kubectl get secret auth-db-secret -n auth -o jsonpath='{.data.password}' | base64 -d

# Verify Secret is referenced in Helm values
helm get values auth -n auth | grep -A 5 DB_PASSWORD
```

**Solutions**:
1. Verify Secret exists: `kubectl get secret auth-db-secret -n auth`
2. Check Secret key name matches (`password` vs `username`)
3. Recreate Secret if needed: `kubectl create secret generic auth-db-secret --from-literal=password=postgres -n auth`

#### Error: "Connection timeout"

**Symptoms**:
```
ERROR   Failed to ping database    {"error": "context deadline exceeded"}
```

**Diagnosis**:
```bash
# Check database pod status
kubectl get pods -n auth -l app=postgres

# Check database logs
kubectl logs -n auth -l app=postgres --tail=50

# Test connectivity from pod
kubectl run -it --rm test --image=postgres:15-alpine --restart=Never -- psql -h auth-db-pooler.postgres-operator.svc.cluster.local -U auth -d auth
```

**Solutions**:
1. Verify database pod is Running: `kubectl get pods -n auth`
2. Check database logs for errors: `kubectl logs -n auth auth-db-0`
3. Verify network policies (if any): `kubectl get networkpolicies -n auth`

### Pooler Issues

#### PgBouncer: "Pool exhausted"

**Symptoms**:
```
ERROR   Database connection pool exhausted
```

**Diagnosis**:
```bash
# Check PgBouncer pool stats
kubectl exec -n auth deployment/auth-db-pooler -- psql -h localhost -U pooler -d pgbouncer -c "SHOW POOLS;"

# Check active connections
kubectl exec -n auth deployment/auth-db-pooler -- psql -h localhost -U pooler -d pgbouncer -c "SHOW CLIENTS;"
```

**Solutions**:
1. Increase pool size: Update `DB_POOL_MAX_CONNECTIONS` in Helm values
2. Check for connection leaks: Review service code for unclosed connections
3. Restart pooler: `kubectl rollout restart deployment/auth-db-pooler -n auth`

#### PgCat: "Routing error"

**Symptoms**:
```
ERROR   PgCat routing failed    {"error": "no healthy replicas available"}
```

**Diagnosis**:
```bash
# Check PgCat pod status
kubectl get pods -n product -l app=pgcat-product

# Check PgCat logs
kubectl logs -n product -l app=pgcat-product --tail=50

# Check database cluster status
kubectl get cluster product-db -n product
```

**Solutions**:
1. Verify database cluster is Ready: `kubectl get cluster product-db -n product`
2. Check PgCat configmap: `kubectl get configmap pgcat-product-config -n product -o yaml`
3. Restart PgCat: `kubectl rollout restart deployment/pgcat-product -n product`

#### PgCat: TOML Configuration Errors

**Symptoms**:
```
TOML parse error at line X, column Y: missing field 'general'
TOML parse error: missing field 'shards'
TOML parse error: Shard 'primary' is not a valid number, shards must be numbered starting at 0
TOML parse error: missing field 'users'
TOML parse error: invalid inline table expected '}'
```

**Common Issues**:

1. **Missing `[general]` section**: PgCat v1.2.0 requires `[general]` section with `admin_username` and `admin_password`
2. **Incorrect shard format**: Shards must be numbered starting at 0: `[pools.<name>.shards.0]` not `[pools.<name>.shards.primary]`
3. **Incorrect servers format**: Servers must be array of tables: `[[pools.<name>.shards.0.servers]]` with `host`, `port`, `user`, `password`, `role` fields
4. **Missing users section**: Each pool needs `[pools.<name>.users]` with inline table format: `username = { username = "...", password = "...", pool_size = ... }`
5. **Wrong service names**: CloudNativePG uses `{cluster-name}-rw` format, not `{cluster-name}-primary`

**Diagnosis**:
```bash
# Check PgCat pod logs for TOML errors
kubectl logs -n product -l app=pgcat-product --tail=50

# Validate configmap format
kubectl get configmap pgcat-product-config -n product -o yaml | grep -A 50 pgcat.toml

# Check for ImagePullBackOff (wrong image)
kubectl get pods -n product -l app=pgcat-product
```

**Solutions**:
1. Verify TOML format matches PgCat v1.2.0 requirements (see config examples in "Pattern 3: PgCat Standalone" section)
2. Check shard numbering (must start at 0): `[pools.<name>.shards.0]` not `[pools.<name>.shards.primary]`
3. Ensure all required sections are present:
   - `[general]` with `admin_username` and `admin_password`
   - `[admin]` with `host` and `port`
   - `[pools.<name>]` with `pool_size`
   - `[pools.<name>.users]` with inline table format
   - `[pools.<name>.shards.0]` with `database`
   - `[[pools.<name>.shards.0.servers]]` array with `host`, `port`, `user`, `password`, `role`
4. Validate service names match CloudNativePG format: `{cluster-name}-rw.{namespace}.svc.cluster.local`
5. Verify image is correct: `ghcr.io/postgresml/pgcat:v1.2.0` (not `postgresml/pgcat:latest`)

#### PgCat: Image Pull Errors

**Symptoms**:
```
Error: ImagePullBackOff
Failed to pull image "postgresml/pgcat:latest": pull access denied
```

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -n product -l app=pgcat-product

# Check image in deployment
kubectl get deployment pgcat-product -n product -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Solutions**:
1. Verify image is `ghcr.io/postgresml/pgcat:v1.2.0` (not `postgresml/pgcat:latest`)
2. Update deployment: `kubectl set image deployment/pgcat-product pgcat=ghcr.io/postgresml/pgcat:v1.2.0 -n product`
3. Check image exists: `docker pull ghcr.io/postgresml/pgcat:v1.2.0`

### HA Failover Scenarios

#### Patroni: Failover not working

**Symptoms**:
- Primary database fails, but no failover occurs
- Services cannot connect after primary failure
- Cluster status shows unhealthy state

**Diagnosis**:
```bash
# Check cluster status (CloudNativePG)
kubectl get cluster transaction-db -n cart -o yaml | grep -A 10 status

# Check cluster status (Zalando)
kubectl get postgresql auth-db -n auth -o yaml | grep -A 10 status

# Check Patroni logs (CloudNativePG - Patroni runs in main container)
kubectl logs -n cart transaction-db-1 --tail=50

# Check Patroni logs (Zalando - Patroni runs in Spilo image)
kubectl logs -n auth auth-db-0 --tail=50

# Check Kubernetes API connectivity (Patroni uses K8s API as DCS)
kubectl get nodes
kubectl get pods -n cart
```

**Solutions**:
1. **Verify Patroni is running**: Both operators use Patroni internally
   - CloudNativePG: Patroni runs in PostgreSQL container
   - Zalando: Patroni runs in Spilo container (part of Zalando operator)
2. **Check Kubernetes API connectivity**: Patroni uses K8s API as Distributed Configuration Store
   - Verify cluster connectivity: `kubectl cluster-info`
   - Check operator can access K8s API: `kubectl get pods -n database`
3. **Verify cluster configuration**: 
   - CloudNativePG: Check `k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml`
   - Zalando: Check `k8s/postgres-operator-zalando/crds/auth-db.yaml`
4. **Review operator logs**:
   - CloudNativePG: `kubectl logs -n database -l app.kubernetes.io/name=cloudnative-pg`
   - Zalando: `kubectl logs -n database -l app.kubernetes.io/name=postgres-operator`
5. **Check for resource constraints**: Insufficient CPU/memory can prevent failover
   - `kubectl describe pod transaction-db-1 -n cart`
   - `kubectl top pod transaction-db-1 -n cart`

**Note**: Patroni uses Kubernetes API (not etcd) for leader election. No separate etcd cluster is needed.

#### Replication Lag

**Symptoms**:
- Read queries return stale data
- Replication lag metrics show high values

**Diagnosis**:
```bash
# Check replication lag (from primary)
kubectl exec -n product product-db-1 -- psql -U product -d product -c "SELECT * FROM pg_stat_replication;"

# Check replica status
kubectl get cluster product-db -n product -o jsonpath='{.status.conditions}'
```

**Solutions**:
1. Check network connectivity between primary and replica
2. Verify WAL shipping is working: Check PostgreSQL logs
3. Consider sync replication for critical data (with performance trade-off)

---

## Monitoring

### postgres_exporter Setup

PostgreSQL metrics are exposed via `postgres_exporter` for all 5 clusters.

**Deployment**:
```bash
# Deploy postgres_exporter (via Helm or manual)
helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  -f k8s/postgres-exporter/values.yaml \
  -n monitoring
```

**Configuration** (`k8s/postgres-exporter/values.yaml`):
```yaml
config:
  datasource:
    host: auth-db.postgres-operator.svc.cluster.local
    port: "5432"
    database: auth
    user: postgres
    password: <from-secret>
```

### ServiceMonitor Configuration

Prometheus auto-discovers postgres_exporter instances via ServiceMonitor:

```yaml
# k8s/prometheus/servicemonitor-postgres.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: postgres-exporter
  endpoints:
    - port: http
      path: /metrics
```

### Grafana Dashboards

PostgreSQL metrics are available in Grafana:

**Key Metrics**:
- `pg_stat_database_*` - Database statistics
- `pg_stat_activity_*` - Active connections
- `pg_replication_*` - Replication lag
- `pg_up` - Database availability

**Query Examples**:
```promql
# Active connections per database
pg_stat_database_numbackends{datname=~"$database"}

# Replication lag (for HA clusters)
pg_replication_lag{instance=~"$instance"}

# Database size
pg_database_size_bytes{datname=~"$database"}
```

### Monitoring Checklist

- [ ] postgres_exporter deployed for all 5 clusters
- [ ] ServiceMonitor created for each exporter
- [ ] Metrics visible in Prometheus (`/metrics` endpoint)
- [ ] Grafana dashboards configured
- [ ] Alerts configured for critical metrics (connection count, replication lag)

---

## Best Practices

### Connection Management

1. **Always use connection pooling** for production workloads
2. **Set appropriate pool sizes** based on service load
3. **Monitor connection pool usage** via metrics
4. **Close connections properly** in Go code (use `defer db.Close()`)

### Configuration

1. **Never hardcode credentials** - Always use Kubernetes Secrets
2. **Use separate env vars** - Don't use `DATABASE_URL` string
3. **Validate configuration** - Fail fast on startup if misconfigured
4. **Document endpoints** - Keep Helm values documented

### High Availability

1. **Test failover scenarios** - Verify automatic failover works
2. **Monitor replication lag** - Set up alerts for high lag
3. **Plan for failover** - Document failover procedures
4. **Use sync replication** for critical data (with performance trade-off)

### Security

1. **Rotate passwords regularly** - Update Secrets periodically
2. **Use SSL in production** - Set `DB_SSLMODE=require` (not `disable`)
3. **Limit database access** - Use least privilege principle
4. **Audit database access** - Enable PostgreSQL logging

---

## Related Documentation

- **[Configuration Guide](./CONFIG_GUIDE.md)** - Complete configuration management
- **[Error Handling](./ERROR_HANDLING.md)** - Database error handling patterns
- **[Setup Guide](../getting-started/SETUP.md)** - Database deployment steps
- **[API Reference](../api/API_REFERENCE.md)** - API endpoints using database

---

**Created:** December 20, 2025  
**Last Updated:** December 20, 2025  
**Status:** Production  
**Related Spec:** [`specs/active/postgres-database-integration/spec.md`](../../specs/active/postgres-database-integration/spec.md)

