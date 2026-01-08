# Implementation Tasks: CloudNativePG Production-Ready Configuration

**Task ID:** cloudnativepg-operator
**Created:** 2026-01-02
**Status:** Ready for Implementation
**Based on:** plan.md

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 9 |
| Estimated Effort | ~19 hours (~2.5 days) |
| Phases | 6 |
| Critical Path | Task 2.1 → 2.2 → 2.3 → 3.1 → 4.1 → 5.1 → 5.2 → 6.1 |

---

## Phase 1: Preparation & Backup (Foundation)

**Goal:** Verify prerequisites, backup current configuration, and prepare rollback plan
**Estimated:** 2 hours

### Task 1.1: Verify Prerequisites and Backup Configuration

**Description:** Verify all required operators and clusters are operational, check current cluster status, and prepare for rollback if needed.

**Acceptance Criteria:**
- [ ] CloudNativePG Operator is running: `kubectl get pods -n database -l app.kubernetes.io/name=cloudnative-pg`
- [ ] Prometheus Operator is running: `kubectl get pods -n monitoring`
- [ ] Grafana Operator is running: `kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana-operator`
- [ ] Transaction-DB cluster is operational: `kubectl get cluster transaction-db -n cart`
- [ ] Product-DB cluster is operational: `kubectl get cluster product-db -n product`
- [ ] Current cluster has 2 instances: `kubectl get pods -n cart -l cnpg.io/cluster=transaction-db`
- [ ] Secrets exist: `kubectl get secret transaction-db-secret -n cart` and `kubectl get secret product-db-secret -n product`
- [ ] CloudNativePG Operator version supports `enablePodMonitor`: Check operator version (v1.20+)
- [ ] Document current cluster configuration state (instance count, resource limits, storage size)

**Effort:** 2 hours
**Priority:** High
**Dependencies:** None
**Assignee:** [Unassigned]

**Verification Commands:**
```bash
# Check operators
kubectl get pods -n database -l app.kubernetes.io/name=cloudnative-pg
kubectl get pods -n monitoring | grep -E "prometheus|grafana"

# Check clusters
kubectl get cluster transaction-db -n cart
kubectl get cluster product-db -n product

# Check current state
kubectl get pods -n cart -l cnpg.io/cluster=transaction-db
kubectl get pods -n product -l cnpg.io/cluster=product-db

# Check secrets
kubectl get secret transaction-db-secret -n cart
kubectl get secret product-db-secret -n product
```

---

## Phase 2: Update Transaction-DB Cluster CRD (Core Configuration)

**Goal:** Upgrade transaction-db cluster to production-ready configuration with HA, logical replication slot sync, and performance tuning
**Estimated:** 6 hours

### Task 2.1: Update HA Configuration (Instances, Replication, Logical Slots)

**Description:** Update transaction-db cluster CRD to enable 3-node HA with synchronous replication and logical replication slot synchronization.

**Acceptance Criteria:**
- [ ] Update `instances: 3` in `k8s/postgres-operator/cloudnativepg/crds/transaction-db.yaml`
- [ ] Add `replicationSlots.highAvailability.synchronizeLogicalDecoding: true` section
- [ ] Add `postgresql.synchronous` configuration with:
  - `method: any`
  - `number: 1`
  - `dataDurability: required`
- [ ] Comment out `syncReplicaElectionConstraint` section (if exists)
- [ ] YAML file is valid (no syntax errors)
- [ ] Changes are documented in commit message

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** [Unassigned]

**Files to Modify:**
- `k8s/postgres-operator/cloudnativepg/crds/transaction-db.yaml`

**Key Changes:**
```yaml
spec:
  instances: 3  # Upgrade from 2
  
  replicationSlots:
    highAvailability:
      synchronizeLogicalDecoding: true
  
  postgresql:
    synchronous:
      method: any
      number: 1
      dataDurability: required
```

---

### Task 2.2: Update PostgreSQL Parameters and Resources

**Description:** Apply comprehensive production tuning parameters, update resource limits, and storage configuration for transaction-db cluster.

**Acceptance Criteria:**
- [ ] Update PostgreSQL parameters section with:
  - Memory settings: `shared_buffers: "512MB"`, `effective_cache_size: "1.5GB"`, `maintenance_work_mem: "512MB"`, `work_mem: "32MB"`
  - WAL settings: `wal_level: "logical"`, `min_wal_size: "2GB"`, `max_wal_size: "8GB"`, `checkpoint_timeout: "15min"`
  - Query planner: `random_page_cost: "1.1"`, `effective_io_concurrency: "200"`
  - Parallelism: `max_worker_processes: "8"`, `max_parallel_workers_per_gather: "4"`, `max_parallel_workers: "8"`, `max_parallel_maintenance_workers: "4"`
  - Autovacuum: All autovacuum parameters configured
  - Logging: All logging parameters configured (`log_statement: "mod"`, `log_min_duration_statement: "1000"`, etc.)
  - Security: `password_encryption: "scram-sha-256"`
  - Replication: `hot_standby_feedback: "on"`
- [ ] Update resource limits:
  - Requests: `memory: "1Gi"`, `cpu: "500m"`
  - Limits: `memory: "2Gi"`, `cpu: "1000m"`
- [ ] Update storage: `size: 100Gi`, `storageClass: standard`
- [ ] YAML file is valid (no syntax errors)
- [ ] All parameters match plan.md specifications

**Effort:** 3 hours
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** [Unassigned]

**Files to Modify:**
- `k8s/postgres-operator/cloudnativepg/crds/transaction-db.yaml`

---

### Task 2.3: Apply Cluster Configuration and Monitor Upgrade

**Description:** Apply the updated transaction-db cluster CRD and monitor the cluster upgrade process to ensure successful transition to 3-node HA.

**Acceptance Criteria:**
- [ ] Apply configuration: `kubectl apply -f k8s/postgres-operator/cloudnativepg/crds/transaction-db.yaml`
- [ ] Cluster CRD update is accepted (no validation errors)
- [ ] Monitor cluster upgrade: `kubectl get cluster transaction-db -n cart -w` shows progression
- [ ] New replica pod starts (transaction-db-2)
- [ ] Cluster enters "Cluster in healthy state" after ~5-10 minutes
- [ ] All 3 pods show "Ready" status: `kubectl get pods -n cart -l cnpg.io/cluster=transaction-db`
- [ ] No critical errors in cluster events: `kubectl describe cluster transaction-db -n cart`
- [ ] Synchronous replication is active (check cluster status)
- [ ] Document upgrade duration and any issues encountered

**Effort:** 1 hour (mostly monitoring/waiting)
**Priority:** High
**Dependencies:** Task 2.2
**Assignee:** [Unassigned]

**Verification Commands:**
```bash
# Watch cluster status
kubectl get cluster transaction-db -n cart -w

# Check pods (should show 3 instances)
kubectl get pods -n cart -l cnpg.io/cluster=transaction-db

# Check cluster events
kubectl describe cluster transaction-db -n cart

# Verify cluster health
kubectl get cluster transaction-db -n cart -o jsonpath='{.status.phase}'
```

**Expected Behavior:**
- Operator detects configuration change
- New replica pod starts (transaction-db-2)
- Cluster enters "Cluster in healthy state" after ~5-10 minutes
- All 3 pods show "Ready" status

---

## Phase 3: Enable Built-in PodMonitor (Monitoring Integration)

**Goal:** Enable operator-managed PodMonitor creation for both CloudNativePG clusters and remove manual PodMonitor files
**Estimated:** 2 hours

### Task 3.1: Enable Built-in PodMonitor and Cleanup Manual Files

**Description:** Add `enablePodMonitor: true` to both transaction-db and product-db Cluster CRDs, apply changes, and remove manual PodMonitor YAML files.

**Acceptance Criteria:**
- [ ] Update transaction-db.yaml: Add `spec.monitoring.enablePodMonitor: true`
- [ ] Update product-db.yaml: Add `spec.monitoring.enablePodMonitor: true`
- [ ] Apply updated Cluster CRDs: `kubectl apply -f k8s/postgres-operator/cloudnativepg/crds/`
- [ ] Verify operator-created PodMonitors exist:
  - `kubectl get podmonitor transaction-db -n cart`
  - `kubectl get podmonitor product-db -n product`
- [ ] Verify PodMonitor labels match cluster: `kubectl get podmonitor transaction-db -n cart -o yaml | grep selector`
- [ ] Verify PodMonitor is operator-managed: Check `ownerReferences` in PodMonitor YAML
- [ ] Delete manual PodMonitor files:
  - `kubectl delete -f k8s/prometheus/podmonitors/podmonitor-transaction-db.yaml` (if exists)
  - `kubectl delete -f k8s/prometheus/podmonitors/podmonitor-product-db.yaml` (if exists)
  - Or delete files: `rm k8s/prometheus/podmonitors/podmonitor-{transaction,product}-db.yaml`
- [ ] Verify Prometheus Operator discovers PodMonitors (check Prometheus targets if accessible)
- [ ] Metrics appear in Prometheus within 1-2 minutes (query `cnpg_collector_up`)

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 2.3
**Assignee:** [Unassigned]

**Files to Modify:**
- `k8s/postgres-operator/cloudnativepg/crds/transaction-db.yaml`
- `k8s/postgres-operator/cloudnativepg/crds/product-db.yaml`

**Files to Delete:**
- `k8s/prometheus/podmonitors/podmonitor-transaction-db.yaml`
- `k8s/prometheus/podmonitors/podmonitor-product-db.yaml`

**Verification Commands:**
```bash
# Check operator-created PodMonitors
kubectl get podmonitor -n cart
kubectl get podmonitor -n product

# Verify PodMonitor is operator-managed (check ownerReferences)
kubectl get podmonitor transaction-db -n cart -o yaml | grep -A 5 ownerReferences

# Check Prometheus targets (if Prometheus UI accessible)
# Should see transaction-db and product-db in targets list
```

**Expected Behavior:**
- Operator automatically creates PodMonitors after Cluster CRD update
- PodMonitors have correct selectors (`cnpg.io/cluster`)
- Prometheus Operator discovers PodMonitors automatically
- Metrics appear in Prometheus within 1-2 minutes
- Manual PodMonitor files removed (cleanup)

---

## Phase 4: Install Grafana Dashboard (Visualization)

**Goal:** Install official CloudNativePG Grafana dashboard using Grafana Operator approach
**Estimated:** 3 hours

### Task 4.1: Download and Install CloudNativePG Grafana Dashboard

**Description:** Download CloudNativePG dashboard JSON, create GrafanaDashboard CRD, and verify dashboard appears in Grafana UI.

**Acceptance Criteria:**
- [ ] Download CloudNativePG dashboard JSON:
  ```bash
  curl -o k8s/grafana-operator/dashboards/cnpg-cluster-dashboard.json \
    https://raw.githubusercontent.com/cloudnative-pg/grafana-dashboards/main/charts/cluster/grafana-dashboard.json
  ```
- [ ] Verify JSON file downloaded successfully and is valid JSON
- [ ] Create GrafanaDashboard CRD:
  - File: `k8s/grafana-operator/dashboards/cnpg-cluster-dashboard.yaml`
  - Use Grafana Operator format (see plan.md Component 3)
  - Set namespace: `monitoring`
  - Set labels: `app: grafana`
  - Configure Prometheus data source mapping: `inputName: DS_PROMETHEUS`, `datasourceName: Prometheus`
  - Set folder: `"Databases"`
- [ ] If JSON is large (>1MB), use ConfigMap approach:
  - Add ConfigMap generator to `k8s/grafana-operator/dashboards/kustomization.yaml`
  - Update GrafanaDashboard CRD to use `configMapRef` instead of inline JSON
- [ ] Apply dashboard: `kubectl apply -k k8s/grafana-operator/dashboards/` or direct apply
- [ ] Verify dashboard created: `kubectl get grafanadashboard cnpg-cluster-dashboard -n monitoring`
- [ ] Check dashboard status: `kubectl describe grafanadashboard cnpg-cluster-dashboard -n monitoring`
- [ ] Verify Grafana Operator discovered dashboard: Check operator logs
- [ ] Check Grafana UI: Dashboard appears in "Databases" folder
- [ ] Dashboard panels show CloudNativePG cluster metrics (if accessible)
- [ ] Prometheus data source correctly configured in dashboard

**Effort:** 3 hours
**Priority:** Medium
**Dependencies:** Task 3.1
**Assignee:** [Unassigned]

**Files to Create:**
- `k8s/grafana-operator/dashboards/cnpg-cluster-dashboard.json` (downloaded)
- `k8s/grafana-operator/dashboards/cnpg-cluster-dashboard.yaml` (new)

**Files to Modify (if using ConfigMap approach):**
- `k8s/grafana-operator/dashboards/kustomization.yaml`

**Verification Commands:**
```bash
# Check GrafanaDashboard CRD
kubectl get grafanadashboard cnpg-cluster-dashboard -n monitoring

# Check dashboard status
kubectl describe grafanadashboard cnpg-cluster-dashboard -n monitoring

# Verify Grafana Operator discovered dashboard
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-operator | grep cnpg
```

**Expected Behavior:**
- GrafanaDashboard CRD created successfully
- Grafana Operator discovers dashboard automatically
- Dashboard appears in Grafana UI under "Databases" folder
- Dashboard panels show CloudNativePG cluster metrics
- Prometheus data source correctly configured

---

## Phase 5: Verification & Testing (Quality Assurance)

**Goal:** Verify all changes are working correctly, test failover scenario, and verify metrics collection
**Estimated:** 4 hours

### Task 5.1: Verify Cluster Configuration and Monitoring

**Description:** Verify transaction-db cluster has 3 instances, synchronous replication is active, logical replication slots are synchronized, and metrics are being collected.

**Acceptance Criteria:**
- [ ] Verify cluster has 3 instances: `kubectl get pods -n cart -l cnpg.io/cluster=transaction-db` shows 3 pods
- [ ] Verify all pods are Ready: All 3 pods show "Ready" status
- [ ] Verify synchronous replication: Check cluster status shows synchronous replicas
  - `kubectl get cluster transaction-db -n cart -o yaml | grep -A 10 synchronous`
- [ ] Verify logical replication slot sync: Check cluster logs for slot synchronization
  - `kubectl logs -n cart -l cnpg.io/cluster=transaction-db | grep -i "replication.*slot"`
- [ ] Verify metrics in Prometheus: Query `cnpg_collector_up{cluster="transaction-db"}` returns 1
- [ ] Verify metrics in Prometheus: Query `cnpg_collector_up{cluster="product-db"}` returns 1
- [ ] Verify additional metrics are available:
  - `cnpg_postgresql_up`
  - `cnpg_postgresql_replication_lag`
  - `cnpg_postgresql_connections`
- [ ] Document verification results

**Effort:** 2 hours
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** [Unassigned]

**Verification Commands:**
```bash
# Cluster status
kubectl get cluster transaction-db -n cart -o yaml | grep -A 10 status

# Pod status
kubectl get pods -n cart -l cnpg.io/cluster=transaction-db -o wide

# Metrics (if Prometheus accessible)
curl http://localhost:9090/api/v1/query?query=cnpg_collector_up{cluster="transaction-db"}
curl http://localhost:9090/api/v1/query?query=cnpg_collector_up{cluster="product-db"}
```

---

### Task 5.2: Test Failover and Performance (Optional)

**Description:** Test failover scenario to verify automatic failover works within 30 seconds and zero data loss is maintained. Optionally check performance improvements.

**Acceptance Criteria:**
- [ ] Document current primary pod: `kubectl get pods -n cart -l cnpg.io/cluster=transaction-db -o jsonpath='{.items[?(@.metadata.labels.cnpg\.io/instanceRole=="primary")].metadata.name}'`
- [ ] Test failover (optional): Delete primary pod: `kubectl delete pod <primary-pod-name> -n cart`
- [ ] Monitor failover: `kubectl get pods -n cart -l cnpg.io/cluster=transaction-db -w`
- [ ] Verify failover completes < 30 seconds: Time from pod deletion to new primary ready
- [ ] Verify zero data loss: Check committed transactions after failover (if test database accessible)
- [ ] Verify new primary is elected: Check cluster status shows new primary
- [ ] Verify replicas reconnect: All replicas show "Ready" status after failover
- [ ] Check performance (optional): Run sample queries and compare with baseline
- [ ] Document failover test results (if performed)

**Effort:** 2 hours
**Priority:** Low (optional)
**Dependencies:** Task 5.1
**Assignee:** [Unassigned]

**Verification Commands:**
```bash
# Failover test (optional)
PRIMARY=$(kubectl get pods -n cart -l cnpg.io/cluster=transaction-db -o jsonpath='{.items[?(@.metadata.labels.cnpg\.io/instanceRole=="primary")].metadata.name}')
kubectl delete pod $PRIMARY -n cart

# Watch for new primary election
kubectl get pods -n cart -l cnpg.io/cluster=transaction-db -w

# Check cluster status after failover
kubectl get cluster transaction-db -n cart -o yaml | grep -A 10 status
```

**Note:** This task is optional. Only perform if you want to verify failover behavior in your environment.

---

## Phase 6: Documentation & Cleanup (Finalization)

**Goal:** Document changes, update research document, and commit all changes to Git
**Estimated:** 2 hours

### Task 6.1: Update Documentation and Commit Changes

**Description:** Update research document with implementation notes, document any issues encountered, update CHANGELOG.md, and commit all changes to Git.

**Acceptance Criteria:**
- [ ] Update research document (`specs/active/cloudnativepg-operator/research.md`) with:
  - Implementation status: "✅ Implemented"
  - Date of implementation
  - Any deviations from plan
  - Issues encountered and resolutions
- [ ] Document operational procedures:
  - How to verify cluster health
  - How to check monitoring status
  - How to access Grafana dashboard
  - Rollback procedure (if needed)
- [ ] Update CHANGELOG.md with new entry:
  - Feature: CloudNativePG production-ready configuration
  - Changes: HA upgrade, monitoring integration, Grafana dashboard
  - Date: 2026-01-02
- [ ] Verify all files are committed:
  - Modified Cluster CRDs
  - New Grafana dashboard files
  - Deleted PodMonitor files (if tracked in Git)
- [ ] Commit message includes:
  - Summary of changes
  - Reference to task ID: cloudnativepg-operator
  - List of key changes (HA upgrade, monitoring, dashboard)
- [ ] All changes pushed to repository

**Effort:** 2 hours
**Priority:** Medium
**Dependencies:** Task 5.1 (Task 5.2 is optional)
**Assignee:** [Unassigned]

**Files to Update:**
- `specs/active/cloudnativepg-operator/research.md`
- `CHANGELOG.md` (if applicable)

**Documentation Sections to Add:**
- Implementation status and date
- Operational procedures
- Troubleshooting guide
- Rollback procedures

---

## Dependency Graph

```
Phase 1: Preparation
└── Task 1.1 (Verify Prerequisites)

Phase 2: Core Configuration (depends on Phase 1)
├── Task 2.1 (Update HA Configuration)
│   └── Task 2.2 (Update PostgreSQL Parameters)
│       └── Task 2.3 (Apply and Monitor Upgrade)

Phase 3: Monitoring Integration (depends on Phase 2)
└── Task 3.1 (Enable Built-in PodMonitor)

Phase 4: Visualization (depends on Phase 3)
└── Task 4.1 (Install Grafana Dashboard)

Phase 5: Verification (depends on Phase 4)
├── Task 5.1 (Verify Configuration)
│   └── Task 5.2 (Test Failover - Optional)

Phase 6: Documentation (depends on Phase 5)
└── Task 6.1 (Update Documentation)
```

---

## Quick Reference Checklist

### Phase 1: Preparation & Backup
- [ ] Task 1.1: Verify Prerequisites and Backup Configuration

### Phase 2: Update Transaction-DB Cluster CRD
- [ ] Task 2.1: Update HA Configuration (Instances, Replication, Logical Slots)
- [ ] Task 2.2: Update PostgreSQL Parameters and Resources
- [ ] Task 2.3: Apply Cluster Configuration and Monitor Upgrade

### Phase 3: Enable Built-in PodMonitor
- [ ] Task 3.1: Enable Built-in PodMonitor and Cleanup Manual Files

### Phase 4: Install Grafana Dashboard
- [ ] Task 4.1: Download and Install CloudNativePG Grafana Dashboard

### Phase 5: Verification & Testing
- [ ] Task 5.1: Verify Cluster Configuration and Monitoring
- [ ] Task 5.2: Test Failover and Performance (Optional)

### Phase 6: Documentation & Cleanup
- [ ] Task 6.1: Update Documentation and Commit Changes

---

## Risk Areas

| Task | Risk | Mitigation |
|------|------|------------|
| Task 2.3 | HA Upgrade Fails | Monitor cluster status closely, have rollback plan ready (Git revert) |
| Task 2.3 | Synchronous Replica Not Available | Primary will block writes until replica ready, monitor cluster status |
| Task 2.3 | Logical Replication Slot Sync Fails | Check operator logs, slots may not sync but cluster will still function |
| Task 3.1 | Built-in PodMonitor Not Created | Check CloudNativePG Operator version (v1.20+), verify syntax |
| Task 4.1 | Grafana Dashboard Not Appearing | Check Grafana Operator logs, verify CRD format, check data source mapping |
| Task 5.2 | Failover Takes > 30 seconds | Monitor failover time, check operator logs, verify Patroni configuration |

---

## Next Steps

1. ✅ Review task breakdown
2. Assign tasks to developers (if team project)
3. Run `/implement cloudnativepg-operator` to start execution
4. Begin with Task 1.1: Verify Prerequisites and Backup Configuration

---

*Tasks created with SDD 2.0*
