# Feature Specification: K6 Traffic Optimization

> **Feature ID**: k6-traffic-optimization  
> **Created**: December 10, 2025  
> **Status**: Specified  
> **Priority**: High  
> **Estimated Effort**: 1-2 hours  

---

## Table of Contents
- [Problem Statement](#problem-statement)
- [Requirements](#requirements)
- [User Stories](#user-stories)
- [Success Metrics](#success-metrics)
- [Implementation Scope](#implementation-scope)
- [Technical Design](#technical-design)
- [Edge Cases & Error Scenarios](#edge-cases--error-scenarios)
- [Dependencies & Risks](#dependencies--risks)
- [Testing Strategy](#testing-strategy)
- [Acceptance Criteria](#acceptance-criteria)

---

## Problem Statement

### Current Situation

K6 load testing hiện đang gọi infrastructure endpoints (`/health` và `/metrics`) chiếm **79% total traffic**, causing significant issues:

**Traffic Distribution (from Grafana):**
- `/health`: **1936 requests (65%)** ❌ Infrastructure
- `/metrics`: **423 requests (14%)** ❌ Infrastructure  
- Business APIs: **~621 requests (21%)** ✅ Only this should be tracked

**Root Causes:**
1. **Health checks in k6 script**: 5 locations calling `/health` endpoint with 10% frequency
2. **Conceptual mistake**: Mixing monitoring concerns (health checks) with load testing (business traffic)
3. **No middleware filtering**: All requests recorded in metrics, including infrastructure endpoints
4. **Redundant monitoring**: Kubernetes probes and Prometheus already monitor health, k6 duplicates this

### Impact Analysis

**1. Dashboard Metrics Accuracy:**
- ❌ **79% noise**: Dashboard shows infrastructure traffic, not business patterns
- ❌ **Skewed percentiles**: P95/P99 latency artificially lowered by fast health checks
- ❌ **Wrong RPS**: Request rate doesn't reflect realistic load
- ❌ **Incorrect error rates**: Denominator includes non-business requests

**2. APM Observability:**
- ❌ **Tempo pollution**: 79% of traces are health check spans
- ❌ **Loki noise**: Health check logs dilute business logs
- ❌ **Pyroscope overhead**: Profiling collects data for infrastructure calls
- ❌ **Storage waste**: Storing unnecessary traces, logs, metrics

**3. Development & Operations:**
- ❌ **Wrong patterns**: Developers learn incorrect load testing practices
- ❌ **Misleading SLOs**: Error budgets calculated on skewed data
- ❌ **Difficult debugging**: Hard to find real issues in 79% noise
- ❌ **Resource waste**: CPU/memory/network for unnecessary requests

### Affected Users

**Primary Users:**
- **DevOps Engineers**: Need accurate dashboard metrics for capacity planning
- **SRE Team**: Need reliable SLO tracking and error budget monitoring
- **Developers**: Need clean APM data for debugging production issues
- **Monitoring Team**: Need realistic traffic patterns for alerting rules

**Secondary Users:**
- **Business Stakeholders**: Need accurate performance reports
- **Security Team**: Need to audit real traffic patterns

### Business Importance

**Critical Priority** because:
1. **Production decisions based on wrong data**: Capacity planning, scaling decisions, SLO targets
2. **Wasted resources**: 79% of monitoring infrastructure processing useless data
3. **Incident response delays**: Hard to identify real issues in noisy data
4. **Compliance risk**: SLO reports don't reflect actual user experience

### Reference Research

Detailed analysis in: `specs/active/k6-traffic-optimization/research.md`

---

## Requirements

### Functional Requirements

**FR-001: Remove Health Check Calls from K6 Script**
- **Description**: Delete all 5 health check code blocks from `k6/load-test-multiple-scenarios.js`
- **Locations**:
  - Line 696-699: `browserUserScenario()` - conditional health check
  - Line 769-772: `shoppingUserScenario()` - conditional health check
  - Line 842-845: `registeredUserScenario()` - conditional health check
  - Line 892: `apiClientScenario()` - **unconditional** health check (always executes!)
  - Line 940-943: `adminUserScenario()` - conditional health check
- **Rationale**: K6 load testing should only simulate business traffic, not infrastructure monitoring
- **Acceptance**: Zero health check calls in k6 logs after deployment

**FR-002: Filter /health Endpoint in Prometheus Middleware**
- **Description**: Add early return in `services/pkg/middleware/prometheus.go` to skip metrics collection for `/health` path
- **Implementation**: Check `c.Request.URL.Path == "/health"` before metrics collection
- **Rationale**: Kubernetes liveness/readiness probes shouldn't pollute business metrics
- **Acceptance**: Prometheus metrics show 0 requests to `/health` endpoint

**FR-003: Filter /metrics Endpoint in Prometheus Middleware**
- **Description**: Add early return in `services/pkg/middleware/prometheus.go` to skip metrics collection for `/metrics` path
- **Implementation**: Check `c.Request.URL.Path == "/metrics"` before metrics collection
- **Rationale**: Prometheus scraping its own endpoint creates circular metrics
- **Acceptance**: Prometheus metrics show 0 requests to `/metrics` endpoint

**FR-004: Filter Infrastructure Endpoints in Tracing Middleware (Optional)**
- **Description**: Add early return in `services/pkg/middleware/tracing.go` to skip span creation for `/health` and `/metrics`
- **Implementation**: Check path before calling OpenTelemetry tracer
- **Rationale**: Reduces Tempo span volume by 79%, cleaner distributed traces
- **Acceptance**: Tempo shows 0 traces for infrastructure endpoints
- **Priority**: Optional but recommended for consistency

**FR-005: Maintain Existing Business API Behavior**
- **Description**: Ensure all business API endpoints (`/api/v1/*`, `/api/v2/*`) continue working exactly as before
- **Implementation**: Filtering logic only affects `/health` and `/metrics` paths
- **Rationale**: Zero breaking changes, backward compatibility
- **Acceptance**: All API endpoints respond with same status codes and latencies

---

### Non-Functional Requirements

**NFR-001: Performance - Zero Latency Impact**
- **Description**: Filtering logic must have negligible performance overhead
- **Target**: < 1 microsecond overhead per request
- **Implementation**: Simple string comparison, early return (fastest path)
- **Measurement**: Benchmark before/after with `go test -bench`
- **Acceptance**: P99 latency unchanged (±1ms tolerance)

**NFR-002: Compatibility - Kubernetes Probes Unaffected**
- **Description**: Health check filtering must not break Kubernetes liveness/readiness probes
- **Implementation**: Probes still reach `/health` endpoint, just not recorded in metrics
- **Verification**: Pod restart count = 0 after deployment
- **Acceptance**: All pods remain in Running state, no CrashLoopBackOff

**NFR-003: Observability - Debugging Capability Maintained**
- **Description**: Ability to debug health check issues must be preserved
- **Implementation**: Health checks still execute, still return responses, just not metrified
- **Alternative**: Manual curl for debugging: `curl http://service:8080/health`
- **Acceptance**: Health endpoint returns `{"status":"ok"}` when queried manually

**NFR-004: Metrics Accuracy - 100% Business Traffic**
- **Description**: Dashboard metrics must reflect only business API traffic
- **Target**: 100% of recorded requests are business endpoints
- **Measurement**: Grafana "Total Requests by Endpoint" panel
- **Acceptance**: No `/health` or `/metrics` in top 10 endpoints

**NFR-005: Code Maintainability - Simple, Clear Logic**
- **Description**: Filtering implementation must be easy to understand and maintain
- **Implementation**: 3-4 lines of code, clear comments explaining rationale
- **Code review**: Pass review with zero questions about logic
- **Acceptance**: Future developers can understand purpose without explanation

**NFR-006: Backward Compatibility - Zero Breaking Changes**
- **Description**: All existing functionality must work unchanged
- **Scope**: APIs, metrics collection for business endpoints, traces, logs
- **Verification**: Smoke test all 9 services × 2 versions = 18 API endpoints
- **Acceptance**: Zero API errors or behavior changes

---

## User Stories

### US-001: DevOps Engineer - Accurate Dashboard Metrics

**As a** DevOps Engineer  
**I want** dashboard metrics to show only business traffic  
**So that** I can make accurate capacity planning and scaling decisions

**Acceptance Criteria:**
- ✅ Grafana "Total Requests by Endpoint" panel shows 100% business APIs
- ✅ `/health` and `/metrics` do not appear in top 10 endpoints
- ✅ P95/P99 latency reflects real business API performance
- ✅ RPS metrics show realistic load (no health check inflation)
- ✅ Error rate calculations based on business traffic only

**Priority**: Critical  
**Effort**: 1 hour (k6 script changes + middleware filter)  
**Dependencies**: None  

**Success Scenario:**
```
Given: Dashboard shows 79% infrastructure traffic
When: Deploy optimized k6 + filtered middleware
Then: Dashboard shows 100% business traffic
And: Capacity planning based on accurate data
```

**Failure Scenario:**
```
Given: Middleware filter has bug
When: All traffic filtered accidentally
Then: Dashboard shows 0% traffic
And: Alert fired "No metrics received"
```

---

### US-002: Developer - Realistic Load Testing

**As a** Backend Developer  
**I want** k6 load tests to simulate realistic user behavior  
**So that** I can validate my API performance under production-like load

**Acceptance Criteria:**
- ✅ K6 script only calls business API endpoints
- ✅ User journeys reflect real customer flows (9-service e-commerce journey)
- ✅ No health check or metrics calls in k6 logs
- ✅ Load test results representative of production patterns
- ✅ Can identify bottlenecks in business logic (not skewed by fast health checks)

**Priority**: High  
**Effort**: 15 minutes (delete 5 code blocks)  
**Dependencies**: None  

**Success Scenario:**
```
Given: K6 script with health checks
When: Remove all 5 health check blocks
Then: K6 logs show only business API calls
And: Load test reflects realistic user behavior
```

---

### US-003: SRE - Clean SLO Tracking

**As an** SRE  
**I want** health checks separated from load testing  
**So that** SLO error budgets reflect actual user experience

**Acceptance Criteria:**
- ✅ SLO calculations based on 100% business traffic
- ✅ Error budget tracking accurate (no health check denominator inflation)
- ✅ Burn rate alerts triggered by real user errors only
- ✅ Kubernetes probes still monitor service health (separate concern)
- ✅ Load testing validates business SLOs, not infrastructure SLOs

**Priority**: Critical  
**Effort**: 30 minutes (verify SLO queries still work)  
**Dependencies**: Sloth Operator PrometheusServiceLevels  

**Success Scenario:**
```
Given: SLO error budget at 95% (5% consumed)
When: Deploy filtered metrics (remove 79% health checks)
Then: Error budget recalculated accurately
And: Represents actual user error rate
```

---

### US-004: Monitoring Team - Cleaner APM Data

**As a** Monitoring Team Member  
**I want** APM data without infrastructure noise  
**So that** I can quickly identify and debug production issues

**Acceptance Criteria:**
- ✅ Tempo traces show only business transaction spans
- ✅ 79% reduction in trace volume (faster queries)
- ✅ Loki logs focused on business operations
- ✅ Pyroscope profiles relevant to business logic
- ✅ Grafana Explore queries return results faster

**Priority**: High  
**Effort**: 30 minutes (add tracing middleware filter)  
**Dependencies**: FR-004 (optional tracing filter)  

**Success Scenario:**
```
Given: Tempo has 10,000 spans/min (79% health checks)
When: Deploy tracing filter
Then: Tempo has 2,100 spans/min (100% business)
And: TraceQL queries 5x faster
```

---

## Success Metrics

### Primary Metrics

**M-001: Business Traffic Percentage**
- **Current**: 21% business, 79% infrastructure
- **Target**: 100% business, 0% infrastructure
- **Measurement**: Grafana "Total Requests by Endpoint" panel
- **Query**: `topk(10, sum by (path) (rate(requests_total[5m])))`
- **Success Criteria**: Top 10 endpoints all start with `/api/v1/` or `/api/v2/`

**M-002: Dashboard Accuracy Improvement**
- **Current**: P95 latency skewed -30% by fast health checks
- **Target**: P95 latency reflects real business API performance
- **Measurement**: Compare P95 before/after for `/api/v1/products`
- **Success Criteria**: P95 latency increases to realistic value (health checks no longer skewing avg)

**M-003: APM Trace Volume Reduction**
- **Current**: 10,000 spans/min (79% health checks)
- **Target**: 2,100 spans/min (100% business)
- **Measurement**: Tempo metrics `tempo_distributor_spans_received_total`
- **Success Criteria**: 79% reduction in span ingestion rate

**M-004: K6 Test Execution**
- **Current**: ~3-4 million requests over 6.5 hours (79% waste)
- **Target**: ~800K business requests (same user behavior, no health checks)
- **Measurement**: K6 summary output `http_reqs` metric
- **Success Criteria**: Total requests reduced ~75%, RPS unchanged for business APIs

---

### Secondary Metrics

**M-005: Zero Breaking Changes**
- **Measurement**: API smoke test (curl all endpoints)
- **Success Criteria**: All 18 endpoints (9 services × 2 versions) return 200 OK

**M-006: Kubernetes Health**
- **Measurement**: Pod restart count
- **Success Criteria**: Zero restarts after deployment (probes still work)

**M-007: Build & Deploy Time**
- **Measurement**: Pipeline execution time
- **Success Criteria**: Same or faster (simpler code, fewer requests)

**M-008: Metrics Storage Efficiency**
- **Measurement**: Prometheus TSDB size growth rate
- **Success Criteria**: 79% slower growth (fewer time series)

---

## Implementation Scope

### In Scope ✅

**Code Changes:**
- ✅ Remove 5 health check blocks from `k6/load-test-multiple-scenarios.js`
- ✅ Add filtering logic to `services/pkg/middleware/prometheus.go` (2-3 lines)
- ✅ Add filtering logic to `services/pkg/middleware/tracing.go` (2-3 lines, optional)
- ✅ Update comments to explain filtering rationale

**Documentation:**
- ✅ Update `docs/k6/K6_LOAD_TESTING.md` - remove health check references
- ✅ Add note in `docs/monitoring/METRICS.md` about filtered endpoints
- ✅ Update `CHANGELOG.md` with v0.6.14 entry

**Build & Deploy:**
- ✅ Rebuild k6 Docker image (`ghcr.io/duynhne/k6:scenarios`)
- ✅ Rebuild all 9 microservice images (middleware changed)
- ✅ Deploy via Helm (k6 + microservices)

**Verification:**
- ✅ Check k6 logs (no health checks)
- ✅ Check Grafana dashboard (100% business traffic)
- ✅ Check Prometheus metrics (no /health or /metrics)
- ✅ Smoke test all APIs (zero breaking changes)

---

### Out of Scope ❌

**NOT Changing:**
- ❌ Kubernetes probe configuration (already correct)
- ❌ Prometheus ServiceMonitor (already scrapes `/metrics` correctly)
- ❌ Grafana dashboard structure (queries work with filtered data)
- ❌ SLO PrometheusServiceLevel CRDs (queries still valid)
- ❌ Health endpoint implementation (still returns `{"status":"ok"}`)

**NOT Adding:**
- ❌ New health check mechanisms
- ❌ Alternative monitoring tools
- ❌ Performance optimizations beyond filtering
- ❌ New k6 scenarios or journeys

**Deferred to Future:**
- ⏳ Logging middleware filtering (separate decision)
- ⏳ Recording rules for pre-filtered metrics
- ⏳ Grafana dashboard templates with filters built-in

---

## Technical Design

### Architecture Overview

**Current Flow (WRONG):**
```
k6 Load Test
  ├─> Business APIs (21%)
  ├─> /health (65%)  ❌ Should not be in load test
  └─> /metrics (14%) ❌ Should not be in load test
         ↓
   Prometheus Middleware (records ALL)
         ↓
   Grafana Dashboard (79% noise)
```

**New Flow (CORRECT):**
```
k6 Load Test
  └─> Business APIs (100%) ✅ Only business traffic

Kubernetes Probes (separate)
  └─> /health ✅ Infrastructure monitoring

Prometheus Scraper (separate)
  └─> /metrics ✅ Metrics collection

Prometheus Middleware (filters /health, /metrics)
  └─> Records only business APIs
         ↓
   Grafana Dashboard (100% business traffic)
```

---

### Component Changes

#### 1. K6 Script Changes

**File**: `k6/load-test-multiple-scenarios.js`

**Change 1: browserUserScenario (lines 696-699)**
```javascript
// REMOVE:
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
  }

// REASON: Health checks are for Kubernetes probes, not load testing
```

**Change 2: shoppingUserScenario (lines 769-772)**
```javascript
// REMOVE:
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.cart}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
```

**Change 3: registeredUserScenario (lines 842-845)**
```javascript
// REMOVE:
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.user}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
```

**Change 4: apiClientScenario (line 892) - CRITICAL**
```javascript
// REMOVE:
  // Health check
  http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });

// NOTE: This one has NO condition - always executes! 
// High priority to remove.
```

**Change 5: adminUserScenario (lines 940-943)**
```javascript
// REMOVE:
  // Health check - only 10% of iterations (monitoring, not load testing)
  if (Math.random() < 0.1) {
    http.get(`${SERVICES.user}/health`, { tags: { ...tags, endpoint: '/health' } });
  }
```

**Total Deletions**: 5 blocks, ~15 lines of code

---

#### 2. Prometheus Middleware Changes

**File**: `services/pkg/middleware/prometheus.go`

**Current Code** (line 65-100):
```go
func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		
		method := c.Request.Method
		path := c.Request.URL.Path
		
		// Increment in-flight requests
		requestsInFlight.WithLabelValues(method, path).Inc()
		
		// ... rest of metrics collection
	}
}
```

**New Code** (add filtering at start):
```go
func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		
		// Skip metrics collection for infrastructure endpoints
		// Rationale: Health checks are for Kubernetes probes, not business metrics
		// Metrics endpoint is for Prometheus scraping, not application requests
		if path == "/health" || path == "/metrics" {
			c.Next()
			return
		}
		
		start := time.Now()
		method := c.Request.Method
		
		// Increment in-flight requests
		requestsInFlight.WithLabelValues(method, path).Inc()
		
		// ... rest of metrics collection (UNCHANGED)
	}
}
```

**Changes**:
- Add path variable before metrics logic
- Add if statement with 2 conditions (OR)
- Early return if infrastructure endpoint
- **Lines added**: 6 (including comments)
- **Performance**: < 1 microsecond (string comparison)

---

#### 3. Tracing Middleware Changes (Optional)

**File**: `services/pkg/middleware/tracing.go`

**Current Code** (simplified):
```go
func TracingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()
		path := c.Request.URL.Path
		
		// Start span for this request
		ctx, span := tracer.Start(ctx, fmt.Sprintf("%s %s", c.Request.Method, path))
		defer span.End()
		
		// ... rest of tracing
	}
}
```

**New Code** (add filtering):
```go
func TracingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		
		// Skip tracing for infrastructure endpoints
		// Rationale: Reduces Tempo span volume by 79%, cleaner distributed traces
		if path == "/health" || path == "/metrics" {
			c.Next()
			return
		}
		
		ctx := c.Request.Context()
		
		// Start span for this request
		ctx, span := tracer.Start(ctx, fmt.Sprintf("%s %s", c.Request.Method, path))
		defer span.End()
		
		// ... rest of tracing (UNCHANGED)
	}
}
```

**Changes**:
- Move path variable to start
- Add if statement (same as Prometheus middleware)
- Early return for infrastructure endpoints
- **Lines added**: 5 (including comments)
- **Impact**: 79% fewer spans in Tempo

---

### Build & Deploy Process

**Phase 1: Code Changes** (10 min)
```bash
# 1. Edit k6 script
vim k6/load-test-multiple-scenarios.js
# Delete 5 health check blocks

# 2. Edit Prometheus middleware
vim services/pkg/middleware/prometheus.go
# Add filtering logic

# 3. Edit Tracing middleware (optional)
vim services/pkg/middleware/tracing.go
# Add filtering logic
```

**Phase 2: Build** (20 min)
```bash
# 1. Build k6 image
cd k6
docker build --build-arg SCRIPT_FILE=load-test-multiple-scenarios.js \
  -t ghcr.io/duynhne/k6:scenarios .
kind load docker-image ghcr.io/duynhne/k6:scenarios --name monitoring-local

# 2. Build all microservices (middleware changed)
cd ..
./scripts/04-build-microservices.sh
# Builds all 9 services
```

**Phase 3: Deploy** (30 min)
```bash
# 1. Deploy microservices
./scripts/05-deploy-microservices.sh --local
# Rolling update, zero downtime

# 2. Redeploy k6
kubectl delete deployment k6-scenarios -n k6
helm upgrade --install k6-scenarios charts/ \
  -f charts/values/k6-scenarios.yaml \
  -n k6 --create-namespace

# Wait for rollout
kubectl rollout status deployment/k6-scenarios -n k6
```

**Phase 4: Verification** (15 min)
```bash
# 1. Check k6 logs (should see NO health checks)
kubectl logs -n k6 -l app=k6-scenarios -f | grep -i health
# Expected: No matches

# 2. Check Grafana dashboard (wait 5-10 min for data)
kubectl port-forward -n monitoring svc/grafana-service 3000:3000
# Open: http://localhost:3000/d/microservices-monitoring-001/
# Panel: "Total Requests by Endpoint"
# Expected: 100% business APIs, no /health or /metrics

# 3. Check Prometheus metrics
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Query: topk(10, sum by (path) (rate(requests_total[5m])))
# Expected: Only /api/v1/* and /api/v2/* paths

# 4. Smoke test all APIs (ensure zero breaking changes)
for service in auth user product cart order review notification shipping; do
  kubectl port-forward -n $service svc/$service 8080:8080 &
  curl -s http://localhost:8080/api/v1/health || echo "$service FAILED"
  kill %1
done
```

---

## Edge Cases & Error Scenarios

### EC-001: Kubernetes Probes Fail After Middleware Change

**Scenario**: Filtering logic accidentally breaks health endpoint

**Root Cause**: Bug in middleware - returns early without executing handler

**Symptoms**:
- Pods enter CrashLoopBackOff state
- Liveness probe failures in pod events
- Services become unreachable

**Prevention**:
```go
// CORRECT: Early return AFTER calling c.Next()
if path == "/health" || path == "/metrics" {
    c.Next()  // Execute handler (health endpoint still works)
    return    // Skip metrics collection
}

// WRONG: Return BEFORE calling c.Next()
if path == "/health" || path == "/metrics" {
    return  // ❌ Handler never executes! Health endpoint breaks!
}
```

**Detection**: Pod restart count > 0 immediately after deployment

**Mitigation**: 
- Code review catches this (simple logic)
- Unit test verifies health endpoint still responds
- Rollback deployment if detected

---

### EC-002: Grafana Dashboard Shows 0% Traffic

**Scenario**: Middleware filter has bug and filters ALL requests

**Root Cause**: Typo in condition (e.g., `!=` instead of `==`)

**Symptoms**:
- "Total Requests by Endpoint" panel empty
- All metrics show 0 values
- Alert "No metrics received" fires

**Prevention**:
```go
// CORRECT:
if path == "/health" || path == "/metrics" {
    c.Next()
    return
}

// WRONG:
if path != "/health" || path != "/metrics" {  // ❌ Filters everything!
    c.Next()
    return
}
```

**Detection**: 
- Grafana dashboard empty 5 minutes after deployment
- Prometheus query returns no results
- K6 logs show requests succeeding (200 OK)

**Mitigation**:
- Code review catches typo
- Integration test verifies metrics still collected for business APIs
- Rollback if detected

---

### EC-003: Health Checks Needed for Debugging

**Scenario**: Developer needs to check if service is healthy

**Challenge**: K6 no longer calls health endpoint, middleware filters it

**Solution**: Use manual curl, not load testing
```bash
# Manual health check (still works!)
kubectl port-forward -n auth svc/auth 8080:8080
curl http://localhost:8080/health
# Response: {"status":"ok"}

# Or from another pod:
kubectl exec -n auth -it auth-pod-xxx -- curl http://localhost:8080/health
```

**Rationale**: 
- Health checks are for debugging/monitoring, not load testing
- Kubernetes probes run every 5-10 seconds (plenty of coverage)
- Manual curl available anytime for troubleshooting

**Documentation**: Add note in K6_LOAD_TESTING.md about manual health checks

---

### EC-004: Metrics Endpoint Still Showing Traffic

**Scenario**: After deployment, `/metrics` still appears in dashboard

**Root Cause**: Prometheus scraping creates requests to `/metrics` endpoint

**Analysis**: 
- Prometheus ServiceMonitor scrapes every 15 seconds
- BUT: Middleware filters these now, so shouldn't appear in metrics
- If still appearing: Something else calling `/metrics` (not Prometheus)

**Investigation**:
```bash
# Check who's calling /metrics
kubectl logs -n auth -l app=auth --tail=100 | grep "/metrics"
# Look at User-Agent header

# Expected: Only Prometheus scraper (filtered by middleware)
# If others: External monitoring tool or misconfigured k6
```

**Mitigation**: 
- Middleware filter should catch all `/metrics` calls
- If still appearing, add debugging logs to identify source

---

### EC-005: SLO Calculations Wrong After Change

**Scenario**: Error budget jumps unexpectedly after filtering health checks

**Root Cause**: SLO queries used denominator including health checks

**Analysis**:
- Before: 1000 total requests (790 health, 210 business, 10 errors) = 1% error rate
- After: 210 total requests (210 business, 10 errors) = 4.7% error rate
- **This is CORRECT** - real error rate was hidden by health check inflation!

**Action**: 
- Recalibrate SLO targets based on realistic traffic
- Update error budget thresholds
- Communicate to stakeholders: "This is more accurate, not worse"

**Documentation**: Add note in SLO docs about baseline recalibration

---

## Dependencies & Risks

### Dependencies

**Required Before Implementation:**
- ✅ Go 1.23 (already installed)
- ✅ Docker (for image builds)
- ✅ Kubernetes cluster (Kind cluster running)
- ✅ Helm 3.x (for deployments)
- ✅ Grafana dashboard deployed (to verify results)

**Required During Implementation:**
- ✅ Access to edit k6 script
- ✅ Access to edit Go middleware code
- ✅ Access to build Docker images
- ✅ Access to deploy to Kubernetes

**Required After Implementation:**
- ✅ 5-10 minutes for Prometheus to scrape new data
- ✅ Grafana dashboard to visualize changes
- ✅ K6 load test running to generate traffic

---

### Risks

**RISK-001: Breaking Kubernetes Probes (Severity: HIGH)**
- **Probability**: Low (simple code, well-tested pattern)
- **Impact**: High (pods crash, service unavailable)
- **Mitigation**: 
  - Code review mandatory
  - Unit test verifies health endpoint responds
  - Deploy to single pod first (canary)
  - Monitor pod restart count
- **Rollback**: Revert commits, redeploy previous version (5 min)

**RISK-002: Filtering Too Much (Severity: MEDIUM)**
- **Probability**: Very Low (explicit path checks)
- **Impact**: Medium (no metrics collected)
- **Mitigation**:
  - Integration test verifies business API metrics still collected
  - Monitor Grafana dashboard immediately after deployment
- **Rollback**: Quick (5 min)

**RISK-003: SLO Baseline Shift (Severity: LOW)**
- **Probability**: High (expected behavior)
- **Impact**: Low (documentation issue, not technical)
- **Mitigation**:
  - Document expected error rate increase (real data vs inflated denominator)
  - Communicate to stakeholders before deployment
  - Recalibrate SLO targets after 1 week of data
- **Rollback**: Not needed (this is correct behavior)

**RISK-004: Missing Health Checks in Edge Cases (Severity: LOW)**
- **Probability**: Low (Kubernetes probes cover this)
- **Impact**: Low (manual curl available)
- **Mitigation**:
  - Document manual health check process
  - Ensure developers know: k6 ≠ monitoring tool
- **Rollback**: Not needed

---

### Assumptions

**A-001: Kubernetes Probes Sufficient**
- **Assumption**: Kubernetes liveness/readiness probes provide adequate health monitoring
- **Validation**: Check probe configuration in Helm chart (already correct)
- **Impact if wrong**: Add separate monitoring solution (not k6)

**A-002: Prometheus Scraping Independent**
- **Assumption**: Prometheus ServiceMonitor scrapes `/metrics` independently of k6
- **Validation**: Check ServiceMonitor YAML (already configured)
- **Impact if wrong**: Already working correctly, no change needed

**A-003: Health Checks Don't Test Business Logic**
- **Assumption**: `/health` endpoint is simple status check, not comprehensive test
- **Validation**: Review health endpoint implementation (`c.JSON(200, gin.H{"status": "ok"})`)
- **Impact if wrong**: If health check were complex, would need separate monitoring strategy

**A-004: Dashboard Queries Generic**
- **Assumption**: Grafana dashboard queries don't hardcode `/health` or `/metrics` filters
- **Validation**: Review dashboard JSON, check for `path=~"/health"` filters
- **Impact if wrong**: Update dashboard queries to exclude filtered paths explicitly

---

## Testing Strategy

### Unit Testing

**Test 1: Prometheus Middleware Filters /health**
```go
// File: services/pkg/middleware/prometheus_test.go

func TestPrometheusMiddleware_FiltersHealthEndpoint(t *testing.T) {
    gin.SetMode(gin.TestMode)
    router := gin.New()
    router.Use(PrometheusMiddleware())
    router.GET("/health", func(c *gin.Context) {
        c.JSON(200, gin.H{"status": "ok"})
    })
    
    // Make request
    w := httptest.NewRecorder()
    req, _ := http.NewRequest("GET", "/health", nil)
    router.ServeHTTP(w, req)
    
    // Verify response still works
    assert.Equal(t, 200, w.Code)
    
    // Verify metrics NOT collected
    metrics := collectMetrics()
    assert.NotContains(t, metrics, `path="/health"`)
}
```

**Test 2: Prometheus Middleware Collects Business API Metrics**
```go
func TestPrometheusMiddleware_CollectsBusinessMetrics(t *testing.T) {
    gin.SetMode(gin.TestMode)
    router := gin.New()
    router.Use(PrometheusMiddleware())
    router.GET("/api/v1/users", func(c *gin.Context) {
        c.JSON(200, gin.H{"users": []string{}})
    })
    
    // Make request
    w := httptest.NewRecorder()
    req, _ := http.NewRequest("GET", "/api/v1/users", nil)
    router.ServeHTTP(w, req)
    
    // Verify metrics WERE collected
    metrics := collectMetrics()
    assert.Contains(t, metrics, `path="/api/v1/users"`)
}
```

**Test 3: Tracing Middleware Filters Infrastructure Endpoints**
```go
func TestTracingMiddleware_FiltersHealthAndMetrics(t *testing.T) {
    // Similar pattern as Prometheus test
    // Verify no spans created for /health or /metrics
}
```

---

### Integration Testing

**Test 1: End-to-End Traffic Flow**
```bash
#!/bin/bash
# File: tests/integration/test_filtered_traffic.sh

# 1. Deploy services with middleware changes
./scripts/05-deploy-microservices.sh --local

# 2. Wait for rollout
kubectl wait --for=condition=available --timeout=300s \
  deployment/auth -n auth

# 3. Generate business traffic
curl -X POST http://auth:8080/api/v1/auth/login \
  -d '{"username":"test","password":"test"}'

# 4. Generate health check (should be filtered)
curl http://auth:8080/health

# 5. Query Prometheus metrics
BUSINESS_METRICS=$(curl -s http://prometheus:9090/api/v1/query \
  --data-urlencode 'query=requests_total{path="/api/v1/auth/login"}' \
  | jq '.data.result | length')

HEALTH_METRICS=$(curl -s http://prometheus:9090/api/v1/query \
  --data-urlencode 'query=requests_total{path="/health"}' \
  | jq '.data.result | length')

# 6. Assert: Business metrics collected, health metrics filtered
[[ $BUSINESS_METRICS -gt 0 ]] || exit 1
[[ $HEALTH_METRICS -eq 0 ]] || exit 1

echo "✅ Integration test PASSED"
```

**Test 2: Kubernetes Probes Still Work**
```bash
#!/bin/bash
# Verify probes don't break after middleware changes

# 1. Check pod status (should be Running)
STATUS=$(kubectl get pod -n auth -l app=auth -o jsonpath='{.items[0].status.phase}')
[[ "$STATUS" == "Running" ]] || exit 1

# 2. Check restart count (should be 0)
RESTARTS=$(kubectl get pod -n auth -l app=auth -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
[[ $RESTARTS -eq 0 ]] || exit 1

# 3. Check probe status
kubectl describe pod -n auth -l app=auth | grep -A 5 "Liveness\|Readiness"

echo "✅ Kubernetes probes PASSED"
```

**Test 3: Grafana Dashboard Accuracy**
```bash
#!/bin/bash
# Verify dashboard shows 100% business traffic

# 1. Query top 10 endpoints
TOP_ENDPOINTS=$(curl -s -G http://prometheus:9090/api/v1/query \
  --data-urlencode 'query=topk(10, sum by (path) (rate(requests_total[5m])))' \
  | jq -r '.data.result[].metric.path')

# 2. Assert: No /health or /metrics in top 10
echo "$TOP_ENDPOINTS" | grep -E "/health|/metrics" && exit 1

# 3. Assert: All endpoints are business APIs
echo "$TOP_ENDPOINTS" | grep -E "/api/v[12]/" || exit 1

echo "✅ Dashboard accuracy PASSED"
```

---

### Load Testing

**Test 1: K6 Script Has No Health Checks**
```bash
# Verify k6 script doesn't call /health
grep -r "\/health" k6/load-test-multiple-scenarios.js
# Expected: No matches (or only in comments)

# Verify k6 logs don't show health checks
kubectl logs -n k6 -l app=k6-scenarios --tail=1000 | grep "/health"
# Expected: No matches
```

**Test 2: K6 Load Test Runs Successfully**
```bash
# Deploy k6
./scripts/06-deploy-k6.sh

# Check k6 pod status
kubectl get pods -n k6 -l app=k6-scenarios

# Check k6 logs for errors
kubectl logs -n k6 -l app=k6-scenarios --tail=100 | grep -i error
# Expected: No errors

# Verify scenarios are executing
kubectl logs -n k6 -l app=k6-scenarios --tail=100 | grep "Starting.*journey"
# Expected: See journey start messages
```

---

### Smoke Testing

**Test 1: All APIs Still Work**
```bash
#!/bin/bash
# Smoke test all 9 services × 2 versions = 18 endpoints

SERVICES="auth user product cart order review notification shipping"
VERSIONS="v1 v2"

for service in $SERVICES; do
  for version in $VERSIONS; do
    # Port-forward
    kubectl port-forward -n $service svc/$service 8080:8080 &
    PID=$!
    sleep 2
    
    # Test endpoint
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
      http://localhost:8080/api/$version/${service}s)
    
    # Assert 200 or 404 (both OK, depends on endpoint)
    if [[ $RESPONSE == "200" ]] || [[ $RESPONSE == "404" ]]; then
      echo "✅ $service/$version: PASS ($RESPONSE)"
    else
      echo "❌ $service/$version: FAIL ($RESPONSE)"
      exit 1
    fi
    
    # Cleanup
    kill $PID
    sleep 1
  done
done

echo "✅ Smoke test PASSED"
```

---

## Acceptance Criteria

### Primary Criteria (Must Have)

**AC-001: Zero Health Checks in K6 Logs**
- **Verification**: `kubectl logs -n k6 -l app=k6-scenarios | grep "/health"`
- **Expected**: No matches
- **Owner**: QA Engineer
- **Status**: ❌ Not Met (will be met after implementation)

**AC-002: 100% Business Traffic in Dashboard**
- **Verification**: Grafana "Total Requests by Endpoint" panel
- **Expected**: Top 10 endpoints all start with `/api/v1/` or `/api/v2/`
- **Owner**: DevOps Engineer
- **Status**: ❌ Not Met

**AC-003: Prometheus Metrics Filtered**
- **Verification**: `curl "http://prometheus:9090/api/v1/query?query=requests_total{path='/health'}"`
- **Expected**: `"result": []` (no data)
- **Owner**: Monitoring Team
- **Status**: ❌ Not Met

**AC-004: All APIs Still Work (Zero Breaking Changes)**
- **Verification**: Smoke test script (18 endpoints)
- **Expected**: All return 200 or 404 (appropriate status)
- **Owner**: Backend Developers
- **Status**: ✅ Will remain met (no API changes)

**AC-005: Kubernetes Probes Functional**
- **Verification**: Pod restart count = 0 after deployment
- **Expected**: All pods in Running state, no CrashLoopBackOff
- **Owner**: Platform Team
- **Status**: ✅ Will remain met (probes unchanged)

---

### Secondary Criteria (Should Have)

**AC-006: Tempo Trace Volume Reduced**
- **Verification**: Tempo metrics `tempo_distributor_spans_received_total`
- **Expected**: 79% reduction in span ingestion rate
- **Owner**: Monitoring Team
- **Status**: ❌ Not Met (optional, depends on tracing filter)

**AC-007: Build & Deploy Success**
- **Verification**: All 9 microservices + k6 build and deploy successfully
- **Expected**: Zero build errors, all pods Running
- **Owner**: CI/CD Team
- **Status**: ❌ Not Met

**AC-008: Documentation Updated**
- **Verification**: Check `docs/k6/K6_LOAD_TESTING.md` and `CHANGELOG.md`
- **Expected**: No references to health checks in k6, CHANGELOG has v0.6.14 entry
- **Owner**: Technical Writer
- **Status**: ❌ Not Met

---

### Success Criteria (Metrics)

**SC-001: Business Traffic Percentage = 100%**
- **Current**: 21%
- **Target**: 100%
- **Measurement**: Grafana dashboard
- **Status**: ❌ Not Met

**SC-002: P95 Latency Reflects Real Performance**
- **Current**: Artificially low due to fast health checks
- **Target**: Realistic value (likely 10-30% higher)
- **Measurement**: Prometheus query `histogram_quantile(0.95, rate(request_duration_seconds_bucket[5m]))`
- **Status**: ❌ Not Met

**SC-003: K6 Total Requests Reduced 75%**
- **Current**: ~3-4 million requests
- **Target**: ~800K-1M requests (only business)
- **Measurement**: K6 summary output
- **Status**: ❌ Not Met

---

## Timeline & Milestones

### Phase 1: Code Changes (Day 1, 10 min)
- ✅ Remove 5 health check blocks from k6 script
- ✅ Add filtering logic to Prometheus middleware
- ✅ Add filtering logic to Tracing middleware (optional)
- ✅ Code review & approval

### Phase 2: Testing (Day 1, 30 min)
- ✅ Unit tests for middleware filtering
- ✅ Integration test for end-to-end flow
- ✅ Verify Kubernetes probes still work

### Phase 3: Build & Deploy (Day 1, 30 min)
- ✅ Build k6 Docker image
- ✅ Build all 9 microservice images
- ✅ Deploy to Kubernetes (rolling update)
- ✅ Monitor deployment rollout

### Phase 4: Verification (Day 1, 15 min)
- ✅ Check k6 logs (no health checks)
- ✅ Check Grafana dashboard (100% business traffic)
- ✅ Check Prometheus metrics (filtered correctly)
- ✅ Smoke test all APIs (zero breaking changes)

### Phase 5: Documentation (Day 1, 15 min)
- ✅ Update `K6_LOAD_TESTING.md`
- ✅ Update `CHANGELOG.md` (v0.6.14)
- ✅ Add note in `METRICS.md` about filtering

**Total Time**: ~1.5 hours (same day)

---

## Rollback Plan

### Rollback Trigger Conditions

**Trigger 1: Kubernetes Probes Fail**
- **Symptom**: Pod restart count > 0
- **Action**: Immediate rollback (within 5 min)

**Trigger 2: All Metrics Disappear**
- **Symptom**: Grafana dashboard shows 0% traffic
- **Action**: Immediate rollback (within 5 min)

**Trigger 3: API Errors Spike**
- **Symptom**: Error rate > 10% after deployment
- **Action**: Investigate first, rollback if unrelated to change

---

### Rollback Procedure

**Step 1: Revert Git Commits** (1 min)
```bash
cd /Users/duyne/work/Github/monitoring
git revert HEAD~3  # Revert last 3 commits (k6, prometheus middleware, tracing middleware)
git push
```

**Step 2: Rebuild Images** (15 min)
```bash
# Rebuild k6 (old version)
cd k6
docker build --build-arg SCRIPT_FILE=load-test-multiple-scenarios.js \
  -t ghcr.io/duynhne/k6:scenarios .
kind load docker-image ghcr.io/duynhne/k6:scenarios --name monitoring-local

# Rebuild microservices (old middleware)
cd ..
./scripts/04-build-microservices.sh
```

**Step 3: Redeploy** (10 min)
```bash
# Redeploy microservices
./scripts/05-deploy-microservices.sh --local

# Redeploy k6
kubectl delete deployment k6-scenarios -n k6
helm upgrade --install k6-scenarios charts/ \
  -f charts/values/k6-scenarios.yaml \
  -n k6 --create-namespace
```

**Step 4: Verify Rollback** (5 min)
```bash
# Check pod status
kubectl get pods -A | grep -E "(auth|user|product|k6)"

# Check metrics are collected again
curl -s "http://prometheus:9090/api/v1/query?query=requests_total" \
  | jq '.data.result | length'

# Expected: > 0 (metrics flowing again)
```

**Total Rollback Time**: ~30 minutes

---

## Appendix

### Related Documents

- **Research**: `specs/active/k6-traffic-optimization/research.md`
- **K6 Load Testing Guide**: `docs/k6/K6_LOAD_TESTING.md`
- **Metrics Guide**: `docs/monitoring/METRICS.md`
- **Best Practices Research**: `specs/active/microservices-best-practices-assessment/research.md`

---

### Glossary

- **Business Traffic**: HTTP requests to business API endpoints (`/api/v1/*`, `/api/v2/*`)
- **Infrastructure Endpoints**: `/health` (Kubernetes probes), `/metrics` (Prometheus scraping)
- **Health Check**: HTTP GET request to `/health` endpoint returning `{"status":"ok"}`
- **Filtering**: Early return in middleware to skip metrics/tracing collection
- **APM**: Application Performance Monitoring (Tempo, Loki, Pyroscope)
- **SLO**: Service Level Objective (error budget tracking)

---

**Specification completed**: December 10, 2025  
**Status**: Ready for `/plan` phase  
**Approval**: Pending review

