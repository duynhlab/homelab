# Connection Poolers Deep Dive

This document provides a detailed analysis of the connection pooling strategies used in the platform, including architecture, trade-offs, and configuration details for **PgBouncer** and **PgDog**. **Two poolers are deployed, one per cluster (ADR-026 pilot):**

- **`platform-db` → CNPG-native PgBouncer** (`Pooler` `platform-db-pooler-rw`, `type: rw`, pooling **auth**, **user**, **notification**, **shipping**, **review** — Temporal connects direct past it). Operator-managed `auth_query` auth; single `rw` endpoint (no read-split in the pilot). Port **5432** (not PgDog's 6432). See [ADR-026](../proposals/adr/ADR-026-platform-db-pgbouncer-pilot/).
- **`product-db` → PgDog** (Helm release `pgdog-product`, pooling **product**, **cart**, **order** — the payment *app* connects direct over TLS, bypassing the pooler). Read/write split + replica load-balancing on port **6432**.

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

| Feature | **PgBouncer** | **PgDog** |
| :--- | :--- | :--- |
| **Type** | Proxy / sidecar or CNPG `Pooler` CR | Proxy / router (Helm) |
| **Language** | C (Single-threaded) | Rust (Multi-threaded) |
| **Architecture** | Event-driven, very lightweight | Async I/O (Tokio), modern |
| **Query Routing** | No (single DB / rw endpoint) | **Yes** (read/write, sharding) |
| **Load Balancing** | No | **Yes** (replica spreading) |
| **Pool Modes** | Session, Transaction, Statement | Session, Transaction |
| **Deployment** | CNPG `Pooler` CR (platform-db) | Standalone Helm chart (product-db) |
| **Maturity** | Very High (industry standard) | Moderate / newer |
| **Used In** | `platform-db` (`platform-db-pooler-rw`) | `product-db` (`pgdog-product`) |

### Current implementation

| Pooler | Cluster | Endpoint | Scope |
| :--- | :--- | :--- | :--- |
| **PgBouncer** (`Pooler` CR) | `platform-db` | `platform-db-pooler-rw.platform.svc:5432` | auth, user, notification, shipping, review (Temporal: direct to `platform-db-rw`) |
| **PgDog** (Helm) | `product-db` | `pgdog-product.product.svc:6432` | product, cart, order (payment app: direct-TLS) |

---

## 3. Deep Dive by Pooler

### 3.1. PgBouncer (CNPG `Pooler` — platform-db)

**Used by**: **`platform-db`** via the CNPG-native `Pooler` resource `platform-db-pooler-rw` (ADR-026 pilot). Replaced the earlier PgDog Helm release for this cluster only.

**Architecture:**
- **Operator-managed**: CloudNativePG provisions PgBouncer auth (`auth_query`, TLS client cert to cluster).
- **Communication**: Application → `platform-db-pooler-rw` Service → PgBouncer pods → `platform-db-rw`.
- **High Availability**: 2 pooler instances (stateless).

**Trade-offs:**
- ✅ **Pros**:
    - **Battle-tested**: Industry standard, extremely stable.
    - **Integrated**: First-party CNPG `Pooler` CR — no separate Helm chart.
    - **Low Latency**: Very minimal overhead.
- ❌ **Cons**:
    - **Single-Threaded**: Can become a bottleneck on very high throughput.
    - **No Routing**: Pilot uses `type: rw` only — no automatic read replica splitting.
    - **No Sharding**: Doesn't support horizontal partitioning logic.

**Configuration:**
- **Mode**: `transaction` (connection returned to pool after transaction commit).
- **Resources**: `50m` CPU, `64Mi` RAM (lightweight).
- **Max client connections**: 1000; default pool size 30.

---

### 3.2. PgDog (Standalone / Router — product-db)

**Used by**: **`product-db`** via Helm release `pgdog-product` (product, cart, order — payment app connects direct-TLS, bypassing PgDog).

**Architecture:**
- **Helm Chart**: Deployed via `pgdog` Helm chart.
- **Function**: Connection pooling + read/write routing for CNPG `-rw` / `-r` services.

**Trade-offs:**
- ✅ **Pros**:
    - **Modern Stack**: Rust memory safety and performance.
    - **Helm Managed**: Easy deployment via standard chart.
    - **Read/Write Splitting**: Offloads read traffic to replicas without app changes.
    - **Multi-Database**: One pooler fronts product, cart, and order.
    - **High Availability**: 3 replicas with PDB (`minAvailable: 2`).
- ❌ **Cons**:
    - **Young Project**: Less community documentation than PgBouncer.
    - **More Configuration**: Chart values for per-database pools and replica hosts.

**Day-2 ops:** [pgdog-operations.md](./runbooks/pgdog-operations.md)

---

## 4. Pool Modes Explained

### 4.1. Transaction Mode (Used Everywhere)
- **Behavior**: Server connection is assigned to client **only for the duration of a transaction**.
- **When released**: On `COMMIT` or `ROLLBACK`.
- **Benefit**: Massive multiplexing. 1000 clients can share 50 DB connections if they are mostly idle or doing short ops.
- **Caveat**: **Prepared Statements** require driver/pooler-aware configuration (see [002-database-integration.md](./002-database-integration.md#go-postgresql-driver-pgx)). Session-based features (e.g. `SET session_var = 'x'`) are reset or unsafe.

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
| **Simple / Standard** | **PgBouncer** | Minimal config, industry standard, CNPG-native on `platform-db`. |
| **High Read Traffic** | **PgDog** | Read/write splitting and replica load-balancing on `product-db`. |
| **Multi-DB routing on one cluster** | **PgDog** | Single Helm release fronts product, cart, order. |
| **Extreme Concurrency (Rust pooler)** | **PgDog** | Multi-threaded pooler for `product-db`. |

---

_Last updated: 2026-07-21 — Aligned with ADR-026 (platform-db PgBouncer, product-db PgDog)._
