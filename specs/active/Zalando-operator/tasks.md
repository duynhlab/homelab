# Implementation Tasks: Zalando Postgres Operator Production-Ready Configuration

**Task ID:** Zalando-operator
**Created:** 2025-12-29
**Status:** Ready for Implementation
**Based on:** plan.md v2.1

**Priority:** 
1. **CRITICAL (Immediate)**: Phase 0 - Cross-Namespace Secret Configuration Fix
2. **High Priority**: Phase 1 - PostgreSQL Performance Tuning
3. **Medium Priority**: Phase 2-4 - Documentation and Validation

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 47 |
| Estimated Effort | ~92 hours (~2.3 weeks) |
| Phases | 8 (Phase 0 CRITICAL + Phases 1-7) |
| Critical Path | Phase 0 (Tasks 0.0-0.7) → Phase 1 (Tasks 1.1-1.5) → Phase 4 (Tasks 4.1-4.2) |

---

## Phase 0: Cross-Namespace Secret Configuration Fix (CRITICAL - DO FIRST)

**Goal:** Fix Helm values structure and enable cross-namespace secret feature to resolve 3 services failing with "secret not found" errors.

**Estimated:** ~8-12 hours

**Why Critical:** 
- 3 services (`notification`, `shipping`, `shipping-v2`) are currently failing
- Root cause: Helm values structure prevents operator from reading configuration
- Blocks all service deployments

### Task 0.0: Fix Helm Values Structure (CRITICAL - DO FIRST)

**Description:** Restructure `k8s/postgres-operator-zalando/values.yaml` to use flat structure (`configKubernetes:`, `configGeneral:`, etc.) instead of nested structure (`config:`), enabling the operator to read the `enable_cross_namespace_secret` setting.

**Acceptance Criteria:**
- [ ] Replace nested `config:` structure with flat top-level keys
- [ ] Move `enable_cross_namespace_secret: true` to `configKubernetes.enable_cross_namespace_secret: true`
- [ ] Restructure all config sections: `configKubernetes:`, `configGeneral:`, `configUsers:`, `configPostgresql:`, `configConnectionPooler:`, `configBackup:`
- [ ] Update image section to use `ghcr.io/zalando/postgres-operator:v1.15.1`
- [ ] YAML syntax is valid (verify with `helm template` or `kubectl apply --dry-run`)
- [ ] No breaking changes to existing configuration values

**Effort:** 2-3 hours
**Priority:** CRITICAL
**Dependencies:** None
**Assignee:** Unassigned

**Files to Modify:**
- `k8s/postgres-operator-zalando/values.yaml`

**Verification:**
```bash
# Verify YAML syntax
helm template postgres-operator postgres-operator/postgres-operator -f k8s/postgres-operator-zalando/values.yaml --dry-run

# Check structure
grep -A 5 "configKubernetes:" k8s/postgres-operator-zalando/values.yaml
```

---

### Task 0.1: Apply Fixed Configuration

**Description:** Upgrade Helm release with corrected values.yaml and verify operator pod restarts successfully.

**Acceptance Criteria:**
- [ ] Helm release upgraded: `helm upgrade postgres-operator postgres-operator/postgres-operator -n database -f k8s/postgres-operator-zalando/values.yaml`
- [ ] Operator pod restarts and becomes ready
- [ ] Operator pod is running: `kubectl get pods -n database -l app.kubernetes.io/name=postgres-operator`
- [ ] No errors in operator pod logs
- [ ] Operator is ready: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgres-operator -n database --timeout=5m`

**Effort:** 1-2 hours
**Priority:** CRITICAL
**Dependencies:** Task 0.0
**Assignee:** Unassigned

**Verification Commands:**
```bash
# Upgrade Helm release
helm upgrade postgres-operator postgres-operator/postgres-operator -n database -f k8s/postgres-operator-zalando/values.yaml

# Wait for operator to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgres-operator -n database --timeout=5m

# Check operator logs
kubectl logs -n database -l app.kubernetes.io/name=postgres-operator --tail=50
```

---

### Task 0.2: Verify Operator Configuration

**Description:** Verify that `enable_cross_namespace_secret: true` is correctly set in OperatorConfiguration CRD after Helm upgrade.

**Acceptance Criteria:**
- [ ] OperatorConfiguration CRD shows `enable_cross_namespace_secret: true`
- [ ] Command succeeds: `kubectl get operatorconfiguration postgres-operator -n database -o yaml | grep -A 5 enable_cross_namespace_secret`
- [ ] Helm values file has correct setting verified
- [ ] Operator logs show no configuration errors

**Effort:** 1 hour
**Priority:** CRITICAL
**Dependencies:** Task 0.1
**Assignee:** Unassigned

**Verification Commands:**
```bash
# Check OperatorConfiguration CRD
kubectl get operatorconfiguration postgres-operator -n database -o yaml | grep -A 5 enable_cross_namespace_secret

# Verify Helm values
grep "enable_cross_namespace_secret" k8s/postgres-operator-zalando/values.yaml
```

---

### Task 0.3: Verify CRD Format and Update Supporting-DB CRD

**Description:** Verify `supporting-db.yaml` uses `namespace.username` format and add missing `shipping` user for shipping-v2 service.

**Acceptance Criteria:**
- [ ] Verify `supporting-db.yaml` uses `namespace.username` format for users:
  - `notification.notification` (already exists)
  - `shipping.shipping` (already exists)
- [ ] Add missing `shipping` user (without namespace prefix) for shipping-v2 service
- [ ] Database section matches user format
- [ ] CRD applied successfully
- [ ] Operator reconciles CRD changes

**Effort:** 1-2 hours
**Priority:** CRITICAL
**Dependencies:** Task 0.2
**Assignee:** Unassigned

**Files to Modify:**
- `k8s/postgres-operator-zalando/crds/supporting-db.yaml`

**Verification Commands:**
```bash
# Check current CRD format
kubectl get postgresql supporting-db -n user -o yaml | grep -A 10 "users:"
kubectl get postgresql supporting-db -n user -o yaml | grep -A 5 "databases:"

# Apply updated CRD
kubectl apply -f k8s/postgres-operator-zalando/crds/supporting-db.yaml
```

---

### Task 0.4: Trigger Secret Recreation and Verify Cross-Namespace Creation

**Description:** Delete existing secrets in `user` namespace to force operator recreation and verify if secrets are created in target namespaces.

**Acceptance Criteria:**
- [ ] Delete existing secrets in `user` namespace:
  - `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do`
  - `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do`
- [ ] Wait for operator to recreate secrets (check operator logs)
- [ ] Verify if secrets are created in target namespaces:
  - `notification` namespace: `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do`
  - `shipping` namespace: `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do`
- [ ] Verify `shipping.supporting-db.credentials.postgresql.acid.zalan.do` is created in `user` namespace (for shipping-v2)

**Effort:** 1-2 hours
**Priority:** CRITICAL
**Dependencies:** Task 0.3
**Assignee:** Unassigned

**Verification Commands:**
```bash
# Delete existing secrets
kubectl delete secret notification.notification.supporting-db.credentials.postgresql.acid.zalan.do -n user
kubectl delete secret shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do -n user

# Wait and check operator logs
kubectl logs -n database -l app.kubernetes.io/name=postgres-operator --tail=100 | grep -i "cross\|namespace\|secret"

# Verify secrets in target namespaces
kubectl get secret notification.notification.supporting-db.credentials.postgresql.acid.zalan.do -n notification
kubectl get secret shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping
kubectl get secret shipping.supporting-db.credentials.postgresql.acid.zalan.do -n user
```

---

### Task 0.5: Verify RBAC Permissions

**Description:** Verify operator has permissions to create secrets in target namespaces.

**Acceptance Criteria:**
- [ ] Check ClusterRole/Role: `kubectl get clusterrole postgres-operator -o yaml | grep -A 10 secrets`
- [ ] Verify operator has `create`, `get`, `update`, `patch` permissions for secrets
- [ ] If using RoleBinding (not ClusterRoleBinding), verify it exists in target namespaces
- [ ] Operator can create secrets in `notification` and `shipping` namespaces

**Effort:** 1 hour
**Priority:** CRITICAL
**Dependencies:** Task 0.4
**Assignee:** Unassigned

**Verification Commands:**
```bash
# Check ClusterRole
kubectl get clusterrole postgres-operator -o yaml | grep -A 10 secrets

# Check RoleBindings in target namespaces
kubectl get rolebinding -n notification | grep postgres-operator
kubectl get rolebinding -n shipping | grep postgres-operator
```

---

### Task 0.6: Create Fallback Secret YAML Files (If Needed)

**Description:** If operator doesn't create secrets in target namespaces after Phase 0.0-0.5, create declarative YAML files to manually copy secrets from `user` namespace to target namespaces.

**Acceptance Criteria:**
- [ ] Secret YAML file created: `k8s/secrets/notification-supporting-db-secret.yaml`
  - Secret name: `notification.notification.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `notification`
  - Copies `username` and `password` keys from source secret
- [ ] Secret YAML file created: `k8s/secrets/shipping-supporting-db-secret.yaml`
  - Secret name: `shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `shipping`
- [ ] Secret YAML file created: `k8s/secrets/shipping-v2-supporting-db-secret.yaml`
  - Secret name: `shipping.supporting-db.credentials.postgresql.acid.zalan.do`
  - Namespace: `shipping`
- [ ] All YAML files use `Opaque` type and correct namespace
- [ ] YAML files can be applied: `kubectl apply -f k8s/secrets/`

**Effort:** 2-3 hours
**Priority:** CRITICAL (Fallback - Only if Phase 0.0-0.5 fails)
**Dependencies:** Task 0.5 (only if secrets not created automatically)
**Assignee:** Unassigned

**Files to Create:**
- `k8s/secrets/notification-supporting-db-secret.yaml`
- `k8s/secrets/shipping-supporting-db-secret.yaml`
- `k8s/secrets/shipping-v2-supporting-db-secret.yaml`

**Note:** Only proceed if operator doesn't create secrets in target namespaces automatically.

---

### Task 0.7: Update Deployment Script and Verify Services

**Description:** Update `scripts/04-deploy-databases.sh` to apply secret YAML files (if fallback needed) and verify all three services can start successfully.

**Acceptance Criteria:**
- [ ] Deployment script updated to apply secret YAML files after database clusters are ready (if fallback needed)
- [ ] Secrets exist in correct namespaces (verified)
- [ ] Notification service pods start successfully: `kubectl get pods -n notification -l app=notification`
- [ ] Shipping service pods start successfully: `kubectl get pods -n shipping -l app=shipping`
- [ ] Shipping-v2 service pods start successfully: `kubectl get pods -n shipping -l app=shipping-v2`
- [ ] No "secret not found" errors in service logs
- [ ] All services can connect to database

**Effort:** 2-3 hours
**Priority:** CRITICAL
**Dependencies:** Task 0.6 (if fallback needed) or Task 0.5 (if operator creates secrets automatically)
**Assignee:** Unassigned

**Files to Modify:**
- `scripts/04-deploy-databases.sh` (if fallback needed)

**Verification Commands:**
```bash
# Check all secrets exist
kubectl get secret notification.notification.supporting-db.credentials.postgresql.acid.zalan.do -n notification
kubectl get secret shipping.shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping
kubectl get secret shipping.supporting-db.credentials.postgresql.acid.zalan.do -n shipping

# Check services can start
kubectl get pods -n notification -l app=notification
kubectl get pods -n shipping -l app=shipping
kubectl get pods -n shipping -l app=shipping-v2

# Check service logs for errors
kubectl logs -n notification -l app=notification --tail=50 | grep -i "error\|secret"
kubectl logs -n shipping -l app=shipping --tail=50 | grep -i "error\|secret"
kubectl logs -n shipping -l app=shipping-v2 --tail=50 | grep -i "error\|secret"
```

---

## Phase 1: PostgreSQL Performance Tuning (After Critical Fix)

**Goal:** Apply production-ready PostgreSQL parameters to auth-db cluster with HA setup and optimized configuration.

**Estimated:** ~20 hours

### Task 1.1: Update auth-db.yaml with PostgreSQL Performance Parameters

**Description:** Update `k8s/postgres-operator-zalando/crds/auth-db.yaml` with comprehensive PostgreSQL tuning parameters including memory, WAL, query planner, parallelism, autovacuum, and logging settings.

**Acceptance Criteria:**
- [ ] Memory settings added (`shared_buffers: 512MB`, `work_mem: 8MB`, `maintenance_work_mem: 128MB`, `effective_cache_size: 1536MB`)
- [ ] WAL settings configured (`wal_buffers: 16MB`, `wal_level: replica`, `checkpoint_timeout: 15min`, `max_wal_size: 2GB`, `min_wal_size: 512MB`)
- [ ] Query planner settings added (`random_page_cost: 1.1`, `effective_io_concurrency: 200`, `default_statistics_target: 100`)
- [ ] Parallelism settings configured (`max_worker_processes: 4`, `max_parallel_workers: 4`, `max_parallel_workers_per_gather: 2`)
- [ ] Autovacuum settings optimized (`autovacuum_max_workers: 2`, `autovacuum_vacuum_scale_factor: 0.1`)
- [ ] Logging settings configured (`log_statement: mod`, `log_min_duration_statement: 5000`, `log_lock_waits: on`, `log_connections: on`, `log_disconnections: on`, `logging_collector: on`, log rotation settings)
- [ ] Connection settings updated (`max_connections: 200`, `password_encryption: scram-sha-256`)
- [ ] All parameters follow production-ready values from plan.md

**Effort:** 4-6 hours
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

**Files to Modify:**
- `k8s/postgres-operator-zalando/crds/auth-db.yaml`

**Verification:**
```bash
# Verify YAML syntax
kubectl apply --dry-run=client -f k8s/postgres-operator-zalando/crds/auth-db.yaml
```

---

### Task 1.2: Update HA Configuration (3 Nodes)

**Description:** Update `auth-db.yaml` to configure High Availability with 3 nodes (1 leader + 2 standbys) for production-ready setup.

**Acceptance Criteria:**
- [ ] `numberOfInstances` changed from `1` to `3`
- [ ] `wal_level` set to `replica` (for streaming replication)
- [ ] Configuration supports leader-standby replication pattern
- [ ] No breaking changes to existing configuration

**Effort:** 1-2 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files to Modify:**
- `k8s/postgres-operator-zalando/crds/auth-db.yaml`

**Verification:**
```bash
# Check numberOfInstances in CRD
kubectl get postgresql auth-db -n auth -o jsonpath='{.spec.numberOfInstances}'
# Should output: 3
```

---

### Task 1.3: Update Resource Limits (Small, Conservative)

**Description:** Update resource limits in `auth-db.yaml` to small, conservative values (CPU: 1 core, Memory: 2Gi) as per plan requirements.

**Acceptance Criteria:**
- [ ] Resource requests updated (`cpu: 100m`, `memory: 512Mi`)
- [ ] Resource limits updated (`cpu: 1`, `memory: 2Gi`)
- [ ] Limits are small and conservative (not large)
- [ ] Limits accommodate `shared_buffers: 512MB` setting

**Effort:** 2-3 hours
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files to Modify:**
- `k8s/postgres-operator-zalando/crds/auth-db.yaml`

**Verification:**
```bash
# Check resource limits
kubectl get postgresql auth-db -n auth -o jsonpath='{.spec.resources}'
```

---

### Task 1.4: Apply CRD Changes and Verify Cluster Deployment

**Description:** Apply updated `auth-db.yaml` CRD and verify that the cluster restarts successfully with new configuration, ensuring no service disruption.

**Acceptance Criteria:**
- [ ] CRD applied successfully (`kubectl apply -f k8s/postgres-operator-zalando/crds/auth-db.yaml`)
- [ ] Zalando operator processes CRD changes
- [ ] Cluster restarts with new configuration
- [ ] All 3 PostgreSQL pods are running (`kubectl get pods -n auth -l application=spilo,cluster-name=auth-db`)
- [ ] Leader pod is identified (`kubectl get pods -n auth -l application=spilo,cluster-name=auth-db,spilo-role=master`)
- [ ] Standby pods are replicating (`kubectl get pods -n auth -l application=spilo,cluster-name=auth-db,spilo-role=replica`)
- [ ] No errors in operator logs
- [ ] No errors in PostgreSQL pod logs

**Effort:** 2-3 hours
**Priority:** High
**Dependencies:** Task 1.1, Task 1.2, Task 1.3
**Assignee:** Unassigned

**Verification Commands:**
```bash
# Apply CRD
kubectl apply -f k8s/postgres-operator-zalando/crds/auth-db.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=Ready postgresql/auth-db -n auth --timeout=10m

# Check pods
kubectl get pods -n auth -l application=spilo,cluster-name=auth-db

# Check operator logs
kubectl logs -n database -l app.kubernetes.io/name=postgres-operator --tail=50

# Check PostgreSQL logs
kubectl logs -n auth auth-db-0 -c postgres --tail=50
```

**Rollback Plan:**
- Revert `auth-db.yaml` to previous version
- Apply old CRD: `kubectl apply -f k8s/postgres-operator-zalando/crds/auth-db.yaml`
- Operator will restart cluster with previous configuration

---

### Task 1.5: Verify Auth Service Connectivity and Functionality

**Description:** Verify that auth service can connect to the updated auth-db cluster via PgBouncer pooler and that all database operations work correctly.

**Acceptance Criteria:**
- [ ] Auth service pods are running (`kubectl get pods -n auth -l app=auth`)
- [ ] Auth service can connect to PgBouncer pooler
- [ ] Database queries execute successfully
- [ ] No connection errors in auth service logs
- [ ] Health check endpoint returns healthy status
- [ ] Authentication operations work correctly (if testable)

**Effort:** 1-2 hours
**Priority:** High
**Dependencies:** Task 1.4
**Assignee:** Unassigned

**Verification Commands:**
```bash
# Check auth service pods
kubectl get pods -n auth -l app=auth

# Check auth service logs for database connection
kubectl logs -n auth -l app=auth --tail=50 | grep -i "database\|connection\|error"

# Check health endpoint
kubectl exec -n auth $(kubectl get pod -n auth -l app=auth -o jsonpath='{.items[0].metadata.name}') -- curl -s http://localhost:8080/health

# Test database connectivity from auth pod
kubectl exec -n auth $(kubectl get pod -n auth -l app=auth -o jsonpath='{.items[0].metadata.name}') -- psql -h auth-db-pooler.auth.svc.cluster.local -U auth -d auth -c "SELECT 1;"
```

---

## Phase 2: Password Rotation Documentation (Week 1)

**Goal:** Document secure password rotation procedures for Zalando-managed database credentials.

**Estimated:** ~12 hours

### Task 2.1: Create Password Rotation Section in DATABASE.md

**Description:** Create a new "Password Rotation" section in `docs/guides/DATABASE.md` with overview, procedures, and best practices.

**Acceptance Criteria:**
- [ ] New section "Password Rotation" added to `docs/guides/DATABASE.md`
- [ ] Section includes overview of password rotation importance
- [ ] Section references `specs/active/Zalando-operator/research.md` for detailed procedures
- [ ] Section includes rotation schedule (infrastructure: 90 days, application users: 180 days)
- [ ] Section includes security best practices
- [ ] Section is properly formatted and integrated with existing documentation

**Effort:** 3-4 hours
**Priority:** Medium
**Dependencies:** None
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

---

### Task 2.2: Document Native Zalando Password Rotation Procedure

**Description:** Document step-by-step procedure for native Zalando password rotation, including password generation, secret update, operator sync, and service restart.

**Acceptance Criteria:**
- [ ] Step-by-step procedure documented in `docs/guides/DATABASE.md`
- [ ] Password generation commands included (`openssl rand -base64 32`)
- [ ] Secret update procedure documented (`kubectl patch secret`)
- [ ] Operator sync verification steps included
- [ ] Service restart procedure documented
- [ ] Troubleshooting guide included
- [ ] Examples provided for auth-db cluster

**Effort:** 2-3 hours
**Priority:** Medium
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

**Reference:**
- `specs/active/Zalando-operator/research.md` - Password Rotation section

---

### Task 2.3: Document Zero-Downtime Rotation Strategy

**Description:** Document zero-downtime password rotation strategy using dual password approach, including rollback procedures.

**Acceptance Criteria:**
- [ ] Zero-downtime rotation strategy documented
- [ ] Dual password approach explained (temporary `password_new` key)
- [ ] Step-by-step procedure for zero-downtime rotation
- [ ] Rollback procedures documented
- [ ] Verification steps included
- [ ] Best practices for production environments

**Effort:** 2-3 hours
**Priority:** Medium
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

---

### Task 2.4: Add External Secrets Operator Integration Guide (Future)

**Description:** Document External Secrets Operator (ESO) integration approach for automatic password rotation from Vault/AWS Secrets Manager (future implementation).

**Acceptance Criteria:**
- [ ] ESO integration architecture documented
- [ ] Configuration examples provided (SecretStore, ExternalSecret)
- [ ] Automatic rotation setup documented
- [ ] Benefits and use cases explained
- [ ] Marked as "Future Implementation" with clear note
- [ ] References to `specs/active/Zalando-operator/research.md` included

**Effort:** 2-3 hours
**Priority:** Low (Future)
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

**Note:** This is documentation only, actual ESO integration will be implemented in a future phase.

---

## Phase 3: Backup Strategy Documentation (Week 1)

**Goal:** Document backup configuration and disaster recovery procedures for production deployment.

**Estimated:** ~14 hours

### Task 3.1: Create Backup Strategy Section in DATABASE.md

**Description:** Create a new "Backup Strategy" section in `docs/guides/DATABASE.md` with overview, configuration, and procedures.

**Acceptance Criteria:**
- [ ] New section "Backup Strategy" added to `docs/guides/DATABASE.md`
- [ ] Section includes overview of backup importance
- [ ] Section references `specs/active/Zalando-operator/research.md` for detailed procedures
- [ ] Section includes RTO/RPO targets (4 hours / 15 minutes)
- [ ] Section includes backup retention policies (daily: 30 days, weekly: 12 weeks, monthly: 12 months)
- [ ] Section is properly formatted and integrated with existing documentation

**Effort:** 3-4 hours
**Priority:** Medium
**Dependencies:** None
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

---

### Task 3.2: Document WAL-E/WAL-G Configuration

**Description:** Document WAL-E/WAL-G backup configuration for continuous WAL archiving to S3/GCS/Azure, including Spilo environment variables and setup instructions.

**Acceptance Criteria:**
- [ ] WAL-E/WAL-G configuration guide documented
- [ ] S3/GCS/Azure setup instructions included
- [ ] Spilo environment variables documented (`WAL_S3_BUCKET`, `USE_WALG_BACKUP`, `WALG_S3_PREFIX`, AWS credentials)
- [ ] Configuration examples provided for auth-db cluster
- [ ] Backup retention policies documented
- [ ] Marked as "Future Implementation" (requires cloud credentials)
- [ ] References to `specs/active/Zalando-operator/research.md` included

**Effort:** 2-3 hours
**Priority:** Low (Future)
**Dependencies:** Task 3.1
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

**Note:** Actual backup implementation will be done when cloud credentials are available.

---

### Task 3.3: Document Point-in-Time Recovery (PITR) Procedures

**Description:** Document Point-in-Time Recovery procedures including recovery point identification, base backup restoration, and WAL replay.

**Acceptance Criteria:**
- [ ] PITR procedures documented step-by-step
- [ ] Recovery point identification process explained
- [ ] Base backup restoration procedure documented
- [ ] WAL replay procedure documented
- [ ] Recovery target configuration explained (`recovery_target_time`, `recovery_target_action`)
- [ ] Verification steps included
- [ ] Examples provided

**Effort:** 2-3 hours
**Priority:** Medium
**Dependencies:** Task 3.1
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

**Reference:**
- `specs/active/Zalando-operator/research.md` - Backup Strategy section

---

### Task 3.4: Create Disaster Recovery Plan

**Description:** Create comprehensive disaster recovery plan including recovery scenarios, RTO/RPO targets, recovery procedures, and testing requirements.

**Acceptance Criteria:**
- [ ] Disaster recovery plan created
- [ ] Recovery scenarios documented (single cluster failure, complete region failure, data corruption)
- [ ] RTO/RPO targets defined (4 hours / 15 minutes)
- [ ] Recovery procedures documented for each scenario
- [ ] Recovery testing procedures documented (monthly restore tests, quarterly DR drills)
- [ ] Rollback procedures included
- [ ] Success criteria defined

**Effort:** 3-4 hours
**Priority:** Medium
**Dependencies:** Task 3.1, Task 3.2, Task 3.3
**Assignee:** Unassigned

**Files to Modify:**
- `docs/guides/DATABASE.md`

---

## Phase 4: Monitoring & Validation (Week 2)

**Goal:** Validate performance improvements and monitor production metrics to ensure tuning objectives are met.

**Estimated:** ~14 hours

### Task 4.1: Monitor Performance Metrics Baseline

**Description:** Establish baseline performance metrics and monitor key PostgreSQL performance indicators (cache hit ratio, query times, connection pool utilization, WAL checkpoint frequency, autovacuum activity).

**Acceptance Criteria:**
- [ ] Cache hit ratio baseline established (`pg_stat_database.blks_hit / (blks_hit + blks_read)`)
- [ ] Query performance baseline established (p50, p95, p99 response times)
- [ ] Connection pool utilization baseline established (PgBouncer metrics)
- [ ] WAL checkpoint frequency baseline established (`pg_stat_bgwriter.checkpoints_timed`)
- [ ] Autovacuum activity baseline established (`pg_stat_user_tables.n_dead_tup`, `last_vacuum`, `last_autovacuum`)
- [ ] Metrics collected over 24-48 hour period
- [ ] Baseline metrics documented

**Effort:** 2-3 hours (setup) + ongoing monitoring
**Priority:** High
**Dependencies:** Task 1.4, Task 1.5
**Assignee:** Unassigned

**Monitoring Commands:**
```bash
# Cache hit ratio
kubectl exec -n auth auth-db-0 -c postgres -- psql -U postgres -c "SELECT datname, (blks_hit::float / NULLIF(blks_hit + blks_read, 0)) * 100 AS cache_hit_ratio FROM pg_stat_database WHERE datname = 'auth';"

# Query performance (from Prometheus metrics)
# Query: pg_stat_statements_query_duration_seconds

# Connection pool utilization (from PgBouncer metrics)
# Query: pgbouncer_pools_cl_active

# WAL checkpoint frequency
kubectl exec -n auth auth-db-0 -c postgres -- psql -U postgres -c "SELECT * FROM pg_stat_bgwriter;"

# Autovacuum activity
kubectl exec -n auth auth-db-0 -c postgres -- psql -U postgres -c "SELECT schemaname, relname, n_dead_tup, last_vacuum, last_autovacuum FROM pg_stat_user_tables WHERE schemaname = 'public';"
```

---

### Task 4.2: Validate Performance Improvements

**Description:** Compare performance metrics after tuning with baseline metrics to validate that tuning objectives are met (cache hit ratio >95%, query response time <100ms p95, connection pool utilization <80%, WAL checkpoint frequency every 15 minutes).

**Acceptance Criteria:**
- [ ] Cache hit ratio >95% achieved (or improvement documented)
- [ ] Query response time <100ms (p95) achieved (or improvement documented)
- [ ] Connection pool utilization <80% maintained
- [ ] WAL checkpoint frequency approximately every 15 minutes
- [ ] Autovacuum activity is effective (dead tuples cleaned up regularly)
- [ ] Performance improvements documented with before/after comparison
- [ ] Any regressions identified and documented

**Effort:** 2-3 hours
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** Unassigned

**Validation Commands:**
```bash
# Compare cache hit ratio
# Before: baseline from Task 4.1
# After: current metrics

# Compare query performance
# Use Prometheus queries for p50, p95, p99

# Compare connection pool utilization
# Use PgBouncer metrics

# Compare WAL checkpoint frequency
# Use pg_stat_bgwriter metrics
```

---

### Task 4.3: Create Grafana Dashboard for Production Metrics (Optional)

**Description:** Create or update Grafana dashboard for PostgreSQL production metrics including cache hit ratio, query performance, connection pool metrics, WAL and checkpoint metrics, and autovacuum activity.

**Acceptance Criteria:**
- [ ] Grafana dashboard created or updated
- [ ] Dashboard includes cache hit ratio panel
- [ ] Dashboard includes query performance panels (p50, p95, p99)
- [ ] Dashboard includes connection pool utilization panel (PgBouncer)
- [ ] Dashboard includes WAL and checkpoint metrics panels
- [ ] Dashboard includes autovacuum activity panel
- [ ] Dashboard is properly configured with Prometheus data source
- [ ] Dashboard is saved and accessible

**Effort:** 4-6 hours
**Priority:** Low (Optional)
**Dependencies:** Task 4.1
**Assignee:** Unassigned

**Note:** This task is optional. If existing dashboards cover these metrics, this task can be skipped.

---

### Task 4.4: Update CHANGELOG.md

**Description:** Update `CHANGELOG.md` with all changes made in this implementation, including PostgreSQL performance tuning, HA configuration, password rotation documentation, and backup strategy documentation.

**Acceptance Criteria:**
- [ ] New changelog entry created (`[0.10.31]` or next version)
- [ ] Entry includes PostgreSQL performance tuning changes
- [ ] Entry includes HA configuration (3 nodes)
- [ ] Entry includes resource limits updates
- [ ] Entry includes password rotation documentation
- [ ] Entry includes backup strategy documentation
- [ ] Entry includes performance validation results
- [ ] All modified files listed

**Effort:** 1-2 hours
**Priority:** Medium
**Dependencies:** Task 1.4, Task 2.1, Task 3.1, Task 4.2
**Assignee:** Unassigned

**Files to Modify:**
- `CHANGELOG.md`

---

## Dependency Graph

```
Phase 0: Cross-Namespace Secret Fix (CRITICAL - DO FIRST)
├── Task 0.0 (Fix Helm values structure)
│   └── Task 0.1 (Apply fixed configuration)
│       └── Task 0.2 (Verify operator configuration)
│           └── Task 0.3 (Verify CRD format and update)
│               └── Task 0.4 (Trigger secret recreation)
│                   └── Task 0.5 (Verify RBAC permissions)
│                       └── Task 0.6 (Create fallback YAML - if needed)
│                           └── Task 0.7 (Update deployment script and verify)

Phase 1: PostgreSQL Performance Tuning (depends on Phase 0)
├── Task 1.1 (Update auth-db.yaml with parameters)
│   ├── Task 1.2 (Update HA configuration)
│   ├── Task 1.3 (Update resource limits)
│   └── Task 1.4 (Apply CRD and verify) ──┐
│                                          │
└── Task 1.5 (Verify auth service) ◄──────┘

Phase 2: Password Rotation Documentation (parallel with Phase 1)
├── Task 2.1 (Create section)
│   ├── Task 2.2 (Document native procedure)
│   ├── Task 2.3 (Document zero-downtime strategy)
│   └── Task 2.4 (Document ESO integration - future)

Phase 3: Backup Strategy Documentation (parallel with Phase 1)
├── Task 3.1 (Create section)
│   ├── Task 3.2 (Document WAL-E/WAL-G)
│   ├── Task 3.3 (Document PITR procedures)
│   └── Task 3.4 (Create DR plan)

Phase 4: Monitoring & Validation (depends on Phase 1)
├── Task 4.1 (Monitor baseline) ──┐
│                                  │
└── Task 4.2 (Validate improvements) ◄──┘
    │
    ├── Task 4.3 (Create Grafana dashboard - optional)
    └── Task 4.4 (Update CHANGELOG)
```

---

## Quick Reference Checklist

### Phase 0: Cross-Namespace Secret Configuration Fix (CRITICAL - DO FIRST)
- [ ] Task 0.0: Fix Helm Values Structure (CRITICAL - DO FIRST)
- [ ] Task 0.1: Apply Fixed Configuration
- [ ] Task 0.2: Verify Operator Configuration
- [ ] Task 0.3: Verify CRD Format and Update Supporting-DB CRD
- [ ] Task 0.4: Trigger Secret Recreation and Verify Cross-Namespace Creation
- [ ] Task 0.5: Verify RBAC Permissions
- [ ] Task 0.6: Create Fallback Secret YAML Files (If Needed)
- [ ] Task 0.7: Update Deployment Script and Verify Services

### Phase 1: PostgreSQL Performance Tuning
- [ ] Task 1.1: Update auth-db.yaml with PostgreSQL Performance Parameters
- [ ] Task 1.2: Update HA Configuration (3 Nodes)
- [ ] Task 1.3: Update Resource Limits (Small, Conservative)
- [ ] Task 1.4: Apply CRD Changes and Verify Cluster Deployment
- [ ] Task 1.5: Verify Auth Service Connectivity and Functionality

### Phase 2: Password Rotation Documentation
- [ ] Task 2.1: Create Password Rotation Section in DATABASE.md
- [ ] Task 2.2: Document Native Zalando Password Rotation Procedure
- [ ] Task 2.3: Document Zero-Downtime Rotation Strategy
- [ ] Task 2.4: Add External Secrets Operator Integration Guide (Future)

### Phase 3: Backup Strategy Documentation
- [ ] Task 3.1: Create Backup Strategy Section in DATABASE.md
- [ ] Task 3.2: Document WAL-E/WAL-G Configuration
- [ ] Task 3.3: Document Point-in-Time Recovery (PITR) Procedures
- [ ] Task 3.4: Create Disaster Recovery Plan

### Phase 4: Monitoring & Validation
- [ ] Task 4.1: Monitor Performance Metrics Baseline
- [ ] Task 4.2: Validate Performance Improvements
- [ ] Task 4.3: Create Grafana Dashboard for Production Metrics (Optional)
- [ ] Task 4.4: Update CHANGELOG.md

### Phase 5: PostgreSQL Monitoring with Sidecar Exporter
- [ ] Task 5.1: Add Sidecar to auth-db CRD
- [ ] Task 5.2: Add Sidecar to review-db CRD
- [ ] Task 5.3: Add Sidecar to supporting-db CRD
- [ ] Task 5.4: Create PodMonitor for auth-db
- [ ] Task 5.5: Create PodMonitor for review-db
- [ ] Task 5.6: Create PodMonitor for supporting-db
- [ ] Task 5.7: Verify Sidecar Containers
- [ ] Task 5.8: Verify Metrics Collection

### Phase 6: PostgreSQL Log Collection with Vector Sidecar
- [ ] Task 6.1: Create Vector ConfigMap for auth-db
- [ ] Task 6.2: Create Vector ConfigMap for review-db
- [ ] Task 6.3: Create Vector ConfigMap for supporting-db
- [ ] Task 6.4: Add Vector Sidecar to auth-db CRD
- [ ] Task 6.5: Add Vector Sidecar to review-db CRD
- [ ] Task 6.6: Add Vector Sidecar to supporting-db CRD
- [ ] Task 6.7: Verify Vector Sidecar Containers
- [ ] Task 6.8: Verify Logs in Loki

### Phase 7: postgres_exporter Custom Queries Configuration
- [ ] Task 7.1: Create Custom Queries ConfigMap for auth-db
- [ ] Task 7.2: Create Custom Queries ConfigMap for review-db
- [ ] Task 7.3: Create Custom Queries ConfigMap for supporting-db
- [ ] Task 7.4: Update auth-db CRD with Custom Queries Configuration
- [ ] Task 7.5: Update review-db CRD with Custom Queries Configuration
- [ ] Task 7.6: Update supporting-db CRD with Custom Queries Configuration
- [ ] Task 7.7: Verify Custom Metrics in Prometheus

---

**Estimated:** ~60 minutes

#### Task 5.1: Add Sidecar to auth-db CRD

**Description:** Add sidecar configuration to `auth-db` PostgreSQL CRD.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/crds/auth-db.yaml` updated with `sidecars` section
- [ ] Sidecar configured with: `name: exporter`, `image: quay.io/prometheuscommunity/postgres-exporter:v0.18.1`
- [ ] Port `9187` named `exporter`
- [ ] Resource limits: `cpu: 500m`, `memory: 256M`
- [ ] Resource requests: `cpu: 100m`, `memory: 256M`
- [ ] Env vars: `DATA_SOURCE_URI`, `DATA_SOURCE_USER`, `DATA_SOURCE_PASS`, `PG_EXPORTER_AUTO_DISCOVER_DATABASES`
- [ ] CRD applied successfully
- [ ] Pod restarts with sidecar container

**Effort:** 10 minutes  
**Priority:** High  
**Dependencies:** None

#### Task 5.2: Add Sidecar to review-db CRD

**Description:** Add sidecar configuration to `review-db` PostgreSQL CRD.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/crds/review-db.yaml` updated with `sidecars` section
- [ ] Sidecar configured same as Task 5.1
- [ ] CRD applied successfully
- [ ] Pod restarts with sidecar container

**Effort:** 10 minutes  
**Priority:** High  
**Dependencies:** None (can be done in parallel with Task 5.1)

#### Task 5.3: Add Sidecar to supporting-db CRD

**Description:** Add sidecar configuration to `supporting-db` PostgreSQL CRD.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/crds/supporting-db.yaml` updated with `sidecars` section
- [ ] Sidecar configured same as Task 5.1
- [ ] CRD applied successfully
- [ ] Pod restarts with sidecar container

**Effort:** 10 minutes  
**Priority:** High  
**Dependencies:** None (can be done in parallel with Task 5.1, 5.2)

#### Task 5.4: Create PodMonitor for auth-db

**Description:** Create `PodMonitor` CRD for `auth-db` cluster.

**Acceptance Criteria:**
- [ ] `k8s/prometheus/podmonitor-auth-db.yaml` created
- [ ] PodMonitor configured with: `name: postgresql-auth-db`, `namespace: auth`
- [ ] Selector: `application: spilo`, `cluster-name: auth-db`
- [ ] Port: `exporter` (9187)
- [ ] Interval: `15s`, Scrape timeout: `10s`
- [ ] PodMonitor applied successfully
- [ ] Prometheus discovers target

**Effort:** 5 minutes  
**Priority:** High  
**Dependencies:** Task 5.1 (sidecar must be running)

#### Task 5.5: Create PodMonitor for review-db

**Description:** Create `PodMonitor` CRD for `review-db` cluster.

**Acceptance Criteria:**
- [ ] `k8s/prometheus/podmonitor-review-db.yaml` created
- [ ] PodMonitor configured same as Task 5.4, with `cluster-name: review-db` and `namespace: review`
- [ ] PodMonitor applied successfully
- [ ] Prometheus discovers target

**Effort:** 5 minutes  
**Priority:** High  
**Dependencies:** Task 5.2 (sidecar must be running)

#### Task 5.6: Create PodMonitor for supporting-db

**Description:** Create `PodMonitor` CRD for `supporting-db` cluster.

**Acceptance Criteria:**
- [ ] `k8s/prometheus/podmonitor-supporting-db.yaml` created
- [ ] PodMonitor configured same as Task 5.4, with `cluster-name: supporting-db` and `namespace: user`
- [ ] PodMonitor applied successfully
- [ ] Prometheus discovers target

**Effort:** 5 minutes  
**Priority:** High  
**Dependencies:** Task 5.3 (sidecar must be running)

#### Task 5.7: Verify Sidecar Containers

**Description:** Verify sidecar containers are running in all pods.

**Acceptance Criteria:**
- [ ] Sidecar container running in `auth-db-0` pod
- [ ] Sidecar container running in `review-db-0` pod
- [ ] Sidecar container running in `supporting-db-0` pod
- [ ] No errors in sidecar logs for all pods
- [ ] All sidecars show `postgres exporter` in container list

**Effort:** 5 minutes  
**Priority:** High  
**Dependencies:** Task 5.1, 5.2, 5.3

#### Task 5.8: Verify Metrics Collection

**Description:** Verify metrics are accessible and being scraped by Prometheus.

**Acceptance Criteria:**
- [ ] Metrics endpoint accessible on port 9187 in all pods
- [ ] `pg_up` metric = 1 for all clusters (tested via port-forward)
- [ ] Prometheus scraping metrics successfully (targets show as "UP")
- [ ] Metrics visible in Prometheus/Grafana:
  - `pg_up{cluster_name="auth-db"}` = 1
  - `pg_up{cluster_name="review-db"}` = 1
  - `pg_up{cluster_name="supporting-db"}` = 1
- [ ] Other PostgreSQL metrics available (e.g., `pg_stat_database_*`, `pg_stat_activity_*`)

**Effort:** 10 minutes  
**Priority:** High  
**Dependencies:** Task 5.4, 5.5, 5.6, 5.7

---

## Phase 6: PostgreSQL Log Collection with Vector Sidecar

**Goal:** Deploy Vector sidecar containers to collect PostgreSQL logs from `/home/postgres/pgdata/pgroot/pg_log/*.log` and send them to Loki for centralized logging.

**Estimated:** ~90 minutes

**Prerequisites:**
- Loki must be deployed in `monitoring` namespace (via `scripts/03c-deploy-loki.sh`)
- Loki endpoint: `http://loki.monitoring.svc.cluster.local:3100`

#### Task 6.1: Create Vector ConfigMap for auth-db

**Description:** Create ConfigMap with Vector configuration for `auth-db` cluster to collect PostgreSQL logs and send to Loki.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/vector-configs/pg-zalando-vector-config-auth.yaml` created
- [ ] ConfigMap name: `pg-zalando-vector-config`
- [ ] Namespace: `auth`
- [ ] Vector config includes:
  - Source: `/home/postgres/pgdata/pgroot/pg_log/*.log`
  - Multiline parsing with pattern: `'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC'`
  - Labels: `job=postgres`, `namespace=auth`, `container=postgres`, `cluster=auth-db`, `pod=<POD_NAME>`
  - Loki sink endpoint: `http://loki.monitoring.svc.cluster.local:3100`
- [ ] ConfigMap applied successfully

**Effort:** 15 minutes  
**Priority:** Medium  
**Dependencies:** None (Loki should be deployed)

**Files to Create:**
- `k8s/postgres-operator/zalando/vector-configs/pg-zalando-vector-config-auth.yaml`

**Verification:**
```bash
kubectl get configmap pg-zalando-vector-config -n auth
kubectl get configmap pg-zalando-vector-config -n auth -o yaml | grep -A 5 "endpoint:"
```

---

#### Task 6.2: Create Vector ConfigMap for review-db

**Description:** Create ConfigMap with Vector configuration for `review-db` cluster.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/vector-configs/pg-zalando-vector-config-review.yaml` created
- [ ] ConfigMap name: `pg-zalando-vector-config`
- [ ] Namespace: `review`
- [ ] Vector config same as Task 6.1, with `namespace=review`, `cluster=review-db`
- [ ] ConfigMap applied successfully

**Effort:** 10 minutes  
**Priority:** Medium  
**Dependencies:** None (can be done in parallel with Task 6.1)

**Files to Create:**
- `k8s/postgres-operator/zalando/vector-configs/pg-zalando-vector-config-review.yaml`

---

#### Task 6.3: Create Vector ConfigMap for supporting-db

**Description:** Create ConfigMap with Vector configuration for `supporting-db` cluster.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/vector-configs/pg-zalando-vector-config-supporting.yaml` created
- [ ] ConfigMap name: `pg-zalando-vector-config`
- [ ] Namespace: `user`
- [ ] Vector config same as Task 6.1, with `namespace=user`, `cluster=supporting-db`
- [ ] ConfigMap applied successfully

**Effort:** 10 minutes  
**Priority:** Medium  
**Dependencies:** None (can be done in parallel with Task 6.1, 6.2)

**Files to Create:**
- `k8s/postgres-operator/zalando/vector-configs/pg-zalando-vector-config-supporting.yaml`

---

#### Task 6.4: Add Vector Sidecar to auth-db CRD

**Description:** Add Vector sidecar container and volume mount to `auth-db` PostgreSQL CRD.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/crds/auth-db.yaml` updated with Vector sidecar in `sidecars` section
- [ ] Vector sidecar configured with:
  - `name: vector`
  - `image: timberio/vector:0.52.0-alpine`
  - Args: `["--config", "/etc/vector/vector.yaml"]`
  - Env: `POD_NAME` from `fieldRef.fieldPath: metadata.name`
  - Volume mount: `pg-zalando-vector-config` at `/etc/vector/vector.yaml`
  - Resource limits: `cpu: 200m`, `memory: 128Mi`
  - Resource requests: `cpu: 50m`, `memory: 64Mi`
- [ ] `additionalVolumes` section added with ConfigMap volume for Vector
- [ ] CRD applied successfully
- [ ] Pod restarts with Vector sidecar container

**Effort:** 15 minutes  
**Priority:** Medium  
**Dependencies:** Task 6.1 (ConfigMap must exist)

**Files to Modify:**
- `k8s/postgres-operator/zalando/crds/auth-db.yaml`

**Verification:**
```bash
kubectl get pod -n auth -l cluster-name=auth-db -o jsonpath='{.items[0].spec.containers[*].name}' | grep vector
kubectl logs -n auth -l cluster-name=auth-db -c vector --tail=20
```

---

#### Task 6.5: Add Vector Sidecar to review-db CRD

**Description:** Add Vector sidecar container and volume mount to `review-db` PostgreSQL CRD.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/crds/review-db.yaml` updated with Vector sidecar
- [ ] Vector sidecar configured same as Task 6.4
- [ ] `additionalVolumes` section added with ConfigMap volume
- [ ] CRD applied successfully
- [ ] Pod restarts with Vector sidecar container

**Effort:** 10 minutes  
**Priority:** Medium  
**Dependencies:** Task 6.2 (ConfigMap must exist)

**Files to Modify:**
- `k8s/postgres-operator/zalando/crds/review-db.yaml`

---

#### Task 6.6: Add Vector Sidecar to supporting-db CRD

**Description:** Add Vector sidecar container and volume mount to `supporting-db` PostgreSQL CRD.

**Acceptance Criteria:**
- [ ] `k8s/postgres-operator/zalando/crds/supporting-db.yaml` updated with Vector sidecar
- [ ] Vector sidecar configured same as Task 6.4
- [ ] `additionalVolumes` section added with ConfigMap volume
- [ ] CRD applied successfully
- [ ] Pod restarts with Vector sidecar container

**Effort:** 10 minutes  
**Priority:** Medium  
**Dependencies:** Task 6.3 (ConfigMap must exist)

**Files to Modify:**
- `k8s/postgres-operator/zalando/crds/supporting-db.yaml`

---

#### Task 6.7: Verify Vector Sidecar Containers

**Description:** Verify Vector sidecar containers are running in all PostgreSQL pods.

**Acceptance Criteria:**
- [ ] Vector sidecar container running in `auth-db-0` pod
- [ ] Vector sidecar container running in `review-db-0` pod
- [ ] Vector sidecar container running in `supporting-db-0` pod
- [ ] No errors in Vector sidecar logs for all pods
- [ ] All Vector sidecars show in container list: `kubectl get pod -n <namespace> <pod-name> -o jsonpath='{.spec.containers[*].name}'`

**Effort:** 10 minutes  
**Priority:** Medium  
**Dependencies:** Task 6.4, 6.5, 6.6

**Verification Commands:**
```bash
# Check auth-db
kubectl get pod -n auth -l cluster-name=auth-db -o jsonpath='{.items[0].spec.containers[*].name}'

# Check review-db
kubectl get pod -n review -l cluster-name=review-db -o jsonpath='{.items[0].spec.containers[*].name}'

# Check supporting-db
kubectl get pod -n user -l cluster-name=supporting-db -o jsonpath='{.items[0].spec.containers[*].name}'

# Check Vector logs
kubectl logs -n auth -l cluster-name=auth-db -c vector --tail=20
kubectl logs -n review -l cluster-name=review-db -c vector --tail=20
kubectl logs -n user -l cluster-name=supporting-db -c vector --tail=20
```

---

#### Task 6.8: Verify Logs in Loki

**Description:** Verify PostgreSQL logs are being collected by Vector and appearing in Loki.

**Acceptance Criteria:**
- [ ] Logs queryable in Loki via LogQL: `{job="postgres", namespace="auth", cluster="auth-db"}`
- [ ] Logs queryable for review-db: `{job="postgres", namespace="review", cluster="review-db"}`
- [ ] Logs queryable for supporting-db: `{job="postgres", namespace="user", cluster="supporting-db"}`
- [ ] Log entries contain PostgreSQL log messages (connections, queries, errors, etc.)
- [ ] Labels are correctly set: `job`, `namespace`, `pod`, `container`, `cluster`
- [ ] Logs visible in Grafana (if Loki datasource configured)

**Effort:** 15 minutes  
**Priority:** Medium  
**Dependencies:** Task 6.7, Loki must be deployed and running

**Verification Commands:**
```bash
# Port-forward to Loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# Query logs via Loki API
curl -G -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="postgres", namespace="auth"}' \
  --data-urlencode 'start=1699999999000000000' \
  --data-urlencode 'end=1700000000000000000' | jq

# Or use Grafana Explore with Loki datasource
# Query: {job="postgres", namespace="auth", cluster="auth-db"}
```

---

## Risk Areas

| Task | Risk | Mitigation |
|------|------|------------|
| Task 0.0 | Helm values structure fix breaks existing configuration | Backup current values.yaml, verify all config sections are properly restructured, test with `helm template --dry-run` |
| Task 0.1 | Operator pod fails to restart after Helm upgrade | Check operator logs, verify Helm chart compatibility, rollback if needed |
| Task 0.4 | Operator doesn't create secrets in target namespaces | Check operator logs for errors, verify RBAC permissions, proceed to Task 0.6 (fallback solution) |
| Task 0.6 | Secret YAML files have incorrect data | Extract secret data from source namespace, verify base64 encoding, test YAML syntax |
| Task 0.7 | Services still fail after secret creation | Verify secret names match Helm values, check service pod logs, verify namespace matches |
| Task 1.4 | Cluster restart causes service disruption | Apply during maintenance window, verify operator handles updates gracefully, have rollback plan ready |
| Task 1.5 | Auth service cannot connect after changes | Verify PgBouncer pooler is still accessible, check SSL configuration, verify secret references |
| Task 4.2 | Performance improvements not achieved | Investigate query patterns, adjust `shared_buffers` if needed, consider workload-specific tuning |
| Task 2.2, 2.3 | Password rotation causes downtime | Use zero-downtime rotation strategy, test in staging first, document rollback procedures |
| Task 3.2, 3.3, 3.4 | Backup procedures incomplete | Reference research.md for detailed procedures, test restore procedures before production |
| Task 6.4, 6.5, 6.6 | Vector sidecar causes pod restart | Pods will restart when CRD is updated, ensure during maintenance window if needed |
| Task 6.8 | Logs not appearing in Loki | Check Vector sidecar logs for errors, verify Loki endpoint is reachable, check network policies |
| Task 7.4, 7.5, 7.6 | Custom queries not working | Verify pg_stat_statements extension is enabled, check ConfigMap mount, verify environment variable path |
| Task 7.7 | Metrics not appearing | Check postgres_exporter logs for query errors, verify permissions on pg_stat_statements view, check Prometheus scraping |

---

## Next Steps

1. ✅ Review task breakdown (this document)
2. **CRITICAL (DO FIRST)**: Begin with Phase 0, Task 0.0 (Fix Helm Values Structure)
3. Assign tasks to developers
4. Run `/implement Zalando-operator` to start execution
5. After Phase 0 complete, proceed to Phase 1, Task 1.1 (Update auth-db.yaml with PostgreSQL Performance Parameters)

---

*Tasks created with SDD 2.0*
