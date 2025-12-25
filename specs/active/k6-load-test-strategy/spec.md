# Specification: Production-Ready k6 Load Testing Strategy

**Task ID:** k6-load-test-strategy
**Created:** 2025-12-25
**Status:** Ready for Planning
**Version:** 1.0

---

## 1. Problem Statement

### The Problem

Current k6 load testing implementation has limitations that prevent accurate production readiness validation:

1. **Fixed Traffic Patterns**: Uses `ramping-vus` executor with predictable linear stages that don't capture real-world traffic spikes and bursts
2. **Incomplete User Journeys**: Current journeys skip account registration, starting directly with login, missing the full user lifecycle
3. **Limited Stack Coverage**: Tests API endpoints but doesn't validate complete flow through Web Layer → Logic Layer → Database Layer
4. **Unrealistic Traffic Simulation**: Virtual user-based approach doesn't match actual request arrival patterns in production
5. **No Burst Testing**: Cannot simulate sudden traffic spikes (flash sales, viral content, marketing campaigns)

### Current Situation

**Current Implementation:**
- Executor: `ramping-vus` with fixed 8-stage pattern over 6.5 hours
- Peak: 250 VUs (100 browser + 75 shopping + 37 registered + 25 API + 13 admin)
- Journeys: Start with login (missing registration step)
- Pattern: Linear ramp-up/down (0% → 60% → 100% → 70% → 90% → 100% → 50% → 20% → 0%)

**Pain Points:**
- Cannot validate system behavior during sudden traffic spikes
- Doesn't test complete user lifecycle (register → use → interact)
- Limited database performance validation (only through API calls, not explicit DB read/write testing)
- Fixed patterns don't match production traffic variability
- Difficult to measure actual system capacity (requests/second)

### Desired Outcome

A production-ready k6 load testing strategy that:

1. **Simulates Realistic Production Traffic**: Uses arrival-rate executors to match actual request patterns
2. **Tests Full User Lifecycles**: Complete journeys from registration → login → browse → purchase
3. **Validates Full Stack**: Tests Web Layer → Logic Layer → Database Layer end-to-end
4. **Simulates Traffic Spikes**: Can test sudden bursts (flash sales, viral content, marketing campaigns)
5. **Provides Accurate Capacity Planning**: Direct RPS measurement for SRE/DevOps capacity planning
6. **Production-Grade Validation**: Ensures system can handle production-like load patterns

---

## 2. User Personas

### Primary User: DevOps/SRE Engineer

- **Who:** Engineers responsible for system reliability, capacity planning, and performance validation
- **Goals:**
  - Validate system can handle production traffic patterns
  - Identify bottlenecks before production deployment
  - Measure actual system capacity (requests/second)
  - Test system behavior during traffic spikes
  - Ensure database performance under realistic load
- **Pain points:**
  - Current load tests don't match production traffic patterns
  - Cannot simulate sudden traffic spikes
  - Limited visibility into database performance during load
  - Fixed patterns don't validate real-world scenarios
- **Tech comfort:** High - Expert in load testing, Kubernetes, monitoring

### Secondary User: Backend Developer

- **Who:** Developers building microservices who need to validate their services under load
- **Goals:**
  - Ensure services handle realistic user journeys
  - Validate database queries perform well under load
  - Test complete request flow (Web → Logic → Database)
  - Identify performance issues before production
- **Pain points:**
  - Current tests don't cover full user lifecycle
  - Limited database performance validation
  - Cannot test complete request flow end-to-end
- **Tech comfort:** High - Expert in Go, microservices, databases

---

## 3. Functional Requirements

### FR-1: Arrival-Rate Executor Migration

**Description:** Migrate from `ramping-vus` executor to `ramping-arrival-rate` executor for realistic production traffic simulation.

**User Story:**
> As a DevOps/SRE engineer, I want k6 to use arrival-rate executors so that load tests simulate actual request arrival patterns (requests/second) rather than virtual user counts, matching real-world production behavior.

**Acceptance Criteria:**
- [ ] All scenarios use `ramping-arrival-rate` or `constant-arrival-rate` executors
- [ ] Traffic patterns defined in RPS (requests per second) rather than VU count
- [ ] Baseline traffic uses `constant-arrival-rate` executor
- [ ] Peak hours use `ramping-arrival-rate` executor with time-based stages
- [ ] Traffic spikes use `ramping-arrival-rate` with sudden target increases
- [ ] Pre-allocated VUs configured for efficiency (`preAllocatedVUs`)
- [ ] Maximum VUs configured to handle peak arrival rates (`maxVUs`)
- [ ] Backward compatibility: Existing journey functions work with new executors

**Priority:** Must Have

**Technical Details:**
- Executor types: `constant-arrival-rate`, `ramping-arrival-rate`
- Configuration: `rate`, `timeUnit`, `preAllocatedVUs`, `maxVUs`, `stages`
- Migration: Update `k6/load-test-multiple-scenarios.js` scenarios configuration

---

### FR-2: Full User Journey Testing

**Description:** Enhance all user journeys to include complete user lifecycle from account registration through purchase, testing full stack (Web → Logic → Database).

**User Story:**
> As a backend developer, I want k6 to test complete user journeys starting from registration so that we validate the entire user lifecycle and full stack performance (Web Layer → Logic Layer → Database Layer).

**Acceptance Criteria:**
- [ ] E-commerce Shopping Journey includes registration step before login
- [ ] Product Review Journey includes registration step before login
- [ ] Order Tracking Journey includes registration step before login
- [ ] Quick Browse Journey includes registration step (for authenticated browsing)
- [ ] All journeys test database reads (GET products, reviews, orders)
- [ ] All journeys test database writes (POST orders, carts, reviews)
- [ ] Journey steps tagged with operation type (`db_read`, `db_write`)
- [ ] Journey steps tagged with stack layer (`web`, `logic`, `database`)
- [ ] Registration uses `/api/v2/auth/register` endpoint
- [ ] Login uses `/api/v2/auth/login` endpoint
- [ ] User profile retrieval uses `/api/v2/users/:id` endpoint
- [ ] Product browsing uses `/api/v2/catalog/items` endpoint
- [ ] Product details use `/api/v1/products/:id` endpoint
- [ ] Cart operations use `/api/v2/carts/:cartId/items` endpoint
- [ ] Order creation uses `/api/v1/orders` endpoint
- [ ] Review reading uses `/api/v1/reviews` endpoint

**Priority:** Must Have

**Journey Coverage:**
- **E-commerce Shopping Journey**: Register → Login → Profile → Browse → View Product → Add Cart → View Cart → Shipping Estimate → Create Order → Notification (10 steps)
- **Product Review Journey**: Register → Login → Profile → View Product → Read Reviews → Write Review (6 steps)
- **Order Tracking Journey**: Register → Login → Profile → View Orders → Order Details → Track Shipping → Check Notifications (7 steps)
- **Quick Browse Journey**: Register → Browse → View Product → Shipping Check → Add Cart (5 steps)

**Technical Details:**
- Update journey functions in `k6/load-test-multiple-scenarios.js`
- Add registration step as first step in authenticated journeys
- Use unique user IDs: `user-${__VU}-${Date.now()}`
- Tag each step with `operation: 'db_read'` or `operation: 'db_write'`
- Tag each step with `stack_layer: 'web'`, `'logic'`, or `'database'`

---

### FR-3: Production Traffic Pattern Simulation

**Description:** Implement realistic production traffic patterns including baseline traffic, peak hours, and traffic spikes.

**User Story:**
> As a DevOps/SRE engineer, I want k6 to simulate realistic production traffic patterns (baseline, peaks, spikes) so that we can validate system behavior under production-like conditions.

**Acceptance Criteria:**
- [ ] Baseline traffic scenario: `constant-arrival-rate` with steady RPS throughout day
- [ ] Peak hours scenario: `ramping-arrival-rate` with morning peak (9 AM - 12 PM) and evening peak (6 PM - 10 PM)
- [ ] Traffic spike scenario: `ramping-arrival-rate` with sudden burst simulation (flash sale pattern)
- [ ] Lunch dip scenario: Reduced traffic during lunch hours (12 PM - 2 PM)
- [ ] Night low scenario: Minimal traffic during night hours (10 PM - 6 AM)
- [ ] All scenarios run concurrently (multiple scenarios in parallel)
- [ ] Traffic patterns configurable via environment variables or config
- [ ] RPS targets documented and adjustable

**Priority:** Must Have

**Traffic Patterns:**

**Baseline Traffic:**
- Duration: 24 hours (continuous)
- Rate: 30 RPS (configurable)
- Executor: `constant-arrival-rate`

**Peak Hours:**
- Morning Peak: 9 AM - 12 PM, 100 RPS
- Lunch Dip: 12 PM - 2 PM, 60 RPS
- Afternoon Recovery: 2 PM - 6 PM, 90 RPS
- Evening Peak: 6 PM - 10 PM, 100 RPS
- Night Low: 10 PM - 6 AM, 20 RPS
- Executor: `ramping-arrival-rate`

**Traffic Spike (Flash Sale):**
- Pre-event: 0 RPS for 2 hours
- Sudden burst: 200 RPS in 30 seconds
- Sustain: 200 RPS for 5 minutes
- Quick drop: 50 RPS in 30 seconds
- Post-event: 0 RPS for 1 hour
- Executor: `ramping-arrival-rate`

**Technical Details:**
- Multiple scenarios run in parallel
- RPS targets configurable via Helm values or environment variables
- Time-based stages for peak hours scenario
- Sudden target increases for spike scenario

---

### FR-4: Burst Traffic Simulation

**Description:** Simulate sudden traffic bursts for flash sales, marketing campaigns, viral content, and scheduled events.

**User Story:**
> As a DevOps/SRE engineer, I want k6 to simulate sudden traffic bursts so that we can validate system behavior during flash sales, marketing campaigns, and viral content scenarios.

**Acceptance Criteria:**
- [ ] Flash sale burst scenario: Sudden spike from 0 to 200+ RPS in < 1 minute
- [ ] Marketing campaign burst scenario: Gradual ramp-up to peak, sustained peak, gradual ramp-down
- [ ] Viral content burst scenario: Exponential traffic increase over short period
- [ ] Scheduled event burst scenario: Predictable spike at specific time
- [ ] Burst scenarios can run independently or alongside baseline traffic
- [ ] Burst duration configurable (30 seconds to 30 minutes)
- [ ] Burst intensity configurable (50 RPS to 500+ RPS)
- [ ] Burst timing configurable (when burst occurs)

**Priority:** Must Have

**Burst Scenarios:**

**Flash Sale:**
- Pattern: Sudden spike → Sustain → Quick drop
- Intensity: 200-500 RPS
- Duration: 5-15 minutes
- Timing: Configurable (e.g., 2 PM)

**Marketing Campaign:**
- Pattern: Gradual ramp-up → Peak → Gradual ramp-down
- Intensity: 100-300 RPS
- Duration: 1-4 hours
- Timing: Configurable (e.g., 10 AM - 2 PM)

**Viral Content:**
- Pattern: Exponential increase → Peak → Gradual decrease
- Intensity: 300-1000 RPS
- Duration: 30 minutes - 2 hours
- Timing: Unpredictable (simulated)

**Technical Details:**
- Use `ramping-arrival-rate` executor with sudden target increases
- Configure `preAllocatedVUs` and `maxVUs` for burst capacity
- Multiple burst scenarios can run in parallel
- Burst timing controlled via stage `duration` offsets

---

### FR-5: Journey Mix Distribution

**Description:** Maintain realistic distribution of user journey types matching production user behavior patterns.

**User Story:**
> As a DevOps/SRE engineer, I want k6 to maintain realistic journey mix percentages so that load tests reflect actual production user behavior distribution.

**Acceptance Criteria:**
- [ ] Browser User: 40% of traffic (browsing, reading)
- [ ] Shopping User: 30% of traffic (complete purchase flow)
- [ ] Registered User: 15% of traffic (authenticated actions)
- [ ] API Client: 10% of traffic (high-volume API calls)
- [ ] Admin User: 5% of traffic (management operations)
- [ ] Journey mix configurable via scenario weights or arrival rates
- [ ] Journey distribution validated in test results/metrics

**Priority:** Must Have

**Journey Distribution:**

**Browser User (40%):**
- 60% Quick Browse Journey (5 steps: Register → Browse → View → Shipping → Cart)
- 40% Simple browsing (legacy behavior)

**Shopping User (30%):**
- 80% E-commerce Shopping Journey (10 steps: Full lifecycle)
- 10% Concurrent Operations Journey (edge case)
- 10% Simple shopping (legacy behavior)

**Registered User (15%):**
- 50% Order Tracking Journey (7 steps)
- 30% Product Review Journey (6 steps)
- 15% Error Handling Journey (edge case)
- 5% Simple authenticated flow (legacy behavior)

**API Client (10%):**
- 70% API Monitoring Journey (7 services)
- 10% Timeout/Retry Journey (edge case)
- 20% Fast endpoint testing (legacy behavior)

**Admin User (5%):**
- Management operations (unchanged)

**Technical Details:**
- Use scenario `weight` or arrival rate distribution to control mix
- Validate distribution in k6 metrics output
- Journey percentages match production analytics (if available)

---

### FR-6: Full Stack Testing Tags

**Description:** Tag all requests with stack layer and operation type to enable full stack performance analysis.

**User Story:**
> As a backend developer, I want k6 to tag requests with stack layer and operation type so that we can analyze performance at each layer (Web → Logic → Database) and operation type (read vs write).

**Acceptance Criteria:**
- [ ] All requests tagged with `stack_layer: 'web'`, `'logic'`, or `'database'`
- [ ] All requests tagged with `operation: 'db_read'` or `'db_write'` (for database operations)
- [ ] Tags visible in k6 metrics output
- [ ] Tags visible in distributed traces (Tempo)
- [ ] Tags enable filtering in Grafana dashboards
- [ ] Tags enable performance analysis by layer and operation type

**Priority:** Should Have

**Tagging Strategy:**

**Stack Layer Tags:**
- `stack_layer: 'web'` - HTTP handler layer
- `stack_layer: 'logic'` - Business logic layer
- `stack_layer: 'database'` - Database query layer

**Operation Type Tags:**
- `operation: 'db_read'` - Database read operations (GET requests)
- `operation: 'db_write'` - Database write operations (POST/PUT requests)
- `operation: 'api_call'` - API-to-API calls

**Technical Details:**
- Add tags to `makeRequest()` function calls
- Tags propagate to Prometheus metrics
- Tags visible in Tempo traces
- Tags enable Grafana filtering and analysis

---

## 4. Non-Functional Requirements

### NFR-1: Performance

**Load Testing Performance:**
- k6 pod must handle 500+ concurrent VUs without resource exhaustion
- k6 script execution must start within 5 seconds
- Test results must be available within 1 minute of test completion

**System Under Test Performance (Targets):**
- Baseline traffic (30 RPS): p95 latency < 500ms, error rate < 0.1%
- Peak traffic (100 RPS): p95 latency < 800ms, error rate < 1%
- Burst traffic (200+ RPS): p95 latency < 1500ms, error rate < 5%
- Database read operations: p95 latency < 200ms
- Database write operations: p95 latency < 300ms

**Measurement:**
- Metrics collected via Prometheus
- Latency percentiles: p50, p95, p99
- Error rates: 4xx/5xx percentage
- Database performance: Query duration metrics

---

### NFR-2: Reliability

**Test Reliability:**
- Load tests must run without k6 pod crashes
- Test scenarios must complete successfully 99% of the time
- Failed tests must provide clear error messages and diagnostics

**System Reliability Under Load:**
- System must maintain < 1% error rate during baseline traffic
- System must maintain < 5% error rate during burst traffic
- No data corruption during high load
- Database connections must remain stable under load

**Measurement:**
- k6 pod uptime and restart count
- Test completion rate
- System error rates during load tests
- Database connection pool metrics

---

### NFR-3: Scalability

**k6 Scalability:**
- k6 must support up to 1000 concurrent VUs (if needed)
- k6 must support multiple concurrent scenarios
- k6 resource usage must scale linearly with VU count

**System Scalability Validation:**
- System must handle 2x expected production load
- System must handle sudden 5x traffic spikes (burst scenarios)
- Database must handle concurrent read/write operations
- Microservices must scale horizontally under load

**Measurement:**
- VU count vs resource usage
- System capacity at different load levels
- Database connection pool utilization
- Microservice replica scaling behavior

---

### NFR-4: Observability

**Test Observability:**
- All k6 requests must generate distributed traces (Tempo)
- All k6 requests must generate metrics (Prometheus)
- Test results must be visible in Grafana dashboards
- Journey steps must be traceable end-to-end

**System Observability Under Load:**
- All microservice requests must have trace IDs
- Database queries must be traced
- Performance metrics must be collected at each layer
- Error rates must be tracked by service and endpoint

**Measurement:**
- Trace coverage: 100% of requests traced
- Metric coverage: All endpoints have metrics
- Dashboard availability: Real-time visibility
- Alert coverage: Critical metrics have alerts

---

### NFR-5: Maintainability

**Code Maintainability:**
- k6 scripts must be well-documented
- Journey functions must be reusable
- Configuration must be externalized (Helm values, env vars)
- Code must follow existing patterns and conventions

**Configuration Management:**
- Traffic patterns configurable via Helm values
- RPS targets configurable via environment variables
- Journey mix configurable via scenario weights
- Burst scenarios configurable via scenario definitions

**Documentation:**
- Journey flows documented with step-by-step descriptions
- Traffic patterns documented with RPS targets and timing
- Configuration options documented in Helm values files
- Troubleshooting guide for common issues

---

## 5. Out of Scope

The following are explicitly NOT included in this feature:

- ❌ **k6 Cloud Integration** - Using k6 Cloud (paid service) is out of scope. Open-source k6 is sufficient.
- ❌ **Custom k6 Extensions** - Creating custom k6 JavaScript extensions or plugins
- ❌ **Load Testing Other Systems** - Only microservices APIs are tested, not external dependencies
- ❌ **Performance Optimization** - This feature tests performance but doesn't optimize the system
- ❌ **Database Schema Changes** - No database schema modifications for load testing
- ❌ **New API Endpoints** - Only existing APIs are used, no new endpoints created
- ❌ **Authentication Token Management** - Using simple username/password, not JWT token management
- ❌ **Multi-Region Testing** - Single-region testing only, no multi-region scenarios
- ❌ **Chaos Engineering** - No intentional system failures or chaos scenarios
- ❌ **Load Testing UI** - No web UI for configuring or viewing tests (k6 CLI only)

---

## 6. Edge Cases & Error Handling

### Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| **Registration with existing username** | System returns 400/409 error, k6 logs error and continues with different username |
| **Login with invalid credentials** | System returns 401 error, k6 logs error and retries with valid credentials |
| **Product not found (404)** | System returns 404 error, k6 logs error and selects different product ID |
| **Cart operations on non-existent cart** | System returns 404 error, k6 creates cart first then adds items |
| **Order creation with invalid data** | System returns 400 error, k6 logs error and uses valid data |
| **Database connection timeout** | System returns 503 error, k6 logs error and retries with exponential backoff |
| **High load causing rate limiting** | System returns 429 error, k6 logs error and reduces arrival rate |
| **Concurrent requests to same resource** | System handles race conditions correctly, k6 validates data consistency |

### Error Scenarios

| Error | User Message | System Action | k6 Action |
|-------|--------------|---------------|-----------|
| **Network timeout** | "Request timeout" | Return 504 Gateway Timeout | Log error, retry with backoff |
| **Service unavailable** | "Service unavailable" | Return 503 Service Unavailable | Log error, continue with next request |
| **Database error** | "Internal server error" | Return 500 Internal Server Error | Log error, mark as failed request |
| **Invalid request** | "Bad request" | Return 400 Bad Request | Log error, use valid request data |
| **Authentication failure** | "Unauthorized" | Return 401 Unauthorized | Log error, retry login |
| **Resource not found** | "Not found" | Return 404 Not Found | Log error, use different resource ID |

### Error Handling Strategy

**k6 Error Handling:**
- All errors logged with context (journey step, user ID, error type)
- Failed requests counted in k6 metrics
- Error rate tracked per scenario and journey type
- Critical errors (5xx) trigger alerts

**System Error Handling:**
- System must return appropriate HTTP status codes
- Error messages must be clear and actionable
- System must not crash under error conditions
- Database errors must be handled gracefully

---

## 7. Success Metrics

### Key Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Test Execution Success Rate** | > 99% | k6 test completion rate (successful test runs / total test runs) |
| **Journey Completion Rate** | > 95% | Percentage of journeys that complete successfully |
| **Baseline Traffic Error Rate** | < 0.1% | 4xx/5xx errors / total requests during baseline (30 RPS) |
| **Peak Traffic Error Rate** | < 1% | 4xx/5xx errors / total requests during peak (100 RPS) |
| **Burst Traffic Error Rate** | < 5% | 4xx/5xx errors / total requests during burst (200+ RPS) |
| **Baseline p95 Latency** | < 500ms | 95th percentile response time during baseline traffic |
| **Peak p95 Latency** | < 800ms | 95th percentile response time during peak traffic |
| **Burst p95 Latency** | < 1500ms | 95th percentile response time during burst traffic |
| **Database Read p95 Latency** | < 200ms | 95th percentile database read query time |
| **Database Write p95 Latency** | < 300ms | 95th percentile database write query time |
| **Full Journey p95 Latency** | < 5s | 95th percentile end-to-end journey completion time |
| **Registration Success Rate** | > 99% | Successful registrations / total registration attempts |
| **Traffic Pattern Accuracy** | ±5% | Actual RPS vs target RPS (arrival-rate executor accuracy) |
| **Trace Coverage** | 100% | Percentage of requests with distributed traces |
| **Metric Coverage** | 100% | Percentage of endpoints with Prometheus metrics |

### Capacity Planning Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Maximum Sustainable RPS** | TBD (to be determined) | Highest RPS where error rate < 1% and p95 < 1000ms |
| **Burst Capacity** | 200+ RPS | Maximum RPS during burst scenario with < 5% error rate |
| **Database Connection Pool Utilization** | < 80% | Active connections / max connections |
| **Microservice CPU Usage** | < 70% | Average CPU usage during peak traffic |
| **Microservice Memory Usage** | < 80% | Average memory usage during peak traffic |

### Definition of Done

- [ ] All functional requirements implemented (FR-1 through FR-6)
- [ ] All non-functional requirements met (NFR-1 through NFR-5)
- [ ] All acceptance criteria satisfied
- [ ] Edge cases handled correctly
- [ ] Error scenarios tested and validated
- [ ] Success metrics achieved (all targets met)
- [ ] Full user journeys tested (registration → purchase)
- [ ] Traffic patterns validated (baseline, peak, burst)
- [ ] Database performance validated (read/write operations)
- [ ] Distributed tracing working (100% trace coverage)
- [ ] Metrics collection working (100% metric coverage)
- [ ] Documentation complete (journey flows, configuration, troubleshooting)
- [ ] Production-ready validation complete (system handles production-like load)

---

## 8. Open Questions

- [ ] **RPS Targets**: What are the specific RPS targets for baseline, peak, and burst scenarios? (Currently TBD - need production data or estimates)
- [ ] **Test Duration**: How long should baseline traffic tests run? (Current: 6.5 hours - is this appropriate?)
- [ ] **Burst Frequency**: How often should burst scenarios run? (Daily, weekly, on-demand?)
- [ ] **Resource Limits**: What are the k6 pod resource limits? (Current: 2-4Gi RAM, 1-2 CPU - sufficient for 500+ RPS?)
- [ ] **Database Load**: What is the expected database load during peak traffic? (Need to validate database can handle concurrent reads/writes)
- [ ] **Journey Mix Validation**: Do the journey mix percentages (40/30/15/10/5) match production analytics? (Need to validate or adjust)

---

## 9. Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-12-25 | Initial specification | System |

---

## Next Steps

1. **Review specification** with DevOps/SRE team and backend developers
2. **Resolve open questions** - Gather production data for RPS targets and validate journey mix
3. **Run `/plan k6-load-test-strategy`** to create technical implementation plan
4. **Run `/tasks k6-load-test-strategy`** to break down into implementation tasks
5. **Validate with stakeholders** - Confirm requirements match production needs

---

*Specification created with SDD 2.0*

