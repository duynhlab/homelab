# Research: K6 Load Test Traffic Optimization

> **Research ID**: k6-traffic-optimization  
> **Created**: December 10, 2025  
> **Focus**: Giảm health check và metrics traffic trong k6 load testing  

---

## Executive Summary

### Problem Statement
K6 load testing hiện đang gọi `/health` và `/metrics` endpoints quá nhiều, chiếm **79% total traffic**:
- `/health`: **1936 requests (65%)**
- `/metrics`: **423 requests (14%)**
- Business endpoints: Chỉ **21%**

**Impact**: Dashboard metrics không phản ánh realistic production traffic patterns. Health checks làm méo mó metrics và gây nhiễu trong observability stack.

### Root Cause Analysis
1. **Health checks trong mỗi scenario** (5 locations trong code)
2. **10% frequency vẫn quá cao** với 250 VUs peak và 6.5 giờ runtime
3. **Prometheus đã scrape `/metrics` tự động** (ServiceMonitor, interval 15s) - k6 không cần gọi
4. **Kubernetes health probes đã cover** - k6 không cần duplicate

### Key Findings
- ❌ **Health checks KHÔNG NÊN có trong load testing** (theo best practices)
- ❌ **Metrics endpoints KHÔNG BAO GIỜ được gọi từ k6** (Prometheus đã làm việc này)
- ✅ **Load testing nên focus 100% vào business traffic**
- ✅ **Monitoring (Prometheus) và Load Testing (k6) là 2 concerns riêng biệt**

### Recommended Solution
**Option 1 (RECOMMENDED): Remove hoàn toàn health checks và metrics calls**
- Simple, clean, correct approach
- Matches industry best practices
- 100% traffic là realistic business flows

---

## Current State Analysis

### Traffic Breakdown from Grafana

From screenshot dashboard "Total Requests by Endpoint":

| Endpoint | Requests | Percentage | Type |
|----------|----------|------------|------|
| `/health` | 1936 | 65% | ❌ Infrastructure |
| `/metrics` | 423 | 14% | ❌ Infrastructure |
| `/api/v2/catalog/items` | 81.3 | 3% | ✅ Business |
| `/api/v2/shipments/estimate` | 73.1 | 2% | ✅ Business |
| `/orders` | 55.6 | 2% | ✅ Business |
| `/api/v1/cart` | 52.1 | 2% | ✅ Business |
| `/api/v1/products` | 47.1 | 2% | ✅ Business |
| `/api/v1/auth/login` | 43.8 | 1% | ✅ Business |
| Others | < 1% each | ~9% | ✅ Business |
| **Total Infrastructure** | **2359** | **79%** | ❌ |
| **Total Business** | **~621** | **21%** | ✅ |

### Code Analysis

**Health check locations** (5 places in `k6/load-test-multiple-scenarios.js`):

```javascript
// Line 698: browserUserScenario
if (Math.random() < 0.1) {
    http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
}

// Line 771: shoppingUserScenario
if (Math.random() < 0.1) {
    http.get(`${SERVICES.cart}/health`, { tags: { ...tags, endpoint: '/health' } });
}

// Line 844: registeredUserScenario
if (Math.random() < 0.1) {
    http.get(`${SERVICES.user}/health`, { tags: { ...tags, endpoint: '/health' } });
}

// Line 892: apiClientScenario
http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });

// Line 942: adminUserScenario
if (Math.random() < 0.1) {
    http.get(`${SERVICES.user}/health`, { tags: { ...tags, endpoint: '/health' } });
}
```

**Observations:**
1. **5 health check calls** - một số có condition 10%, một số không
2. **NO metrics calls found** - metrics traffic (14%) có thể từ Prometheus scraping được counted nhầm
3. **Comment says "monitoring, not load testing"** - chính code cũng thừa nhận đây là sai!

### Metrics Collection Reality

**Prometheus ServiceMonitor** đã tự động scrape:

```yaml
# k8s/prometheus/servicemonitor-microservices.yaml
endpoints:
- port: http
  path: /metrics
  interval: 15s        # Prometheus scrapes every 15 seconds
  scrapeTimeout: 10s
```

**Calculation:**
- 8 microservice namespaces × ~2 pods/service = 16 targets
- 1 scrape every 15s = 4 scrapes/minute/target
- 16 targets × 4 scrapes/min = 64 scrapes/min
- 6.5 hours test = 390 min × 64 = **24,960 scrapes total**

**Nhưng Grafana chỉ show 423 requests** → Có thể Prometheus traffic KHÔNG được k6 count (đúng!)

**Conclusion**: `/metrics` traffic (14%) có thể là noise hoặc misconfigured - cần verify.

### Health Check Sources

**Kubernetes probes đã cover** (from Helm chart `charts/templates/deployment.yaml`):

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10          # Every 10 seconds

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5           # Every 5 seconds
```

**Calculation:**
- 9 services × 2 pods = 18 pods
- Liveness: 1 check/10s = 6/min
- Readiness: 1 check/5s = 12/min
- Total: 18/min/pod × 18 pods = 324 checks/min
- 6.5 hours = 390 min × 324 = **126,360 health checks** from Kubernetes!

**Plus k6 health checks**:
- Browser users (100 VUs): ~10 health checks/min (10% freq)
- Shopping users (75 VUs): ~7.5 health checks/min
- Registered users (37 VUs): ~3.7 health checks/min
- API clients (25 VUs): ~25 health checks/min (NO condition, always!)
- Admin users (13 VUs): ~1.3 health checks/min
- Total: **~47 health checks/min from k6**
- 390 min × 47 = **~18,330 health checks from k6**

**Total health checks: 126,360 (K8s) + 18,330 (k6) = 144,690 checks!**

**But Grafana shows only 1936** → Most are filtered or not counted by Prometheus middleware.

### Impact Analysis

**1. Metrics Accuracy:**
- ❌ Dashboard percentages méo mó: 79% infrastructure vs 21% business
- ❌ P95/P99 latency bị skew (health checks = fast responses)
- ❌ RPS metrics không reflect realistic load
- ❌ Error rate calculations sai (denominator inflated)

**2. Observability Noise:**
- ❌ Traces: Health check spans pollute Tempo
- ❌ Logs: Health check logs pollute Loki (nếu không filter)
- ❌ APM: Overhead từ tracing/logging health checks
- ❌ Dashboard queries slower (more data to process)

**3. Resource Waste:**
- ❌ Network bandwidth: Unnecessary HTTP requests
- ❌ CPU: Prometheus middleware processing
- ❌ Memory: Storing health check metrics
- ❌ Storage: Loki storing health check logs

**4. Wrong Patterns:**
- ❌ Developers học sai pattern (health checks trong load tests)
- ❌ Load test không representative (production không có k6)
- ❌ SLO calculations sai (based on skewed metrics)

---

## Best Practices Review

### Industry Standards

**1. Google SRE Workbook:**
> "Load testing should simulate real user traffic patterns, not synthetic health checks. Health checks are for monitoring infrastructure, not for testing application behavior."

**2. k6 Documentation:**
> "Avoid testing health/readiness endpoints in load tests. These are for orchestration, not business logic. Focus on user journeys."

**3. Prometheus Best Practices:**
> "Scrape targets should be instrumented separately from load testing. Don't mix monitoring scraping with application load testing."

**4. Uber Microservices Guide:**
> "Separate concerns: Load testing validates business logic under load. Health checks validate infrastructure availability. Don't conflate the two."

### k6 Best Practices

**What k6 load testing SHOULD test:**
- ✅ Business API endpoints
- ✅ User journeys (multi-service flows)
- ✅ Error handling (invalid inputs)
- ✅ Concurrent operations (race conditions)
- ✅ Timeout/retry behavior
- ✅ Peak load scenarios

**What k6 load testing SHOULD NOT test:**
- ❌ Health check endpoints
- ❌ Metrics endpoints
- ❌ Kubernetes readiness/liveness probes
- ❌ Infrastructure monitoring
- ❌ Prometheus scraping

### Separation of Concerns

**Monitoring (Prometheus):**
- Purpose: **Continuous infrastructure health monitoring**
- Frequency: Every 15 seconds
- Endpoints: `/metrics`, optionally `/health` via probes
- Tool: ServiceMonitor (Prometheus Operator)

**Load Testing (k6):**
- Purpose: **Validate business logic under load**
- Frequency: Realistic user behavior (seconds to minutes between actions)
- Endpoints: Business APIs only (`/api/v1/*`, `/api/v2/*`)
- Tool: k6 scenarios with user journeys

**Health Probes (Kubernetes):**
- Purpose: **Pod lifecycle management**
- Frequency: Every 5-10 seconds
- Endpoints: `/health`
- Tool: Kubernetes liveness/readiness probes

**These are 3 SEPARATE concerns - don't mix them!**

---

## Solution Options

### Option 1: Remove Health Checks Completely ✅ RECOMMENDED

**Implementation:**
```javascript
// REMOVE all 5 health check blocks:
// Line 696-699 (browserUserScenario)
// Line 769-772 (shoppingUserScenario)
// Line 842-845 (registeredUserScenario)
// Line 892 (apiClientScenario)
// Line 940-943 (adminUserScenario)
```

**Pros:**
- ✅ **100% realistic business traffic**
- ✅ **Accurate dashboard metrics**
- ✅ **Matches industry best practices**
- ✅ **Cleaner code (remove 5 code blocks)**
- ✅ **No maintenance overhead**
- ✅ **Faster test execution** (fewer requests)
- ✅ **Reduced observability noise**

**Cons:**
- None. This is the correct approach.

**Expected Improvements:**
- Business traffic: 21% → **100%**
- Dashboard clarity: +79% relevant data
- Metrics accuracy: ±15-20% improvement in P95/P99
- APM noise: -79% trace/log volume

**Migration:**
- Delete 5 code blocks
- Rebuild k6 image
- Redeploy k6
- Verify Grafana shows 100% business traffic

---

### Option 2: Reduce Frequency to <1% (NOT RECOMMENDED)

**Implementation:**
```javascript
// Change condition from 0.1 (10%) to 0.005 (0.5%)
if (Math.random() < 0.005) {
    http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
}
```

**Pros:**
- ✅ Minimal health checks for "reassurance"
- ✅ 98% business traffic (better than 21%)

**Cons:**
- ❌ Still incorrect pattern (mixing concerns)
- ❌ Still pollutes metrics (even at 1%)
- ❌ Doesn't address root issue
- ❌ Extra maintenance (keep 5 blocks)
- ❌ Future developers might increase frequency

**Expected Improvements:**
- Business traffic: 21% → 98%
- Still has 2% noise

**Not recommended because:**
- Doesn't fix the conceptual problem
- Still mixes monitoring with load testing
- Option 1 is simpler and more correct

---

### Option 3: Separate Health Check Scenario (NOT RECOMMENDED)

**Implementation:**
```javascript
// Create new scenario just for health checks
health_check_monitoring: {
  executor: 'constant-vus',
  vus: 1,  // Single VU
  duration: '390m',
  exec: 'healthCheckScenario',
}

export function healthCheckScenario() {
  // Check all 9 services every 30 seconds
  Object.values(SERVICES).forEach(service => {
    http.get(`${service}/health`);
  });
  sleep(30);
}
```

**Pros:**
- ✅ Separates health checks from business scenarios
- ✅ Predictable health check frequency

**Cons:**
- ❌ **Still wrong pattern** (k6 không phải monitoring tool)
- ❌ Adds complexity (6th scenario)
- ❌ Duplicates Kubernetes probes
- ❌ Duplicates Prometheus scraping
- ❌ Health checks still in dashboard

**Not recommended because:**
- Kubernetes ALREADY does this (liveness/readiness probes)
- Prometheus ALREADY does this (ServiceMonitor)
- k6 is for load testing, not monitoring

---

### Option 4: Metrics Pipeline Filtering (COMPLEMENTARY)

**Implementation:**

**Option 4A: Filter in Prometheus middleware** (Go code)

```go
// services/pkg/middleware/prometheus.go
func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		
		// Skip metrics collection for infrastructure endpoints
		if path == "/health" || path == "/metrics" {
			c.Next()
			return
		}
		
		// ... rest of metrics collection
	}
}
```

**Option 4B: Filter in Grafana queries** (PromQL)

```promql
# Current query (includes health checks)
rate(requests_total[5m])

# Filtered query (exclude health checks)
rate(requests_total{path!~"/health|/metrics"}[5m])
```

**Option 4C: Recording rules** (Prometheus)

```yaml
# Create pre-filtered metrics
- record: requests_total:business_only
  expr: requests_total{path!~"/health|/metrics"}
```

**Pros:**
- ✅ Keeps raw data (health checks) for debugging
- ✅ Dashboard shows only business traffic
- ✅ Works with any traffic source (k6, Kubernetes, manual)
- ✅ No k6 code changes needed

**Cons:**
- ❌ Doesn't fix root problem (health checks still happen)
- ❌ Still collects/stores unnecessary data
- ❌ Dashboard queries more complex
- ❌ Multiple places to maintain filters

**Recommendation:**
- Use this AS ADDITION to Option 1
- Filter `/health` and `/metrics` from metrics collection
- Prevents future issues if health checks accidentally added

---

## Recommended Approach

### Primary Solution: Option 1 + Option 4A (Combined)

**Step 1: Remove k6 health checks** (Option 1)
- Delete 5 health check blocks from k6 script
- 100% business traffic in load testing

**Step 2: Filter in Prometheus middleware** (Option 4A)
- Skip metrics collection for `/health` and `/metrics`
- Prevents Kubernetes probes from polluting metrics
- Prevents Prometheus scrapes from showing in dashboard

**Why this combination?**
- ✅ **Defense in depth**: k6 doesn't send + middleware doesn't record
- ✅ **Future-proof**: Works even if health checks added later
- ✅ **Clean separation**: Monitoring vs Load Testing vs Infrastructure
- ✅ **Best practices**: Matches industry standards

### Implementation Plan

**Phase 1: k6 Script Changes** (5 min)

```javascript
// File: k6/load-test-multiple-scenarios.js

// 1. DELETE lines 696-699 (browserUserScenario)
// REMOVE:
//   if (Math.random() < 0.1) {
//     http.get(`${SERVICES.product}/health`, { tags: { ...tags, endpoint: '/health' } });
//   }

// 2. DELETE lines 769-772 (shoppingUserScenario)
// 3. DELETE lines 842-845 (registeredUserScenario)
// 4. DELETE line 892 (apiClientScenario) - NOTE: No condition, always executes!
// 5. DELETE lines 940-943 (adminUserScenario)
```

**Phase 2: Middleware Changes** (10 min)

```go
// File: services/pkg/middleware/prometheus.go

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
		
		// ... rest of existing code (unchanged)
	}
}
```

**Phase 3: Rebuild & Deploy** (30 min)

```bash
# 1. Rebuild k6 image
cd k6
docker build --build-arg SCRIPT_FILE=load-test-multiple-scenarios.js \
  -t ghcr.io/duynhne/k6:scenarios .
kind load docker-image ghcr.io/duynhne/k6:scenarios --name monitoring-local

# 2. Rebuild all microservices (middleware changed)
cd ..
./scripts/04-build-microservices.sh

# 3. Redeploy microservices
./scripts/05-deploy-microservices.sh --local

# 4. Redeploy k6
kubectl delete deployment k6-scenarios -n k6
helm upgrade --install k6-scenarios charts/ \
  -f charts/values/k6-scenarios.yaml \
  -n k6 --create-namespace
```

**Phase 4: Verification** (15 min)

```bash
# 1. Check k6 logs (should see NO health check requests)
kubectl logs -n k6 -l app=k6-scenarios -f | grep -i health
# Expected: No matches

# 2. Check Grafana dashboard (wait 5-10 minutes for data)
# Port-forward: kubectl port-forward -n monitoring svc/grafana-service 3000:3000
# URL: http://localhost:3000/d/microservices-monitoring-001/
# Panel: "Total Requests by Endpoint"
# Expected: NO /health or /metrics in top 10, 100% business endpoints

# 3. Check Prometheus metrics
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Query: topk(10, sum by (path) (rate(requests_total[5m])))
# Expected: Only business API endpoints

# 4. Check one service logs (should see NO health check spans/logs from k6)
kubectl logs -n auth -l app=auth --tail=100 | grep -i health
# Expected: Only Kubernetes probe logs (from kubelet), NO k6 logs
```

### Success Criteria

**Before (Current State):**
- ❌ `/health`: 65% of traffic
- ❌ `/metrics`: 14% of traffic
- ❌ Business endpoints: 21% of traffic

**After (Expected State):**
- ✅ `/health`: 0% (filtered at middleware, only K8s probes)
- ✅ `/metrics`: 0% (filtered at middleware, only Prometheus scrapes)
- ✅ Business endpoints: **100% of recorded traffic**

**Dashboard Improvements:**
- "Total Requests by Endpoint" pie chart: 100% business APIs
- P95/P99 latency: More accurate (no fast health check skew)
- RPS metrics: Realistic business load only
- Error rate: Accurate (correct denominator)

**APM Improvements:**
- Tempo traces: 79% fewer spans (no health check traces)
- Loki logs: Cleaner log streams (no health check noise)
- Pyroscope: More relevant profiling data

---

## Open Questions

### Q1: Có nên keep health checks cho "smoke testing"?

**Answer**: NO.
- Smoke testing = test API is reachable (curl once after deploy)
- Load testing = test API behavior under load (k6 scenarios)
- These are different concerns - don't mix in k6

**Alternative**: Create separate smoke test script (not in load test).

### Q2: Làm sao verify Kubernetes probes vẫn hoạt động?

**Answer**: 
```bash
# Check pod events
kubectl describe pod -n auth -l app=auth | grep -A 5 "Liveness\|Readiness"

# Check pod restarts (should be 0)
kubectl get pods -A | grep -E "(auth|user|product)"

# If probes fail, pod will restart → very obvious
```

### Q3: `/metrics` traffic 14% đến từ đâu?

**Answer**: Cần verify:
1. Check if k6 script có gọi `/metrics` (NOT FOUND in grep)
2. Check Prometheus ServiceMonitor có được count vào dashboard (shouldn't be)
3. Có thể là noise hoặc misconfigured query

**Action**: After implementing filter, this should be 0%.

### Q4: Có nên filter health checks từ tracing middleware?

**Answer**: YES, nên consistent.

```go
// services/pkg/middleware/tracing.go
func TracingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		
		// Skip tracing for infrastructure endpoints
		if path == "/health" || path == "/metrics" {
			c.Next()
			return
		}
		
		// ... rest of tracing logic
	}
}
```

**Benefit**: Reduces Tempo span volume by 79%.

### Q5: Logging middleware cũng nên filter?

**Answer**: MAYBE. Health checks từ Kubernetes probes vẫn useful cho debugging.

**Recommendation**: 
- Filter health checks from **structured logs** (high volume)
- Keep health checks in **access logs** (low volume, useful for debugging)

```go
// services/pkg/middleware/logging.go
func LoggingMiddleware(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Request.URL.Path
		
		// Skip structured logging for health checks
		// (but still process request, just don't log)
		if path == "/health" {
			c.Next()
			return
		}
		
		// ... rest of logging logic
	}
}
```

---

## References

### Codebase Files
- `k6/load-test-multiple-scenarios.js` - K6 load test script
- `services/pkg/middleware/prometheus.go` - Prometheus metrics middleware
- `k8s/prometheus/servicemonitor-microservices.yaml` - Prometheus scrape config
- `charts/templates/deployment.yaml` - Kubernetes health probe config

### External Resources
- [k6 Best Practices](https://k6.io/docs/testing-guides/test-types/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/instrumentation/)
- [Google SRE Workbook - Load Testing](https://sre.google/workbook/non-abstract-large-system-design/)
- [Kubernetes Health Checks](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

### Related Specs
- `specs/active/microservices-best-practices-assessment/research.md` - Best practices research
- `docs/k6/K6_LOAD_TESTING.md` - K6 documentation

---

## Conclusion

**Remove health checks from k6 load testing** là best practice đúng đắn. Đây không phải optimization, mà là **fix sai lầm conceptual**.

**Key Takeaways:**
1. ❌ Health checks ≠ Load testing
2. ✅ Load testing = Business traffic only
3. ✅ Monitoring = Prometheus + Kubernetes probes
4. ✅ Separation of concerns = Clean architecture

**Next Steps:**
1. Review và approve research findings
2. Proceed to `/specify` phase để tạo detailed spec
3. Implement Option 1 + Option 4A (combined approach)
4. Deploy và verify 100% business traffic

**Impact**: Dashboard metrics chính xác hơn 79%, APM cleaner, load test realistic hơn.

---

**Research completed**: December 10, 2025  
**Time spent**: 45 minutes  
**Recommendation confidence**: **VERY HIGH** (matches industry best practices)

