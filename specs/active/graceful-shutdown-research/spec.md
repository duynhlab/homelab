# Specification: Graceful Shutdown Enhancement for Go Microservices

**Task ID:** graceful-shutdown-research
**Created:** 2025-12-25
**Status:** Ready for Planning
**Version:** 1.0

---

## 1. Problem Statement

### The Problem

Our Go microservices currently implement basic graceful shutdown using legacy patterns (channel-based signal handling). While functional, this approach:
- Doesn't align with modern Go best practices (`signal.NotifyContext`)
- Lacks Kubernetes-specific configuration (`terminationGracePeriodSeconds`)
- Has fixed shutdown timeout (not configurable)
- Doesn't follow explicit resource cleanup sequences used by industry leaders (Shopee, Grab, Uber)

This creates risks during production deployments and rolling updates, potentially leading to:
- Request loss during pod termination
- Incomplete resource cleanup
- SIGKILL during shutdown if grace period is exceeded
- Poor developer experience when debugging shutdown issues

### Current Situation

**Current Implementation:**
- All 9 services use channel-based signal handling (`signal.Notify`)
- Fixed 10-second shutdown timeout
- Database connections closed via `defer` (not explicit in shutdown sequence)
- No Kubernetes-specific graceful shutdown configuration
- Parallel shutdown of tracer and HTTP server (good, but can be improved)

**Pain Points:**
- Code doesn't follow modern Go idioms
- No way to tune shutdown timeout per service
- Missing Kubernetes configuration for optimal graceful shutdown
- Harder to test (channel-based approach)
- Not aligned with industry best practices

### Desired Outcome

After implementation:
- ✅ Modern Go patterns (`signal.NotifyContext`) used across all services
- ✅ Configurable shutdown timeout per service
- ✅ Kubernetes `terminationGracePeriodSeconds` configured
- ✅ Explicit resource cleanup sequence
- ✅ Zero request loss during rolling updates
- ✅ All shutdowns complete within grace period
- ✅ Code follows industry best practices (Stripe, GitHub, Uber, Grab, Shopee)
- ✅ Better testability and maintainability

---

## 2. User Personas

### Primary User 1: Go Developer

- **Who:** Backend developers working on microservices
- **Goals:** 
  - Write idiomatic Go code
  - Understand modern patterns
  - Learn best practices for production systems
- **Pain points:** 
  - Current code uses legacy patterns
  - Hard to test graceful shutdown
  - Unclear shutdown sequence
- **Tech comfort:** High (Go developers)

### Primary User 2: SRE/DevOps Engineer

- **Who:** Engineers managing Kubernetes deployments
- **Goals:**
  - Ensure zero downtime during deployments
  - Prevent request loss during rolling updates
  - Monitor and debug shutdown issues
- **Pain points:**
  - No Kubernetes-specific graceful shutdown config
  - Can't tune shutdown timeout per service
  - Hard to debug shutdown failures
- **Tech comfort:** High (Kubernetes, infrastructure)

### Primary User 3: End User

- **Who:** Users consuming the API services
- **Goals:**
  - Reliable API responses
  - No errors during deployments
  - Consistent service availability
- **Pain points:**
  - Request failures during deployments
  - Inconsistent service behavior
- **Tech comfort:** Low (end users don't interact with code)

---

## 3. Functional Requirements

### FR-1: Migrate to Modern Signal Handling

**Description:** Replace channel-based signal handling (`signal.Notify`) with context-based approach (`signal.NotifyContext`) across all 9 microservices.

**User Story:**
> As a Go developer, I want to use modern Go patterns for signal handling so that the code is more idiomatic, testable, and maintainable.

**Acceptance Criteria:**
- [ ] All 9 services use `signal.NotifyContext` instead of `signal.Notify`
- [ ] Signal context properly integrated with shutdown context
- [ ] Code follows modern Go idioms (context-based patterns)
- [ ] Signal handling is testable (can cancel context programmatically)
- [ ] Backward compatible behavior (handles SIGTERM and SIGINT)
- [ ] Proper cleanup with `defer stop()`

**Priority:** Must Have

**Services Affected:** All 9 services (auth, user, product, cart, order, review, notification, shipping, shipping-v2)

**Files:** `services/cmd/{service}/main.go`

---

### FR-2: Add Kubernetes Graceful Shutdown Configuration

**Description:** Configure Kubernetes `terminationGracePeriodSeconds` in Helm charts to ensure pods have enough time for graceful shutdown.

**User Story:**
> As an SRE/DevOps engineer, I want Kubernetes to wait long enough for graceful shutdown so that pods aren't force-killed during deployments.

**Acceptance Criteria:**
- [ ] `terminationGracePeriodSeconds` added to Helm deployment template
- [ ] Configurable via Helm values (default: 30 seconds)
- [ ] Value set to `shutdown_timeout + buffer` (e.g., 15-20s if shutdown timeout is 10s)
- [ ] Applied to all 9 service deployments
- [ ] Documented in Helm values files

**Priority:** Must Have

**Files:**
- `charts/templates/deployment.yaml`
- `charts/values/{service}.yaml` (all 9 services)

---

### FR-3: Make Shutdown Timeout Configurable

**Description:** Allow shutdown timeout to be configured per service via environment variable instead of hardcoded 10 seconds.

**User Story:**
> As an SRE/DevOps engineer, I want to configure shutdown timeout per service so that different services can have appropriate timeout values based on their needs.

**Acceptance Criteria:**
- [ ] Shutdown timeout read from `SHUTDOWN_TIMEOUT` environment variable
- [ ] Default value: 10 seconds (if env var not set)
- [ ] Validates timeout value (e.g., must be positive, reasonable max)
- [ ] Applied to all 9 services
- [ ] Documented in configuration guide
- [ ] Can be set via Helm values

**Priority:** Must Have

**Files:**
- `services/cmd/{service}/main.go` (all 9 services)
- `charts/values/{service}.yaml` (all 9 services)
- `docs/guides/CONFIGURATION.md`

---

### FR-4: Implement Explicit Resource Cleanup Sequence

**Description:** Replace implicit cleanup (defer) with explicit cleanup sequence during shutdown for better predictability and debugging.

**User Story:**
> As a Go developer, I want explicit resource cleanup sequence so that shutdown order is predictable and easier to debug.

**Acceptance Criteria:**
- [ ] Explicit cleanup sequence: HTTP server → Database → Tracer
- [ ] Each cleanup step logged with success/failure
- [ ] Errors in cleanup don't prevent other cleanup steps
- [ ] Database connection closed explicitly (in addition to defer for safety)
- [ ] Tracer shutdown with proper context timeout
- [ ] All cleanup steps use shutdown context with timeout
- [ ] Applied to all 9 services

**Priority:** Must Have

**Files:** `services/cmd/{service}/main.go` (all 9 services)

---

## 4. Non-Functional Requirements

### NFR-1: Performance

- **Shutdown Time:** Graceful shutdown must complete within configured timeout (default 10s)
- **Zero Request Loss:** No requests should be lost during rolling updates
- **Resource Cleanup:** All resources (connections, spans) must be properly closed

### NFR-2: Reliability

- **Grace Period Compliance:** All shutdowns must complete within `terminationGracePeriodSeconds` (default 30s)
- **Error Handling:** Cleanup errors should be logged but not prevent shutdown completion
- **Signal Handling:** Must handle SIGTERM and SIGINT correctly

### NFR-3: Maintainability

- **Code Consistency:** All 9 services must follow the same graceful shutdown pattern
- **Documentation:** Changes must be documented in code comments and guides
- **Testability:** Code must be testable (context-based approach enables this)

### NFR-4: Compatibility

- **Go Version:** Requires Go 1.16+ (we have Go 1.25 ✅)
- **Kubernetes Version:** Works with Kubernetes 1.33+ (we have 1.33-1.34 ✅)
- **Backward Compatibility:** Behavior remains the same from user perspective (no breaking changes)

### NFR-5: Observability

- **Logging:** All shutdown steps must be logged with appropriate log levels
- **Metrics:** Shutdown duration should be observable (via existing Prometheus metrics)
- **Tracing:** Shutdown process should be traceable (via OpenTelemetry)

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **preStop Hook** - Not needed for current use case. Can be added later if connection draining is required.
- ❌ **In-Flight Request Tracking with WaitGroup** - Not needed since handlers are synchronous. Gin handles this automatically.
- ❌ **Rollback Plan** - This is a dev/learning project, rollback not required.
- ❌ **Gradual Rollout** - All services will be updated together.
- ❌ **Monitoring Dashboards** - Existing dashboards sufficient, no new dashboards needed.
- ❌ **Alerting Rules** - No new alerts needed for graceful shutdown.

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **Shutdown timeout exceeded** | Log warning, continue with cleanup, exit with non-zero code if critical resources not closed |
| **Database connection already closed** | Log info, skip database cleanup step, continue with other cleanup |
| **Tracer not initialized** | Skip tracer shutdown (current behavior), continue with other cleanup |
| **Multiple shutdown signals received** | Handle gracefully, don't process shutdown multiple times |
| **Context cancellation during shutdown** | Respect context timeout, force cleanup if timeout exceeded |
| **Service receives SIGKILL** | No cleanup possible (expected Kubernetes behavior), process killed immediately |

### Error Scenarios

| Error | User Message | System Action |
|-------|--------------|---------------|
| **Invalid SHUTDOWN_TIMEOUT value** | Log error, use default 10s, continue startup | Use default timeout, log warning |
| **Server.Shutdown() fails** | Log error with details | Continue with other cleanup steps |
| **Database.Close() fails** | Log error with details | Continue with tracer cleanup |
| **Tracer.Shutdown() fails** | Log error with details | Complete shutdown, exit |
| **Signal context creation fails** | Log fatal error, exit | Exit immediately (shouldn't happen) |

### Error Handling Strategy

1. **Non-Critical Errors:** Log error, continue shutdown sequence
2. **Critical Errors:** Log error, attempt cleanup, exit with non-zero code
3. **Timeout Errors:** Log warning, force cleanup, exit
4. **All errors logged** with appropriate log levels (Error, Warn, Info)

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Zero Request Loss** | 0 requests lost during rolling updates | Monitor request metrics during deployments |
| **Shutdown Completion Rate** | 100% of shutdowns complete within grace period | Monitor pod termination events, check for SIGKILL |
| **Shutdown Duration** | < configured timeout (default 10s) | Log shutdown duration, monitor via metrics |
| **Code Quality** | All services use modern patterns | Code review, static analysis |
| **Test Coverage** | Graceful shutdown logic testable | Unit tests for signal handling |

### Definition of Done

- [ ] All 9 services migrated to `signal.NotifyContext`
- [ ] Kubernetes `terminationGracePeriodSeconds` configured for all services
- [ ] Shutdown timeout configurable via environment variable
- [ ] Explicit resource cleanup sequence implemented
- [ ] All acceptance criteria met
- [ ] Edge cases handled
- [ ] Error scenarios covered
- [ ] Code reviewed and follows Go best practices
- [ ] Documentation updated (code comments, guides)
- [ ] All services tested in Kubernetes environment
- [ ] Zero request loss verified during rolling updates
- [ ] All shutdowns complete within grace period

---

## 8. Technical Details

### Implementation Approach

**Pattern to Follow:**
```go
// Modern signal handling
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()

// Start server
go func() {
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        logger.Fatal("Server failed", zap.Error(err))
    }
}()

// Wait for shutdown signal
<-ctx.Done()
logger.Info("Shutdown signal received")

// Shutdown with configurable timeout
shutdownTimeout := getShutdownTimeout() // From env var, default 10s
shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
defer cancel()

// Explicit cleanup sequence
// 1. Stop accepting new connections
if err := srv.Shutdown(shutdownCtx); err != nil {
    logger.Error("Server shutdown error", zap.Error(err))
} else {
    logger.Info("Server shutdown complete")
}

// 2. Close database connections
if err := db.Close(); err != nil {
    logger.Error("Database close error", zap.Error(err))
} else {
    logger.Info("Database closed")
}

// 3. Flush tracing spans
if tp != nil {
    if err := tp.Shutdown(shutdownCtx); err != nil {
        logger.Error("Tracer shutdown error", zap.Error(err))
    } else {
        logger.Info("Tracer shutdown complete")
    }
}

logger.Info("Graceful shutdown complete")
```

### Kubernetes Configuration

**Helm Template:**
```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds | default 30 }}
```

**Helm Values:**
```yaml
terminationGracePeriodSeconds: 30  # shutdown_timeout (10s) + buffer (20s)
env:
  - name: SHUTDOWN_TIMEOUT
    value: "10s"
```

### Services to Update

All 9 microservices:
1. auth
2. user
3. product
4. cart
5. order
6. review
7. notification
8. shipping
9. shipping-v2

---

## 9. Open Questions

- [ ] Should we add metrics for shutdown duration? (Recommendation: Yes, via existing Prometheus middleware)
- [ ] Should we add health check endpoint that returns "shutting down" status? (Recommendation: No, out of scope)
- [ ] Should we validate shutdown timeout format? (Recommendation: Yes, use `time.ParseDuration`)

---

## 10. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-12-25 | Initial specification | System |

---

## Next Steps

1. ✅ Review spec with team
2. Run `/plan graceful-shutdown-research` to create technical implementation plan
3. Run `/tasks graceful-shutdown-research` to break down into implementation tasks
4. Implement changes across all 9 services
5. Test in Kubernetes environment
6. Verify zero request loss during rolling updates
7. Update documentation

---

*Specification created with SDD 2.0*

