# Research: PgBouncer and PgCat Connection Poolers Deep Dive

**Task ID:** connection-poolers-deepdive
**Date:** 2025-12-30
**Status:** Complete

---

## Executive Summary

This research provides a comprehensive deep dive into PostgreSQL connection poolers, specifically **PgBouncer** (used with Zalando operator), **PgCat** (used with CloudNativePG clusters), and **PgDog** (alternative for advanced sharding needs). The analysis covers architecture, use cases, benefits, HA integration patterns, monitoring strategies, and real-world deployment scenarios.

**Key Findings:**
- **PgBouncer** is a mature, single-threaded pooler ideal for low-to-medium connection counts with Zalando operator's built-in sidecar integration
- **PgCat** is a modern, multi-threaded Rust-based pooler with advanced features (load balancing, failover, sharding) suitable for high-connection scenarios
- **PgDog** is a newer Rust-based pooler with production-grade sharding, two-phase commit, and advanced features (pub/sub, service discovery) for enterprise-scale deployments
- All three poolers solve the "too many connections" problem but differ in architecture, features, and scalability
- PgCat can integrate with HA clusters (transaction-db 3-node) for automatic failover and read replica routing
- PgDog offers advanced sharding capabilities with two-phase commit for distributed transactions
- Monitoring is available via Prometheus/OpenMetrics metrics (PgCat/PgDog HTTP endpoints) and admin databases (all poolers)

**Primary Recommendation:**
- **Keep PgBouncer** for Auth DB (Zalando built-in, simple, proven)
- **Enhance PgCat** for Transaction DB with HA integration (read replica routing, automatic failover)
- **Consider PgDog** for future sharding needs or if advanced features (two-phase commit, pub/sub) are required
- **Add monitoring** for both poolers (ServiceMonitor for PgCat, existing PodMonitor for PostgreSQL)

---

## Codebase Analysis

### Existing Patterns

#### PgBouncer Implementation (Zalando Operator)

**Location:** `k8s/postgres-operator-zalando/crds/auth-db.yaml`

**How it works:**
- Zalando operator automatically deploys PgBouncer as a **sidecar container** in PostgreSQL pods
- Configuration via `connectionPooler` section in PostgreSQL CRD
- Creates a separate Kubernetes Service (`auth-db-pooler`) for pooler access
- Uses transaction pooling mode by default

**Code example:**
```yaml
# k8s/postgres-operator-zalando/crds/auth-db.yaml
connectionPooler:
  numberOfInstances: 2
  schema: pooler
  user: pooler
  mode: transaction  # Transaction pooling for short-lived connections
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

**Reusability:** This pattern is Zalando-specific and cannot be reused for CloudNativePG clusters. It's ideal for Auth DB because:
- Built-in integration (no separate deployment needed)
- Automatic service creation
- Co-located with PostgreSQL pods (low latency)

#### PgCat Implementation (Standalone)

**Location:** `k8s/pgcat/transaction/` and `k8s/pgcat/product/`

**How it works:**
- **Standalone Deployment**: Separate Kubernetes Deployment (2 replicas)
- **ConfigMap-based**: Configuration via TOML file in ConfigMap
- **Multi-database routing**: Supports multiple databases (cart, order) on same cluster
- **Service**: ClusterIP service exposing port 5432 (PostgreSQL) and 9930 (admin)

**Code example:**
```yaml
# k8s/pgcat/transaction/configmap.yaml
[pools.cart]
pool_size = 30

[[pools.cart.shards.0.servers]]
host = "transaction-db-rw.cart.svc.cluster.local"
port = 5432
role = "primary"
```

**Reusability:** This pattern is used for both Product and Transaction databases. It's ideal for CloudNativePG because:
- Independent lifecycle (can upgrade without affecting PostgreSQL)
- Multi-database support (cart + order on same cluster)
- Can be extended with read replica routing

#### PgDog Implementation (supporting-db)

**Location:** `kubernetes/infra/configs/databases/poolers/supporting/` (to be created)

**How it works:**
- **Helm Chart Deployment**: Standalone deployment via Helm chart (`helm.pgdog.dev/pgdog`)
- **Multi-Database Routing**: Routes to 3 databases (user, notification, shipping) on Zalando cluster
- **Service**: ClusterIP service exposing port 6432 (PostgreSQL) and 9090 (OpenMetrics)
- **Configuration**: Helm values define databases, users, and pool settings

**Helm Chart Setup:**
```bash
# Add PgDog Helm repository
helm repo add pgdogdev https://helm.pgdog.dev
helm repo update
```

**Helm Values Example:**
```yaml
# kubernetes/infra/configs/databases/poolers/supporting/values.yaml
replicas: 2  # HA deployment

port: 6432  # PostgreSQL protocol port
openMetricsPort: 9090  # Prometheus metrics port

# Multi-database configuration
databases:
  - name: user
    host: supporting-db.user.svc.cluster.local
    port: 5432
    database: user
    poolSize: 30
    poolMode: transaction
  - name: notification
    host: supporting-db.user.svc.cluster.local
    port: 5432
    database: notification
    poolSize: 20
    poolMode: transaction
  - name: shipping
    host: supporting-db.user.svc.cluster.local
    port: 5432
    database: shipping
    poolSize: 20
    poolMode: transaction

# User authentication (from Kubernetes secrets)
users:
  - name: user
    passwordFromSecret:
      name: user.supporting-db.credentials.postgresql.acid.zalan.do
      key: password
  - name: notification.notification
    passwordFromSecret:
      name: notification.notification.supporting-db.credentials.postgresql.acid.zalan.do
      key: password
  - name: shipping.shipping
    passwordFromSecret:
      name: shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do
      key: password

# Resources
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

# ServiceMonitor for Prometheus
serviceMonitor:
  enabled: true
```

**Service Endpoints:**
- **PostgreSQL**: `pgdog-supporting.user.svc.cluster.local:6432`
- **OpenMetrics**: `pgdog-supporting.user.svc.cluster.local:9090/metrics`

**Application Connection:**
```yaml
# Service Helm values (e.g., charts/values/user.yaml)
env:
  - name: DB_HOST
    value: "pgdog-supporting.user.svc.cluster.local"  # PgDog service
  - name: DB_PORT
    value: "6432"  # PgDog port (not PostgreSQL port 5432)
  - name: DB_NAME
    value: "user"  # Database name (PgDog routes by database name)
  - name: DB_USER
    value: "user"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: user.supporting-db.credentials.postgresql.acid.zalan.do
        key: password
  - name: DB_SSLMODE
    value: "require"
```

**Reusability:** This pattern is ideal for Zalando clusters with multiple databases because:
- **No Built-in Pooler**: Zalando operator doesn't provide built-in pooler for multi-database clusters (only sidecar for single database)
- **Multi-Database Support**: PgDog routes by database name, perfect for shared clusters
- **Advanced Features**: Prepared statements, pub/sub support for future needs
- **Production-Ready**: Helm chart provides HA, monitoring, and security features

**Why PgDog over PgBouncer for supporting-db:**
- ✅ **Multi-Database**: PgDog has better multi-database support than PgBouncer
- ✅ **Prepared Statements**: Full support in transaction mode (PgBouncer only in session mode)
- ✅ **Future-Proof**: Advanced features (pub/sub, sharding) available if needed
- ✅ **Helm Chart**: Production-ready Helm chart with HA, monitoring, security

**Why PgDog over PgCat for supporting-db:**
- ✅ **Zalando Compatibility**: PgDog works well with Zalando clusters (no CloudNativePG requirement)
- ✅ **Helm Chart**: Official Helm chart simplifies deployment
- ✅ **Advanced Features**: Better prepared statements support, pub/sub if needed

### Current Monitoring Patterns

**Location:** `k8s/prometheus/podmonitors/`

**Pattern:**
- **PostgreSQL clusters**: Use PodMonitor CRDs to scrape `postgres_exporter` sidecars
- **Port**: `9187` (exporter) for Zalando, `metrics` (9187) for CloudNativePG
- **No pooler monitoring**: Currently, poolers (PgBouncer, PgCat) are not monitored

**Gap identified:**
- PgCat exposes Prometheus metrics on HTTP endpoint (not yet configured)
- PgBouncer has admin database but no Prometheus integration
- Need ServiceMonitor for PgCat HTTP metrics endpoint

### Conventions to Follow

1. **Pooler Configuration**: Use ConfigMap for PgCat (TOML format), CRD section for PgBouncer (YAML)
2. **Service Naming**: `{cluster-name}-pooler` for PgBouncer, `pgcat` or `pgcat-{service}` for PgCat
3. **Resource Limits**: Conservative limits (CPU: 100m-500m, Memory: 128Mi-512Mi)
4. **Deployment**: 2 replicas for standalone poolers (HA), matches PostgreSQL instances for sidecars

---

## External Solutions

### Option 1: PgBouncer (Current Implementation)

**Overview:** Lightweight, single-threaded connection pooler written in C, widely used in PostgreSQL community.

**Architecture:**
- **Single-threaded**: Uses `libevent` for async I/O
- **Lightweight**: Minimal memory footprint (~2-5MB per instance)
- **Mature**: 15+ years in production, battle-tested

**Pooling Modes:**
1. **Session Pooling**: Client connection maps to one server connection for entire session
   - Supports: Prepared statements, SET commands, advisory locks
   - Use case: Applications requiring session-level features
2. **Transaction Pooling** (default for Zalando): Server connection returned to pool after each transaction
   - Supports: SET LOCAL, transaction-scoped locks
   - Use case: Short-lived transactions, high connection churn
3. **Statement Pooling**: Server connection returned after each statement
   - Use case: Very high connection churn (rarely used)

**Pros:**
- ✅ **Mature and stable**: 15+ years in production
- ✅ **Low resource usage**: Minimal CPU/memory overhead
- ✅ **Simple configuration**: INI file format, easy to understand
- ✅ **Zalando integration**: Built-in sidecar, automatic deployment
- ✅ **Live reload**: Can reload config without restart (SIGHUP)
- ✅ **Admin database**: Virtual database `pgbouncer` for monitoring

**Cons:**
- ❌ **Single-threaded**: Performance bottleneck with >50 concurrent connections
- ❌ **No load balancing**: Cannot route reads to replicas
- ❌ **No automatic failover**: Manual configuration required
- ❌ **No sharding**: Cannot distribute queries across shards
- ❌ **Limited monitoring**: Admin database only, no Prometheus metrics

**Fit for our use case:** **High** - Perfect for Auth DB with Zalando operator
- Low-to-medium connection count (<50 concurrent)
- Built-in integration (no separate deployment)
- Transaction pooling matches short-lived auth requests

**Performance Characteristics:**
- **Latency**: <1ms overhead per connection
- **Throughput**: Excellent for <50 connections, degrades with more
- **Memory**: ~2-5MB per instance
- **CPU**: Single core, minimal usage

**Best Practices:**
1. **Use transaction pooling** for web applications (default)
2. **Set `max_client_conn`** to expected peak connections
3. **Set `default_pool_size`** to 25-50% of PostgreSQL `max_connections`
4. **Monitor via admin database**: `SHOW POOLS`, `SHOW STATS`
5. **Use SSL/TLS** for production (PgBouncer requires SSL from clients)

**When to Use:**
- ✅ Zalando operator clusters (built-in integration)
- ✅ Low-to-medium connection counts (<50 concurrent)
- ✅ Simple pooling needs (no load balancing, sharding)
- ✅ Mature, stable requirements

**When NOT to Use:**
- ❌ High connection counts (>100 concurrent)
- ❌ Need read replica load balancing
- ❌ Need automatic failover
- ❌ Need sharding capabilities

---

### Option 2: PgCat (Current Implementation)

**Overview:** Modern, multi-threaded connection pooler written in Rust, designed for high-performance and advanced features.

**Architecture:**
- **Multi-threaded**: Uses Tokio async runtime, leverages all CPU cores
- **Modern**: Rust-based, memory-safe, high performance
- **Feature-rich**: Load balancing, failover, sharding, query parsing

**Pooling Modes:**
1. **Transaction Pooling** (default): Same as PgBouncer
2. **Session Pooling**: Same as PgBouncer

**Advanced Features:**
1. **Load Balancing**: Automatic read query distribution across replicas
2. **Failover**: Automatic server health checks, bans unhealthy servers
3. **Query Parsing**: SQL parser routes SELECT to replicas, writes to primary
4. **Sharding**: Hash-based sharding with extended SQL syntax
5. **Mirroring**: Route queries to multiple databases (testing)

**Pros:**
- ✅ **High performance**: Multi-threaded, handles 1000+ connections
- ✅ **Load balancing**: Automatic read replica routing
- ✅ **Automatic failover**: Health checks, server banning
- ✅ **Query parsing**: Intelligent routing (SELECT → replica, writes → primary)
- ✅ **Prometheus metrics**: HTTP endpoint `/metrics` for monitoring
- ✅ **Live reload**: TOML config reload without restart
- ✅ **Multi-database**: Supports multiple databases on same cluster
- ✅ **Sharding support**: Hash-based sharding (experimental)

**Cons:**
- ❌ **Newer project**: Less battle-tested than PgBouncer
- ❌ **Standalone deployment**: Requires separate Kubernetes resources
- ❌ **More complex**: TOML config, more features to understand
- ❌ **Resource usage**: Higher memory/CPU than PgBouncer (still minimal)

**Fit for our use case:** **High** - Ideal for Transaction DB with HA
- High connection potential (cart + order services)
- Need read replica routing (3-node HA cluster)
- Need automatic failover (production-ready)
- Multi-database support (cart + order)

**Performance Characteristics:**
- **Latency**: <1ms overhead per connection
- **Throughput**: Excellent for 100+ connections, scales linearly
- **Memory**: ~10-20MB per instance
- **CPU**: Multi-core, efficient utilization

**Best Practices:**
1. **Configure replicas** in TOML for read load balancing
2. **Set `ban_time`** for failover (default 60s)
3. **Use query parser** for automatic read/write routing
4. **Monitor via Prometheus**: HTTP endpoint `/metrics`
5. **Use admin database**: `pgcat` or `pgbouncer` for compatibility

**When to Use:**
- ✅ High connection counts (>50 concurrent)
- ✅ Need read replica load balancing
- ✅ Need automatic failover
- ✅ Multi-database routing
- ✅ CloudNativePG clusters (standalone deployment)

**When NOT to Use:**
- ❌ Zalando operator (use built-in PgBouncer)
- ❌ Very low connection counts (<10)
- ❌ Simple pooling needs only

---

### Option 3: PgDog (Alternative Consideration)

**Overview:** Modern, multi-threaded connection pooler written in Rust, designed for advanced sharding, load balancing, and production-grade features. Built on lessons learned from PgCat with performance improvements and enterprise features.

**Architecture:**
- **Multi-threaded**: Uses Tokio async runtime, leverages all CPU cores
- **Modern**: Rust-based, memory-safe, high performance
- **Enterprise-ready**: Advanced sharding, two-phase commit, prepared statements support
- **Configuration**: TOML format with multiple files (`pgdog.toml`, `users.toml`)

**Pooling Modes:**
1. **Transaction Pooling** (default): Optimized for high-throughput scenarios, shares few PostgreSQL connections with thousands of clients
2. **Session Pooling**: Full PostgreSQL feature support (LISTEN/NOTIFY, session variables, prepared statements)

**Advanced Features:**
1. **Advanced Sharding**: PostgreSQL-compatible sharding with two-phase commit support
2. **Load Balancing**: Multiple strategies (random, round-robin, least-active-connections)
3. **Read/Write Split**: Configurable read/write query routing:
   - `include_primary`: Use primary for reads and writes
   - `exclude_primary`: Send all reads to replicas, primary only for writes
   - `include_primary_if_replica_banned`: Use primary as failover for reads
4. **Prepared Statements**: Full support in all modes (unlike PgBouncer's session-only limitation)
5. **Two-Phase Commit**: Automatic conversion for cross-shard transactions
6. **Service Discovery**: Multicast-based mutual service discovery for multi-instance deployments
7. **Pub/Sub Support**: PostgreSQL LISTEN/NOTIFY support (unique among poolers)
8. **Mirroring**: Route queries to mirror databases for testing with configurable exposure
9. **Query Parser**: Advanced SQL parsing for intelligent routing and sharding decisions

**Configuration:**
- **Format**: TOML (separate files: `pgdog.toml` for general settings, `users.toml` for user authentication)
- **Sections**: General, Databases, Mirroring, Sharded tables, Plugins, Users, Admin
- **Port**: 6432 (default, configurable via `host` and `port` in `[general]`)
- **Admin Port**: Configurable (separate from metrics)
- **Metrics Port**: OpenMetrics endpoint (configurable via `openmetrics_port`)

**Pros:**
- ✅ **Production-grade sharding**: Two-phase commit, cross-shard queries, resharding support
- ✅ **Full prepared statements**: Support in all pooling modes (transaction and session)
- ✅ **Advanced load balancing**: Multiple strategies, configurable read/write split
- ✅ **Service discovery**: Automatic peer discovery via multicast
- ✅ **Performance**: ~10% better than PgBouncer in benchmarks ([pgdog.dev](https://pgdog.dev/blog/pgbouncer-vs-pgdog))
- ✅ **OpenMetrics**: Prometheus-compatible metrics endpoint
- ✅ **Enterprise features**: Pub/sub, mirroring, plugins, dry-run mode for sharding testing
- ✅ **Microservices-ready**: Designed for database-per-service pattern with sharding support

**Cons:**
- ❌ **Newest project**: Less battle-tested than PgBouncer/PgCat (1-2 years vs 15+ years / 2-3 years)
- ❌ **Standalone deployment**: Requires separate Kubernetes resources
- ❌ **More complex**: Advanced features require deeper understanding
- ❌ **Resource usage**: Higher than PgBouncer (similar to PgCat, higher for sharding features)
- ❌ **Learning curve**: More configuration options, sharding concepts to understand

**Fit for our use case:** **High** - Recommended for supporting-db
- **supporting-db**: Multi-database cluster (user, notification, shipping) needs pooler with multi-database routing
- **Zalando Compatibility**: PgDog works well with Zalando clusters (no built-in pooler for multi-database)
- **Advanced Features**: Prepared statements, pub/sub support for future needs
- **Production-Ready**: Helm chart provides HA, monitoring, security
- **Future-proof**: Sharding capabilities available if databases grow > 100GB

**Performance Characteristics:**
- **Latency**: <1ms overhead per connection
- **Throughput**: Excellent for 100+ connections, scales linearly
- **Memory**: ~10-20MB per instance (similar to PgCat, higher with sharding features)
- **CPU**: Multi-core, efficient utilization (configurable workers: 2 per virtual CPU default)

**Best Practices:**
1. **Configure workers**: 2 per virtual CPU (default: 2), adjust for IO-bound vs CPU-bound workloads
2. **Set pool sizes**: Keep `default_pool_size` well below PostgreSQL `max_connections` (recommendation: 25-50%)
3. **Use read/write split**: Configure `read_write_split` based on read/write ratio
4. **Monitor via OpenMetrics**: Configure `openmetrics_port` for Prometheus scraping
5. **Use service discovery**: Enable `broadcast_address` for multi-instance deployments
6. **Configure health checks**: Adjust `healthcheck_interval` and `idle_healthcheck_interval` based on network stability
7. **Test sharding**: Use `dry_run` mode to test sharding compatibility before enabling

**When to Use:**
- ✅ Need advanced sharding with two-phase commit
- ✅ Need full prepared statements support in transaction mode
- ✅ Need pub/sub (LISTEN/NOTIFY) support
- ✅ Need service discovery for multi-instance deployments
- ✅ High connection counts with sharding requirements (200+ microservices)
- ✅ Enterprise-scale deployments requiring horizontal scaling
- ✅ **Zalando clusters with multiple databases** (no built-in pooler for multi-database)
- ✅ **Multi-database routing** on shared cluster (user, notification, shipping)
- ✅ **Future-proofing** for advanced features (sharding, pub/sub) if needed later

**When NOT to Use:**
- ❌ Simple pooling needs with single database (PgBouncer sufficient)
- ❌ No sharding requirements and CloudNativePG cluster (PgCat sufficient)
- ❌ Zalando operator with single database (use built-in PgBouncer sidecar)
- ❌ Very low connection counts (<10)
- ❌ Small-to-medium microservices with single database (<50 services, <100 conn/service)

**Microservices Architecture Fit:**
- **Database-per-service pattern**: Excellent fit - supports sharding for scale
- **Shared database pattern**: Good fit - multi-database support
- **Configuration**: Separate `pgdog.toml` per service or shared pooler with database routing

**References:**
- [PgDog Documentation](https://docs.pgdog.dev/)
- [PgDog Configuration](https://docs.pgdog.dev/configuration/pgdog.toml/general/)
- [PgDog vs PgBouncer Benchmarks](https://pgdog.dev/blog/pgbouncer-vs-pgdog)

---

## Sharding vs Pooling: When Do You Need Each?

### Understanding the Difference

**Connection Pooling:**
- **Problem Solved**: Too many client connections to PostgreSQL
- **Solution**: Reuse a small pool of PostgreSQL connections (e.g., 30 connections) to serve many clients (e.g., 1000+)
- **When Needed**: High connection churn, connection limit exhaustion
- **Example**: 100 microservices, each opening 10 connections = 1000 connections → Pooler reduces to 30 PostgreSQL connections

**Sharding:**
- **Problem Solved**: Database too large or write throughput too high for single database
- **Solution**: Split data across multiple databases (shards) based on a key (e.g., `user_id % 10`)
- **When Needed**: Database size > 100GB, write throughput exceeds single database capacity
- **Example**: 50M users → Split into 10 shards → Each shard has 5M users

### Use-Case Decision Matrix

| Scenario | Solution | Reason |
|----------|----------|--------|
| **1000+ client connections, database < 100GB** | Connection Pooling | Too many connections, but database size manageable |
| **Database > 100GB, growing fast** | Sharding | Database size is the bottleneck, not connections |
| **High write throughput (10K+ writes/sec)** | Sharding | Single database can't handle write load |
| **High read load, need read scaling** | Pooling + Read Replicas | Connection pooling + read replica routing |
| **Multi-database cluster (3+ databases)** | Pooling (multi-database support) | Pooler routes by database name, no sharding needed |

### supporting-db Use-Case Analysis

**Current State:**
- **Databases**: 3 databases (user, notification, shipping) on single Zalando cluster
- **Size**: Each database < 10GB (estimated)
- **Connections**: User service (2 replicas × 10 conn), Notification (2 replicas × 10 conn), Shipping (2 replicas × 10 conn) = ~60 total connections
- **Traffic**: Low-to-medium traffic, no sharding requirements

**Decision: Connection Pooling Only (No Sharding)**

**Why Pooling:**
- ✅ **Connection Management**: Even with 60 connections, pooling reduces PostgreSQL connection overhead
- ✅ **Future-Proof**: As services scale (more replicas), connection count grows (e.g., 10 replicas × 10 conn = 100 connections)
- ✅ **Multi-Database Support**: PgDog can route to 3 databases (user, notification, shipping) on same cluster
- ✅ **Performance**: Connection reuse improves latency and reduces connection establishment overhead

**Why NOT Sharding:**
- ❌ **Database Size**: Each database < 10GB, no size pressure
- ❌ **Write Throughput**: Low write load, single database sufficient
- ❌ **Complexity**: Sharding adds complexity (cross-shard queries, two-phase commit) without benefit
- ❌ **Future Growth**: Can add sharding later if databases grow > 100GB

**Conclusion**: supporting-db needs **connection pooling with multi-database routing**, not sharding. PgDog provides excellent multi-database support and advanced features (prepared statements, pub/sub) that may be useful in the future.

---

## Comparison Matrix

| Criteria | PgBouncer | PgCat | PgDog |
|----------|-----------|-------|-------|
| **Architecture** | Single-threaded (C, libevent) | Multi-threaded (Rust, Tokio) | Multi-threaded (Rust, Tokio) |
| **Performance (<50 conn)** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐ Very Good | ⭐⭐⭐⭐ Very Good |
| **Performance (>50 conn)** | ⭐⭐ Degrades | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐⭐ Excellent (~10% better than PgBouncer) |
| **Memory Usage** | ⭐⭐⭐⭐⭐ Very Low (2-5MB) | ⭐⭐⭐⭐ Low (10-20MB) | ⭐⭐⭐⭐ Low (10-20MB) |
| **CPU Usage** | ⭐⭐⭐⭐⭐ Minimal (single core) | ⭐⭐⭐⭐ Efficient (multi-core) | ⭐⭐⭐⭐ Efficient (multi-core, configurable workers) |
| **Maturity** | ⭐⭐⭐⭐⭐ 15+ years | ⭐⭐⭐ Newer (2-3 years) | ⭐⭐ Newest (1-2 years) |
| **Load Balancing** | ❌ No | ✅ Yes (read replicas) | ✅ Yes (multiple strategies) |
| **Load Balancing Strategies** | N/A | Random | Random, Round-robin, Least-active |
| **Read/Write Split** | ❌ No | ✅ Yes (automatic) | ✅ Yes (configurable: include_primary, exclude_primary, include_primary_if_replica_banned) |
| **Automatic Failover** | ❌ No | ✅ Yes (health checks) | ✅ Yes (health checks, advanced) |
| **Sharding** | ❌ No | ✅ Yes (experimental) | ✅ Yes (production-grade, two-phase commit) |
| **Two-Phase Commit** | ❌ No | ❌ No | ✅ Yes (automatic conversion) |
| **Query Parsing** | ❌ No | ✅ Yes (SQL parser) | ✅ Yes (SQL parser, advanced) |
| **Prepared Statements** | ⚠️ Limited (session mode only) | ✅ Yes (caching, sharing) | ✅ Yes (full support, all modes) |
| **Pub/Sub (LISTEN/NOTIFY)** | ⚠️ Limited | ❌ No | ✅ Yes (full support) |
| **Service Discovery** | ❌ No | ❌ No | ✅ Yes (multicast-based) |
| **Mirroring** | ❌ No | ✅ Yes (testing) | ✅ Yes (testing, configurable) |
| **Monitoring** | ⭐⭐⭐ Admin DB only | ⭐⭐⭐⭐⭐ Prometheus + Admin DB | ⭐⭐⭐⭐⭐ OpenMetrics + Admin DB |
| **Config Format** | INI | TOML | TOML (pgdog.toml, users.toml) |
| **Config Sections** | Single file | Single file | Multiple files (general, users, databases, sharding) |
| **Live Reload** | ✅ Yes (SIGHUP) | ✅ Yes (SIGHUP) | ✅ Yes (SIGHUP) |
| **Zalando Integration** | ✅ Built-in sidecar | ❌ Standalone only | ❌ Standalone only |
| **CloudNativePG Fit** | ❌ No built-in | ✅ Standalone deployment | ✅ Standalone deployment |
| **Multi-Database** | ⚠️ Limited | ✅ Full support | ✅ Full support |
| **SSL/TLS** | ✅ Yes (MD5, plain) | ✅ Yes (TLS 1.3, MD5, SCRAM-SHA-256) | ✅ Yes (TLS, SCRAM-SHA-256, MD5, plain) |
| **Complexity** | ⭐⭐ Simple | ⭐⭐⭐ Moderate | ⭐⭐⭐⭐ Advanced |
| **Microservices Fit** | ⭐⭐⭐ Good (simple) | ⭐⭐⭐⭐ Very Good | ⭐⭐⭐⭐⭐ Excellent (sharding-ready) |

---

## HA Integration for PgCat with transaction-db

### Current State

**Transaction DB Cluster:**
- **Instances**: 3 (1 primary + 2 replicas)
- **Replication**: Synchronous replication
- **Services**: 
  - `transaction-db-rw.cart.svc.cluster.local` (read-write, primary)
  - `transaction-db-r.cart.svc.cluster.local` (read-only, replicas)

**Current PgCat Configuration:**
- Only primary server configured
- No replica routing
- No failover configuration

### Target State: HA-Integrated PgCat

**Configuration Pattern:**
```toml
# PgCat Configuration with HA Support
[pools.cart.shards.0]
database = "cart"

[[pools.cart.shards.0.servers]]
host = "transaction-db-rw.cart.svc.cluster.local"
port = 5432
role = "primary"

[[pools.cart.shards.0.servers]]
host = "transaction-db-r.cart.svc.cluster.local"
port = 5432
role = "replica"
```

**Features Enabled:**
1. **Automatic Read Routing**: SELECT queries → replicas, writes → primary
2. **Failover**: If replica fails, queries routed to primary
3. **Health Checks**: PgCat checks server health before routing
4. **Load Balancing**: Read queries distributed across 2 replicas

**Benefits:**
- ✅ **Read Scaling**: Distribute read load across 2 replicas
- ✅ **Automatic Failover**: Replica failures don't break reads
- ✅ **Zero Configuration**: Query parser automatically routes
- ✅ **Production-Ready**: Works with 3-node HA cluster

**Implementation Notes:**
- PgCat uses CloudNativePG's read-only service (`transaction-db-r`)
- Health checks prevent routing to unhealthy replicas
- Primary can never be banned (safety feature)
- Ban time: 60s (configurable via `ban_time`)

---

## Monitoring Strategies

### PgBouncer Monitoring

**Current State:** No monitoring configured

**Options:**
1. **Admin Database** (Available):
   ```sql
   -- Connect to admin database
   psql -h auth-db-pooler.auth.svc.cluster.local -p 5432 -U pooler -d pgbouncer
   
   -- Show pool statistics
   SHOW POOLS;
   SHOW STATS;
   SHOW DATABASES;
   SHOW CLIENTS;
   ```

2. **Prometheus Exporter** (Not available):
   - PgBouncer doesn't have built-in Prometheus metrics
   - Would need external exporter (e.g., `pgbouncer_exporter`)
   - Not recommended for Zalando sidecar (adds complexity)

**Recommendation:** Use admin database for manual checks, focus monitoring on PostgreSQL metrics (already configured)

### PgCat Monitoring

**Current State:** HTTP metrics endpoint available but not configured

**Available Metrics:**
- **HTTP Endpoint**: `http://pgcat.cart.svc.cluster.local:9930/metrics`
- **Prometheus Format**: Standard Prometheus metrics
- **Key Metrics**:
  - `pgcat_pools_active_connections` - Active connections per pool
  - `pgcat_pools_waiting_clients` - Clients waiting for connections
  - `pgcat_servers_health` - Server health status
  - `pgcat_queries_total` - Total queries processed
  - `pgcat_errors_total` - Error count

**Configuration Pattern:**
```yaml
# ServiceMonitor for PgCat
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgcat-transaction
  namespace: cart
spec:
  selector:
    matchLabels:
      app: pgcat-transaction
  endpoints:
  - port: metrics  # Port 9930 (admin port) serves both admin interface and Prometheus metrics endpoint
    interval: 15s
    path: /metrics
```

**Admin Database:**
```sql
-- Connect to admin database (port 9930)
psql -h pgcat.cart.svc.cluster.local -p 9930 -U admin -d pgbouncer

-- Show statistics (PgBouncer-compatible)
SHOW POOLS;
SHOW STATS;
```

**Recommendation:** 
- ✅ **Add ServiceMonitor** for Prometheus scraping
- ✅ **Use admin database** for manual troubleshooting
- ✅ **Create Grafana dashboard** for pooler metrics

### PgDog Monitoring

**Current State:** OpenMetrics endpoint available via Helm chart configuration

**Available Metrics:**
- **HTTP Endpoint**: `http://pgdog-supporting.user.svc.cluster.local:9090/metrics` (configurable via Helm `openMetricsPort`)
- **OpenMetrics Format**: Prometheus-compatible metrics
- **Key Metrics**:
  - `pgdog_pools_active_connections` - Active connections per pool
  - `pgdog_pools_waiting_clients` - Clients waiting for connections
  - `pgdog_servers_health` - Server health status (per database)
  - `pgdog_queries_total` - Total queries processed (by database)
  - `pgdog_errors_total` - Error count (by database and error type)
  - `pgdog_query_duration_seconds` - Query latency histogram
  - `pgdog_pool_utilization` - Pool utilization percentage

**Helm Chart Configuration:**
```yaml
# kubernetes/infra/configs/databases/poolers/supporting/values.yaml
openMetricsPort: 9090  # Prometheus metrics port
openMetricsNamespace: "pgdog_"  # Metric name prefix

# Enable ServiceMonitor
serviceMonitor:
  enabled: true
  interval: 15s
  scrapeTimeout: 10s
```

**ServiceMonitor Configuration (Auto-generated by Helm):**
```yaml
# Automatically created by Helm chart when serviceMonitor.enabled: true
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgdog-supporting
  namespace: user
  labels:
    app: pgdog-supporting
spec:
  selector:
    matchLabels:
      app: pgdog-supporting
  endpoints:
  - port: metrics  # Service port name (mapped to openMetricsPort)
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
```

**Manual ServiceMonitor (if Helm doesn't create):**
```yaml
# kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgdog-supporting
  namespace: user
spec:
  selector:
    matchLabels:
      app: pgdog-supporting
  endpoints:
  - port: metrics
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
```

**Admin Database:**
```sql
-- Connect to admin database (PostgreSQL port 6432)
psql -h pgdog-supporting.user.svc.cluster.local -p 6432 -U admin -d pgbouncer

-- Show pool statistics (PgBouncer-compatible)
SHOW POOLS;  # Active connections per pool
SHOW STATS;  # Query statistics
SHOW DATABASES;  # Configured databases
SHOW CLIENTS;  # Active client connections

-- PgDog-specific commands
SHOW QUERY_CACHE;  # Query routing decisions (for sharding)
SHOW SERVERS;  # Backend server status
```

**Grafana Dashboard:**
- **Metrics to Visualize**:
  - Connection pool utilization (active/max connections)
  - Query rate and latency (P50, P95, P99)
  - Error rate by database
  - Waiting clients (pool exhaustion indicator)
  - Server health status
- **Recommended Panels**:
  - Pool utilization per database (user, notification, shipping)
  - Query latency histogram
  - Error rate trend
  - Connection pool exhaustion alerts

**Alerting Thresholds:**
- **Critical**:
  - Pool exhaustion: `pgdog_pools_waiting_clients > 10` for >30s
  - High error rate: `rate(pgdog_errors_total[5m]) > 0.01` (1% of queries)
  - Server down: `pgdog_servers_health == 0` for >1m
- **Warning**:
  - High pool utilization: `pgdog_pool_utilization > 0.8` (80%)
  - High latency: `histogram_quantile(0.95, pgdog_query_duration_seconds) > 0.1` (100ms P95)

**Recommendation:** 
- ✅ **Enable ServiceMonitor** via Helm chart (`serviceMonitor.enabled: true`)
- ✅ **Configure OpenMetrics port** in Helm values (`openMetricsPort: 9090`)
- ✅ **Create Grafana dashboard** for pooler metrics visualization
- ✅ **Set up alerts** for pool exhaustion and high error rates
- ✅ **Use admin database** for manual troubleshooting and query routing inspection
- ✅ **Monitor per-database metrics** (user, notification, shipping) separately

---

## Real-World Use Cases: Microservices with Separate Databases

### Microservices Architecture Pattern

**Common Pattern:**
- Each microservice has its own database (database-per-service pattern)
- Services scale independently
- Connection pooling critical for high-traffic services
- Need for read scaling and failover

### PgBouncer Use Cases

**Companies/Scenarios:**
1. **GitHub** - Uses PgBouncer for connection pooling in their PostgreSQL infrastructure
2. **Heroku** - Built-in PgBouncer for all PostgreSQL databases
3. **Zalando** - Uses PgBouncer as sidecar in their Postgres Operator
4. **Small-to-medium microservices** - Simple pooling needs, low connection counts

**Characteristics:**
- 10-50 microservices
- Each service: <50 concurrent connections
- Simple transaction pooling sufficient
- No read replica routing needed
- Zalando operator integration preferred

### PgCat Use Cases

**Companies/Scenarios:**
1. **PostgresML** - Developed PgCat for their ML workloads
2. **High-traffic microservices** - Services with >50 concurrent connections
3. **Multi-database clusters** - Services sharing database clusters (cart + order)
4. **Read-heavy workloads** - Need read replica load balancing

**Characteristics:**
- 50-200 microservices
- Each service: 50-200 concurrent connections
- Need read replica routing
- Multi-database support required
- CloudNativePG operator integration

### PgDog Use Cases

**Companies/Scenarios:**
1. **Large-scale microservices** - 200+ microservices
2. **Sharding requirements** - Need horizontal scaling via sharding
3. **Enterprise workloads** - Two-phase commit, cross-shard transactions
4. **Pub/Sub requirements** - Need LISTEN/NOTIFY support
5. **Service discovery** - Multi-instance deployments with automatic discovery

**Characteristics:**
- 200+ microservices
- Each service: 100-1000+ concurrent connections
- Sharding required for scale
- Two-phase commit for distributed transactions
- Advanced features needed (pub/sub, service discovery)

### Decision Matrix for Microservices

| Scenario | Recommended Pooler | Reason |
|----------|-------------------|--------|
| **<10 microservices, <50 conn/service** | PgBouncer | Simple, proven, low overhead |
| **10-50 microservices, 50-100 conn/service** | PgCat | Good balance, read routing, failover |
| **50-200 microservices, 100-500 conn/service** | PgCat or PgDog | PgCat if no sharding, PgDog if sharding needed |
| **200+ microservices, 500+ conn/service, sharding** | PgDog | Advanced sharding, two-phase commit |
| **Zalando operator** | PgBouncer | Built-in integration |
| **CloudNativePG operator** | PgCat or PgDog | Standalone deployment, choose based on features |
| **Need pub/sub (LISTEN/NOTIFY)** | PgDog | Only pooler with full support |
| **Need two-phase commit** | PgDog | Only pooler with production-grade support |
| **Database-per-service, no sharding** | PgCat | Good balance of features and simplicity |
| **Database-per-service, with sharding** | PgDog | Production-grade sharding support |

### Microservices Configuration Patterns

**Pattern 1: One Pooler Per Service (Database-Per-Service)**
- Each microservice has its own database and pooler instance
- **PgBouncer**: Sidecar per PostgreSQL pod (Zalando)
- **PgCat/PgDog**: Standalone deployment per service
- **Pros**: Isolation, independent scaling
- **Cons**: More resources, more management

**Pattern 2: Shared Pooler (Multi-Database)**
- Multiple services share a database cluster, pooler routes by database name
- **PgCat/PgDog**: Single pooler instance with multiple database pools
- **Example**: Cart + Order services share transaction-db cluster
- **Pros**: Resource efficiency, shared HA
- **Cons**: Coupling, shared failure domain

**Pattern 3: Sharded Services (PgDog)**
- Large services sharded across multiple databases
- **PgDog**: Automatic sharding with two-phase commit
- **Use Case**: Very high-traffic services (1000+ conn/service)
- **Pros**: Horizontal scaling, performance
- **Cons**: Complexity, cross-shard transaction overhead

---

## DevOps/SRE Production Considerations

### Production Deployment Patterns

#### PgBouncer Deployment
- **Pattern**: Sidecar (Zalando) or standalone
- **Replicas**: Match PostgreSQL instances (sidecar) or 2 replicas (standalone)
- **Resources**: CPU: 100m, Memory: 128Mi (minimal)
- **High Availability**: Via PostgreSQL HA (Patroni)
- **Upgrade Strategy**: Rolling restart with PostgreSQL pods

#### PgCat Deployment
- **Pattern**: Standalone Deployment
- **Replicas**: 2 (for HA, independent of PostgreSQL)
- **Resources**: CPU: 100m-500m, Memory: 256Mi-512Mi
- **High Availability**: Independent HA, can survive PostgreSQL restarts
- **Upgrade Strategy**: Rolling update, zero-downtime possible

#### PgDog Deployment
- **Pattern**: Standalone Deployment
- **Replicas**: 2+ (with service discovery for multi-instance)
- **Resources**: CPU: 200m-1000m, Memory: 512Mi-1Gi (higher for sharding)
- **High Availability**: Independent HA, service discovery for coordination
- **Upgrade Strategy**: Rolling update, zero-downtime, canary deployments

### Monitoring & Observability

#### Key Metrics to Monitor

**All Poolers:**
- Active connections (client and server)
- Waiting clients (connection pool exhaustion)
- Query rate and latency
- Error rate
- Pool utilization

**PgCat/PgDog Specific:**
- Read/write query split ratio
- Replica health status
- Failover events
- Shard distribution (PgDog)

#### Alerting Thresholds

**Critical Alerts:**
- Pool exhaustion: Waiting clients > 10 for >30s
- High error rate: Error rate > 1% of queries
- Replica failures: All replicas unhealthy
- Connection failures: >5% connection failures

**Warning Alerts:**
- High pool utilization: >80% pool size
- High latency: P95 latency >100ms
- Replica lag: >1s replication lag

### Troubleshooting Guide

#### Common Issues

**1. Connection Pool Exhaustion**
- **Symptoms**: Waiting clients, slow queries
- **PgBouncer**: Increase `default_pool_size`, check `max_client_conn`
- **PgCat/PgDog**: Increase `pool_size` in TOML config
- **Root Cause**: Too many client connections, pool too small

**2. High Latency**
- **Symptoms**: Slow query response times
- **Check**: PostgreSQL performance, network latency, pooler overhead
- **PgBouncer**: Single-threaded bottleneck (consider PgCat/PgDog)
- **PgCat/PgDog**: Check worker threads, CPU utilization

**3. Replica Routing Not Working**
- **Symptoms**: All queries go to primary
- **PgCat**: Check replica servers in TOML, verify health checks
- **PgDog**: Check `read_write_split` configuration, replica health
- **Verify**: Replica services are healthy, DNS resolution works

**4. Failover Not Triggering**
- **Symptoms**: Queries fail when replica down
- **Check**: Health check configuration, ban_timeout settings
- **PgCat**: Verify `ban_time` in config
- **PgDog**: Check `ban_timeout` and health check intervals

### Performance Tuning

#### PgBouncer Tuning
- **Pool Size**: 25-50% of PostgreSQL max_connections
- **Client Connections**: Set `max_client_conn` to expected peak
- **Idle Timeout**: 60s default, adjust based on connection patterns

#### PgCat Tuning
- **Pool Size**: 30-50 per database (our current: 30-50)
- **Workers**: Default 2, increase for high connection counts
- **Ban Time**: 60s default, reduce for faster failover (trade-off: false positives)

#### PgDog Tuning
- **Workers**: 2 per virtual CPU (default: 2), adjust for workload type
- **Pool Size**: Keep below PostgreSQL max_connections (recommendation: 25-50%)
- **Read/Write Split**: Configure based on read/write ratio
- **Health Checks**: Adjust intervals based on network stability
- **Sharding**: Use `dry_run` mode to test before enabling

### Cost Considerations

**Resource Usage Comparison:**
- **PgBouncer**: Lowest (2-5MB memory, single core)
- **PgCat**: Low (10-20MB memory, multi-core efficient)
- **PgDog**: Low-Medium (10-20MB memory, multi-core, higher for sharding features)

**Operational Cost:**
- **PgBouncer**: Lowest (simple, proven, minimal maintenance)
- **PgCat**: Low (standalone deployment, moderate complexity)
- **PgDog**: Medium (advanced features, more configuration, potential sharding complexity)

**Total Cost of Ownership:**
- **PgBouncer**: Lowest TCO for simple use cases
- **PgCat**: Low TCO, good ROI for HA and read routing
- **PgDog**: Higher TCO, but necessary for sharding requirements

---

## Recommendations

### Primary Recommendation

**Keep Current Architecture with Enhancements:**

1. **PgBouncer (Auth DB)** - **Keep as-is**
   - ✅ Zalando built-in integration works well
   - ✅ Low connection count (<50) is ideal
   - ✅ Transaction pooling matches use case
   - ✅ No changes needed

2. **PgCat (Transaction DB)** - **Enhance with HA**
   - ✅ Add replica servers to TOML config
   - ✅ Enable automatic read routing
   - ✅ Configure failover (already built-in)
   - ✅ Add ServiceMonitor for Prometheus metrics

3. **PgDog (supporting-db)** - **Add Pooler**
   - ✅ Deploy PgDog via Helm chart for multi-database support
   - ✅ Route to 3 databases (user, notification, shipping) on Zalando cluster
   - ✅ Enable ServiceMonitor for OpenMetrics scraping
   - ✅ Configure connection pooling (30 conn for user, 20 each for notification/shipping)
   - ✅ **Why PgDog**: Multi-database support, prepared statements, future-proof features

4. **Monitoring** - **Add Pooler Monitoring**
   - ✅ Create ServiceMonitor for PgCat HTTP metrics (Transaction DB)
   - ✅ Enable ServiceMonitor for PgDog OpenMetrics (supporting-db)
   - ✅ Create Grafana dashboards for pooler metrics
   - ✅ Set up alerts for pool exhaustion and high error rates
   - ✅ Use admin databases for manual troubleshooting
   - ✅ Focus PostgreSQL monitoring on database metrics (already done)

### Alternative Approach

**If PgBouncer monitoring is critical:**
- Deploy `pgbouncer_exporter` as sidecar (adds complexity)
- Use admin database queries via cron job
- **Not recommended**: Adds overhead for minimal benefit

---

## Open Questions

1. **PgCat HA Integration**: Should we configure read replica routing now or wait for higher read load?
   - **Answer**: Configure now for production-ready setup, even if read load is low

2. **Monitoring Priority**: Is PgCat monitoring critical or can we rely on PostgreSQL metrics?
   - **Answer**: Add PgCat monitoring for complete observability, but PostgreSQL metrics are primary

3. **PgBouncer Monitoring**: Is admin database sufficient or do we need Prometheus metrics?
   - **Answer**: Admin database is sufficient for Zalando sidecar, focus on PostgreSQL metrics

---

## Next Steps

1. ✅ **Research Complete** - Document findings
2. **Specification** - Define HA integration requirements for PgCat
3. **Implementation** - Add replica servers to PgCat config, create ServiceMonitor
4. **Documentation** - Update DATABASE.md with comparison table and HA integration guide

---

## Comparison Table for Documentation

**Note:** This section is ready to be added to `docs/guides/DATABASE.md` after the "PgCat Standalone" section (around line 453).

### Connection Pooler Comparison

#### When to Use Each Pooler

| Pooler | Use Case | Operator | Architecture | Best For |
|--------|----------|----------|--------------|----------|
| **PgBouncer** | Built-in sidecar | Zalando | Single-threaded (C) | Low-to-medium connections (<50), simple pooling |
| **PgCat** | Standalone deployment | CloudNativePG | Multi-threaded (Rust) | High connections (>50), load balancing, failover |

#### Feature Comparison

| Feature | PgBouncer | PgCat |
|---------|-----------|-------|
| **Pooling Modes** | Session, Transaction, Statement | Session, Transaction |
| **Load Balancing** | ❌ No | ✅ Yes (read replicas) |
| **Automatic Failover** | ❌ No | ✅ Yes (health checks) |
| **Query Parsing** | ❌ No | ✅ Yes (SQL parser) |
| **Sharding** | ❌ No | ✅ Yes (experimental) |
| **Multi-Database** | ⚠️ Limited | ✅ Full support |
| **Monitoring** | Admin DB only | Prometheus + Admin DB |
| **Performance (<50 conn)** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐ Very Good |
| **Performance (>50 conn)** | ⭐⭐ Degrades | ⭐⭐⭐⭐⭐ Excellent |
| **Resource Usage** | Very Low (2-5MB) | Low (10-20MB) |
| **Maturity** | 15+ years | 2-3 years |

#### Why Use Connection Poolers?

**Problem Solved:**
- PostgreSQL has limited connections (`max_connections` typically 100-200)
- Each connection consumes ~10MB memory
- Opening/closing connections is expensive (network overhead)
- High connection churn causes performance degradation

**Benefits:**
- ✅ **Reduce Connection Overhead**: Reuse connections instead of creating new ones
- ✅ **Lower Memory Usage**: Fewer PostgreSQL connections = less memory
- ✅ **Better Performance**: Faster connection establishment (from pool)
- ✅ **Connection Limits**: Handle 1000+ client connections with 25-50 PostgreSQL connections

#### When to Use Each Pooler

**Use PgBouncer when:**
- ✅ Using Zalando operator (built-in integration)
- ✅ Low-to-medium connection counts (<50 concurrent)
- ✅ Simple pooling needs (no load balancing, sharding)
- ✅ Mature, stable requirements

**Use PgCat when:**
- ✅ Using CloudNativePG operator (standalone deployment)
- ✅ High connection counts (>50 concurrent)
- ✅ Need read replica load balancing
- ✅ Need automatic failover
- ✅ Multi-database routing (cart + order)

#### Monitoring

**PgBouncer:**
- Admin database: `psql -h auth-db-pooler.auth.svc.cluster.local -U pooler -d pgbouncer`
- Commands: `SHOW POOLS`, `SHOW STATS`, `SHOW CLIENTS`
- No Prometheus metrics (admin DB only)

**PgCat:**
- Prometheus metrics: `http://pgcat.cart.svc.cluster.local:9930/metrics`
- Admin database: `psql -h pgcat.cart.svc.cluster.local -p 9930 -U admin -d pgbouncer`
- ServiceMonitor: Can be configured for Prometheus scraping

**PgDog:**
- OpenMetrics: `http://pgdog.service.svc.cluster.local:{openmetrics_port}/metrics` (configurable port)
- Admin database: `psql -h pgdog.service.svc.cluster.local -p 6432 -U admin -d pgbouncer`
- ServiceMonitor: Can be configured for OpenMetrics scraping
- Query cache: `SHOW QUERY_CACHE` for sharding routing decisions

---

## Changelog

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.2 | 2026-01-13 | [REFINED] Added PgDog implementation for supporting-db, expanded monitoring section with Helm chart config, added sharding vs pooling use-case explanation, updated recommendations | System |
| 1.1 | 2026-01-02 | [REFINED] Added PgDog research, expanded comparison to 3 poolers, added real-world use cases and DevOps/SRE analysis | System |
| 1.0 | 2025-12-30 | Initial research: PgBouncer and PgCat comparison | System |

---

*Research completed with SDD 2.0, refined 2026-01-02*
