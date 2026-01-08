# Implementation Tasks: PgCat HA Integration for Transaction Database

**Task ID:** connection-poolers-deepdive
**Created:** 2025-12-30
**Status:** Ready for Implementation
**Based on:** plan.md

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 15 |
| Estimated Effort | ~80 minutes (1.3 hours) |
| Phases | 4 |
| Critical Path | Phase 1 → Phase 2 → Phase 3 → Phase 4 |

---

## Phase 1: Configuration Update (Foundation)

**Goal:** Add replica server configuration to PgCat ConfigMap for HA read routing
**Estimated:** 15 minutes

### Task 1.1: Backup Current ConfigMap

**Description:** Create a backup of the current PgCat ConfigMap before making changes for safety and rollback capability.

**Acceptance Criteria:**
- [ ] Backup file created: `pgcat-config-backup.yaml` (or similar)
- [ ] Backup contains complete ConfigMap YAML
- [ ] Backup file is readable and valid YAML

**Effort:** 2 minutes
**Priority:** High
**Dependencies:** None
**Assignee:** [Unassigned]

**Commands:**
```bash
kubectl get configmap pgcat-transaction-config -n cart -o yaml > pgcat-config-backup.yaml
```

---

### Task 1.2: Update ConfigMap with Replica Servers

**Description:** Add replica server entries to both `cart` and `order` database pools in the PgCat ConfigMap. Each pool should have one primary server (existing) and one replica server (new).

**Acceptance Criteria:**
- [ ] ConfigMap file updated: `k8s/pgcat/transaction/configmap.yaml`
- [ ] Replica server added for `cart` database pool (after line 38)
  - Host: `transaction-db-r.cart.svc.cluster.local`
  - Port: `5432`
  - User: `cart`
  - Password: `postgres`
  - Role: `replica`
- [ ] Replica server added for `order` database pool (after line 55)
  - Same configuration as cart pool
- [ ] All existing configuration preserved (pool sizes, users, primary servers)
- [ ] TOML syntax is valid

**Effort:** 10 minutes
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** [Unassigned]

**Files to Modify:**
- `k8s/pgcat/transaction/configmap.yaml`

**Expected Changes:**
```toml
# After line 38 (cart pool)
[[pools.cart.shards.0.servers]]
host = "transaction-db-r.cart.svc.cluster.local"
port = 5432
user = "cart"
password = "postgres"
role = "replica"

# After line 55 (order pool)
[[pools.order.shards.0.servers]]
host = "transaction-db-r.cart.svc.cluster.local"
port = 5432
user = "cart"
password = "postgres"
role = "replica"
```

---

### Task 1.3: Apply ConfigMap and Reload PgCat

**Description:** Apply the updated ConfigMap to Kubernetes and reload PgCat configuration using live reload (SIGHUP) for zero downtime.

**Acceptance Criteria:**
- [ ] ConfigMap applied successfully: `kubectl apply -f k8s/pgcat/transaction/configmap.yaml`
- [ ] ConfigMap updated in cluster: `kubectl get configmap pgcat-transaction-config -n cart -o yaml` shows replica servers
- [ ] PgCat configuration reloaded (live reload via SIGHUP or pod restart)
- [ ] PgCat pods running: `kubectl get pods -n cart -l app=pgcat-transaction` shows all pods Running

**Effort:** 3 minutes
**Priority:** High
**Dependencies:** Task 1.2
**Assignee:** [Unassigned]

**Commands:**
```bash
# Apply ConfigMap
kubectl apply -f k8s/pgcat/transaction/configmap.yaml

# Verify ConfigMap updated
kubectl get configmap pgcat-transaction-config -n cart -o yaml | grep -A 5 "role ="

# Reload PgCat (Option 1: Live reload - preferred)
kubectl exec -n cart deployment/pgcat-transaction -- kill -s SIGHUP 1

# OR Reload PgCat (Option 2: Restart pods - if live reload doesn't work)
kubectl rollout restart deployment/pgcat-transaction -n cart

# Verify pods running
kubectl get pods -n cart -l app=pgcat-transaction
```

---

### Task 1.4: Verify Configuration Loaded

**Description:** Verify that PgCat successfully loaded the new configuration with replica servers.

**Acceptance Criteria:**
- [ ] PgCat logs show no errors about replica servers
- [ ] PgCat logs show both primary and replica servers recognized
- [ ] No configuration parsing errors in logs
- [ ] PgCat admin database shows both servers (optional verification)

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 1.3
**Assignee:** [Unassigned]

**Commands:**
```bash
# Check PgCat logs
kubectl logs -n cart -l app=pgcat-transaction --tail=50 | grep -i "replica\|primary\|server\|error"

# Verify no errors
kubectl logs -n cart -l app=pgcat-transaction --tail=100 | grep -i "error\|fail"

# Optional: Check PgCat admin database
psql -h pgcat.cart.svc.cluster.local -p 9930 -U admin -d pgbouncer -c "SHOW POOLS;"
```

---

## Phase 2: Monitoring Integration

**Goal:** Enable Prometheus scraping of PgCat metrics via ServiceMonitor
**Estimated:** 20 minutes

### Task 2.1: Create ServiceMonitor CRD

**Description:** Create a ServiceMonitor Custom Resource Definition for PgCat that enables Prometheus to discover and scrape PgCat metrics from the HTTP admin endpoint.

**Acceptance Criteria:**
- [ ] ServiceMonitor file created: `k8s/prometheus/servicemonitors/servicemonitor-pgcat-transaction.yaml`
- [ ] ServiceMonitor configured with:
  - Namespace selector: `cart` (where PgCat service is located)
  - Service selector: `app: pgcat-transaction`
  - Endpoint: port `metrics` (9930), path `/metrics` - admin port serves both admin interface and metrics endpoint
  - Appropriate labels: `release: kube-prometheus-stack`
  - Relabelings configured for job, service, namespace labels
- [ ] YAML syntax is valid
- [ ] ServiceMonitor follows existing ServiceMonitor patterns in the codebase

**Effort:** 10 minutes
**Priority:** High
**Dependencies:** Phase 1 complete
**Assignee:** [Unassigned]

**Files to Create:**
- `k8s/prometheus/servicemonitors/servicemonitor-pgcat-transaction.yaml`

**Expected Structure:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgcat-transaction
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - cart
  selector:
    matchLabels:
      app: pgcat-transaction
  endpoints:
  - port: metrics  # Port 9930 (admin port) serves both admin interface and Prometheus metrics endpoint
    path: /metrics
    interval: 15s
    scrapeTimeout: 10s
    relabelings:
      - targetLabel: job
        replacement: pgcat-transaction
      - sourceLabels: [__meta_kubernetes_service_name]
        targetLabel: service
      - sourceLabels: [__meta_kubernetes_namespace]
        targetLabel: namespace
```

---

### Task 2.2: Apply ServiceMonitor

**Description:** Apply the ServiceMonitor to Kubernetes and verify it is created successfully.

**Acceptance Criteria:**
- [ ] ServiceMonitor applied: `kubectl apply -f k8s/prometheus/servicemonitors/servicemonitor-pgcat-transaction.yaml`
- [ ] ServiceMonitor created: `kubectl get servicemonitor -n monitoring pgcat-transaction` shows the resource
- [ ] ServiceMonitor status shows no errors
- [ ] ServiceMonitor labels match Prometheus Operator selector requirements

**Effort:** 3 minutes
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** [Unassigned]

**Commands:**
```bash
# Apply ServiceMonitor
kubectl apply -f k8s/prometheus/servicemonitors/servicemonitor-pgcat-transaction.yaml

# Verify created
kubectl get servicemonitor -n monitoring pgcat-transaction

# Check details
kubectl describe servicemonitor -n monitoring pgcat-transaction
```

---

### Task 2.3: Verify Prometheus Discovery

**Description:** Verify that Prometheus discovers the PgCat service as a target and can scrape metrics.

**Acceptance Criteria:**
- [ ] Prometheus discovers PgCat target (port-forward to Prometheus UI)
- [ ] Target status is UP in Prometheus targets page
- [ ] Target shows correct labels (job, service, namespace)
- [ ] No discovery errors in Prometheus logs

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 2.2
**Assignee:** [Unassigned]

**Commands:**
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Then visit: http://localhost:9090/targets
# Look for "pgcat-transaction" target with status UP

# Or check via API
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="pgcat-transaction")'
```

---

### Task 2.4: Verify Metrics Available

**Description:** Verify that PgCat metrics are available in Prometheus with correct labels.

**Acceptance Criteria:**
- [ ] Key metrics queryable in Prometheus:
  - `pgcat_pools_active_connections`
  - `pgcat_servers_health`
  - `pgcat_queries_total`
- [ ] Metrics have correct labels:
  - `pool` (cart, order)
  - `server_role` (primary, replica)
  - `server_host` (transaction-db-rw..., transaction-db-r...)
- [ ] Metrics endpoint returns 200 OK: `curl http://localhost:9930/metrics` (via port-forward)

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 2.3
**Assignee:** [Unassigned]

**Commands:**
```bash
# Port-forward to PgCat admin endpoint
kubectl port-forward -n cart svc/pgcat 9930:9930

# Test metrics endpoint
curl http://localhost:9930/metrics | grep pgcat

# Query Prometheus for key metrics
curl http://localhost:9090/api/v1/query?query=pgcat_pools_active_connections
curl http://localhost:9090/api/v1/query?query=pgcat_servers_health
curl http://localhost:9090/api/v1/query?query=pgcat_queries_total
```

---

## Phase 3: Verification & Testing

**Goal:** Verify HA integration works correctly (read routing, failover, load balancing, backward compatibility)
**Estimated:** 30 minutes

### Task 3.1: Verify Read Query Routing

**Description:** Verify that SELECT queries are correctly routed to replica servers.

**Acceptance Criteria:**
- [ ] Can connect to PgCat: `psql -h pgcat.cart.svc.cluster.local -U cart -d cart`
- [ ] SELECT queries execute successfully
- [ ] PgCat logs show queries routed to replica servers (check logs for routing decisions)
- [ ] Prometheus metrics show `pgcat_queries_total{server_role="replica"}` increasing
- [ ] No errors in PgCat logs or application logs

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Phase 2 complete
**Assignee:** [Unassigned]

**Commands:**
```bash
# Connect to PgCat
psql -h pgcat.cart.svc.cluster.local -U cart -d cart

# Execute SELECT queries
SELECT COUNT(*) FROM <table>;

# Check PgCat logs
kubectl logs -n cart -l app=pgcat-transaction --tail=100 | grep -i "routing\|replica\|SELECT"

# Check metrics
curl http://localhost:9090/api/v1/query?query=pgcat_queries_total{server_role="replica"}
```

---

### Task 3.2: Verify Write Query Routing

**Description:** Verify that INSERT/UPDATE/DELETE queries are correctly routed to primary server.

**Acceptance Criteria:**
- [ ] Write queries (INSERT/UPDATE/DELETE) execute successfully
- [ ] PgCat logs show queries routed to primary server
- [ ] Prometheus metrics show `pgcat_queries_total{server_role="primary"}` increasing
- [ ] Data is persisted correctly (verify with SELECT after INSERT)
- [ ] No errors in PgCat logs or application logs

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 3.1
**Assignee:** [Unassigned]

**Commands:**
```bash
# Execute write queries
INSERT INTO <table> VALUES (...);
UPDATE <table> SET ... WHERE ...;
DELETE FROM <table> WHERE ...;

# Check PgCat logs
kubectl logs -n cart -l app=pgcat-transaction --tail=100 | grep -i "routing\|primary\|INSERT\|UPDATE\|DELETE"

# Check metrics
curl http://localhost:9090/api/v1/query?query=pgcat_queries_total{server_role="primary"}
```

---

### Task 3.3: Verify Load Balancing

**Description:** Verify that SELECT queries are load balanced across replica servers.

**Acceptance Criteria:**
- [ ] Execute 100 SELECT queries (via script or manual)
- [ ] Prometheus metrics show queries distributed across both replica servers
- [ ] Distribution is approximately 40-60% per replica (not 100% to one replica)
- [ ] Both replica servers show activity in metrics

**Effort:** 5 minutes
**Priority:** Medium
**Dependencies:** Task 3.1
**Assignee:** [Unassigned]

**Commands:**
```bash
# Execute multiple SELECT queries (100 times)
for i in {1..100}; do
  psql -h pgcat.cart.svc.cluster.local -U cart -d cart -c "SELECT COUNT(*) FROM <table>;"
done

# Check query distribution per replica server
curl http://localhost:9090/api/v1/query?query=pgcat_queries_total{server_role="replica"}

# Should show queries distributed across both replicas
# Compare: pgcat_queries_total{server_host="transaction-db-r...", server_role="replica"}
```

---

### Task 3.4: Test Failover (Optional)

**Description:** Test that PgCat handles replica failures correctly by automatically routing to remaining healthy replicas.

**Acceptance Criteria:**
- [ ] Simulate replica failure (if safe): `kubectl delete pod transaction-db-1 -n cart` (or similar)
- [ ] PgCat detects failure and routes queries to remaining replica + primary
- [ ] Metrics show `pgcat_servers_health{status="unhealthy"}` for failed replica
- [ ] No application errors during failover
- [ ] Replica pod restarts and PgCat automatically includes it back (after ban_time expires)

**Effort:** 10 minutes
**Priority:** Low (optional, can be manual test)
**Dependencies:** Task 3.3
**Assignee:** [Unassigned]

**Warning:** Only perform this test if safe to delete a replica pod. Ensure transaction-db cluster has 3 instances (1 primary + 2 replicas) so deleting one replica doesn't break HA.

**Commands:**
```bash
# Simulate replica failure (if safe)
kubectl delete pod transaction-db-1 -n cart

# Monitor PgCat logs
kubectl logs -n cart -l app=pgcat-transaction --tail=100 -f

# Check metrics for unhealthy server
curl http://localhost:9090/api/v1/query?query=pgcat_servers_health

# Verify queries still work (routed to remaining replica + primary)
psql -h pgcat.cart.svc.cluster.local -U cart -d cart -c "SELECT COUNT(*) FROM <table>;"

# Wait for replica to restart and rejoin
kubectl get pods -n cart -l cnpg.io/cluster=transaction-db
```

---

### Task 3.5: Verify Backward Compatibility

**Description:** Verify that cart and order services continue to work without errors after PgCat HA integration.

**Acceptance Criteria:**
- [ ] Cart service pods running: `kubectl get pods -n cart -l app=cart` shows all pods Running
- [ ] Order service pods running: `kubectl get pods -n order -l app=order` shows all pods Running
- [ ] Both services can connect to PgCat and execute queries
- [ ] No application errors in service logs
- [ ] No connection failures or timeouts

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 3.2
**Assignee:** [Unassigned]

**Commands:**
```bash
# Check cart service
kubectl get pods -n cart -l app=cart
kubectl logs -n cart -l app=cart --tail=50 | grep -i "error\|fail\|timeout"

# Check order service
kubectl get pods -n order -l app=order
kubectl logs -n order -l app=order --tail=50 | grep -i "error\|fail\|timeout"

# Test connectivity from services (if possible)
kubectl exec -n cart deployment/cart -- psql -h pgcat.cart.svc.cluster.local -U cart -d cart -c "SELECT 1;"
```

---

### Task 3.6: Verify Monitoring Integration

**Description:** Verify that all PgCat metrics are available in Prometheus and show correct read/write distribution.

**Acceptance Criteria:**
- [ ] All key metrics available in Prometheus:
  - `pgcat_pools_active_connections{pool="cart"}`
  - `pgcat_pools_active_connections{pool="order"}`
  - `pgcat_servers_health{server_role="primary"}`
  - `pgcat_servers_health{server_role="replica"}`
  - `pgcat_queries_total{pool="cart", server_role="replica"}`
  - `pgcat_queries_total{pool="cart", server_role="primary"}`
- [ ] Metrics show correct read/write distribution (replica queries > 0, primary queries > 0)
- [ ] Metrics have correct labels (pool, server_role, server_host, namespace)
- [ ] Grafana can query metrics (optional, if Grafana is available)

**Effort:** 5 minutes
**Priority:** Medium
**Dependencies:** Task 3.5
**Assignee:** [Unassigned]

**Commands:**
```bash
# Query all key metrics
curl http://localhost:9090/api/v1/query?query=pgcat_pools_active_connections
curl http://localhost:9090/api/v1/query?query=pgcat_servers_health
curl http://localhost:9090/api/v1/query?query=pgcat_queries_total

# Verify read/write distribution
curl http://localhost:9090/api/v1/query?query=sum(pgcat_queries_total{server_role="replica"})
curl http://localhost:9090/api/v1/query?query=sum(pgcat_queries_total{server_role="primary"})

# Check labels
curl http://localhost:9090/api/v1/query?query=pgcat_queries_total | jq '.data.result[].metric'
```

---

## Phase 4: Documentation Update

**Goal:** Update DATABASE.md with HA integration details
**Estimated:** 15 minutes

### Task 4.1: Update DATABASE.md with HA Integration

**Description:** Add HA integration section to the PgCat Standalone section in DATABASE.md, documenting the replica server configuration, monitoring setup, and troubleshooting.

**Acceptance Criteria:**
- [ ] Documentation updated: `docs/guides/DATABASE.md`
- [ ] New section added: "High Availability Integration" under "PgCat Standalone" section
- [ ] Documentation includes:
  - Replica server configuration (TOML structure)
  - ServiceMonitor setup
  - Monitoring metrics overview
  - Troubleshooting guide for HA scenarios
- [ ] Internal links updated if needed
- [ ] Documentation follows existing style and format

**Effort:** 15 minutes
**Priority:** Medium
**Dependencies:** Phase 3 complete
**Assignee:** [Unassigned]

**Files to Modify:**
- `docs/guides/DATABASE.md`

**Expected Location:**
- After "PgCat Standalone" section (around line 453)

**Content to Add:**
- HA Integration Overview
- Replica Server Configuration
- Monitoring Setup (ServiceMonitor)
- Key Metrics
- Troubleshooting (replica routing, failover, load balancing)

---

## Dependency Graph

```
Phase 1: Configuration Update (Foundation)
├── Task 1.1: Backup ConfigMap
│   └── Task 1.2: Update ConfigMap with Replica Servers
│       └── Task 1.3: Apply ConfigMap and Reload PgCat
│           └── Task 1.4: Verify Configuration Loaded

Phase 2: Monitoring Integration (depends on Phase 1)
├── Task 2.1: Create ServiceMonitor CRD
│   └── Task 2.2: Apply ServiceMonitor
│       └── Task 2.3: Verify Prometheus Discovery
│           └── Task 2.4: Verify Metrics Available

Phase 3: Verification & Testing (depends on Phase 2)
├── Task 3.1: Verify Read Query Routing
│   ├── Task 3.2: Verify Write Query Routing
│   │   └── Task 3.5: Verify Backward Compatibility
│   └── Task 3.3: Verify Load Balancing
│       └── Task 3.4: Test Failover (Optional)
│           └── Task 3.6: Verify Monitoring Integration

Phase 4: Documentation Update (depends on Phase 3)
└── Task 4.1: Update DATABASE.md with HA Integration
```

---

## Quick Reference Checklist

### Phase 1: Configuration Update (Foundation)
- [ ] Task 1.1: Backup Current ConfigMap
- [ ] Task 1.2: Update ConfigMap with Replica Servers
- [ ] Task 1.3: Apply ConfigMap and Reload PgCat
- [ ] Task 1.4: Verify Configuration Loaded

### Phase 2: Monitoring Integration
- [ ] Task 2.1: Create ServiceMonitor CRD
- [ ] Task 2.2: Apply ServiceMonitor
- [ ] Task 2.3: Verify Prometheus Discovery
- [ ] Task 2.4: Verify Metrics Available

### Phase 3: Verification & Testing
- [ ] Task 3.1: Verify Read Query Routing
- [ ] Task 3.2: Verify Write Query Routing
- [ ] Task 3.3: Verify Load Balancing
- [ ] Task 3.4: Test Failover (Optional)
- [ ] Task 3.5: Verify Backward Compatibility
- [ ] Task 3.6: Verify Monitoring Integration

### Phase 4: Documentation Update
- [ ] Task 4.1: Update DATABASE.md with HA Integration

---

## Risk Areas

| Task | Risk | Mitigation |
|------|------|------------|
| Task 1.2 | ConfigMap syntax error breaks PgCat | Validate TOML syntax before applying. Keep backup. |
| Task 1.3 | Live reload (SIGHUP) doesn't work | Fallback to pod restart. Test in staging first. |
| Task 2.1 | ServiceMonitor not discovered by Prometheus | Verify labels match Prometheus Operator selector. Check existing ServiceMonitors for patterns. |
| Task 2.3 | Prometheus target shows DOWN | Check ServiceMonitor namespace selector, service selector, and port name. Verify PgCat service exists. |
| Task 3.1 | SELECT queries not routing to replicas | Check PgCat logs for routing decisions. Verify replica servers are healthy. Check metrics. |
| Task 3.4 | Replica failure breaks HA | Only test if safe (3 instances). Monitor primary load. Ensure CloudNativePG HA is working. |
| Task 3.5 | Application errors after update | Monitor application logs. Test with sample queries. Verify connection strings unchanged. |
| Task 4.1 | Documentation out of sync with implementation | Review all implementation changes. Test documentation commands. Update as needed. |

---

## Next Steps

1. ✅ Review task breakdown
2. Run `/implement connection-poolers-deepdive` to start execution
3. Tasks will be executed in dependency order (Phase 1 → Phase 2 → Phase 3 → Phase 4)
4. Mark tasks as complete in this file as you progress

---

*Tasks created with SDD 2.0*
