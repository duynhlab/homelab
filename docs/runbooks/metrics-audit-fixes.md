# Metrics Audit: Before & After

## Overview

| Field | Value |
|-------|-------|
| **Audit Date** | 2026-02-18 |
| **Scope** | 8 microservices (`middleware/prometheus.go`) |
| **Dashboard** | `microservices-dashboard.json` (34 data panels + 5 row panels, 4 template variables) |
| **SLO** | `mop` Helm chart `slo.yaml` (3 objectives per service) |
| **Methodology** | Static code analysis + PromQL audit + dashboard JSON audit + Go compilation verification |

This runbook documents each metrics issue found during the audit, with before/after code, PromQL proof queries, dashboard impact analysis, and verification steps. Useful for interviews, onboarding, and incident reference.

---

## Issue 1: Path Label Cardinality Bomb (CRITICAL)

### Problem

The `path` label used raw URLs from `c.Request.URL.Path`, creating a new time series for every unique URL including dynamic segments (product IDs, user IDs, order IDs).

**Before (code):**

```go
path := c.Request.URL.Path  // "/api/v1/products/123"
requestDuration.WithLabelValues(method, path, statusCode).Observe(duration)
```

**Impact calculation:**
- 10,000 unique product IDs = 10,000 unique `path` values per metric
- 4 metrics x 3 methods x 10,000 paths x 5 status codes = **600,000 time series** from products alone
- All 8 services with similar patterns: cardinality grows proportional to data volume

### Dashboard Impact

8 dashboard panels use the `path` label:

| Panel ID | Panel Title | Impact |
|----------|-------------|--------|
| 10 | Total Requests by Endpoint (pie) | Shows thousands of slices instead of ~20 routes |
| 12 | RPS by Endpoint | Legend becomes unreadable with unique URLs |
| 13 | Response time P95 | One line per unique URL instead of per route |
| 14 | Response time P50 | Same as above |
| 15 | Response time P99 | Same as above |
| 23 | Request Rate by Endpoint | Same as above |
| 24 | Request Rate by Method/Endpoint | Same as above |
| 25 | Error Rate by Method/Endpoint | Same as above |

### After (fix)

```go
path := c.FullPath()  // "/api/v1/products/:id" (Gin route pattern)
if path == "" {
    path = "unknown"   // 404 or unmatched routes
}
```

### PromQL Verification

```promql
-- Check unique path count (should be < 30 after fix, was unbounded before)
count(count by (path) ({job="microservices"}))

-- Identify high-cardinality labels
topk(10, count by (__name__, path) ({job="microservices"}))

-- Before: returns thousands of unique paths like /api/v1/products/123
-- After: returns ~20 route patterns like /api/v1/products/:id
```

### References

- **Uber M3**: Built their entire aggregation platform to handle unbounded cardinality. Path normalization is enforced at the SDK level.
- **Prometheus Best Practices**: "Do not use labels to store dimensions with high cardinality (many different label values), such as user IDs, email addresses, or other unbounded sets of values."

---

## Issue 2: Redundant Metrics (HIGH)

### Problem

The middleware defined 6 custom metrics, but 2 were exact duplicates of sub-metrics already provided by the histogram:

**Before (metric definitions):**

```go
// Histogram (KEEP) -- provides _count and _bucket automatically
requestDuration = promauto.NewHistogramVec(...)

// Counter (REDUNDANT) -- identical to request_duration_seconds_count
requestTotal = promauto.NewCounterVec(prometheus.CounterOpts{
    Name: "requests_total",
}, []string{"method", "path", "code"})

// Counter (REDUNDANT) -- subset of request_duration_seconds_count{code=~"5.."}
errorRate = promauto.NewCounterVec(prometheus.CounterOpts{
    Name: "error_rate_total",
}, []string{"method", "path", "code"})
```

**Why they're redundant:**

| Redundant Metric | Equivalent (already exists) | Proof |
|-----------------|---------------------------|-------|
| `requests_total{method="GET", path="/api/v1/users", code="200"}` | `request_duration_seconds_count{method="GET", path="/api/v1/users", code="200"}` | Both `.Inc()` on every request, same labels |
| `error_rate_total{code="500"}` | `request_duration_seconds_count{code="500"}` | Both count 5xx, same labels |

### Dashboard Impact

**Full dashboard JSON audit result:**

| Metric | Panels Using It | Dashboard Impact of Removal |
|--------|----------------|---------------------------|
| `requests_total` | **0 panels** | ZERO impact |
| `error_rate_total` | **0 panels** | ZERO impact |
| `request_duration_seconds_count` | **14 panels** + 2 template variables | Already the source of truth |

**SLO template audit:** The mop chart's `slo.yaml` template ([`duyhenryer/charts` repo](https://github.com/duyhenryer/charts/blob/main/charts/mop/templates/slo.yaml)) uses only `request_duration_seconds_count` and `request_duration_seconds_bucket`. Zero references to `requests_total` or `error_rate_total`.

### After (fix)

Removed both redundant metrics. Middleware now defines 4 metrics:

| Metric | Type | Purpose |
|--------|------|---------|
| `request_duration_seconds` | Histogram | RED: Rate (_count), Errors (_count+code), Duration (_bucket) |
| `requests_in_flight` | Gauge | Saturation (4th Golden Signal) |
| `request_size_bytes` | Histogram | Request body size, RX traffic |
| `response_size_bytes` | Histogram | Response body size, TX traffic |

### PromQL Verification

```promql
-- After deployment, these should return "no data":
requests_total{job="microservices"}
error_rate_total{job="microservices"}

-- These should continue working (unchanged):
rate(request_duration_seconds_count{job="microservices"}[5m])
rate(request_duration_seconds_count{job="microservices", code=~"5.."}[5m])
```

### Impact

- Time series reduction: ~33% (from 6 custom metrics to 4, same labels)
- Storage reduction: proportional to series count reduction
- Query performance: fewer series to scan

---

## Issue 3: request_size_bytes Empty Code Label (HIGH)

### Problem

`request_size_bytes` was recorded BEFORE `c.Next()` with an empty string for the `code` label, because the status code is unknown until after the handler runs.

**Before (code):**

```go
// BEFORE c.Next() -- status code unknown, uses empty string
requestSize.WithLabelValues(method, path, "").Observe(float64(c.Request.ContentLength))

c.Next()

// AFTER c.Next() -- status code known, used correctly
statusCode := strconv.Itoa(c.Writer.Status())
responseSize.WithLabelValues(method, path, statusCode).Observe(float64(c.Writer.Size()))
```

**Impact:** Creates phantom series with `code=""` that don't match standard filters like `code=~"2.."`:

```promql
-- Returns data (phantom series)
request_size_bytes_count{code=""}

-- Misses request_size_bytes entirely (code="" doesn't match)
request_size_bytes_count{code=~"2.."}
```

### Dashboard Impact

| Panel ID | Panel Title | Uses `request_size_bytes` | Impact |
|----------|-------------|--------------------------|--------|
| 18 | Total Network Traffic | `request_size_bytes_sum` (no code filter) | No visible breakage, but data quality issue |

### After (fix)

Moved `requestSize` recording to after `c.Next()`:

```go
c.Next()

statusCode := strconv.Itoa(c.Writer.Status())
requestSize.WithLabelValues(method, path, statusCode).Observe(float64(c.Request.ContentLength))
responseSize.WithLabelValues(method, path, statusCode).Observe(float64(c.Writer.Size()))
```

### PromQL Verification

```promql
-- After deployment, should return "no data":
request_size_bytes_count{code=""}

-- Should now return data (previously missed these):
request_size_bytes_count{code=~"2.."}
```

---

## Issue 4: Histogram Buckets Not SLO-Tuned (MEDIUM)

### Problem

The `request_duration_seconds` histogram used Prometheus default buckets, which have a 250ms gap in the SLO boundary zone (between 250ms and 500ms). This causes poor P95 precision when latency is near the 500ms SLO threshold.

**Before (buckets):**

```go
Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10}
//                                                   ^^^^  ^^^
//                                                   250ms gap at SLO boundary
```

**Precision problem:** `histogram_quantile` uses linear interpolation between bucket boundaries. With a 250ms gap between `le="0.25"` and `le="0.5"`, a request at 350ms is interpolated between 250ms and 500ms -- potentially reporting P95 as 400ms when actual P95 is 350ms.

### Dashboard Impact

7 panels use `_bucket` for percentile calculations:

| Panel ID | Panel Title | Impact |
|----------|-------------|--------|
| 1, 2, 3 | P99, P95, P50 Response Success | Better precision around SLO boundary |
| 6 | Apdex Score | Uses `le="0.5"` and `le="2"` -- both present in new set |
| 13, 14, 15 | Response time P95, P50, P99 by endpoint | Better precision |

**No query changes needed.** All existing `histogram_quantile()` queries work with any bucket set.

### After (fix)

```go
Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 0.75, 1, 2, 5, 10}
//                                                  ^^^  ^^^      ^^^^
//                                                  added for SLO precision
```

| Change | Reason |
|--------|--------|
| Added `0.2` | Precision before SLO threshold |
| Added `0.3` | Precision before SLO threshold |
| Removed `0.25` | Replaced by 0.2 and 0.3 (finer granularity) |
| Added `0.75` | Precision after SLO threshold |
| Changed `2.5` to `2` | Aligns with Apdex tolerating boundary |

Total: 13 buckets (was 11). Minimal storage increase (~18%), significantly better P95 accuracy in the 200ms-750ms range.

### PromQL Verification

```promql
-- Compare P95 precision before/after with same traffic
histogram_quantile(0.95, sum(rate(request_duration_seconds_bucket{job="microservices"}[5m])) by (le))

-- Verify Apdex still works (needs le="0.5" and le="2")
(
  sum(rate(request_duration_seconds_bucket{le="0.5"}[5m]))
  + 0.5 * (
    sum(rate(request_duration_seconds_bucket{le="2"}[5m]))
    - sum(rate(request_duration_seconds_bucket{le="0.5"}[5m]))
  )
) / sum(rate(request_duration_seconds_count[5m]))
```

---

## Issue 5: No Exemplars (MEDIUM)

### Problem

When P99 latency spikes in Grafana, engineers had no way to jump from the metric to the specific distributed trace that caused the spike. Investigation required manual correlation: check the timestamp, open Tempo, search for traces in that time window, filter by duration.

### Dashboard Impact

| Panel ID | Panel Title | Enhancement |
|----------|-------------|------------|
| 13 | Response time P95 | Exemplar dots on time series |
| 14 | Response time P50 | Exemplar dots on time series |
| 15 | Response time P99 | Exemplar dots on time series |

### After (fix)

```go
span := trace.SpanFromContext(c.Request.Context())
if span.SpanContext().HasTraceID() {
    requestDuration.WithLabelValues(method, path, statusCode).(prometheus.ExemplarObserver).ObserveWithExemplar(
        duration, prometheus.Labels{"traceID": span.SpanContext().TraceID().String()},
    )
} else {
    requestDuration.WithLabelValues(method, path, statusCode).Observe(duration)
}
```

**Prerequisites:**
- Prometheus: `--enable-feature=exemplar-storage`
- Tracing middleware runs before Prometheus middleware (already configured)
- Grafana: Tempo datasource configured (already done)

### Verification

1. Deploy the updated middleware
2. Generate traffic (e.g., via k6 load test)
3. Open Grafana -> Response time P99 panel
4. Enable "Exemplars" toggle in query options
5. Exemplar dots should appear on the time series
6. Click a dot -> `traceID` field shown -> click through to Tempo

---

## Appendix A: Full Dashboard Metrics Audit

### Panel-to-Metric Mapping

| Panel ID | Panel Title | Metric | Labels Used |
|----------|-------------|--------|-------------|
| 1 | 99th Percentile Response Success | `request_duration_seconds_bucket` | method, path, code, le |
| 2 | 95th Percentile Response Success | `request_duration_seconds_bucket` | method, path, code, le |
| 3 | 50th Percentile Response Success | `request_duration_seconds_bucket` | method, path, code, le |
| 4 | Total RPS | `request_duration_seconds_count` | app, namespace |
| 5 | Total Request | `request_duration_seconds_count` | app, namespace |
| 6 | Apdex Score | `request_duration_seconds_bucket`, `_count` | le (0.5, 2) |
| 7 | Up Instances | `up` | job, app, namespace |
| 8 | Restarts | `kube_pod_container_status_restarts_total` | namespace, pod |
| 9 | Status Code Distribution | `request_duration_seconds_count` | code |
| 10 | Total Requests by Endpoint | `request_duration_seconds_count` | path |
| 12 | RPS by Endpoint | `request_duration_seconds_count` | path |
| 13 | Response time P95 | `request_duration_seconds_bucket` | le, path, code |
| 14 | Response time P50 | `request_duration_seconds_bucket` | le, path, code |
| 15 | Response time P99 | `request_duration_seconds_bucket` | le, path, code |
| 19 | Total Requests In Flight | `requests_in_flight` | app |
| 18 | Total Network Traffic | `response_size_bytes_sum`, `request_size_bytes_sum` | app |
| 23 | Request Rate by Endpoint | `request_duration_seconds_count` | path |
| 24 | Request Rate by Method/Endpoint | `request_duration_seconds_count` | method, path |
| 25 | Error Rate by Method/Endpoint | `request_duration_seconds_count` | method, path, code |
| 26 | Success RPS (2xx) | `request_duration_seconds_count` | code |
| 27 | Error RPS (4xx/5xx) | `request_duration_seconds_count` | code |
| 28 | Success Rate % | `request_duration_seconds_count` | code |
| 30 | Error Rate % | `request_duration_seconds_count` | code |
| 201 | Client Errors (4xx) | `request_duration_seconds_count` | app, code |
| 202 | Server Errors (5xx) | `request_duration_seconds_count` | app, code |
| 31 | Heap Allocated Memory | `go_memstats_alloc_bytes` | app |
| 32 | Heap In-Use Memory | `go_memstats_heap_inuse_bytes` | app |
| 33 | Process Memory (RSS) | `process_resident_memory_bytes` | app |
| 21 | Goroutines & Threads | `go_goroutines`, `go_threads` | app |
| 20 | GC Duration | `go_gc_duration_seconds_sum` | app |
| 34 | GC Frequency | `go_gc_duration_seconds_count` | app |
| 16 | Total Memory per Service | `go_memstats_alloc_bytes` | app |
| 17 | Total CPU per Service | `process_cpu_seconds_total` | app |
| 22 | Memory Allocations per Service | `go_memstats_frees_total` | app |

### Metric-to-Panel Count

| Custom Metric | Panel Count | Status |
|--------------|-------------|--------|
| `request_duration_seconds_count` | 14 + 2 variables | Core metric (RED) |
| `request_duration_seconds_bucket` | 7 | Core metric (RED) |
| `requests_in_flight` | 1 | Saturation signal |
| `request_size_bytes_sum` | 1 | Network RX |
| `response_size_bytes_sum` | 1 | Network TX |
| `requests_total` (removed) | **0** | Was redundant with `_count` |
| `error_rate_total` (removed) | **0** | Was redundant with `_count{code=~"5.."}` |

### Template Variable Dependencies

| Variable | Metric Used | Query |
|----------|-------------|-------|
| `$namespace` | `request_duration_seconds_count` | `label_values(request_duration_seconds_count, namespace)` |
| `$app` | `request_duration_seconds_count` | `label_values(request_duration_seconds_count{namespace=~"$namespace"}, app)` |
| `$rate` | N/A (custom interval) | `1m,2m,3m,5m,10m,30m,1h,...` |
| `$DS_PROMETHEUS` | N/A (datasource) | `prometheus` |

---

**Last Updated**: 2026-02-20
**Version**: 1.0
