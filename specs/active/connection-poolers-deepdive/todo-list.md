# Implementation Todo List: Connection Poolers Deep Dive - PgCat HA & PgDog for supporting-db

**Task ID:** connection-poolers-deepdive
**Started:** 2025-12-30
**Status:** Ready for Implementation
**Version:** 2.0

---

## Phase 1: Configuration Update (Foundation)

- [ ] Task 1.1: Backup Current ConfigMap (estimated: 2m)
  - Files: Create backup file
  - Dependencies: None
  
- [ ] Task 1.2: Update ConfigMap with Replica Servers (estimated: 10m)
  - Files: `k8s/pgcat/transaction/configmap.yaml`
  - Dependencies: Task 1.1

- [ ] Task 1.3: Apply ConfigMap and Reload PgCat (estimated: 3m)
  - Files: Apply ConfigMap to cluster
  - Dependencies: Task 1.2

- [ ] Task 1.4: Verify Configuration Loaded (estimated: 5m)
  - Files: Check logs and verify
  - Dependencies: Task 1.3

## Phase 2: Monitoring Integration

- [ ] Task 2.1: Create ServiceMonitor CRD (estimated: 10m)
  - Files: `k8s/prometheus/servicemonitors/servicemonitor-pgcat-transaction.yaml`
  - Dependencies: Phase 1 complete

- [ ] Task 2.2: Apply ServiceMonitor (estimated: 3m)
  - Files: Apply ServiceMonitor to cluster
  - Dependencies: Task 2.1

- [ ] Task 2.3: Verify Prometheus Discovery (estimated: 5m)
  - Files: Check Prometheus targets
  - Dependencies: Task 2.2

- [ ] Task 2.4: Verify Metrics Available (estimated: 5m)
  - Files: Query Prometheus metrics
  - Dependencies: Task 2.3

## Phase 3: Verification & Testing

- [ ] Task 3.1: Verify Read Query Routing (estimated: 5m)
  - Files: Test SELECT queries
  - Dependencies: Phase 2 complete

- [ ] Task 3.2: Verify Write Query Routing (estimated: 5m)
  - Files: Test INSERT/UPDATE queries
  - Dependencies: Task 3.1

- [ ] Task 3.3: Verify Load Balancing (estimated: 5m)
  - Files: Test query distribution
  - Dependencies: Task 3.1

- [ ] Task 3.4: Test Failover (Optional) (estimated: 10m)
  - Files: Test replica failure scenario
  - Dependencies: Task 3.3

- [ ] Task 3.5: Verify Backward Compatibility (estimated: 5m)
  - Files: Test cart/order services
  - Dependencies: Task 3.2

- [ ] Task 3.6: Verify Monitoring Integration (estimated: 5m)
  - Files: Check all metrics available
  - Dependencies: Task 3.5

## Phase 4: PgDog Deployment

- [x] Task 4.1: Add PgDog Helm Repository (estimated: 5m)
  - Files: `kubernetes/clusters/local/sources/helm/pgdog.yaml`
  - Dependencies: None

- [x] Task 4.2: Create PgDog HelmRelease and Values (estimated: 10m)
  - Files: `kubernetes/infra/configs/databases/poolers/supporting/helmrelease.yaml`, `kubernetes/infra/configs/databases/poolers/supporting/kustomization.yaml`
  - Dependencies: Task 4.1

- [ ] Task 4.3: Apply PgDog Deployment (estimated: 3m)
  - Files: Apply via Flux GitOps
  - Dependencies: Task 4.2

- [ ] Task 4.4: Verify PgDog Configuration (estimated: 5m)
  - Files: Check logs and admin database
  - Dependencies: Task 4.3

## Phase 5: PgDog Monitoring Integration

- [ ] Task 5.1: Create ServiceMonitor for PgDog (estimated: 8m)
  - Files: `kubernetes/infra/configs/monitoring/servicemonitors/pgdog-supporting.yaml`
  - Dependencies: Phase 4 complete

- [ ] Task 5.2: Apply ServiceMonitor and Verify Discovery (estimated: 5m)
  - Files: Apply ServiceMonitor and check Prometheus
  - Dependencies: Task 5.1

- [ ] Task 5.3: Verify PgDog Metrics Available (estimated: 5m)
  - Files: Query Prometheus metrics
  - Dependencies: Task 5.2

## Phase 6: Service Configuration Updates

- [x] Task 6.1: Update User Service Configuration (estimated: 3m)
  - Files: `kubernetes/apps/user.yaml` (DB_HOST, DB_PORT, migrations)
  - Dependencies: Phase 4 complete

- [x] Task 6.2: Update Notification Service Configuration (estimated: 3m)
  - Files: `kubernetes/apps/notification.yaml` (DB_HOST, DB_PORT, migrations)
  - Dependencies: Task 6.1

- [x] Task 6.3: Update Shipping Service Configuration (estimated: 3m)
  - Files: `kubernetes/apps/shipping.yaml`, `kubernetes/apps/shipping-v2.yaml` (DB_HOST, DB_PORT, migrations)
  - Dependencies: Task 6.2

- [ ] Task 6.4: Apply Service Updates and Verify (estimated: 5m)
  - Files: Apply via Flux and check service logs
  - Dependencies: Task 6.3

## Phase 7: PgDog Verification & Testing

- [ ] Task 7.1: Verify Multi-Database Routing (estimated: 5m)
  - Files: Test connections to all 3 databases
  - Dependencies: Phase 6 complete

- [ ] Task 7.2: Verify Service Connectivity (estimated: 5m)
  - Files: Check service logs and pods
  - Dependencies: Task 7.1

- [ ] Task 7.3: Verify PgDog Monitoring (estimated: 5m)
  - Files: Check Prometheus metrics
  - Dependencies: Task 7.2

- [ ] Task 7.4: Verify Backward Compatibility (estimated: 5m)
  - Files: Test all services work correctly
  - Dependencies: Task 7.2

## Phase 8: Documentation Update

- [x] Task 8.1: Update DATABASE.md with HA Integration and PgDog (estimated: 15m)
  - Files: `docs/guides/DATABASE.md`
  - Dependencies: Phase 7 complete
  - Status: Added PgDog section to Connection Poolers

---

## Progress Log

| Date | Completed | Notes |
|------|-----------|-------|
| 2025-12-30 | Starting implementation | Creating todo-list and beginning Phase 1 |
| 2025-12-30 | Phase 1-4 code complete | All code changes done. Tasks 1.3-1.4, 2.2-2.4, 3.1-3.6 require kubectl commands for manual verification |
| 2025-12-30 | Manual verification done | User applied ConfigMap and ServiceMonitor manually. PgCat pods reloaded successfully. Diagram updated with CloudNativePG services. |
| 2026-01-13 | Tasks updated | Added Phase 4-8 for PgDog deployment (supporting-db pooler) |

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 28 |
| Completed | 0 |
| Remaining | 28 |
| Estimated Effort | ~150 minutes (2.5 hours) |
| Phases | 8 (Phase 1-3: PgCat HA, Phase 4-7: PgDog, Phase 8: Documentation) |