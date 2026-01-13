# Specification: Connection Poolers Deep Dive - PgCat HA & PgDog for supporting-db

**Task ID:** connection-poolers-deepdive
**Created:** 2025-12-30
**Status:** Ready for Planning
**Version:** 2.0

---

## 1. Problem Statement

### The Problem

This specification addresses two connection pooler improvements:

**Problem 1: PgCat HA Integration for Transaction Database**

The current PgCat configuration for the transaction-db cluster (3-node HA: 1 primary + 2 replicas) only routes all queries to the primary server. This creates several production-readiness gaps:

1. **Unused Replica Capacity**: Two synchronous replicas are available but not utilized for read queries
2. **No Read Load Distribution**: All read queries hit the primary, limiting throughput and increasing primary load
3. **No Automatic Failover**: If a replica fails, there's no automatic routing adjustment
4. **No Pooler Monitoring**: PgCat metrics are not exposed to Prometheus, making it impossible to monitor pooler health, connection counts, and query routing

### Current Situation

**Transaction Database Cluster:**
- **Instances**: 3 (1 primary + 2 replicas) with synchronous replication
- **Services**: 
  - `transaction-db-rw.cart.svc.cluster.local` (read-write, primary)
  - `transaction-db-r.cart.svc.cluster.local` (read-only, all replicas)
- **Databases**: `cart` and `order` (multi-database on same cluster)

**Current PgCat Configuration:**
- Only primary server (`transaction-db-rw`) configured in TOML
- No replica servers configured
- No automatic read/write query routing
- No monitoring (ServiceMonitor not configured)
- PgCat HTTP metrics endpoint available but not scraped

**Impact:**
- Read queries cannot scale beyond primary capacity
- Replicas remain idle despite being available
- No visibility into pooler performance
- Manual intervention required if replica issues occur

**Problem 2: supporting-db Missing Connection Pooler**

The supporting-db cluster (Zalando operator, single instance) currently uses direct connections from 3 services (user, notification, shipping). This creates connection management challenges:

1. **No Connection Pooling**: Each service opens direct connections to PostgreSQL, increasing connection overhead
2. **Connection Limit Risk**: As services scale (more replicas), connection count grows (e.g., 10 replicas × 10 conn = 100 connections)
3. **No Multi-Database Routing**: Services must know exact database names and connection strings
4. **No Monitoring**: No pooler metrics for connection health and performance
5. **Future Growth**: No prepared statements support, no advanced features for future needs

**Current Situation:**

**supporting-db Cluster:**
- **Operator**: Zalando Postgres Operator
- **Instances**: 1 (single instance, no HA)
- **Databases**: 3 databases on same cluster (user, notification, shipping)
- **Services**: User service, Notification service, Shipping service (v1 and v2)
- **Connection Pattern**: Direct connection to `supporting-db.user.svc.cluster.local:5432`

**Current Configuration:**
- No connection pooler (direct connections)
- Each service manages its own connection pool (application-level)
- No centralized connection management
- No pooler-level monitoring

**Impact:**
- Connection overhead as services scale
- No connection reuse optimization
- No centralized monitoring
- Limited future-proofing for advanced features

### Desired Outcome

**Outcome 1: Production-Ready PgCat HA Configuration**

A production-ready PgCat configuration that:
- Automatically routes SELECT queries to replicas for read scaling
- Routes writes (INSERT, UPDATE, DELETE, DDL) to primary
- Automatically fails over to primary if replicas become unavailable
- Load balances read queries across 2 replicas
- Provides Prometheus metrics for monitoring and alerting
- Maintains backward compatibility with existing cart/order services
- Works seamlessly with CloudNativePG's 3-node HA cluster

**Outcome 2: PgDog Pooler for supporting-db**

A production-ready PgDog deployment that:
- Provides connection pooling for 3 databases (user, notification, shipping) on Zalando cluster
- Routes connections by database name (multi-database support)
- Supports prepared statements in transaction mode (future-proof)
- Provides OpenMetrics metrics for monitoring
- Deploys via Helm chart with HA (2 replicas)
- Maintains backward compatibility with existing services
- Works seamlessly with Zalando Postgres Operator

---

## 2. User Personas

### Primary User: DevOps/SRE Engineer

- **Who:** Infrastructure engineer responsible for database operations and monitoring
- **Goals:** 
  - Ensure high availability and performance of transaction database
  - Monitor pooler health and connection metrics
  - Automate failover and load balancing
  - Maintain production-ready infrastructure
- **Pain points:** 
  - No visibility into pooler metrics
  - Manual configuration required for failover
  - Cannot verify read load distribution
- **Tech comfort:** High - comfortable with Kubernetes, PostgreSQL, monitoring tools

### Secondary User: Application Developer

- **Who:** Developer working on cart/order services
- **Goals:**
  - Use database without worrying about connection management
  - Experience improved read performance
  - Rely on automatic failover for reliability
- **Pain points:**
  - Unaware of pooler configuration (transparent to application)
  - May experience slow reads if primary is overloaded
- **Tech comfort:** Medium - focuses on application code, not infrastructure

---

## 3. Functional Requirements

### Part A: PgCat HA Integration (Transaction DB)

### FR-1: Read Replica Routing

**Description:** PgCat must automatically route SELECT queries to replica servers while routing write queries (INSERT, UPDATE, DELETE, DDL) to the primary server.

**User Story:**
> As a DevOps/SRE engineer, I want PgCat to automatically route read queries to replicas so that read load is distributed and primary server capacity is preserved for writes.

**Acceptance Criteria:**
- [ ] Given a SELECT query, when PgCat receives it, then it routes to a replica server
- [ ] Given an INSERT/UPDATE/DELETE query, when PgCat receives it, then it routes to the primary server
- [ ] Given a DDL statement (CREATE, ALTER, DROP), when PgCat receives it, then it routes to the primary server
- [ ] Given a transaction with both reads and writes, when PgCat processes it, then writes go to primary and reads can go to replicas
- [ ] Query parser correctly identifies query type (SELECT vs write operations)

**Priority:** Must Have

**Technical Details:**
- Use PgCat's built-in SQL query parser
- Configure replica servers in TOML with `role = "replica"`
- Configure primary server with `role = "primary"`
- Query parser automatically routes based on SQL statement type

---

### FR-2: Automatic Failover

**Description:** PgCat must automatically detect unhealthy replica servers and route queries away from them, falling back to primary if all replicas are unavailable.

**User Story:**
> As a DevOps/SRE engineer, I want PgCat to automatically failover from unhealthy replicas so that read queries continue to work even when replicas fail.

**Acceptance Criteria:**
- [ ] Given a replica server becomes unhealthy, when PgCat detects it, then it bans the server and routes queries to remaining healthy servers
- [ ] Given all replicas are unhealthy, when PgCat detects it, then it routes all queries to primary
- [ ] Given a replica recovers, when PgCat detects it, then it automatically includes it back in the routing pool
- [ ] Given primary server fails, when PgCat detects it, then it never bans primary (safety feature)
- [ ] Health checks run before routing queries to servers
- [ ] Ban time is configurable (default: 60 seconds)

**Priority:** Must Have

**Technical Details:**
- PgCat performs health checks with `;` query before routing
- Unhealthy servers are banned for `ban_time` duration (default: 60s)
- Primary can never be banned (safety feature)
- Automatic recovery when server becomes healthy again

---

### FR-3: Load Balancing Across Replicas

**Description:** PgCat must distribute read queries across available replica servers using load balancing algorithms.

**User Story:**
> As a DevOps/SRE engineer, I want PgCat to load balance read queries across replicas so that read load is evenly distributed and no single replica is overloaded.

**Acceptance Criteria:**
- [ ] Given multiple healthy replicas, when PgCat routes read queries, then queries are distributed across all replicas
- [ ] Given 2 replicas available, when PgCat routes 100 read queries, then queries are approximately evenly split (50/50 distribution)
- [ ] Load balancing algorithm uses least open connections or random selection
- [ ] Load balancing only applies to read queries (SELECT)
- [ ] Write queries always go to primary (no load balancing for writes)

**Priority:** Must Have

**Technical Details:**
- PgCat supports load balancing algorithms: random or least open connections
- Configure via `default_role` setting in TOML
- Load balancing applies only to replicas
- Primary handles all writes regardless of load balancing setting

---

### FR-4: Health Checks

**Description:** PgCat must continuously monitor server health and prevent routing queries to unhealthy servers.

**User Story:**
> As a DevOps/SRE engineer, I want PgCat to perform health checks on servers so that queries are never routed to unhealthy or unreachable servers.

**Acceptance Criteria:**
- [ ] Given a server becomes unreachable, when PgCat performs health check, then it detects the failure and bans the server
- [ ] Given a server returns errors, when PgCat processes queries, then it monitors errors and bans server if threshold exceeded
- [ ] Health checks run before routing queries to servers
- [ ] Health checks use fast query (`;`) to minimize overhead
- [ ] Health check failures are logged for troubleshooting
- [ ] Health check interval is configurable

**Priority:** Must Have

**Technical Details:**
- PgCat performs health checks with `;` query (very fast)
- Health checks run before routing queries
- Server health monitored with every client query
- Unhealthy servers automatically banned
- Health check failures logged in PgCat logs

---

### FR-5: Monitoring Integration

**Description:** PgCat must expose Prometheus metrics via HTTP endpoint and be scraped by Prometheus Operator via ServiceMonitor.

**User Story:**
> As a DevOps/SRE engineer, I want PgCat metrics exposed to Prometheus so that I can monitor pooler health, connection counts, query routing, and failover events.

**Acceptance Criteria:**
- [ ] Given PgCat is running, when Prometheus scrapes metrics, then it can access HTTP endpoint `/metrics` on port 9930
- [ ] Given a ServiceMonitor is configured, when Prometheus Operator reconciles, then it discovers and scrapes PgCat metrics
- [ ] Metrics include: active connections, waiting clients, server health status, query counts, error counts
- [ ] Metrics are labeled with pool name (cart, order), server role (primary, replica)
- [ ] Metrics available in Grafana for visualization
- [ ] ServiceMonitor configured in `k8s/prometheus/servicemonitors/` directory

**Priority:** Must Have

**Technical Details:**
- PgCat exposes metrics on HTTP endpoint: `http://pgcat.cart.svc.cluster.local:9930/metrics`
- Create ServiceMonitor CRD for Prometheus Operator
- ServiceMonitor selects PgCat service via labels
- Metrics format: Prometheus standard format
- Key metrics: `pgcat_pools_active_connections`, `pgcat_pools_waiting_clients`, `pgcat_servers_health`, `pgcat_queries_total`, `pgcat_errors_total`

---

### Part B: PgDog Pooler for supporting-db

### FR-6: PgDog Deployment

**Description:** Deploy PgDog via Helm chart to provide connection pooling for supporting-db cluster with multi-database support.

**User Story:**
> As a DevOps/SRE engineer, I want PgDog deployed for supporting-db so that connection pooling is centralized and services can scale without connection limit issues.

**Acceptance Criteria:**
- [ ] PgDog Helm chart deployed in `user` namespace
- [ ] PgDog configured with 2 replicas (HA)
- [ ] PgDog routes to 3 databases (user, notification, shipping) on supporting-db cluster
- [ ] PgDog service endpoint: `pgdog-supporting.user.svc.cluster.local:6432`
- [ ] PgDog OpenMetrics endpoint: `pgdog-supporting.user.svc.cluster.local:9090/metrics`
- [ ] All 3 databases accessible via PgDog (verified via admin database)

**Priority:** Must Have

**Technical Details:**
- Deploy via Helm chart: `helm.pgdog.dev/pgdog`
- Helm values configure databases, users, and pool settings
- Service type: ClusterIP (internal only)
- Port 6432: PostgreSQL protocol
- Port 9090: OpenMetrics endpoint

---

### FR-7: Multi-Database Routing

**Description:** PgDog must route connections to correct database based on database name in connection string.

**User Story:**
> As an application developer, I want to connect to PgDog with my database name so that queries are routed to the correct database on the shared cluster.

**Acceptance Criteria:**
- [ ] Given connection to `pgdog-supporting:6432/user`, when query executes, then it routes to `user` database
- [ ] Given connection to `pgdog-supporting:6432/notification`, when query executes, then it routes to `notification` database
- [ ] Given connection to `pgdog-supporting:6432/shipping`, when query executes, then it routes to `shipping` database
- [ ] Database routing is transparent to applications (no code changes needed)
- [ ] Each database has its own connection pool (configurable pool size)

**Priority:** Must Have

**Technical Details:**
- PgDog routes by database name in connection string
- Each database configured in Helm values `databases` section
- Pool size configurable per database (30 for user, 20 each for notification/shipping)
- Connection string format: `postgresql://user:pass@pgdog-supporting:6432/database_name`

---

### FR-8: Service Configuration Update

**Description:** Update user, notification, and shipping services to connect via PgDog instead of direct PostgreSQL connection.

**User Story:**
> As a DevOps/SRE engineer, I want services to connect via PgDog so that connection pooling is centralized and connection limits are managed.

**Acceptance Criteria:**
- [ ] User service Helm values updated: `DB_HOST=pgdog-supporting.user.svc.cluster.local`, `DB_PORT=6432`
- [ ] Notification service Helm values updated: `DB_HOST=pgdog-supporting.user.svc.cluster.local`, `DB_PORT=6432`
- [ ] Shipping service Helm values updated: `DB_HOST=pgdog-supporting.user.svc.cluster.local`, `DB_PORT=6432`
- [ ] All services can connect and execute queries successfully
- [ ] No application errors or connection failures
- [ ] Database names unchanged (user, notification, shipping)

**Priority:** Must Have

**Technical Details:**
- Update Helm values files: `charts/values/user.yaml`, `charts/values/notification.yaml`, `charts/values/shipping.yaml`
- Change `DB_HOST` from `supporting-db.user.svc.cluster.local` to `pgdog-supporting.user.svc.cluster.local`
- Change `DB_PORT` from `5432` to `6432` (PgDog port)
- Database names and credentials unchanged
- Apply via Flux HelmRelease reconciliation

---

### FR-9: PgDog Monitoring Integration

**Description:** PgDog must expose OpenMetrics metrics via HTTP endpoint and be scraped by Prometheus Operator via ServiceMonitor.

**User Story:**
> As a DevOps/SRE engineer, I want PgDog metrics exposed to Prometheus so that I can monitor pooler health, connection counts, and query performance.

**Acceptance Criteria:**
- [ ] PgDog OpenMetrics endpoint accessible: `http://pgdog-supporting.user.svc.cluster.local:9090/metrics`
- [ ] ServiceMonitor created and applied for PgDog
- [ ] Prometheus discovers and scrapes PgDog metrics
- [ ] Metrics include: active connections, waiting clients, server health, query counts, error counts
- [ ] Metrics are labeled with database name (user, notification, shipping)
- [ ] Metrics available in Grafana for visualization

**Priority:** Must Have

**Technical Details:**
- Configure `openMetricsPort: 9090` in Helm values
- Enable ServiceMonitor via Helm: `serviceMonitor.enabled: true`
- Or create manual ServiceMonitor: `kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml`
- Key metrics: `pgdog_pools_active_connections`, `pgdog_pools_waiting_clients`, `pgdog_servers_health`, `pgdog_queries_total`, `pgdog_errors_total`
- Metrics namespace: `pgdog_` (configurable)

---

## 4. Non-Functional Requirements

### NFR-1: Performance

- **Query Routing Overhead**: <1ms latency added per query for routing decision
- **Health Check Overhead**: Health checks must use fast query (`;`) with <10ms overhead
- **Connection Pool Efficiency**: Maintain current pool size (30 connections per database) with replica routing
- **Read Throughput**: Read queries should scale linearly with number of healthy replicas (2x throughput with 2 replicas)

### NFR-2: Reliability

- **Failover Time**: Automatic failover from unhealthy replica to primary must complete within 60 seconds (ban_time)
- **Zero Downtime**: Configuration changes (adding replicas) must not cause service interruption
- **Backward Compatibility**: Existing cart/order services must continue working without code changes
- **Primary Safety**: Primary server can never be banned (safety feature to prevent complete outage)

### NFR-3: Compatibility

- **CloudNativePG Integration**: Must work with CloudNativePG services:
  - `transaction-db-rw.cart.svc.cluster.local` (primary)
  - `transaction-db-r.cart.svc.cluster.local` (replicas)
- **Multi-Database Support**: Must support both `cart` and `order` databases on same cluster
- **Kubernetes Native**: All configuration via Kubernetes resources (ConfigMap, ServiceMonitor)
- **No Application Changes**: Application code (cart/order services) requires no modifications

### NFR-4: Observability

- **Metrics Availability**: Prometheus metrics must be available within 30 seconds of PgCat startup
- **Metric Labels**: All metrics must include labels: `pool` (cart/order), `server_role` (primary/replica), `server_host`
- **Logging**: Health check failures and failover events must be logged with appropriate log levels
- **Admin Database**: Admin database (`pgcat` or `pgbouncer`) must remain accessible for manual troubleshooting

### NFR-5: Maintainability

- **Configuration Management**: All configuration in ConfigMap (TOML format) for easy updates
- **Live Reload**: Configuration changes (except host/port) can be reloaded without restart (SIGHUP)
- **Documentation**: Configuration changes must be documented in `docs/guides/DATABASE.md`
- **Deployment Script**: Updates to `scripts/04-deploy-databases.sh` if needed for ServiceMonitor deployment

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

**PgCat HA Integration:**
- ❌ **PgBouncer Changes** - PgBouncer configuration remains unchanged (Zalando operator built-in sidecar)
- ❌ **Product DB PgCat** - Only transaction-db cluster is enhanced (product-db remains as-is)
- ❌ **Sharding** - PgCat sharding features are experimental and not included
- ❌ **Mirroring** - Query mirroring to multiple databases is not needed
- ❌ **Custom Load Balancing Algorithms** - Use PgCat default algorithms (random or least connections)
- ❌ **Connection Pool Size Changes** - Keep current pool sizes (30 per database)

**PgDog supporting-db:**
- ❌ **Sharding** - PgDog sharding features not needed for supporting-db (databases < 10GB each)
- ❌ **HA PostgreSQL** - supporting-db remains single instance (no replicas to route to)
- ❌ **Read/Write Split** - Not applicable (single instance, no replicas)
- ❌ **Two-Phase Commit** - Not needed (no sharding, single database per service)
- ❌ **Pub/Sub Features** - LISTEN/NOTIFY support not required for initial deployment

**General:**
- ❌ **PgBouncer Monitoring** - PgBouncer admin database is sufficient, no Prometheus exporter needed
- ❌ **SSL/TLS Configuration** - Keep current SSL settings (disable for Kind cluster)
- ❌ **review-db Pooler** - review-db remains with direct connection (low traffic, single database)

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **All replicas fail simultaneously** | All queries (reads and writes) route to primary. Primary handles full load. |
| **Primary fails (CloudNativePG failover)** | CloudNativePG promotes replica to primary. PgCat continues routing to new primary via `transaction-db-rw` service. |
| **One replica slow (not failed)** | PgCat health checks may detect slowness. If health check fails, replica is banned. Queries route to remaining healthy replica and primary. |
| **Replica recovers after ban** | PgCat automatically includes replica back in routing pool after ban_time expires. Health checks verify recovery. |
| **Mixed read/write transaction** | Writes go to primary. Reads within same transaction may go to replicas (transaction pooling mode). |
| **DDL statements (CREATE, ALTER, DROP)** | Always route to primary, never to replicas (replicas are read-only). |
| **Explicit transaction with SET SERVER ROLE** | Client can override routing with `SET SERVER ROLE TO 'primary'` or `'replica'`. PgCat respects client preference. |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| **Replica connection timeout** | Logged in PgCat logs | Replica banned, queries routed to primary |
| **Replica returns error** | Logged in PgCat logs | Server health monitored, banned if threshold exceeded |
| **Primary connection timeout** | Logged in PgCat logs | Primary never banned (safety). Queries fail with connection error. |
| **Health check failure** | Logged in PgCat logs | Server banned for ban_time duration |
| **ConfigMap update fails** | Kubernetes error | PgCat continues with previous configuration |
| **ServiceMonitor not discovered** | Prometheus Operator logs | Metrics not scraped, but PgCat continues operating normally |

### Recovery Procedures

| Failure Type | Recovery Action |
|--------------|-----------------|
| **Replica failure** | Automatic: Replica banned, queries route to primary. Manual: Fix replica, wait for ban_time, replica automatically rejoins. |
| **Primary failure (CloudNativePG)** | Automatic: CloudNativePG promotes replica. PgCat continues using `transaction-db-rw` service (points to new primary). |
| **PgCat pod failure** | Kubernetes: Pod restarted automatically. PgCat reconnects to all servers. |
| **ConfigMap misconfiguration** | Manual: Fix ConfigMap, reload PgCat config (SIGHUP) or restart pod. |

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Read Query Distribution** | >80% of SELECT queries routed to replicas | Prometheus: `pgcat_queries_total{query_type="SELECT", server_role="replica"}` / total SELECT queries |
| **Failover Time** | <60 seconds from replica failure to routing adjustment | Prometheus: Time between `pgcat_servers_health{status="unhealthy"}` and query routing change |
| **Load Balance Distribution** | Read queries split 40-60% between 2 replicas | Prometheus: Compare `pgcat_queries_total` per replica server |
| **Primary Write Load** | <50% of total queries (reads offloaded to replicas) | Prometheus: `pgcat_queries_total{server_role="primary"}` / total queries |
| **Metrics Availability** | 100% uptime for metrics endpoint | Prometheus: `up{job="pgcat-transaction"}` = 1 |
| **Connection Pool Utilization** | <80% of pool size (headroom for spikes) | Prometheus: `pgcat_pools_active_connections` / `pgcat_pools_max_connections` |

### Definition of Done

**PgCat HA Integration:**
- [ ] All acceptance criteria met for FR-1 through FR-5
- [ ] Replica servers configured in PgCat TOML for both cart and order databases
- [ ] Read queries automatically route to replicas (verified via logs/metrics)
- [ ] Write queries automatically route to primary (verified via logs/metrics)
- [ ] Automatic failover works when replica fails (tested manually)
- [ ] Load balancing distributes reads across replicas (verified via metrics)
- [ ] ServiceMonitor created and Prometheus scraping PgCat metrics
- [ ] Metrics visible in Grafana (optional but recommended)
- [ ] Backward compatibility verified (cart/order services work without changes)

**PgDog supporting-db:**
- [ ] All acceptance criteria met for FR-6 through FR-9
- [ ] PgDog deployed via Helm chart with 2 replicas (HA)
- [ ] PgDog routes to 3 databases (user, notification, shipping)
- [ ] All 3 services (user, notification, shipping) connect via PgDog
- [ ] ServiceMonitor created and Prometheus scraping PgDog metrics
- [ ] Metrics visible in Grafana (optional but recommended)
- [ ] Backward compatibility verified (all services work without errors)

**Documentation:**
- [ ] Configuration documented in `docs/guides/DATABASE.md`
- [ ] PgDog deployment documented with Helm chart details
- [ ] Edge cases handled (all scenarios in section 6 tested or documented)

---

## 8. Open Questions

- [x] **Load Balancing Algorithm**: Use default "random" algorithm. Configuration will be shown in TOML for reference, but default is sufficient.
- [x] **Ban Time Configuration**: Use default 60 seconds. Can be configured via `ban_time` in TOML if needed, but default is appropriate.
- [x] **Health Check Interval**: Use PgCat default (checks before each query). No additional configuration needed.
- [x] **Grafana Dashboard**: Out of scope for initial implementation. Focus on getting Prometheus metrics working first. Dashboard can be added later if needed.

---

## 9. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 2.0 | 2026-01-13 | [REFINED] Added PgDog pooler for supporting-db (FR-6 through FR-9), expanded scope to include multi-database routing and service configuration updates | System |
| 1.0 | 2025-12-30 | Initial specification: PgCat HA integration only | AI Agent |

---

## Next Steps

1. ✅ Review spec with stakeholders (DevOps/SRE)
2. ✅ Resolve open questions (load balancing algorithm, PgDog use-case)
3. ✅ Run `/plan connection-poolers-deepdive` to create technical implementation plan
4. ✅ Run `/tasks connection-poolers-deepdive` to break down into implementation tasks
5. Implement PgCat HA integration and PgDog deployment
6. Update documentation in `docs/guides/DATABASE.md`

---

## Related Documentation

- **Research Document**: [`specs/active/connection-poolers-deepdive/research.md`](./research.md)
- **Current PgCat Config**: `k8s/pgcat/transaction/configmap.yaml`
- **Transaction DB CRD**: `k8s/postgres-operator-cloudnativepg/crds/transaction-db.yaml`
- **Database Guide**: `docs/guides/DATABASE.md`

---

*Specification created with SDD 2.0*
