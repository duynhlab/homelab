# Remaining Todos: PostgreSQL Database Integration

> **Status**: ~50% Complete  
> **Last Updated**: December 14, 2025

---

## Summary

**Completed**: Infrastructure files, code templates, Helm values, deployment script  
**Remaining**: Deployment actions, code implementation, monitoring, testing

---

## Phase 1: Infrastructure Setup (Files Created, Deployment Pending)

### ⏳ Task 1.1: Deploy Zalando Postgres Operator
- [x] Created `k8s/postgres-operator-zalando/values.yaml` ✅
- [ ] **User Action**: Add Helm repo: `helm repo add postgres-operator https://opensource.zalando.com/postgres-operator/charts/postgres-operator`
- [ ] **User Action**: Deploy: `helm upgrade --install postgres-operator postgres-operator/postgres-operator -f k8s/postgres-operator-zalando/values.yaml -n monitoring --create-namespace --wait`
- [ ] **User Action**: Verify: `kubectl get pods -n monitoring -l app.kubernetes.io/name=postgres-operator`

### ⏳ Task 1.2: Deploy CrunchyData Postgres Operator
- [x] Created `k8s/postgres-operator-crunchydata/values.yaml` ✅
- [ ] **User Action**: Add Helm repo: `helm repo add postgres-operator-crunchydata https://charts.crunchydata.com`
- [ ] **User Action**: Deploy operator
- [ ] **User Action**: Verify deployment

### ⏳ Task 1.3-1.7: Create Database Clusters
- [x] All CRDs created ✅ (review-db, auth-db, supporting-db, product-db, transaction-db)
- [ ] **User Action**: Apply CRDs: `kubectl apply -f k8s/postgres-operator-zalando/crds/`
- [ ] **User Action**: Apply CRDs: `kubectl apply -f k8s/postgres-operator-crunchydata/crds/`
- [ ] **User Action**: Wait for clusters ready (5-10 minutes)
- [ ] **User Action**: Verify clusters: `kubectl get postgresql -A` and `kubectl get postgrescluster -A`

**Or use script**: `./scripts/04-deploy-databases.sh` (handles all of the above)

---

## Phase 2: Connection Poolers (Files Created, Deployment Pending)

### ⏳ Task 2.1: PgBouncer for Auth
- [x] Verified PgBouncer is built into Zalando operator ✅
- [ ] **User Action**: Verify sidecar after cluster deployment

### ⏳ Task 2.2-2.3: PgCat Poolers
- [x] All PgCat manifests created ✅ (product, transaction)
- [ ] **User Action**: Apply: `kubectl apply -f k8s/pgcat/product/`
- [ ] **User Action**: Apply: `kubectl apply -f k8s/pgcat/transaction/`
- [ ] **User Action**: Verify pods: `kubectl get pods -n product -l app=pgcat-product`

**Or use script**: `./scripts/04-deploy-databases.sh` (includes PgCat deployment)

---

## Phase 3: Database Schemas & Migrations

### ⏳ Task 3.1: Design Database Schemas
- [x] Schemas designed in plan.md ✅
- [ ] **TODO**: Document in `docs/database/SCHEMA_DESIGN.md`

### ✅ Task 3.2: SQL Migration Scripts
- [x] All 8 SQL scripts created ✅
- [x] Scripts are idempotent (IF NOT EXISTS) ✅

### ⏳ Task 3.3: Migrate to Flyway Migration System ⭐ NEW

**Status**: Dockerfiles and migration files created, ready for implementation

**Related Research**: [research-flyway-migration.md](./research-flyway-migration.md)  
**Tasks Summary**: [FLYWAY_TASKS_SUMMARY.md](./FLYWAY_TASKS_SUMMARY.md)

#### ✅ Task 3.3.1: Create Flyway Migration Dockerfiles
- [x] Created all 7 Dockerfiles ✅
- [ ] **TODO**: Test Dockerfile builds locally

#### ✅ Task 3.3.2: Convert Migration Files to Flyway Format
- [x] Created all 7 `V1__Initial_schema.sql` files ✅
- [x] Removed `IF NOT EXISTS` clauses ✅
- [ ] **TODO**: Test migration files in Flyway container

#### ⏳ Task 3.3.3: Build Migration Images
- [ ] **TODO**: Update `scripts/05-build-microservices.sh` to build migration images
- [ ] **TODO**: Build and push migration images to registry

#### ⏳ Task 3.3.4: Update Helm Chart Templates for Flyway
- [ ] **TODO**: Update `charts/templates/deployment.yaml` with Flyway init container
- [ ] **TODO**: Remove `charts/templates/configmap-migrations.yaml` (not needed)
- [ ] **TODO**: Update `charts/values.yaml` with new migrations structure
- [ ] **TODO**: Update all service values files (remove `migrations.sql`, add `migrations.image`)

#### ⏳ Task 3.3.5: Test Flyway Migrations
- [ ] **TODO**: Test with one service (auth)
- [ ] **TODO**: Test with existing database (baseline)
- [ ] **TODO**: Apply to all services

---

## Phase 4: Go Code Integration

### ✅ Task 4.1: DatabaseConfig
- [x] Added to `services/pkg/config/config.go` ✅

### ✅ Task 4.2: database.go Files
- [x] Created for 9 services ✅ (auth, user, product, cart, order, review, notification, shipping, shipping-v2)

### ⏳ Task 4.3: Update Service Handlers to Use Database
- [ ] **TODO**: For each service (9 services):
  - Update `services/cmd/{service}/main.go`:
    - Initialize database connection: `database.Connect()`
    - Pass DB connection to handlers
  - Update `services/internal/{service}/logic/v1/service.go`:
    - Replace mock data with database queries
    - Implement CRUD operations using `database.GetDB()`
  - Update `services/internal/{service}/logic/v2/service.go`:
    - Same as v1
  - Update `services/internal/{service}/web/v1/handler.go`:
    - Use database-backed service layer
  - Update `services/internal/{service}/web/v2/handler.go`:
    - Same as v1
- [ ] **TODO**: Add error handling for database errors
- [ ] **TODO**: Add database tracing spans (optional)
- [ ] **TODO**: Test each endpoint

**Estimated Time**: 8-12 hours (largest remaining task)

### ⏳ Task 4.4: Add PostgreSQL Driver
- [ ] **User Action**: Run `cd services && go get github.com/lib/pq`
- [ ] **User Action**: Verify `go.mod` and `go.sum` updated

---

## Phase 5: Helm Charts & Configuration

### ⏳ Task 5.1: Create Kubernetes Secrets
- [x] Created `k8s/secrets/README.md` ✅
- [ ] **User Action**: Create secrets manually (see `k8s/secrets/README.md`):
  ```bash
  kubectl create secret generic auth-db-secret --from-literal=password='postgres' -n auth
  kubectl create secret generic review-db-secret --from-literal=password='postgres' -n review
  kubectl create secret generic product-db-secret --from-literal=password='postgres' -n product
  kubectl create secret generic transaction-db-secret --from-literal=password='postgres' -n cart
  kubectl create secret generic supporting-db-secret --from-literal=password='postgres' -n user
  ```

### ✅ Task 5.2: Update Helm Values
- [x] Updated 8 service values files ✅ (auth, review, product, cart, order, user, notification, shipping-v2)
- [ ] **Optional**: Update `charts/values/shipping.yaml` (no database for now)
- [x] **Update `charts/values/shipping-v2.yaml`** ✅ Updated (uses shared `supporting-db` cluster)

### ⏳ Task 5.3: Test Helm Chart Deployment
- [ ] **TODO**: Deploy one service: `helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth`
- [ ] **TODO**: Verify env vars: `kubectl exec -n auth <pod-name> -- env | grep DB_`
- [ ] **TODO**: Check logs for database connection
- [ ] **TODO**: Test service endpoint

---

## Phase 6: Monitoring

### ⏳ Task 6.1: Deploy postgres_exporter
- [x] Created `k8s/postgres-exporter/values.yaml` ✅
- [ ] **TODO**: Create exporter deployments for 5 clusters:
  - `k8s/postgres-exporter/product-exporter.yaml`
  - `k8s/postgres-exporter/review-exporter.yaml`
  - `k8s/postgres-exporter/auth-exporter.yaml`
  - `k8s/postgres-exporter/transaction-exporter.yaml`
  - `k8s/postgres-exporter/supporting-exporter.yaml`
- [ ] **TODO**: Deploy via Helm: `helm upgrade --install postgres-exporter-{cluster} prometheus-community/prometheus-postgres-exporter -f k8s/postgres-exporter/{cluster}-exporter.yaml -n monitoring`
- [ ] **TODO**: Verify exporters running

### ⏳ Task 6.2: Create ServiceMonitors
- [ ] **TODO**: Create ServiceMonitor for each exporter (5 files)
- [ ] **TODO**: Apply: `kubectl apply -f k8s/postgres-exporter/*-servicemonitor.yaml`
- [ ] **TODO**: Verify Prometheus discovers targets

### ⏳ Task 6.3: Verify Metrics
- [ ] **TODO**: Query PostgreSQL metrics in Prometheus
- [ ] **TODO**: Verify `pg_up = 1` for all clusters

---

## Phase 7: Deployment Scripts

### ✅ Task 7.1: Deployment Script
- [x] Created `scripts/04-deploy-databases.sh` ✅

### ✅ Task 7.2: Documentation
- [x] Updated `AGENTS.md` ✅

### ⏳ Task 7.3: Test Full Deployment Flow
- [ ] **TODO**: Test end-to-end deployment
- [ ] **TODO**: Verify all components working

---

## Phase 8: Testing & Validation

### ⏳ Task 8.1: Test Database Connections
- [ ] **TODO**: Test all 9 services connect to databases
- [ ] **TODO**: Test CRUD operations
- [ ] **TODO**: Verify data persists

### ⏳ Task 8.2: Test k6 Load Testing
- [ ] **TODO**: Run k6 load test
- [ ] **TODO**: Verify data created in databases
- [ ] **TODO**: Check database metrics during load

### ⏳ Task 8.3: Verify Monitoring Metrics
- [ ] **TODO**: Check Prometheus for PostgreSQL metrics
- [ ] **TODO**: Verify metrics update during load test

### ⏳ Task 8.4: Test HA Failover
- [ ] **TODO**: Test Patroni failover for Cart+Order cluster
- [ ] **TODO**: Verify failover time < 30 seconds
- [ ] **TODO**: Verify no data loss

---

## Priority Order

### High Priority (Required for Basic Functionality)
1. **Task 4.4**: Add `github.com/lib/pq` to go.mod (user action - 5 min)
2. **Task 3.3.3**: Build migration images (1-2 hours)
3. **Task 3.3.4**: Update Helm charts for Flyway (3-4 hours)
4. **Task 3.3.5**: Test Flyway migrations (3-4 hours)
5. **Task 5.1**: Create Kubernetes Secrets (user action - 10 min)
6. **Task 5.3**: Test Helm deployment (1-2 hours)

### Medium Priority (Required for Full Functionality)
6. **Task 6.1-6.2**: Deploy postgres_exporter and ServiceMonitors (3-4 hours)
7. **Task 8.1**: Test database connections (2-3 hours)
8. **Task 8.2**: Test k6 load testing (3-4 hours)

### Low Priority (Nice to Have)
9. **Task 3.1**: Document schemas in `docs/database/SCHEMA_DESIGN.md` (1 hour)
10. **Task 6.3**: Verify metrics in Prometheus (1 hour)
11. **Task 8.4**: Test HA failover (1-2 hours)
12. **Task 7.3**: Test full deployment flow (2-3 hours)

---

## Quick Start (Next Steps)

1. **Immediate** (User actions):
   ```bash
   # Add PostgreSQL driver
   cd services && go get github.com/lib/pq
   
   # Deploy databases (step 4, before build)
   ./scripts/04-deploy-databases.sh
   
   # Create secrets
   kubectl create secret generic auth-db-secret --from-literal=password='postgres' -n auth
   # ... (see k8s/secrets/README.md for all secrets)
   
   # Build services (step 5, renamed from 04)
   ./scripts/05-build-microservices.sh
   
   # Deploy services (step 6, renamed from 05)
   ./scripts/06-deploy-microservices.sh --local
   ```

2. **Next** (Code implementation):
   - Update service handlers (Task 4.3) - 8-12 hours
   - Create init containers (Task 3.3) - 2-3 hours
   - Test deployment (Task 5.3) - 1-2 hours

3. **Then** (Monitoring & Testing):
   - Deploy postgres_exporter (Task 6.1-6.2) - 3-4 hours
   - Test connections (Task 8.1) - 2-3 hours
   - Test k6 (Task 8.2) - 3-4 hours

---

**Total Remaining Estimated Time**: ~25-35 hours (excluding user actions and testing)

---

## Script Renaming Status

✅ **Completed Renames:**
- `04-deploy-databases.sh` - Created (correct order, step 4)
- `05-build-microservices.sh` - Renamed from `04-build-microservices.sh`
- `06-deploy-microservices.sh` - Renamed from `05-deploy-microservices.sh`
- `07-deploy-k6.sh` - Renamed from `06-deploy-k6.sh`
- `08-deploy-slo.sh` - Renamed from `07-deploy-slo.sh`
- `09-setup-access.sh` - Renamed from `08-setup-access.sh`
- `10-reload-dashboard.sh` - Renamed from `09-reload-dashboard.sh`

✅ **All Scripts Renamed:**
- `04-deploy-databases.sh` - Created (step 4)
- `05-build-microservices.sh` - Renamed from 04
- `06-deploy-microservices.sh` - Renamed from 05
- `07-deploy-k6.sh` - Renamed from 06
- `08-deploy-slo.sh` - Renamed from 07
- `09-setup-access.sh` - Renamed from 08
- `10-reload-dashboard.sh` - Renamed from 09
- `11-diagnose-latency.sh` - Renamed from 10
- `12-error-budget-alert.sh` - Renamed from 11

**Status**: ✅ All scripts correctly numbered. Old files deleted, new files created.
