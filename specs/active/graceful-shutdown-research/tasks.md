# Implementation Tasks: Graceful Shutdown Enhancement for Go Microservices

**Task ID:** graceful-shutdown-research
**Created:** 2025-12-25
**Status:** Ready for Implementation
**Based on:** plan.md

---

## Summary

| Metric | Value |
|--------|-------|
| Total Tasks | 25 |
| Estimated Effort | ~3 days (24 hours) |
| Phases | 5 |
| Critical Path | Configuration → Signal Handling → Cleanup → K8s Config → Testing |
| Services Affected | 9 microservices |

---

## Phase 1: Configuration Foundation

**Goal:** Add configuration support for shutdown timeout across all services.
**Estimated:** 4 hours

### Task 1.1: Create `getShutdownTimeout()` Helper Function

**Description:** Create a helper function to read and validate `SHUTDOWN_TIMEOUT` environment variable with proper error handling and validation.

**Acceptance Criteria:**
- [ ] Function reads `SHUTDOWN_TIMEOUT` from environment
- [ ] Default value: 10 seconds (if env var not set)
- [ ] Validates timeout format using `time.ParseDuration`
- [ ] Validates timeout is positive and <= 60 seconds (safety limit)
- [ ] Returns default on invalid values (with silent fallback or logging)
- [ ] Function is reusable across all services

**Effort:** 2 hours
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

**Files:**
- `services/cmd/{service}/main.go` (add helper function)

---

### Task 1.2: Add SHUTDOWN_TIMEOUT to Helm Values Files

**Description:** Add `SHUTDOWN_TIMEOUT` environment variable to all 9 service Helm values files.

**Acceptance Criteria:**
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/auth.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/user.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/product.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/cart.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/order.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/review.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/notification.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/shipping.yaml`
- [ ] `SHUTDOWN_TIMEOUT` added to `charts/values/shipping-v2.yaml`
- [ ] All values set to `"10s"` (default, can be overridden)

**Effort:** 1 hour
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

**Files:**
- `charts/values/{service}.yaml` (all 9 services)

---

### Task 1.3: Update Configuration Documentation

**Description:** Document `SHUTDOWN_TIMEOUT` environment variable in configuration guide.

**Acceptance Criteria:**
- [ ] `SHUTDOWN_TIMEOUT` documented in `docs/guides/CONFIGURATION.md`
- [ ] Default value explained (10s)
- [ ] Format explained (Go duration format: "10s", "30s", etc.)
- [ ] Validation rules documented (positive, max 60s)
- [ ] Examples provided
- [ ] Helm values configuration documented

**Effort:** 1 hour
**Priority:** Medium
**Dependencies:** Task 1.1, Task 1.2
**Assignee:** Unassigned

**Files:**
- `docs/guides/CONFIGURATION.md`

---

## Phase 2: Signal Handling Migration

**Goal:** Migrate all 9 services from channel-based to context-based signal handling.
**Estimated:** 8 hours

### Task 2.1: Migrate Auth Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in auth service.

**Acceptance Criteria:**
- [ ] Replace `signal.Notify(quit, ...)` with `signal.NotifyContext`
- [ ] Use `ctx.Done()` instead of `<-quit`
- [ ] Add `defer stop()` for proper cleanup
- [ ] Maintain backward compatibility (handles SIGTERM and SIGINT)
- [ ] Code follows modern Go idioms
- [ ] Test locally: Ctrl+C (SIGINT) works
- [ ] Test locally: SIGTERM works

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/auth/main.go`

---

### Task 2.2: Migrate User Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in user service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to user service
- [ ] Consistent pattern with auth service

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1 (for pattern consistency)
**Assignee:** Unassigned

**Files:**
- `services/cmd/user/main.go`

---

### Task 2.3: Migrate Product Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in product service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to product service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/product/main.go`

---

### Task 2.4: Migrate Cart Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in cart service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to cart service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/cart/main.go`

---

### Task 2.5: Migrate Order Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in order service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to order service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/order/main.go`

---

### Task 2.6: Migrate Review Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in review service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to review service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/review/main.go`

---

### Task 2.7: Migrate Notification Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in notification service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to notification service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/notification/main.go`

---

### Task 2.8: Migrate Shipping Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in shipping service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to shipping service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/shipping/main.go`

---

### Task 2.9: Migrate Shipping-v2 Service Signal Handling

**Description:** Replace `signal.Notify` with `signal.NotifyContext` in shipping-v2 service.

**Acceptance Criteria:**
- [ ] Same as Task 2.1, applied to shipping-v2 service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/shipping-v2/main.go`

---

## Phase 3: Explicit Cleanup Sequence

**Goal:** Implement explicit resource cleanup sequence across all 9 services.
**Estimated:** 6 hours

### Task 3.1: Implement Explicit Cleanup in Auth Service

**Description:** Replace parallel cleanup with explicit sequential cleanup (HTTP Server → Database → Tracer) in auth service.

**Acceptance Criteria:**
- [ ] Remove parallel WaitGroup cleanup pattern
- [ ] Implement sequential cleanup: HTTP Server → Database → Tracer
- [ ] Each cleanup step logged with success/failure
- [ ] Errors in cleanup don't prevent other cleanup steps
- [ ] Keep `defer db.Close()` for safety (defensive programming)
- [ ] All cleanup uses shutdown context with timeout
- [ ] Test shutdown sequence locally

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 2.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/auth/main.go`

---

### Task 3.2: Implement Explicit Cleanup in User Service

**Description:** Replace parallel cleanup with explicit sequential cleanup in user service.

**Acceptance Criteria:**
- [ ] Same as Task 3.1, applied to user service
- [ ] Consistent pattern with auth service

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 3.1 (for pattern consistency)
**Assignee:** Unassigned

**Files:**
- `services/cmd/user/main.go`

---

### Task 3.3: Implement Explicit Cleanup in Product Service

**Description:** Replace parallel cleanup with explicit sequential cleanup in product service.

**Acceptance Criteria:**
- [ ] Same as Task 3.1, applied to product service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 3.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/product/main.go`

---

### Task 3.4: Implement Explicit Cleanup in Cart Service

**Description:** Replace parallel cleanup with explicit sequential cleanup in cart service.

**Acceptance Criteria:**
- [ ] Same as Task 3.1, applied to cart service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 3.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/cart/main.go`

---

### Task 3.5: Implement Explicit Cleanup in Order Service

**Description:** Replace parallel cleanup with explicit sequential cleanup in order service.

**Acceptance Criteria:**
- [ ] Same as Task 3.1, applied to order service
- [ ] Consistent pattern with previous services

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 3.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/order/main.go`

---

### Task 3.6: Implement Explicit Cleanup in Remaining Services

**Description:** Replace parallel cleanup with explicit sequential cleanup in review, notification, shipping, and shipping-v2 services.

**Acceptance Criteria:**
- [ ] Review service: Explicit cleanup implemented
- [ ] Notification service: Explicit cleanup implemented
- [ ] Shipping service: Explicit cleanup implemented
- [ ] Shipping-v2 service: Explicit cleanup implemented
- [ ] All follow same pattern as previous services
- [ ] All tested locally

**Effort:** 2 hours (4 services, 30 min each)
**Priority:** High
**Dependencies:** Task 3.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/review/main.go`
- `services/cmd/notification/main.go`
- `services/cmd/shipping/main.go`
- `services/cmd/shipping-v2/main.go`

---

## Phase 4: Kubernetes Configuration

**Goal:** Add Kubernetes graceful shutdown configuration to Helm charts.
**Estimated:** 3 hours

### Task 4.1: Add terminationGracePeriodSeconds to Helm Template

**Description:** Update Helm deployment template to support `terminationGracePeriodSeconds` configuration.

**Acceptance Criteria:**
- [ ] `terminationGracePeriodSeconds` added to `charts/templates/deployment.yaml`
- [ ] Uses Helm value with default fallback: `{{ .Values.terminationGracePeriodSeconds | default 30 }}`
- [ ] Template syntax is correct
- [ ] Applied to pod spec (not container spec)

**Effort:** 1 hour
**Priority:** High
**Dependencies:** None
**Assignee:** Unassigned

**Files:**
- `charts/templates/deployment.yaml`

---

### Task 4.2: Add terminationGracePeriodSeconds to All Helm Values

**Description:** Add `terminationGracePeriodSeconds: 30` to all 9 service Helm values files.

**Acceptance Criteria:**
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/auth.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/user.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/product.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/cart.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/order.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/review.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/notification.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/shipping.yaml`
- [ ] `terminationGracePeriodSeconds: 30` added to `charts/values/shipping-v2.yaml`
- [ ] Value set to 30 seconds (shutdown_timeout 10s + buffer 20s)

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 4.1
**Assignee:** Unassigned

**Files:**
- `charts/values/{service}.yaml` (all 9 services)

---

### Task 4.3: Document Kubernetes Configuration

**Description:** Document Kubernetes graceful shutdown configuration in deployment guide.

**Acceptance Criteria:**
- [ ] Kubernetes termination lifecycle explained
- [ ] `terminationGracePeriodSeconds` documented
- [ ] Relationship to `SHUTDOWN_TIMEOUT` explained
- [ ] Best practices documented (shutdown_timeout + buffer)
- [ ] Examples provided

**Effort:** 1 hour
**Priority:** Medium
**Dependencies:** Task 4.1, Task 4.2
**Assignee:** Unassigned

**Files:**
- `docs/guides/SETUP.md` or new section in deployment guide

---

## Phase 5: Testing & Validation

**Goal:** Comprehensive testing and validation of graceful shutdown implementation.
**Estimated:** 3 hours

### Task 5.1: Write Unit Tests for getShutdownTimeout()

**Description:** Create comprehensive unit tests for the `getShutdownTimeout()` helper function.

**Acceptance Criteria:**
- [ ] Test default value when env var not set
- [ ] Test valid duration parsing ("15s", "30s")
- [ ] Test invalid format handling ("invalid")
- [ ] Test negative value handling ("-5s")
- [ ] Test too large value handling ("120s")
- [ ] Test boundary values (0s, 60s, 61s)
- [ ] All tests pass
- [ ] Test coverage > 80%

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Task 1.1
**Assignee:** Unassigned

**Files:**
- `services/cmd/{service}/main_test.go` (or shared test file)

---

### Task 5.2: Integration Test - Signal Handling

**Description:** Create integration test to verify signal handling works correctly.

**Acceptance Criteria:**
- [ ] Test signal context creation
- [ ] Test context cancellation on signal
- [ ] Test SIGTERM handling
- [ ] Test SIGINT handling
- [ ] Test multiple signals (should handle gracefully)
- [ ] All tests pass

**Effort:** 1 hour
**Priority:** Medium
**Dependencies:** Phase 2 complete (all services migrated)
**Assignee:** Unassigned

**Files:**
- `services/cmd/{service}/main_test.go`

---

### Task 5.3: Manual Testing - Kubernetes Rolling Update

**Description:** Manually test graceful shutdown in Kubernetes environment with rolling update.

**Acceptance Criteria:**
- [ ] Deploy one service (e.g., auth) with new graceful shutdown code
- [ ] Trigger rolling update (change image tag or config)
- [ ] Monitor pod termination events (`kubectl get events`)
- [ ] Verify no SIGKILL (check pod events for graceful termination)
- [ ] Verify shutdown completes within grace period
- [ ] Check logs for shutdown sequence
- [ ] Verify zero request loss (monitor metrics during update)

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Phase 1-4 complete
**Assignee:** Unassigned

**Files:**
- Manual testing (no code changes)

---

### Task 5.4: Code Review - Consistency Check

**Description:** Review all 9 services to ensure consistent implementation pattern.

**Acceptance Criteria:**
- [ ] All services use same signal handling pattern
- [ ] All services use same cleanup sequence
- [ ] All services use same helper function (or consistent implementation)
- [ ] All services have same logging pattern
- [ ] All services handle errors consistently
- [ ] Code follows Go best practices
- [ ] No inconsistencies found

**Effort:** 1 hour
**Priority:** High
**Dependencies:** Phase 1-3 complete
**Assignee:** Unassigned

**Files:**
- All `services/cmd/{service}/main.go` files

---

### Task 5.5: Documentation Review

**Description:** Review and update all documentation related to graceful shutdown.

**Acceptance Criteria:**
- [ ] Configuration guide updated (`docs/guides/CONFIGURATION.md`)
- [ ] Deployment guide updated (if applicable)
- [ ] Code comments added for shutdown logic
- [ ] README updated (if needed)
- [ ] All documentation is accurate and complete

**Effort:** 1 hour
**Priority:** Medium
**Dependencies:** Phase 1-4 complete
**Assignee:** Unassigned

**Files:**
- `docs/guides/CONFIGURATION.md`
- `docs/guides/SETUP.md`
- Code comments in `services/cmd/{service}/main.go`

---

## Dependency Graph

```
Phase 1: Configuration Foundation
├── Task 1.1: getShutdownTimeout() helper (foundation)
│   ├── Task 1.2: Helm values (parallel)
│   └── Task 1.3: Documentation (depends on 1.1, 1.2)

Phase 2: Signal Handling Migration (depends on Phase 1)
├── Task 2.1: Auth service (pattern template)
│   ├── Task 2.2: User service
│   ├── Task 2.3: Product service
│   ├── Task 2.4: Cart service
│   ├── Task 2.5: Order service
│   ├── Task 2.6: Review service
│   ├── Task 2.7: Notification service
│   ├── Task 2.8: Shipping service
│   └── Task 2.9: Shipping-v2 service

Phase 3: Explicit Cleanup (depends on Phase 2)
├── Task 3.1: Auth service (pattern template)
│   ├── Task 3.2: User service
│   ├── Task 3.3: Product service
│   ├── Task 3.4: Cart service
│   ├── Task 3.5: Order service
│   └── Task 3.6: Remaining 4 services

Phase 4: Kubernetes Configuration (parallel with Phase 3)
├── Task 4.1: Helm template
│   ├── Task 4.2: Helm values (depends on 4.1)
│   └── Task 4.3: Documentation (depends on 4.1, 4.2)

Phase 5: Testing & Validation (depends on Phase 1-4)
├── Task 5.1: Unit tests (depends on 1.1)
├── Task 5.2: Integration tests (depends on Phase 2)
├── Task 5.3: Manual K8s testing (depends on Phase 1-4)
├── Task 5.4: Code review (depends on Phase 1-3)
└── Task 5.5: Documentation review (depends on Phase 1-4)
```

---

## Quick Reference Checklist

### Phase 1: Configuration Foundation (4 hours)
- [ ] Task 1.1: Create `getShutdownTimeout()` helper function
- [ ] Task 1.2: Add SHUTDOWN_TIMEOUT to all Helm values files
- [ ] Task 1.3: Update configuration documentation

### Phase 2: Signal Handling Migration (8 hours)
- [ ] Task 2.1: Migrate auth service signal handling
- [ ] Task 2.2: Migrate user service signal handling
- [ ] Task 2.3: Migrate product service signal handling
- [ ] Task 2.4: Migrate cart service signal handling
- [ ] Task 2.5: Migrate order service signal handling
- [ ] Task 2.6: Migrate review service signal handling
- [ ] Task 2.7: Migrate notification service signal handling
- [ ] Task 2.8: Migrate shipping service signal handling
- [ ] Task 2.9: Migrate shipping-v2 service signal handling

### Phase 3: Explicit Cleanup Sequence (6 hours)
- [ ] Task 3.1: Implement explicit cleanup in auth service
- [ ] Task 3.2: Implement explicit cleanup in user service
- [ ] Task 3.3: Implement explicit cleanup in product service
- [ ] Task 3.4: Implement explicit cleanup in cart service
- [ ] Task 3.5: Implement explicit cleanup in order service
- [ ] Task 3.6: Implement explicit cleanup in remaining 4 services

### Phase 4: Kubernetes Configuration (3 hours)
- [ ] Task 4.1: Add terminationGracePeriodSeconds to Helm template
- [ ] Task 4.2: Add terminationGracePeriodSeconds to all Helm values
- [ ] Task 4.3: Document Kubernetes configuration

### Phase 5: Testing & Validation (5 hours)
- [ ] Task 5.1: Write unit tests for getShutdownTimeout()
- [ ] Task 5.2: Integration test - signal handling
- [ ] Task 5.3: Manual testing - Kubernetes rolling update
- [ ] Task 5.4: Code review - consistency check
- [ ] Task 5.5: Documentation review

---

## Risk Areas

| Task | Risk | Mitigation |
|------|------|------------|
| **Task 2.1-2.9** | Inconsistent implementation across services | Use Task 2.1 as template, copy pattern exactly |
| **Task 3.1-3.6** | Breaking existing cleanup logic | Keep `defer db.Close()` as safety net, test thoroughly |
| **Task 4.1** | Helm template syntax error | Test template rendering before applying |
| **Task 5.3** | Request loss during rolling update | Monitor metrics closely, verify zero loss |
| **All Tasks** | Time estimation too optimistic | Add 20% buffer, prioritize critical path tasks |

---

## Parallelization Opportunities

**Can be done in parallel:**
- Task 1.1 and Task 1.2 (helper function and Helm values)
- Tasks 2.2-2.9 (all service migrations after Task 2.1)
- Tasks 3.2-3.6 (all service cleanups after Task 3.1)
- Task 4.2 and Task 4.3 (Helm values and documentation)
- Tasks 5.1, 5.2, 5.4, 5.5 (various testing/documentation tasks)

**Must be sequential:**
- Phase 1 → Phase 2 → Phase 3 (code changes build on each other)
- Task 4.1 → Task 4.2 (Helm template must exist before values)
- Phase 1-4 → Phase 5 (testing requires implementation complete)

---

## Next Steps

1. ✅ Review task breakdown
2. Assign tasks to developers (can parallelize service migrations)
3. Run `/implement graceful-shutdown-research` to start execution
4. Start with Task 1.1 (foundation) and Task 2.1 (pattern template)

---

*Tasks created with SDD 2.0*

