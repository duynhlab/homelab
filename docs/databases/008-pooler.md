# Connection Poolers Deep Dive

This document provides a detailed analysis of the connection pooling strategies used in the platform, including architecture, trade-offs, and configuration details for **PgBouncer**, **PgCat**, and **PgDog**. **PgCat is not deployed for CloudNativePG:** **PgDog** fronts `cnpg-db` and pools **product**, **cart**, and **order** (all three databases on one CNPG cluster). PgCat remains here for comparison with PgDog and for generic Rust-router patterns.

## 1. Why Connection Pooling?

PostgreSQL uses a **process-based model** where each connection spawns a new OS process. This consumes significant memory (approx. 10MB per connection) and CPU for context switching.

**Without Pooling:**
- **High Resource Usage**: 1000 microservice pods = 1000 Postgres processes -> ~10GB RAM just for connections.
- **Connection Latency**: Establishing a new TCP + SSL + Auth connection is slow (~10-30ms).
- **Database Overload**: Too many active connections can bring down the database.

**With Pooling:**
- **Multiplexing**: Thousands of client connections share a small number of server connections (e.g., 50).
- **Reuse**: Connections are kept open and reused (0ms setup time).
- **Protection**: Limits max load on the database server.

---

## 2. Pooler Implementations Comparison

| Feature | **PgBouncer** | **PgCat** | **PgDog** |
| :--- | :--- | :--- | :--- |
| **Type** | Proxy / Sidecar | Proxy / Router | Proxy / Router |
| **Language** | C (Single-threaded) | Rust (Multi-threaded) | Rust (Multi-threaded) |
| **Architecture** | Event-driven, very lightweight | Async I/O (Tokio), modern | Async I/O (Tokio), modern |
| **Query Routing** | No (Single DB) | **Yes** (Read/Write, Sharding) | **Yes** (Read/Write, Sharding) |
| **Load Balancing** | No | **Yes** (Replica spreading) | **Yes** (Replica spreading) |
| **Pool Modes** | Session, Transaction, Statement | Session, Transaction | Session, Transaction |
| **Deployment** | Sidecar (Zalando) | Standalone Deployment | Standalone Helm Chart |
| **Maturity** | Very High (Standard) | High (PostgresML maintained) | Moderate/New |
| **Used In** | `auth-db`, `supporting-shared-db` | Not used in this platform (see §3.2) | `cnpg-db` (product, cart, order) |

### Current implementation

| Cluster(s) | Pooler | Scope |
| :--- | :--- | :--- |
| `auth-db`, `supporting-shared-db` | PgBouncer (Zalando sidecar) | Per Zalando cluster |
| `cnpg-db` | PgDog (Helm) | **product**, **cart**, and **order** databases on the unified CNPG primary |

---

## 3. Deep Dive by Cluster

### 3.1. PgBouncer (Sidecar)
**Used by**: `auth-db`, `supporting-shared-db` (Zalando Postgres Operator)

**Architecture:**
- **Sidecar Pattern**: Deployed tightly coupled with the PostgreSQL pod.
- **Communication**: Application -> K8s Service (`-pooler`) -> PgBouncer Pod -> Localhost `5432`.
- **High Availability**: 2 replicas by default (stateless).

**Trade-offs:**
- ✅ **Pros**:
    - **Battle-tested**: Industry standard, extremely stable.
    - **Integrated**: Managed automatically by Zalando Operator.
    - **Low Latency**: Very minimal overhead.
- ❌ **Cons**:
    - **Single-Threaded**: Can become a bottleneck on very high throughput (though rarely an issue for sidecars).
    - **No Routing**: Cannot route "read" queries to replicas automatically; strictly 1-to-1 mapping.
    - **No Sharding**: Doesn't support horizontal partitioning logic.

**Configuration (Zalando):**
- **Mode**: `transaction` (Connection returned to pool after transaction commit).
- **Resources**: `50m` CPU, `64Mi` RAM (Very lightweight).
- **Max Connections**: Clamped to avoid OOM.

---

### 3.2. PgCat (Standalone / Router)
**Used by**: **Not used for CloudNativePG in this platform.** CNPG workloads previously split across separate clusters now run on a single primary cluster (`cnpg-db`); **PgDog** handles connection pooling and routing for **product**, **cart**, and **order** databases (see §3.3). PgCat remains documented here for comparison with PgDog and for teams evaluating Rust-based routers.

**Architecture (reference):**
- **Standalone Deployment**: Typical pattern is a separate Deployment (e.g. per namespace).
- **Routing Logic**: Parses SQL queries to detect `SELECT` vs `INSERT/UPDATE`.
- **Topology Awareness**: Routes writes to Primary (`-rw`), reads to Replicas (`-r`).

**Trade-offs:**
- ✅ **Pros**:
    - **Read/Write Splitting**: Offloads read traffic to replicas automatically without app code changes.
    - **Multi-Database**: Can serve multiple DBs (`cart`, `order`) from one pooler cluster.
    - **Rust-based**: Multi-threaded, handles high concurrency better than PgBouncer.
    - **Sharding Capable**: Supports sharding logic (future proofing).
- ❌ **Cons**:
    - **Complexity**: Configuration (`pgcat.toml`) is more complex.
    - **Parsing Overhead**: Minimal, but parsing every query adds non-zero CPU cost.
    - **Maturity**: Newer than PgBouncer, though stable.

**Configuration:**
- **Replicas**: 2 (HA).
- **Strategy**: `query_parser_read_write_splitting = true`.
- **Health Checks**: Actively monitors backend health.

---

### 3.3. PgDog (Standalone / Router)
**Used by**: `cnpg-db` — **all three** application databases (**product**, **cart**, **order**). PgDog replaces PgCat for CNPG: one pooler tier serves the unified cluster instead of a separate PgCat deployment per old cluster layout.

**Architecture:**
- **Helm Chart**: Deployed via `pgdog` Helm chart.
- **Technology**: Built on similar tech to PgCat (Rust/Tokio).
- **Function**: Connection pooling + read/write routing for the CNPG backends that host product, cart, and order data.

**Trade-offs:**
- ✅ **Pros**:
    - **Modern Stack**: Rust memory safety and performance.
    - **Helm Managed**: Easy deployment via standard chart.
- ❌ **Cons**:
    - **Young Project**: Less community documentation than PgBouncer.
    - **Feature Overlap**: Very similar to PgCat; selected here to demonstrate/evaluate CloudNativePG integration patterns.

---

## 4. Pool Modes Explained

### 4.1. Transaction Mode (Used Everywhere)
- **Behavior**: Server connection is assigned to client **only for the duration of a transaction**.
- **When released**: On `COMMIT` or `ROLLBACK`.
- **Benefit**: Massive multiplexing. 1000 clients can share 50 DB connections if they are mostly idle or doing short ops.
- **Caveat**: **Prepared Statements** specific handling is required (supported by newer poolers or protocol-level catchers). Session-based features (e.g. `SET session_var = 'x'`) are reset or unsafe.

### 4.2. Session Mode (Not Used)
- **Behavior**: Server connection assigned for the **entire lifetime** of the client connection.
- **Benefit**: Full compatibility (Prepared statements, TEMPORARY tables work out of the box).
- **Drawback**: No multiplexing benefit. If you have 1000 client pods, you need 1000 DB connections. **Avoid for microservices.**

### 4.3. Statement Mode
- **Behavior**: Connection returned after every *statement*.
- **Caveat**: Breaks multi-statement transactions (`BEGIN; ...; COMMIT;` would run on different connections). **Dangerous for general use.**

---

## 5. Decision Matrix: Which one to choose?

| Requirement | Recommendation | Reason |
| :--- | :--- | :--- |
| **Simple / Standard** | **PgBouncer** | "Just works", minimal config, industry standard. |
| **High Read Traffic** | **PgDog** (CNPG) / **PgCat** (generic) | PgDog routes CNPG traffic; PgCat-style parsers can split reads to replicas when enabled. |
| **Sharding** | **PgCat** (generic) | Built-in sharding logic; not required for current `cnpg-db` layout. |
| **Extreme Concurrency** | **PgDog** | Multi-threaded Rust pooler for `cnpg-db` (product / cart / order). |
