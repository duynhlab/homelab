# Implementation Tasks: Connection Poolers Deep Dive - PgCat HA & PgDog for supporting-db

**Task ID:** connection-poolers-deepdive
**Created:** 2025-12-30
**Status:** Ready for Implementation
**Based on:** plan.md (v2.0)
**Version:** 2.0

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 28 |
| Estimated Effort | ~150 minutes (2.5 hours) |
| Phases | 7 |
| Critical Path | Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 |

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

## Phase 4: PgDog Deployment

**Goal:** Deploy PgDog via Helm chart for supporting-db with multi-database support
**Estimated:** 20 minutes

### Task 4.1: Add PgDog Helm Repository

**Description:** Add PgDog Helm repository to Flux system for GitOps deployment.

**Acceptance Criteria:**
- [ ] HelmRepository CRD created: `kubernetes/infra/configs/databases/poolers/supporting/helmrepository.yaml`
- [ ] Repository URL: `https://helm.pgdog.dev`
- [ ] Repository accessible: `helm repo list` shows `pgdogdev`
- [ ] Flux reconciles HelmRepository successfully

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** None
**Assignee:** [Unassigned]

**Files to Create:**
- `kubernetes/infra/configs/databases/poolers/supporting/helmrepository.yaml`

**Expected Structure:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: pgdogdev
  namespace: flux-system
spec:
  interval: 1h
  url: https://helm.pgdog.dev
```

---

### Task 4.2: Create PgDog HelmRelease and Values

**Description:** Create HelmRelease CRD and Helm values file for PgDog deployment with multi-database configuration.

**Acceptance Criteria:**
- [ ] HelmRelease file created: `kubernetes/infra/configs/databases/poolers/supporting/helmrelease.yaml`
- [ ] Helm values file created: `kubernetes/infra/configs/databases/poolers/supporting/values.yaml`
- [ ] HelmRelease configured with:
  - Chart: `pgdog`
  - Source: `pgdogdev` HelmRepository
  - Version: `0.31` (or latest)
  - Namespace: `user`
- [ ] Helm values configured with:
  - Replicas: 2
  - Port: 6432
  - OpenMetricsPort: 9090
  - 3 databases (user, notification, shipping)
  - Pool sizes: 30 (user), 20 (notification), 20 (shipping)
  - User authentication from Kubernetes secrets
  - ServiceMonitor enabled
  - Resources: CPU 500m-1000m, Memory 512Mi-1Gi

**Effort:** 10 minutes
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** [Unassigned]

**Files to Create:**
- `kubernetes/infra/configs/databases/poolers/supporting/helmrelease.yaml`
- `kubernetes/infra/configs/databases/poolers/supporting/values.yaml`

---

### Task 4.3: Apply PgDog Deployment

**Description:** Apply HelmRelease via Flux GitOps and verify PgDog deployment.

**Acceptance Criteria:**
- [ ] HelmRelease applied: Commit files to GitOps repository
- [ ] Flux reconciles HelmRelease: `flux get helmrelease pgdog-supporting -n user`
- [ ] PgDog pods running: `kubectl get pods -n user -l app=pgdog-supporting` shows 2 pods Running
- [ ] PgDog service created: `kubectl get svc -n user pgdog-supporting`
- [ ] Service exposes ports: 6432 (PostgreSQL), 9090 (OpenMetrics)

**Effort:** 3 minutes
**Priority:** High
**Dependencies:** Task 4.2
**Assignee:** [Unassigned]

**Commands:**
```bash
# Commit and push to GitOps repository
git add kubernetes/infra/configs/databases/poolers/supporting/
git commit -m "Add PgDog HelmRelease for supporting-db"
git push

# Verify Flux reconciliation
flux get helmrelease pgdog-supporting -n user

# Verify pods
kubectl get pods -n user -l app=pgdog-supporting

# Verify service
kubectl get svc -n user pgdog-supporting
```

---

### Task 4.4: Verify PgDog Configuration

**Description:** Verify that PgDog successfully loaded configuration with all 3 databases.

**Acceptance Criteria:**
- [ ] PgDog logs show no errors about database configuration
- [ ] PgDog logs show all 3 databases recognized (user, notification, shipping)
- [ ] Admin database accessible: `psql -h pgdog-supporting.user.svc.cluster.local -p 6432 -U admin -d pgbouncer`
- [ ] Can list databases: `SHOW DATABASES` shows all 3 databases
- [ ] Can show pools: `SHOW POOLS` shows pools for all databases

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 4.3
**Assignee:** [Unassigned]

**Commands:**
```bash
# Check PgDog logs
kubectl logs -n user -l app=pgdog-supporting --tail=50 | grep -i "database\|error\|config"

# Test admin database
psql -h pgdog-supporting.user.svc.cluster.local -p 6432 -U admin -d pgbouncer

# Show databases
SHOW DATABASES;

# Show pools
SHOW POOLS;
```

---

## Phase 5: PgDog Monitoring Integration

**Goal:** Enable Prometheus scraping of PgDog metrics
**Estimated:** 15 minutes

### Task 5.1: Create ServiceMonitor for PgDog

**Description:** Create ServiceMonitor CRD for PgDog metrics (if not auto-created by Helm).

**Acceptance Criteria:**
- [ ] ServiceMonitor file created: `kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml`
- [ ] ServiceMonitor configured with:
  - Namespace selector: `user` (where PgDog service is located)
  - Service selector: `app: pgdog-supporting`
  - Endpoint: port `metrics` (9090), path `/metrics`
  - Appropriate labels and relabelings
- [ ] YAML syntax is valid
- [ ] ServiceMonitor follows existing ServiceMonitor patterns

**Effort:** 8 minutes
**Priority:** High
**Dependencies:** Phase 4 complete
**Assignee:** [Unassigned]

**Files to Create:**
- `kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml`

**Note:** If Helm chart auto-creates ServiceMonitor (`serviceMonitor.enabled: true`), this task can be skipped. Verify first: `kubectl get servicemonitor -n monitoring pgdog-supporting`

---

### Task 5.2: Apply ServiceMonitor and Verify Discovery

**Description:** Apply ServiceMonitor and verify Prometheus discovers PgDog metrics.

**Acceptance Criteria:**
- [ ] ServiceMonitor applied: `kubectl apply -f kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml`
- [ ] ServiceMonitor created: `kubectl get servicemonitor -n monitoring pgdog-supporting`
- [ ] Prometheus discovers PgDog target (port-forward to Prometheus UI)
- [ ] Target status is UP in Prometheus targets page
- [ ] Metrics endpoint returns 200 OK: `curl http://pgdog-supporting.user.svc.cluster.local:9090/metrics`

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 5.1
**Assignee:** [Unassigned]

**Commands:**
```bash
# Apply ServiceMonitor
kubectl apply -f kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml

# Verify created
kubectl get servicemonitor -n monitoring pgdog-supporting

# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets
# Look for "pgdog-supporting" target with status UP

# Test metrics endpoint
kubectl port-forward -n user svc/pgdog-supporting 9090:9090
curl http://localhost:9090/metrics | grep pgdog
```

---

### Task 5.3: Verify PgDog Metrics Available

**Description:** Verify that PgDog metrics are available in Prometheus with correct labels.

**Acceptance Criteria:**
- [ ] Key metrics queryable in Prometheus:
  - `pgdog_pools_active_connections`
  - `pgdog_servers_health`
  - `pgdog_queries_total`
  - `pgdog_errors_total`
- [ ] Metrics have correct labels:
  - `database` (user, notification, shipping)
  - `pool` (database name)
- [ ] Metrics show activity for all 3 databases

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 5.2
**Assignee:** [Unassigned]

**Commands:**
```bash
# Query Prometheus for key metrics
curl http://localhost:9090/api/v1/query?query=pgdog_pools_active_connections
curl http://localhost:9090/api/v1/query?query=pgdog_servers_health
curl http://localhost:9090/api/v1/query?query=pgdog_queries_total
```

---

## Phase 6: Service Configuration Updates

**Goal:** Update user, notification, and shipping services to connect via PgDog
**Estimated:** 15 minutes

### Task 6.1: Update User Service Configuration

**Description:** Update user service Helm values to connect via PgDog instead of direct PostgreSQL connection.

**Acceptance Criteria:**
- [ ] Helm values file updated: `charts/values/user.yaml`
- [ ] `DB_HOST` changed: `pgdog-supporting.user.svc.cluster.local`
- [ ] `DB_PORT` changed: `6432`
- [ ] `DB_NAME` unchanged: `user`
- [ ] All other database configuration unchanged (credentials, SSL mode, etc.)

**Effort:** 3 minutes
**Priority:** High
**Dependencies:** Phase 4 complete
**Assignee:** [Unassigned]

**Files to Modify:**
- `charts/values/user.yaml`

**Expected Changes:**
```yaml
env:
  - name: DB_HOST
    value: "pgdog-supporting.user.svc.cluster.local"  # Changed from supporting-db.user.svc.cluster.local
  - name: DB_PORT
    value: "6432"  # Changed from 5432
  - name: DB_NAME
    value: "user"  # Unchanged
```

---

### Task 6.2: Update Notification Service Configuration

**Description:** Update notification service Helm values to connect via PgDog.

**Acceptance Criteria:**
- [ ] Helm values file updated: `charts/values/notification.yaml`
- [ ] `DB_HOST` changed: `pgdog-supporting.user.svc.cluster.local`
- [ ] `DB_PORT` changed: `6432`
- [ ] `DB_NAME` unchanged: `notification`

**Effort:** 3 minutes
**Priority:** High
**Dependencies:** Task 6.1
**Assignee:** [Unassigned]

**Files to Modify:**
- `charts/values/notification.yaml`

---

### Task 6.3: Update Shipping Service Configuration

**Description:** Update shipping service Helm values to connect via PgDog.

**Acceptance Criteria:**
- [ ] Helm values file updated: `charts/values/shipping.yaml`
- [ ] `DB_HOST` changed: `pgdog-supporting.user.svc.cluster.local`
- [ ] `DB_PORT` changed: `6432`
- [ ] `DB_NAME` unchanged: `shipping`

**Effort:** 3 minutes
**Priority:** High
**Dependencies:** Task 6.2
**Assignee:** [Unassigned]

**Files to Modify:**
- `charts/values/shipping.yaml`

---

### Task 6.4: Apply Service Updates and Verify

**Description:** Apply service configuration updates via Flux and verify services can connect to PgDog.

**Acceptance Criteria:**
- [ ] Changes committed to GitOps repository
- [ ] Flux reconciles HelmReleases for all 3 services
- [ ] Services restart successfully
- [ ] Service logs show no connection errors
- [ ] Services can execute queries successfully

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 6.3
**Assignee:** [Unassigned]

**Commands:**
```bash
# Commit changes
git add charts/values/user.yaml charts/values/notification.yaml charts/values/shipping.yaml
git commit -m "Update services to connect via PgDog"
git push

# Verify Flux reconciliation
flux get helmrelease user -n user
flux get helmrelease notification -n notification
flux get helmrelease shipping -n shipping

# Check service logs
kubectl logs -n user -l app=user --tail=50 | grep -i "error\|fail\|database"
kubectl logs -n notification -l app=notification --tail=50 | grep -i "error\|fail\|database"
kubectl logs -n shipping -l app=shipping --tail=50 | grep -i "error\|fail\|database"
```

---

## Phase 7: PgDog Verification & Testing

**Goal:** Verify PgDog deployment works correctly (multi-database routing, monitoring, service connectivity)
**Estimated:** 20 minutes

### Task 7.1: Verify Multi-Database Routing

**Description:** Verify that PgDog correctly routes connections to the correct database based on database name.

**Acceptance Criteria:**
- [ ] Can connect to user database: `psql -h pgdog-supporting.user.svc.cluster.local -p 6432 -U user -d user`
- [ ] Can connect to notification database: `psql -h pgdog-supporting.user.svc.cluster.local -p 6432 -U notification.notification -d notification`
- [ ] Can connect to shipping database: `psql -h pgdog-supporting.user.svc.cluster.local -p 6432 -U shipping.shipping -d shipping`
- [ ] Each connection routes to correct database (verified via queries)
- [ ] No routing errors in PgDog logs

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Phase 6 complete
**Assignee:** [Unassigned]

---

### Task 7.2: Verify Service Connectivity

**Description:** Verify that all 3 services (user, notification, shipping) can connect and execute queries via PgDog.

**Acceptance Criteria:**
- [ ] User service pods running: `kubectl get pods -n user -l app=user` shows all pods Running
- [ ] Notification service pods running: `kubectl get pods -n notification -l app=notification` shows all pods Running
- [ ] Shipping service pods running: `kubectl get pods -n shipping -l app=shipping` shows all pods Running
- [ ] No connection errors in service logs
- [ ] Services can execute queries (test via health endpoints or logs)

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 7.1
**Assignee:** [Unassigned]

---

### Task 7.3: Verify PgDog Monitoring

**Description:** Verify that PgDog metrics show activity for all 3 databases and services.

**Acceptance Criteria:**
- [ ] Metrics show active connections for all 3 databases
- [ ] Metrics show query counts per database
- [ ] Metrics have correct labels (database, pool)
- [ ] Metrics visible in Grafana (optional)

**Effort:** 5 minutes
**Priority:** Medium
**Dependencies:** Task 7.2
**Assignee:** [Unassigned]

---

### Task 7.4: Verify Backward Compatibility

**Description:** Verify that all services continue to work without errors after PgDog deployment.

**Acceptance Criteria:**
- [ ] All services can connect and execute queries
- [ ] No application errors in service logs
- [ ] No connection failures or timeouts
- [ ] Service health endpoints return healthy status

**Effort:** 5 minutes
**Priority:** High
**Dependencies:** Task 7.2
**Assignee:** [Unassigned]

---

## Phase 8: Documentation Update

**Goal:** Update DATABASE.md with HA integration and PgDog deployment details
**Estimated:** 15 minutes

### Task 8.1: Update DATABASE.md with HA Integration and PgDog

**Description:** Add HA integration section to PgCat Standalone section and PgDog deployment section for supporting-db in DATABASE.md.

**Acceptance Criteria:**
- [ ] Documentation updated: `docs/guides/DATABASE.md`
- [ ] New section added: "High Availability Integration" under "PgCat Standalone" section
- [ ] New section added: "PgDog Pooler for supporting-db" in Connection Poolers section
- [ ] Documentation includes:
  - PgCat HA: Replica server configuration (TOML structure), ServiceMonitor setup, monitoring metrics, troubleshooting
  - PgDog: Helm chart deployment, multi-database configuration, ServiceMonitor setup, monitoring metrics, troubleshooting
- [ ] Internal links updated if needed
- [ ] Documentation follows existing style and format

**Effort:** 15 minutes
**Priority:** Medium
**Dependencies:** Phase 7 complete
**Assignee:** [Unassigned]

**Files to Modify:**
- `docs/guides/DATABASE.md`

**Expected Locations:**
- After "PgCat Standalone" section (around line 453) - HA Integration
- After "PgCat (Product & Transaction DB)" section - PgDog section

**Content to Add:**
- PgCat HA Integration Overview
- PgCat Replica Server Configuration
- PgDog Deployment Overview
- PgDog Helm Chart Configuration
- PgDog Multi-Database Routing
- Monitoring Setup (ServiceMonitor for both)
- Key Metrics
- Troubleshooting guides

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

Phase 4: PgDog Deployment (depends on Phase 3)
├── Task 4.1: Add PgDog Helm Repository
│   └── Task 4.2: Create PgDog HelmRelease and Values
│       └── Task 4.3: Apply PgDog Deployment
│           └── Task 4.4: Verify PgDog Configuration

Phase 5: PgDog Monitoring Integration (depends on Phase 4)
├── Task 5.1: Create ServiceMonitor for PgDog
│   └── Task 5.2: Apply ServiceMonitor and Verify Discovery
│       └── Task 5.3: Verify PgDog Metrics Available

Phase 6: Service Configuration Updates (depends on Phase 4)
├── Task 6.1: Update User Service Configuration
│   └── Task 6.2: Update Notification Service Configuration
│       └── Task 6.3: Update Shipping Service Configuration
│           └── Task 6.4: Apply Service Updates and Verify

Phase 7: PgDog Verification & Testing (depends on Phase 6)
├── Task 7.1: Verify Multi-Database Routing
│   ├── Task 7.2: Verify Service Connectivity
│   │   ├── Task 7.3: Verify PgDog Monitoring
│   │   └── Task 7.4: Verify Backward Compatibility

Phase 8: Documentation Update (depends on Phase 7)
└── Task 8.1: Update DATABASE.md with HA Integration and PgDog
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

### Phase 4: PgDog Deployment
- [ ] Task 4.1: Add PgDog Helm Repository
- [ ] Task 4.2: Create PgDog HelmRelease and Values
- [ ] Task 4.3: Apply PgDog Deployment
- [ ] Task 4.4: Verify PgDog Configuration

### Phase 5: PgDog Monitoring Integration
- [ ] Task 5.1: Create ServiceMonitor for PgDog
- [ ] Task 5.2: Apply ServiceMonitor and Verify Discovery
- [ ] Task 5.3: Verify PgDog Metrics Available

### Phase 6: Service Configuration Updates
- [ ] Task 6.1: Update User Service Configuration
- [ ] Task 6.2: Update Notification Service Configuration
- [ ] Task 6.3: Update Shipping Service Configuration
- [ ] Task 6.4: Apply Service Updates and Verify

### Phase 7: PgDog Verification & Testing
- [ ] Task 7.1: Verify Multi-Database Routing
- [ ] Task 7.2: Verify Service Connectivity
- [ ] Task 7.3: Verify PgDog Monitoring
- [ ] Task 7.4: Verify Backward Compatibility

### Phase 8: Documentation Update
- [ ] Task 8.1: Update DATABASE.md with HA Integration and PgDog

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

---

## Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 2.0 | 2026-01-13 | [REFINED] Added PgDog deployment tasks (Phase 4-7), service configuration updates, and expanded documentation task | System |
| 1.0 | 2025-12-30 | Initial tasks: PgCat HA integration only | AI Agent |

---

*Tasks created with SDD 2.0, refined 2026-01-13*
