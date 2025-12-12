# Task Breakdown: Error Handling Improvements

> **Task ID**: microservices-best-practices-assessment  
> **Feature**: Error Handling Improvements (Phase 1)  
> **Total Tasks**: 45  
> **Estimated Effort**: 5-7 days (1 developer) OR 2-3 days (with parallel execution)  
> **Status**: Ready for Implementation  
> **Created**: December 10, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Task Summary](#task-summary)
3. [Phase 1: Foundation](#phase-1-foundation)
4. [Phase 2: Service Migration](#phase-2-service-migration)
5. [Phase 3: Testing & Validation](#phase-3-testing--validation)
6. [Phase 4: Deployment](#phase-4-deployment)
7. [Progress Tracking](#progress-tracking)
8. [Dependencies Map](#dependencies-map)
9. [Parallel Execution Guide](#parallel-execution-guide)

---

## Overview

### Goal
Implement error handling improvements across all 9 microservices using Go standard library error wrapping, sentinel errors, and `errors.Is()` checking.

### Success Criteria
- ✅ 18 errors.go files created (9 services × 2 versions)
- ✅ All service methods use `fmt.Errorf("%w")` for error wrapping
- ✅ All handlers use `errors.Is()` for error checking
- ✅ API responses unchanged (no breaking changes)
- ✅ Error logs include full context
- ✅ All services deployed successfully

### Key Constraints
- **No breaking changes**: API responses must remain identical
- **Zero new dependencies**: Use only Go standard library
- **Backward compatible**: Safe rollback at any point
- **Production quality**: All changes must pass testing

---

## Task Summary

### By Phase

| Phase | Tasks | Effort | Can Parallelize |
|-------|-------|--------|-----------------|
| **Phase 1: Foundation** | 5 | 1.5-2 days | Partial |
| **Phase 2: Service Migration** | 32 | 2-3 days | ✅ Yes (8 services) |
| **Phase 3: Testing & Validation** | 5 | 1 day | Partial |
| **Phase 4: Deployment** | 3 | 0.5 day | No |
| **Total** | **45** | **5-7 days** | |

### By Priority

| Priority | Count | Description |
|----------|-------|-------------|
| **P0 (Critical)** | 10 | Foundation + Auth service |
| **P1 (High)** | 32 | Service migrations |
| **P2 (Medium)** | 3 | Testing & validation |
| **P3 (Low)** | 0 | None |

### Task Status Legend

- 🔵 **TODO**: Not started
- 🟡 **IN PROGRESS**: Currently being worked on
- 🔴 **BLOCKED**: Waiting on dependency
- ✅ **DONE**: Completed and verified

---

## Phase 1: Foundation

**Goal**: Establish error handling pattern and reference implementation  
**Duration**: 1.5-2 days (sequential) OR 1 day (with parallelization)  
**Dependencies**: None  

### TASK-001: Create Sentinel Error Definitions (All Services)

**Status**: 🔵 TODO  
**Priority**: P0 (Critical)  
**Effort**: 2-3 hours  
**Assignee**: TBD  
**Dependencies**: None  

**Description**:
Create `errors.go` files for all 9 services (v1 and v2 versions) with sentinel error definitions.

**Acceptance Criteria**:
- [ ] 18 errors.go files created:
  - [ ] `services/internal/auth/logic/v1/errors.go`
  - [ ] `services/internal/auth/logic/v2/errors.go`
  - [ ] `services/internal/user/logic/v1/errors.go`
  - [ ] `services/internal/user/logic/v2/errors.go`
  - [ ] `services/internal/product/logic/v1/errors.go`
  - [ ] `services/internal/product/logic/v2/errors.go`
  - [ ] `services/internal/cart/logic/v1/errors.go`
  - [ ] `services/internal/cart/logic/v2/errors.go`
  - [ ] `services/internal/order/logic/v1/errors.go`
  - [ ] `services/internal/order/logic/v2/errors.go`
  - [ ] `services/internal/review/logic/v1/errors.go`
  - [ ] `services/internal/review/logic/v2/errors.go`
  - [ ] `services/internal/notification/logic/v1/errors.go`
  - [ ] `services/internal/notification/logic/v2/errors.go`
  - [ ] `services/internal/shipping/logic/v1/errors.go`
  - [ ] `services/internal/shipping/logic/v2/errors.go`
- [ ] Each file contains:
  - [ ] Package documentation
  - [ ] Usage examples in comments
  - [ ] Sentinel error definitions (3-6 errors per service)
  - [ ] Error documentation comments
- [ ] All errors follow naming convention: `Err{Noun}{Verb}`
- [ ] Code formatted with `go fmt`
- [ ] No linter errors

**Files Changed**:
- 18 new files (~35-40 lines each)

**Testing**:
```bash
# Verify all files created
find services/internal -name "errors.go" | wc -l  # Should be 18

# Check each file has content
for f in $(find services/internal -name "errors.go"); do
    echo "$f: $(wc -l < "$f") lines"
done

# Run linter
go vet ./services/...
```

**Reference**:
- Template in `plan.md` section "Step 1.1"
- Sentinel errors defined in `spec.md` section "FR-002"

---

### TASK-002: Migrate Auth Service v1 (Service Layer)

**Status**: 🔵 TODO  
**Priority**: P0 (Critical)  
**Effort**: 2-3 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001  

**Description**:
Update auth service v1 logic layer to use error wrapping and sentinel errors.

**Acceptance Criteria**:
- [ ] File `services/internal/auth/logic/v1/service.go` updated:
  - [ ] Import `errors` and `fmt` packages
  - [ ] `Login()` method uses error wrapping
  - [ ] `Register()` method uses error wrapping
  - [ ] Input validation with wrapped errors
  - [ ] Sentinel errors used instead of custom types
  - [ ] Context added to all error messages (include username)
- [ ] All errors wrapped with `fmt.Errorf("%w")`
- [ ] Code formatted with `go fmt`
- [ ] No linter errors
- [ ] Compiles successfully

**Files Changed**:
- `services/internal/auth/logic/v1/service.go` (~20 lines modified)

**Testing**:
```bash
# Compile check
cd services
go build ./cmd/auth

# Verify error wrapping
grep -n "fmt.Errorf.*%w" internal/auth/logic/v1/service.go
```

**Reference**:
- Code example in `plan.md` section "Step 2.1"
- Pattern: `return nil, fmt.Errorf("authenticate user %q: %w", username, ErrInvalidCredentials)`

---

### TASK-003: Migrate Auth Service v1 (Handler Layer)

**Status**: 🔵 TODO  
**Priority**: P0 (Critical)  
**Effort**: 2-3 hours  
**Assignee**: TBD  
**Dependencies**: TASK-002  

**Description**:
Update auth service v1 handler layer to use `errors.Is()` for error checking.

**Acceptance Criteria**:
- [ ] File `services/internal/auth/web/v1/handler.go` updated:
  - [ ] Import `errors` package
  - [ ] `Login()` handler uses `errors.Is()`
  - [ ] `Register()` handler uses `errors.Is()`
  - [ ] Switch statement for multiple error checks
  - [ ] Full error logged with `zap.Error(err)`
  - [ ] No type assertions remaining
- [ ] HTTP status codes unchanged
- [ ] Error response messages unchanged
- [ ] Code formatted with `go fmt`
- [ ] No linter errors
- [ ] Compiles successfully

**Files Changed**:
- `services/internal/auth/web/v1/handler.go` (~15 lines modified)

**Testing**:
```bash
# Compile check
cd services
go build ./cmd/auth

# Verify errors.Is() usage
grep -n "errors.Is" internal/auth/web/v1/handler.go

# Verify no type assertions
grep -n "err.(\*" internal/auth/web/v1/handler.go  # Should be empty
```

**Reference**:
- Code example in `plan.md` section "Step 2.2"

---

### TASK-004: Migrate Auth Service v2

**Status**: 🔵 TODO  
**Priority**: P0 (Critical)  
**Effort**: 3-4 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001  

**Description**:
Update auth service v2 (both service and handler layers) to use error wrapping and `errors.Is()`.

**Acceptance Criteria**:
- [ ] File `services/internal/auth/logic/v2/service.go` updated (same as TASK-002)
- [ ] File `services/internal/auth/web/v2/handler.go` updated (same as TASK-003)
- [ ] All changes follow same pattern as v1
- [ ] Code formatted with `go fmt`
- [ ] No linter errors
- [ ] Compiles successfully

**Files Changed**:
- `services/internal/auth/logic/v2/service.go` (~20 lines modified)
- `services/internal/auth/web/v2/handler.go` (~15 lines modified)

**Testing**:
```bash
# Compile check
cd services
go build ./cmd/auth

# Verify pattern consistency
diff <(grep "fmt.Errorf.*%w" internal/auth/logic/v1/service.go | wc -l) \
     <(grep "fmt.Errorf.*%w" internal/auth/logic/v2/service.go | wc -l)
```

---

### TASK-005: Test Auth Service Migration

**Status**: 🔵 TODO  
**Priority**: P0 (Critical)  
**Effort**: 2-3 hours  
**Assignee**: TBD  
**Dependencies**: TASK-002, TASK-003, TASK-004  

**Description**:
Manually test auth service to verify error handling improvements work correctly and API responses are unchanged.

**Acceptance Criteria**:
- [ ] Build and deploy auth service locally
- [ ] Test v1 endpoints:
  - [ ] Valid login returns 200 + token (unchanged)
  - [ ] Invalid credentials returns 401 + error message (unchanged)
  - [ ] Missing fields returns 400 + error message (unchanged)
- [ ] Test v2 endpoints:
  - [ ] Same tests as v1
- [ ] Check error logs:
  - [ ] Error logs include full error chain
  - [ ] Error logs include username parameter
  - [ ] Trace-ID present in logs
- [ ] Check OpenTelemetry traces:
  - [ ] Spans record errors correctly
- [ ] No panics or crashes

**Testing Commands**:
```bash
# Build and deploy
cd services
docker build -t auth:latest -f Dockerfile --build-arg SERVICE=auth .
kubectl port-forward -n auth svc/auth 8080:8080

# Test valid login (v1)
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"password"}' \
  -w "\nStatus: %{http_code}\n"

# Test invalid credentials (v1)
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"wrong"}' \
  -w "\nStatus: %{http_code}\n"

# Check logs
kubectl logs -n auth -l app=auth --tail=20 | grep "Login failed"

# Expected log format:
# "error": "authenticate user \"admin\": invalid credentials"
```

**Success Criteria**:
- [ ] All API responses identical to before
- [ ] Error logs show full context
- [ ] No regressions

**Reference**:
- Testing guide in `plan.md` section "Step 2.4"

---

### TASK-006: Create Error Handling Documentation

**Status**: 🔵 TODO  
**Priority**: P0 (Critical)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-005 (auth service working)  

**Description**:
Create comprehensive error handling guide for developers using auth service as reference.

**Acceptance Criteria**:
- [ ] File `docs/development/ERROR_HANDLING.md` created
- [ ] Contains sections:
  - [ ] Overview
  - [ ] Sentinel Errors (definition, location)
  - [ ] Error Wrapping (pattern, benefits)
  - [ ] Error Checking (errors.Is() usage)
  - [ ] Layer Responsibilities (service vs handler)
  - [ ] Examples by Service (auth service example)
  - [ ] Common Patterns
  - [ ] Troubleshooting
- [ ] Code examples from auth service included
- [ ] BEFORE/AFTER comparisons shown
- [ ] Clear and easy to follow

**Files Changed**:
- `docs/development/ERROR_HANDLING.md` (new file, ~300 lines)

**Testing**:
- [ ] Document reviewed by team
- [ ] Examples compile and run
- [ ] Easy for new developers to understand

**Reference**:
- Template in `plan.md` section "Step 4.1"

---

## Phase 2: Service Migration

**Goal**: Migrate remaining 8 services following auth service pattern  
**Duration**: 2-3 days (sequential) OR 0.5-1 day (with 8 parallel agents)  
**Dependencies**: Phase 1 complete (especially TASK-001 and TASK-006)  

**Pattern**: Each service has 4 tasks:
1. Migrate v1 service layer (logic)
2. Migrate v1 handler layer (web)
3. Migrate v2 service layer (logic)
4. Migrate v2 handler layer (web)

### User Service (TASK-007 to TASK-010)

#### TASK-007: User Service v1 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes (independent of other services)

**Description**:
Update user service v1 logic layer with error wrapping.

**Acceptance Criteria**:
- [ ] File `services/internal/user/logic/v1/service.go` updated:
  - [ ] Import `errors` and `fmt`
  - [ ] `GetUser()` uses error wrapping
  - [ ] `CreateUser()` uses error wrapping
  - [ ] `GetProfile()` uses error wrapping
  - [ ] Sentinel errors used: `ErrUserNotFound`, `ErrUserExists`, `ErrInvalidEmail`
  - [ ] Context added to error messages (include user_id, username)
- [ ] Code formatted and linted
- [ ] Compiles successfully

**Files Changed**:
- `services/internal/user/logic/v1/service.go` (~25 lines modified)

**Testing**:
```bash
cd services && go build ./cmd/user
grep -n "fmt.Errorf.*%w" internal/user/logic/v1/service.go
```

---

#### TASK-008: User Service v1 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-007  

**Description**:
Update user service v1 handler layer with `errors.Is()`.

**Acceptance Criteria**:
- [ ] File `services/internal/user/web/v1/handler.go` updated:
  - [ ] Import `errors`
  - [ ] `GetUser()` uses `errors.Is()`
  - [ ] `CreateUser()` uses `errors.Is()`
  - [ ] `GetProfile()` uses `errors.Is()`
  - [ ] Switch statement for error checking
  - [ ] Full error logging with context
- [ ] HTTP responses unchanged
- [ ] Code formatted and linted

**Files Changed**:
- `services/internal/user/web/v1/handler.go` (~20 lines modified)

---

#### TASK-009: User Service v2 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes (can parallelize with TASK-007/008)

**Description**:
Update user service v2 logic layer (same pattern as v1).

**Acceptance Criteria**:
- [ ] File `services/internal/user/logic/v2/service.go` updated
- [ ] Same changes as TASK-007 for v2

**Files Changed**:
- `services/internal/user/logic/v2/service.go` (~25 lines modified)

---

#### TASK-010: User Service v2 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-009  

**Description**:
Update user service v2 handler layer (same pattern as v1).

**Acceptance Criteria**:
- [ ] File `services/internal/user/web/v2/handler.go` updated
- [ ] Same changes as TASK-008 for v2

**Files Changed**:
- `services/internal/user/web/v2/handler.go` (~20 lines modified)

---

### Product Service (TASK-011 to TASK-014)

#### TASK-011: Product Service v1 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update product service v1 logic layer with error wrapping.

**Acceptance Criteria**:
- [ ] File `services/internal/product/logic/v1/service.go` updated:
  - [ ] Methods: `ListProducts()`, `GetProduct()`, `CreateProduct()`
  - [ ] Sentinel errors: `ErrProductNotFound`, `ErrInsufficientStock`, `ErrInvalidPrice`
  - [ ] Error wrapping with product context (product_id, name)

**Files Changed**:
- `services/internal/product/logic/v1/service.go` (~25 lines modified)

---

#### TASK-012: Product Service v1 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-011  

**Acceptance Criteria**:
- [ ] File `services/internal/product/web/v1/handler.go` updated
- [ ] Handlers: `ListProducts`, `GetProduct`, `CreateProduct`
- [ ] Use `errors.Is()` for error checking

**Files Changed**:
- `services/internal/product/web/v1/handler.go` (~20 lines modified)

---

#### TASK-013: Product Service v2 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Acceptance Criteria**:
- [ ] File `services/internal/product/logic/v2/service.go` updated
- [ ] Same pattern as v1

**Files Changed**:
- `services/internal/product/logic/v2/service.go` (~25 lines modified)

---

#### TASK-014: Product Service v2 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-013  

**Acceptance Criteria**:
- [ ] File `services/internal/product/web/v2/handler.go` updated
- [ ] Same pattern as v1

**Files Changed**:
- `services/internal/product/web/v2/handler.go` (~20 lines modified)

---

### Cart Service (TASK-015 to TASK-018)

#### TASK-015: Cart Service v1 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update cart service v1 logic layer with error wrapping.

**Acceptance Criteria**:
- [ ] File `services/internal/cart/logic/v1/service.go` updated
- [ ] Sentinel errors: `ErrCartNotFound`, `ErrCartEmpty`, `ErrItemNotInCart`, `ErrInvalidQuantity`
- [ ] Error wrapping with cart context

**Files Changed**:
- `services/internal/cart/logic/v1/service.go` (~25 lines modified)

---

#### TASK-016: Cart Service v1 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-015  

**Acceptance Criteria**:
- [ ] File `services/internal/cart/web/v1/handler.go` updated
- [ ] Use `errors.Is()` for error checking

**Files Changed**:
- `services/internal/cart/web/v1/handler.go` (~20 lines modified)

---

#### TASK-017: Cart Service v2 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Acceptance Criteria**:
- [ ] File `services/internal/cart/logic/v2/service.go` updated

**Files Changed**:
- `services/internal/cart/logic/v2/service.go` (~25 lines modified)

---

#### TASK-018: Cart Service v2 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-017  

**Acceptance Criteria**:
- [ ] File `services/internal/cart/web/v2/handler.go` updated

**Files Changed**:
- `services/internal/cart/web/v2/handler.go` (~20 lines modified)

---

### Order Service (TASK-019 to TASK-022)

#### TASK-019: Order Service v1 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update order service v1 logic layer with error wrapping.

**Acceptance Criteria**:
- [ ] File `services/internal/order/logic/v1/service.go` updated
- [ ] Sentinel errors: `ErrOrderNotFound`, `ErrInvalidOrderState`, `ErrPaymentFailed`
- [ ] Error wrapping with order context (order_id)

**Files Changed**:
- `services/internal/order/logic/v1/service.go` (~25 lines modified)

---

#### TASK-020: Order Service v1 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-019  

**Acceptance Criteria**:
- [ ] File `services/internal/order/web/v1/handler.go` updated

**Files Changed**:
- `services/internal/order/web/v1/handler.go` (~20 lines modified)

---

#### TASK-021: Order Service v2 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Acceptance Criteria**:
- [ ] File `services/internal/order/logic/v2/service.go` updated

**Files Changed**:
- `services/internal/order/logic/v2/service.go` (~25 lines modified)

---

#### TASK-022: Order Service v2 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-021  

**Acceptance Criteria**:
- [ ] File `services/internal/order/web/v2/handler.go` updated

**Files Changed**:
- `services/internal/order/web/v2/handler.go` (~20 lines modified)

---

### Review Service (TASK-023 to TASK-026)

#### TASK-023: Review Service v1 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update review service v1 logic layer with error wrapping.

**Acceptance Criteria**:
- [ ] File `services/internal/review/logic/v1/service.go` updated
- [ ] Sentinel errors: `ErrReviewNotFound`, `ErrDuplicateReview`, `ErrInvalidRating`
- [ ] Validate rating range (1-5)

**Files Changed**:
- `services/internal/review/logic/v1/service.go` (~25 lines modified)

---

#### TASK-024: Review Service v1 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-023  

**Acceptance Criteria**:
- [ ] File `services/internal/review/web/v1/handler.go` updated

**Files Changed**:
- `services/internal/review/web/v1/handler.go` (~20 lines modified)

---

#### TASK-025: Review Service v2 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Acceptance Criteria**:
- [ ] File `services/internal/review/logic/v2/service.go` updated

**Files Changed**:
- `services/internal/review/logic/v2/service.go` (~25 lines modified)

---

#### TASK-026: Review Service v2 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-025  

**Acceptance Criteria**:
- [ ] File `services/internal/review/web/v2/handler.go` updated

**Files Changed**:
- `services/internal/review/web/v2/handler.go` (~20 lines modified)

---

### Notification Service (TASK-027 to TASK-030)

#### TASK-027: Notification Service v1 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update notification service v1 logic layer with error wrapping.

**Acceptance Criteria**:
- [ ] File `services/internal/notification/logic/v1/service.go` updated
- [ ] Sentinel errors: `ErrNotificationNotFound`, `ErrInvalidRecipient`, `ErrDeliveryFailed`

**Files Changed**:
- `services/internal/notification/logic/v1/service.go` (~20 lines modified)

---

#### TASK-028: Notification Service v1 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-027  

**Acceptance Criteria**:
- [ ] File `services/internal/notification/web/v1/handler.go` updated

**Files Changed**:
- `services/internal/notification/web/v1/handler.go` (~15 lines modified)

---

#### TASK-029: Notification Service v2 - Service Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Acceptance Criteria**:
- [ ] File `services/internal/notification/logic/v2/service.go` updated

**Files Changed**:
- `services/internal/notification/logic/v2/service.go` (~20 lines modified)

---

#### TASK-030: Notification Service v2 - Handler Layer

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-029  

**Acceptance Criteria**:
- [ ] File `services/internal/notification/web/v2/handler.go` updated

**Files Changed**:
- `services/internal/notification/web/v2/handler.go` (~15 lines modified)

---

### Shipping Service (TASK-031 to TASK-032)

#### TASK-031: Shipping Service v1

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 3 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update shipping service v1 (service + handler layers).

**Note**: Shipping service only has v1, no v2 separate version.

**Acceptance Criteria**:
- [ ] File `services/internal/shipping/logic/v1/service.go` updated
- [ ] File `services/internal/shipping/web/v1/handler.go` updated
- [ ] Sentinel errors: `ErrShipmentNotFound`, `ErrInvalidAddress`, `ErrCarrierUnavailable`

**Files Changed**:
- `services/internal/shipping/logic/v1/service.go` (~20 lines modified)
- `services/internal/shipping/web/v1/handler.go` (~15 lines modified)

---

#### TASK-032: Shipping-v2 Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 3 hours  
**Assignee**: TBD  
**Dependencies**: TASK-001, TASK-006  
**Can Run in Parallel**: ✅ Yes

**Description**:
Update shipping-v2 service (separate service with only v2 API).

**Note**: This is a separate service (`cmd/shipping-v2`), not a version within shipping service.

**Acceptance Criteria**:
- [ ] File `services/internal/shipping/logic/v2/service.go` updated
- [ ] File `services/internal/shipping/web/v2/handler.go` updated
- [ ] Same sentinel errors as shipping v1

**Files Changed**:
- `services/internal/shipping/logic/v2/service.go` (~20 lines modified)
- `services/internal/shipping/web/v2/handler.go` (~15 lines modified)

---

### Per-Service Testing (TASK-033 to TASK-040)

**Note**: These testing tasks can be done incrementally as each service is migrated, or batched together.

#### TASK-033: Test User Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-007, TASK-008, TASK-009, TASK-010  

**Acceptance Criteria**:
- [ ] Manual API testing (v1 and v2)
- [ ] Error log validation
- [ ] API responses unchanged

---

#### TASK-034: Test Product Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-011, TASK-012, TASK-013, TASK-014  

---

#### TASK-035: Test Cart Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-015, TASK-016, TASK-017, TASK-018  

---

#### TASK-036: Test Order Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-019, TASK-020, TASK-021, TASK-022  

---

#### TASK-037: Test Review Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-023, TASK-024, TASK-025, TASK-026  

---

#### TASK-038: Test Notification Service

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-027, TASK-028, TASK-029, TASK-030  

---

#### TASK-039: Test Shipping Services

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-031, TASK-032  

---

## Phase 3: Testing & Validation

**Goal**: Validate all changes work correctly and maintain backward compatibility  
**Duration**: 1 day  
**Dependencies**: All Phase 2 tasks complete  

### TASK-040: Integration Testing (All Services)

**Status**: 🔵 TODO  
**Priority**: P2 (Medium)  
**Effort**: 3-4 hours  
**Assignee**: TBD  
**Dependencies**: All Phase 2 tasks  

**Description**:
Comprehensive integration testing across all 9 services to ensure error handling works end-to-end.

**Acceptance Criteria**:
- [ ] **API Regression Testing**:
  - [ ] All v1 endpoints tested
  - [ ] All v2 endpoints tested
  - [ ] HTTP status codes verified unchanged
  - [ ] Response JSON verified unchanged
  - [ ] Error messages verified unchanged
- [ ] **Error Log Validation**:
  - [ ] Error logs include full error chains
  - [ ] Error logs include context (usernames, IDs, etc.)
  - [ ] Trace-IDs present in all error logs
  - [ ] Log format is JSON
- [ ] **OpenTelemetry Validation**:
  - [ ] Spans record errors correctly
  - [ ] Error attributes set on spans
  - [ ] Trace context propagated
- [ ] **Grafana/Loki Validation**:
  - [ ] Logs visible in Loki
  - [ ] Can query by error type
  - [ ] Trace-to-log correlation works
- [ ] **Prometheus Validation**:
  - [ ] Error metrics still collected
  - [ ] Error rate unchanged
  - [ ] No metric regressions

**Testing Script**:
```bash
# Test all services systematically
for svc in auth user product cart order review notification shipping; do
    echo "Testing $svc..."
    kubectl port-forward -n $svc svc/$svc 8080:8080 &
    PID=$!
    
    # Test endpoints (use service-specific curl commands)
    # ...
    
    # Check logs
    kubectl logs -n $svc -l app=$svc --tail=50 | grep -i error
    
    kill $PID
done
```

**Success Criteria**:
- [ ] All tests pass
- [ ] No API regressions
- [ ] Error handling improvements visible in logs
- [ ] No breaking changes

---

### TASK-041: Code Review

**Status**: 🔵 TODO  
**Priority**: P2 (Medium)  
**Effort**: 2-3 hours  
**Assignee**: TBD  
**Dependencies**: All Phase 2 tasks  

**Description**:
Comprehensive code review of all changes to ensure consistency and quality.

**Review Checklist**:
- [ ] **Code Quality**:
  - [ ] All code formatted with `go fmt`
  - [ ] No linter errors (`go vet`)
  - [ ] Consistent error naming
  - [ ] Consistent error wrapping pattern
- [ ] **Error Handling**:
  - [ ] All errors use `fmt.Errorf("%w")`
  - [ ] All handlers use `errors.Is()`
  - [ ] No type assertions remaining
  - [ ] Error context includes relevant parameters
- [ ] **Consistency**:
  - [ ] Same pattern across all 9 services
  - [ ] Similar error types named consistently
  - [ ] Similar operations handled identically
- [ ] **Documentation**:
  - [ ] errors.go files documented
  - [ ] ERROR_HANDLING.md accurate
  - [ ] Examples match actual code

**Files to Review**:
- All 18 errors.go files
- All 18 service.go files (logic layer)
- All 18 handler.go files (web layer)
- `docs/development/ERROR_HANDLING.md`

---

### TASK-042: Fix Code Review Issues

**Status**: 🔵 TODO  
**Priority**: P2 (Medium)  
**Effort**: 2-4 hours (contingency)  
**Assignee**: TBD  
**Dependencies**: TASK-041  

**Description**:
Address any issues found during code review.

**Acceptance Criteria**:
- [ ] All code review comments addressed
- [ ] Re-review approved
- [ ] All tests still passing

---

### TASK-043: Update CHANGELOG.md

**Status**: 🔵 TODO  
**Priority**: P2 (Medium)  
**Effort**: 30 minutes  
**Assignee**: TBD  
**Dependencies**: TASK-042  

**Description**:
Document changes in CHANGELOG.md.

**Acceptance Criteria**:
- [ ] File `CHANGELOG.md` updated:
  - [ ] New section for this release
  - [ ] Added: Sentinel errors, error wrapping, errors.Is()
  - [ ] Changed: Error messages, error logging
  - [ ] Technical: 18 errors.go files, 36 files modified
  - [ ] No breaking changes noted
- [ ] Date and version noted (if applicable)

**Files Changed**:
- `CHANGELOG.md` (~15 lines added)

**Reference**:
- Template in `plan.md` section "Step 4.2"

---

### TASK-044: Performance Validation

**Status**: 🔵 TODO  
**Priority**: P2 (Medium)  
**Effort**: 1-2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-040  

**Description**:
Validate that error handling improvements have zero performance impact.

**Acceptance Criteria**:
- [ ] **Grafana Metrics Validation**:
  - [ ] P50 latency unchanged (< 1% variance)
  - [ ] P95 latency unchanged (< 5% variance)
  - [ ] P99 latency unchanged (< 5% variance)
  - [ ] Request rate unchanged
  - [ ] Error rate unchanged (or improved)
  - [ ] No increase in restarts/crashes
- [ ] **Pyroscope Profiling**:
  - [ ] CPU usage unchanged
  - [ ] Memory usage unchanged
  - [ ] No new allocation hotspots
- [ ] **Load Testing (k6)**:
  - [ ] Load test passes
  - [ ] Same throughput as before
  - [ ] Same latency distribution

**Testing Commands**:
```bash
# Deploy k6 load test
./scripts/06-deploy-k6.sh

# Monitor in Grafana
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
# Open: http://localhost:3000/d/microservices-monitoring-001/

# Compare metrics before/after
```

**Success Criteria**:
- [ ] No measurable performance degradation
- [ ] Performance metrics within variance threshold

---

## Phase 4: Deployment

**Goal**: Deploy all changes to production  
**Duration**: 0.5 day  
**Dependencies**: Phase 3 complete  

### TASK-045: Build Docker Images

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 30 minutes  
**Assignee**: TBD  
**Dependencies**: TASK-044 (performance validated)  

**Description**:
Build Docker images for all 9 services with error handling improvements.

**Acceptance Criteria**:
- [ ] All services build successfully
- [ ] Docker images tagged correctly
- [ ] Images pushed to registry (if applicable)

**Commands**:
```bash
# Build all services
./scripts/04-build-microservices.sh

# Expected output:
# Building auth...
# Building user...
# Building product...
# ...
# All services built successfully
```

**Verification**:
```bash
# List images
docker images | grep -E "(auth|user|product|cart|order|review|notification|shipping)"

# Verify each image
for svc in auth user product cart order review notification shipping; do
    docker inspect $svc:latest
done
```

---

### TASK-046: Deploy to Kubernetes

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: TBD  
**Dependencies**: TASK-045  

**Description**:
Deploy all services to Kubernetes cluster using Helm.

**Acceptance Criteria**:
- [ ] All 9 services deployed successfully
- [ ] Rolling updates completed
- [ ] All pods running (18 pods total: 9 services × 2 replicas)
- [ ] Health checks passing
- [ ] No pod restarts

**Commands**:
```bash
# Deploy all services
./scripts/05-deploy-microservices.sh --local

# Verify deployment
kubectl get pods -A | grep -E "(auth|user|product|cart|order|review|notification|shipping)"

# Check rollout status
for svc in auth user product cart order review notification shipping; do
    kubectl rollout status deployment/$svc -n $svc
done
```

**Rollback Plan**:
```bash
# If issues detected, rollback
for svc in auth user product cart order review notification shipping; do
    helm rollback $svc -n $svc
done
```

**Success Criteria**:
- [ ] All deployments successful
- [ ] Zero downtime
- [ ] No errors in logs
- [ ] Metrics flowing to Prometheus
- [ ] Logs flowing to Loki
- [ ] Traces flowing to Tempo

---

### TASK-047: Post-Deployment Validation

**Status**: 🔵 TODO  
**Priority**: P1 (High)  
**Effort**: 1-2 hours  
**Assignee**: TBD  
**Dependencies**: TASK-046  

**Description**:
Validate deployment and monitor for issues.

**Acceptance Criteria**:
- [ ] **Service Health**:
  - [ ] All pods running
  - [ ] Health checks passing
  - [ ] No CrashLoopBackOff
  - [ ] No excessive restarts
- [ ] **API Functionality**:
  - [ ] Spot-check key endpoints
  - [ ] Verify responses correct
  - [ ] No 500 errors spike
- [ ] **Observability**:
  - [ ] Grafana dashboards working
  - [ ] Error logs visible in Loki
  - [ ] Traces visible in Tempo
  - [ ] Metrics in Prometheus
- [ ] **Error Handling**:
  - [ ] Trigger test errors
  - [ ] Verify error logs have context
  - [ ] Verify trace-ID correlation
  - [ ] Verify error chains visible
- [ ] **SLO Tracking**:
  - [ ] SLO dashboards updated
  - [ ] Error budget unchanged
  - [ ] No SLO violations

**Monitoring Duration**: 2-4 hours after deployment

**Success Criteria**:
- [ ] No incidents
- [ ] No customer complaints
- [ ] Metrics stable
- [ ] Error handling improvements visible

---

## Progress Tracking

### Overall Progress

| Phase | Tasks | Completed | In Progress | Blocked | Pending |
|-------|-------|-----------|-------------|---------|---------|
| **Phase 1: Foundation** | 6 | 0 | 0 | 0 | 6 |
| **Phase 2: Migration** | 32 | 0 | 0 | 0 | 32 |
| **Phase 3: Testing** | 5 | 0 | 0 | 0 | 5 |
| **Phase 4: Deployment** | 3 | 0 | 0 | 0 | 3 |
| **Total** | **46** | **0** | **0** | **0** | **46** |

**Completion**: 0% (0/46 tasks)

### Milestone Progress

- [ ] **M1**: Foundation Complete (TASK-001 to TASK-006) - Target: Day 1
- [ ] **M2**: 50% Services Migrated (16/32 service tasks) - Target: Day 3
- [ ] **M3**: All Services Migrated (all Phase 2 tasks) - Target: Day 4
- [ ] **M4**: Testing Complete (all Phase 3 tasks) - Target: Day 5
- [ ] **M5**: Deployed to Production (all Phase 4 tasks) - Target: Day 5-6

### Daily Progress Tracking

**Day 1**: _________  
**Day 2**: _________  
**Day 3**: _________  
**Day 4**: _________  
**Day 5**: _________  

---

## Dependencies Map

### Critical Path

```
TASK-001 (errors.go)
    ↓
TASK-002 (auth v1 service) → TASK-003 (auth v1 handler)
    ↓
TASK-005 (test auth)
    ↓
TASK-006 (documentation)
    ↓
[Phase 2: All service migrations in parallel - 32 tasks]
    ↓
TASK-040 (integration testing)
    ↓
TASK-041 (code review) → TASK-042 (fixes)
    ↓
TASK-044 (performance validation)
    ↓
TASK-045 (build) → TASK-046 (deploy) → TASK-047 (validate)
```

### Parallel Execution Opportunities

**After TASK-001 and TASK-006 complete, these can run in parallel:**
- User Service (TASK-007 to TASK-010, TASK-033)
- Product Service (TASK-011 to TASK-014, TASK-034)
- Cart Service (TASK-015 to TASK-018, TASK-035)
- Order Service (TASK-019 to TASK-022, TASK-036)
- Review Service (TASK-023 to TASK-026, TASK-037)
- Notification Service (TASK-027 to TASK-030, TASK-038)
- Shipping Services (TASK-031 to TASK-032, TASK-039)

**With 8 parallel agents**: Can complete all 8 services simultaneously!

---

## Parallel Execution Guide

### Setup for Multi-Agent Execution

**Prerequisites**:
- Cursor 2.1+ with multi-agent support (up to 8 parallel agents)
- All developers have access to codebase
- TASK-001 and TASK-006 must be complete first

### Parallel Execution Plan

**Phase 1**: Sequential (Day 1)
- One person completes TASK-001 to TASK-006
- Establishes pattern and documentation

**Phase 2**: Parallel (Day 2-3)
- **Agent 1**: User Service (TASK-007 to TASK-010, TASK-033)
- **Agent 2**: Product Service (TASK-011 to TASK-014, TASK-034)
- **Agent 3**: Cart Service (TASK-015 to TASK-018, TASK-035)
- **Agent 4**: Order Service (TASK-019 to TASK-022, TASK-036)
- **Agent 5**: Review Service (TASK-023 to TASK-026, TASK-037)
- **Agent 6**: Notification Service (TASK-027 to TASK-030, TASK-038)
- **Agent 7**: Shipping Service (TASK-031, half of TASK-039)
- **Agent 8**: Shipping-v2 Service (TASK-032, half of TASK-039)

**Result**: 8 services migrated in ~4 hours instead of 3 days!

### Assignment Strategy

**Option 1: By Service** (Recommended)
- Each developer owns 1 service end-to-end
- Better ownership and accountability
- Easier to test incrementally

**Option 2: By Layer**
- Some developers do service layer
- Others do handler layer
- Requires more coordination

### Communication Protocol

**Daily Standup**:
- What tasks completed yesterday
- What tasks planned today
- Any blockers or questions

**Slack/Teams Channel**:
- Post when tasks complete
- Ask questions if pattern unclear
- Share discoveries or issues

**Pull Requests**:
- One PR per service (recommended)
- Or one PR per task (more granular)
- Tag code reviewers

---

## Appendix: Quick Reference

### Task IDs by Service

| Service | Service v1 | Handler v1 | Service v2 | Handler v2 | Test |
|---------|-----------|-----------|-----------|-----------|------|
| **Auth** | TASK-002 | TASK-003 | TASK-004 | (included) | TASK-005 |
| **User** | TASK-007 | TASK-008 | TASK-009 | TASK-010 | TASK-033 |
| **Product** | TASK-011 | TASK-012 | TASK-013 | TASK-014 | TASK-034 |
| **Cart** | TASK-015 | TASK-016 | TASK-017 | TASK-018 | TASK-035 |
| **Order** | TASK-019 | TASK-020 | TASK-021 | TASK-022 | TASK-036 |
| **Review** | TASK-023 | TASK-024 | TASK-025 | TASK-026 | TASK-037 |
| **Notification** | TASK-027 | TASK-028 | TASK-029 | TASK-030 | TASK-038 |
| **Shipping** | TASK-031 | (included) | N/A | N/A | TASK-039 |
| **Shipping-v2** | TASK-032 | (included) | N/A | N/A | TASK-039 |

### Effort Summary

| Task Type | Count | Hours Each | Total Hours |
|-----------|-------|------------|-------------|
| **errors.go creation** | 1 | 2-3h | 2-3h |
| **Auth service migration** | 3 | 2-3h | 6-9h |
| **Documentation** | 1 | 2h | 2h |
| **Service migrations** | 32 | 2h | 64h |
| **Testing** | 9 | 1h | 9h |
| **Integration testing** | 1 | 3-4h | 3-4h |
| **Code review** | 1 | 2-3h | 2-3h |
| **Deployment** | 3 | 1h | 3h |
| **Total (Sequential)** | 51 | - | **91-97h** (~12-13 days) |
| **Total (8 Parallel)** | 51 | - | **~24-32h** (~3-4 days) |

### Critical Commands

```bash
# Create errors.go files
for svc in auth user product cart order review notification shipping; do
    touch services/internal/$svc/logic/v1/errors.go
    touch services/internal/$svc/logic/v2/errors.go
done

# Build all services
./scripts/04-build-microservices.sh

# Deploy all services
./scripts/05-deploy-microservices.sh --local

# Check progress
find services/internal -name "errors.go" | wc -l  # Should be 18
grep -r "fmt.Errorf.*%w" services/internal/*/logic/ | wc -l
grep -r "errors.Is" services/internal/*/web/ | wc -l
```

---

## Summary

**Total Tasks**: 46  
**Estimated Time**: 5-7 days (sequential) OR 2-3 days (parallel)  
**Breaking Changes**: None (100% backward compatible)  
**Risk**: Low (safe rollback, incremental deployment)

**Next Step**: Start with TASK-001 to create foundation! 🚀

---

**Task Breakdown Status**: ✅ Complete and Ready for Implementation  
**Created**: December 10, 2025  
**Last Updated**: December 10, 2025

