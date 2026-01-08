# PgCat ConfigMap Configuration Analysis

**File:** `k8s/pgcat/transaction/configmap.yaml`

---

## Overview

This ConfigMap defines the PgCat connection pooler configuration for the Transaction Database cluster, supporting both Cart and Order services with High Availability (HA) read replica routing.

---

## Configuration Structure

### 1. General Settings (`[general]`)

```toml
[general]
host = "0.0.0.0"           # Listen on all interfaces
port = 5432                # PostgreSQL protocol port (clients connect here)
pool_mode = "transaction"  # Transaction-level pooling (reuses connections efficiently)
log_level = "info"         # Logging verbosity
admin_username = "admin"   # Admin interface credentials
admin_password = "admin"   # Admin interface password
```

**Ý nghĩa:**
- `host = "0.0.0.0"`: PgCat listens on all network interfaces inside the pod
- `port = 5432`: Standard PostgreSQL port - applications connect to this port (not directly to PostgreSQL)
- `pool_mode = "transaction"`: Connection pooling mode - connections are reused per transaction, not per query
- `log_level = "info"`: Logs important events (connections, errors, routing decisions)

**Pooling Modes (pool_mode):**

PgCat supports multiple pooling modes, each with different connection reuse strategies:

1. **Transaction Pooling** (`pool_mode = "transaction"`) - **Current Setting**
   - **Behavior**: Server connection is returned to pool after each transaction (COMMIT/ROLLBACK)
   - **Connection Lifecycle**: 
     - Client connects → PgCat assigns server connection
     - Transaction executes (BEGIN → queries → COMMIT/ROLLBACK)
     - Server connection returned to pool
     - Next transaction may use different server connection
   - **Supports**: 
     - ✅ `SET LOCAL` (transaction-scoped settings)
     - ✅ Transaction-scoped locks (`SELECT ... FOR UPDATE`)
     - ✅ Temporary tables (within transaction)
   - **Does NOT Support**:
     - ❌ Prepared statements (cannot persist across transactions)
     - ❌ Session-level `SET` commands (not transaction-scoped)
     - ❌ Advisory locks (session-scoped)
   - **Use Case**: **Recommended for most web applications**
     - Short-lived transactions (typical web requests)
     - High connection churn
     - Stateless applications
     - **Current use**: Transaction database (cart, order) - perfect fit ✅

2. **Session Pooling** (`pool_mode = "session"`)
   - **Behavior**: Client connection maps to one server connection for entire session (until disconnect)
   - **Connection Lifecycle**:
     - Client connects → PgCat assigns server connection
     - Server connection stays assigned for entire client session
     - Server connection returned to pool only when client disconnects
   - **Supports**:
     - ✅ Prepared statements (persist across transactions)
     - ✅ Session-level `SET` commands
     - ✅ Advisory locks (session-scoped)
     - ✅ Session variables
   - **Does NOT Support**:
     - ❌ High connection churn (connections held longer)
   - **Use Case**: Applications requiring session-level features
     - Long-running connections
     - Applications using prepared statements
     - Applications using advisory locks
     - **Example**: Reporting tools, data analysis tools, long-running ETL jobs

3. **Statement Pooling** (`pool_mode = "statement"`) - **Rarely Used**
   - **Behavior**: Server connection is returned to pool after each SQL statement
   - **Connection Lifecycle**:
     - Client sends statement → PgCat assigns server connection
     - Statement executes
     - Server connection immediately returned to pool
     - Next statement may use different server connection
   - **Supports**: Only single-statement transactions
   - **Does NOT Support**:
     - ❌ Multi-statement transactions (each statement uses different connection)
     - ❌ Transaction control (BEGIN/COMMIT/ROLLBACK)
     - ❌ Prepared statements
     - ❌ Session variables
   - **Use Case**: Very high connection churn scenarios (rarely needed)
     - Simple query-only workloads
     - No transaction requirements
     - **Note**: Not recommended for most applications

**Comparison Table:**

| Feature | Transaction | Session | Statement |
|---------|-------------|---------|-----------|
| **Connection Reuse** | Per transaction | Per session | Per statement |
| **Prepared Statements** | ❌ | ✅ | ❌ |
| **SET commands** | `SET LOCAL` only | ✅ All | ❌ |
| **Advisory Locks** | Transaction-scoped | ✅ Session-scoped | ❌ |
| **Transaction Control** | ✅ | ✅ | ❌ |
| **Connection Efficiency** | High | Medium | Very High |
| **Use Case** | Web apps (default) | Long-running apps | Query-only (rare) |
| **Current Setting** | ✅ **Transaction** | | |

**Why Transaction Pooling for Transaction Database?**

- ✅ **Web Application Pattern**: Cart and Order services follow typical web request pattern:
  - Short-lived transactions (HTTP request → DB transaction → response)
  - High connection churn (many concurrent users)
  - Stateless (no session persistence needed)
- ✅ **Connection Efficiency**: Maximizes connection reuse with minimal overhead
- ✅ **Compatibility**: Works with all common PostgreSQL features needed by web apps
- ✅ **Performance**: Optimal for high-throughput scenarios

### 2. Admin Interface (`[admin]`)

```toml
[admin]
host = "0.0.0.0"   # Admin interface listens on all interfaces
port = 9930         # HTTP admin/metrics endpoint
```

**Ý nghĩa:**
- `port = 9930`: HTTP endpoint for admin operations and Prometheus metrics (`/metrics`)
- Used by ServiceMonitor to scrape metrics
- Accessible via: `http://pgcat.cart.svc.cluster.local:9930/metrics`

### 3. Cart Database Pool (`[pools.cart]`)

```toml
[pools.cart]
pool_size = 30  # Maximum 30 connections to PostgreSQL for cart database
```

**Ý nghĩa:**
- `pool_size = 30`: Maximum number of PostgreSQL connections PgCat maintains for the `cart` database
- Connections are shared across all client connections to PgCat
- Reduces connection overhead on PostgreSQL

#### User Configuration (`[pools.cart.users]`)

```toml
[pools.cart.users]
cart = { username = "cart", password = "postgres", pool_size = 30 }
```

**Ý nghĩa:**
- Defines which PostgreSQL user can connect to the `cart` pool
- `username = "cart"`: PostgreSQL username
- `password = "postgres"`: PostgreSQL password (matches `transaction-db-secret`)
- `pool_size = 30`: Same as pool-level setting (can be overridden per user)

#### Shard Configuration (`[pools.cart.shards.0]`)

```toml
[pools.cart.shards.0]
database = "cart"  # PostgreSQL database name
```

**Ý nghĩa:**
- `shards.0`: First shard (sharding not used, but required by PgCat structure)
- `database = "cart"`: Actual PostgreSQL database name

#### Server Configuration (`[[pools.cart.shards.0.servers]]`)

**Primary Server:**
```toml
[[pools.cart.shards.0.servers]]
host = "transaction-db-rw.cart.svc.cluster.local"  # CloudNativePG read-write service
port = 5432
user = "cart"
password = "postgres"
role = "primary"  # Handles all writes (INSERT, UPDATE, DELETE, DDL)
```

**Ý nghĩa:**
- `host = "transaction-db-rw.cart.svc.cluster.local"`: **CloudNativePG automatically creates this service**
  - Format: `{cluster-name}-rw.{namespace}.svc.cluster.local`
  - Points to the current primary instance
  - Updates automatically during failover
- `role = "primary"`: PgCat routes all write queries (INSERT, UPDATE, DELETE, DDL) to this server
- This is the **only** server that handles writes

**Replica Server:**
```toml
[[pools.cart.shards.0.servers]]
host = "transaction-db-r.cart.svc.cluster.local"  # CloudNativePG read-only service
port = 5432
user = "cart"
password = "postgres"
role = "replica"  # Handles read queries (SELECT)
```

**Ý nghĩa:**
- `host = "transaction-db-r.cart.svc.cluster.local"`: **CloudNativePG automatically creates this service**
  - Format: `{cluster-name}-r.{namespace}.svc.cluster.local`
  - Load balances across all replica instances (Replica1, Replica2)
  - Automatically updates when replicas are added/removed
- `role = "replica"`: PgCat routes all SELECT queries to this server
- **Load balancing**: PgCat automatically distributes SELECT queries across all healthy replicas using "random" algorithm

### 4. Order Database Pool (`[pools.order]`)

Same structure as `cart` pool, but for the `order` database:

```toml
[pools.order]
pool_size = 30

[pools.order.users]
cart = { username = "cart", password = "postgres", pool_size = 30 }

[pools.order.shards.0]
database = "order"

# Primary server (same as cart - shared PostgreSQL cluster)
[[pools.order.shards.0.servers]]
host = "transaction-db-rw.cart.svc.cluster.local"
port = 5432
user = "cart"
password = "postgres"
role = "primary"

# Replica server (same as cart - shared PostgreSQL cluster)
[[pools.order.shards.0.servers]]
host = "transaction-db-r.cart.svc.cluster.local"
port = 5432
user = "cart"
password = "postgres"
role = "replica"
```

**Ý nghĩa:**
- Both `cart` and `order` databases are on the same PostgreSQL cluster (`transaction-db`)
- They share the same primary and replica servers
- PgCat routes queries based on the database name (`cart` vs `order`)

---

## How CloudNativePG Services Work

### Service: `transaction-db-rw`

**Created by:** CloudNativePG Operator automatically

**Purpose:** Read-write endpoint pointing to the current primary instance

**Format:** `{cluster-name}-rw.{namespace}.svc.cluster.local`

**Behavior:**
- Always points to the current primary instance
- Updates automatically during failover/switchover
- Single endpoint (no load balancing)

**Example:**
```bash
# Check service
kubectl get svc -n cart transaction-db-rw

# Service endpoints point to primary pod
kubectl get endpoints -n cart transaction-db-rw
```

### Service: `transaction-db-r`

**Created by:** CloudNativePG Operator automatically

**Purpose:** Read-only endpoint load balancing across all replica instances

**Format:** `{cluster-name}-r.{namespace}.svc.cluster.local`

**Behavior:**
- Load balances across all healthy replica instances
- Automatically excludes unhealthy replicas
- Updates automatically when replicas are added/removed

**Example:**
```bash
# Check service
kubectl get svc -n cart transaction-db-r

# Service endpoints point to all replica pods
kubectl get endpoints -n cart transaction-db-r
```

**Why use this service:**
- Single endpoint for all replicas (simpler than listing each replica individually)
- Automatic load balancing by Kubernetes
- Automatic health checking and failover
- No need to update PgCat config when replicas change

---

## Query Routing Logic

### Write Queries (INSERT, UPDATE, DELETE, DDL)

1. Client sends query to PgCat: `pgcat.cart.svc.cluster.local:5432`
2. PgCat parses SQL query
3. If query is INSERT/UPDATE/DELETE/DDL → Route to `transaction-db-rw` (primary)
4. Primary executes query
5. Results returned to client

### Read Queries (SELECT)

1. Client sends SELECT query to PgCat: `pgcat.cart.svc.cluster.local:5432`
2. PgCat parses SQL query
3. If query is SELECT → Route to `transaction-db-r` (replica endpoint)
4. Kubernetes service load balances to one of the replica pods
5. Replica executes query (read-only)
6. Results returned to client

### Load Balancing

- **Write queries**: Always go to primary (no balancing)
- **Read queries**: Distributed across replicas via:
  1. PgCat routes to `transaction-db-r` service
  2. Kubernetes service load balances to replica pods
  3. PgCat can also balance across multiple replica servers (if configured)

---

## Health Checks & Failover

### Health Check Method

PgCat performs fast health checks before each query:
- Query: `;` (empty query - minimal overhead)
- If server responds → Healthy
- If server fails → Unhealthy

### Failover Behavior

1. **Replica becomes unhealthy:**
   - PgCat detects failure (health check fails)
   - Bans unhealthy replica for 60 seconds (default `ban_time`)
   - Routes queries to remaining healthy replicas + primary
   - When replica recovers, automatically rejoins pool

2. **Primary becomes unhealthy:**
   - CloudNativePG detects primary failure
   - Promotes one replica to primary
   - `transaction-db-rw` service automatically points to new primary
   - PgCat continues routing writes to `transaction-db-rw` (now points to new primary)
   - No PgCat configuration change needed

---

## Configuration Files & Scripts

### ConfigMap Deployment

**Script:** `scripts/04-deploy-databases.sh` (line 203)

```bash
kubectl apply -f "$PROJECT_ROOT/k8s/pgcat/transaction/"
```

**What it does:**
- Applies all files in `k8s/pgcat/transaction/` directory:
  - `configmap.yaml` (this file)
  - `deployment.yaml` (PgCat pods)
  - `service.yaml` (PgCat service)

**Manual apply:**
```bash
kubectl apply -f k8s/pgcat/transaction/configmap.yaml
```

### ServiceMonitor Deployment

**Script:** `scripts/02-deploy-monitoring.sh` (line 50-52)

```bash
if [ -d "k8s/prometheus/servicemonitors" ]; then
    kubectl apply -f k8s/prometheus/servicemonitors/
fi
```

**What it does:**
- Applies all ServiceMonitors from `k8s/prometheus/servicemonitors/` directory
- Includes `servicemonitor-pgcat-transaction.yaml`

**Manual apply:**
```bash
kubectl apply -f k8s/prometheus/servicemonitors/servicemonitor-pgcat-transaction.yaml
```

---

## Summary

**Key Points:**

1. **CloudNativePG Services**: Automatically created by operator
   - `transaction-db-rw`: Primary endpoint (writes)
   - `transaction-db-r`: Replica endpoint (reads, load balanced)

2. **PgCat Routing**: Automatic based on SQL query type
   - Writes → Primary (`transaction-db-rw`)
   - Reads → Replicas (`transaction-db-r`)

3. **Load Balancing**: Two levels
   - Kubernetes service (`transaction-db-r`) balances across replica pods
   - PgCat can balance across multiple replica servers (if configured)

4. **High Availability**: Automatic failover
   - Replica failures: PgCat bans and routes to remaining replicas
   - Primary failures: CloudNativePG promotes replica, service updates automatically

5. **Configuration**: Declarative
   - ConfigMap defines servers and roles
   - Services are auto-created by CloudNativePG
   - No manual service discovery needed
