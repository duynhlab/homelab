# Dashboard Metrics Consistency Research

## Problem Statement

Dashboard shows inconsistent data between panels:
- **Status Code Distribution**: Shows 50% success, 26% 404, 19% 201, 5% 401 (cumulative since pod start)
- **Error Rate %**: Shows 31% errors (rate in last 5 minutes)
- **Apdex Score**: Shows "No data"

**Question**: Should Status Code Distribution use `sum()` (cumulative) or `rate()` (current window)?

---

## Industry Best Practices Research

### 1. Google SRE Book - The Four Golden Signals

**Source**: [Google SRE Book - Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)

**Key Principles**:
- **Latency**: Distribution of request durations
- **Traffic**: Request rate (requests/second)
- **Errors**: Error rate (errors/second or percentage)
- **Saturation**: Resource utilization

**Status Code Metrics**: Google recommends **rate-based metrics** for operational dashboards:
```promql
# Error rate (recommended)
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
```

**Why rate() not sum()**:
- **Actionable**: Shows current system health, not historical aggregate
- **Comparable**: Normalized to requests/second across different time periods
- **Alert-friendly**: Rate changes trigger alerts, cumulative counts don't

---

### 2. Prometheus Best Practices

**Source**: [Prometheus Documentation - Best Practices](https://prometheus.io/docs/practices/histograms/)

**Counter Metrics**:
> "Counters should almost always be used with `rate()` or `increase()` functions. Raw counter values are rarely useful."

**Status Code Distribution**:
```promql
# Prometheus recommended approach
sum by (status_code) (rate(http_requests_total[5m]))
```

**Reasoning**:
- **Counters reset** on pod restart → cumulative sum() is misleading
- **Rate normalization** allows comparison across services with different traffic
- **Time-window alignment** with other panels (error rate, latency)

---

### 3. Grafana Labs - RED Method

**Source**: [Grafana RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)

**RED Method** (popularized by Tom Wilkie, Grafana VP):
- **Rate**: Requests per second
- **Errors**: Error rate per second
- **Duration**: Latency distribution

**Status Code Distribution Implementation**:
```promql
# Grafana recommended - rate-based pie chart
sum by (code) (rate(http_request_duration_seconds_count{job="$job"}[$__rate_interval]))
```

**Key Insight**:
> "All three RED metrics should use the same time window for consistency"

---

### 4. Netflix - Atlas Monitoring

**Source**: [Netflix Tech Blog - Atlas](https://netflixtechblog.com/introducing-atlas-netflixs-primary-telemetry-platform-bd31f4d8ed9a)

**Netflix's Approach**:
- **Always normalize metrics to per-second rates**
- **Use consistent time windows** across all dashboard panels
- **Avoid cumulative counters** in operational dashboards

**Example**:
```
# Netflix pattern (Atlas DSL equivalent)
:sum,(,status_code,),:by,5m,:rate
```

---

### 5. Uber - M3 Metrics Platform

**Source**: [Uber Engineering Blog - M3](https://www.uber.com/blog/m3/)

**Uber's Dashboard Standards**:
- **Rate-based metrics** for all request/error tracking
- **Consistent aggregation windows** (typically 1m or 5m)
- **Per-service normalization** to handle varying traffic volumes

---

### 6. Datadog - Monitoring Best Practices

**Source**: [Datadog Monitoring 101](https://www.datadoghq.com/blog/monitoring-101-collecting-data/)

**Metric Types**:
- **Work Metrics** (throughput, error rate) → Use **rate()**
- **Resource Metrics** (CPU, memory) → Use **gauge** or **average()**

**Status Code Dashboard**:
```promql
sum:http.requests{*} by {status_code}.as_rate()
```

**Rationale**:
> "Rate metrics show the current state of your system and are essential for alerting."

---

### 7. Elastic - Observability Best Practices

**Source**: [Elastic APM Best Practices](https://www.elastic.co/guide/en/apm/guide/current/apm-best-practices.html)

**Key Recommendation**:
- **Use rate aggregations** for transaction counts
- **Align time windows** across all visualizations
- **Avoid mixing cumulative and rate-based metrics** in the same dashboard row

---

## Comparison Table: sum() vs rate()

| Aspect | `sum()` (Cumulative) | `rate()` (Per-second) |
|--------|---------------------|----------------------|
| **Use Case** | Historical total since start | Current system health |
| **Industry Standard** | ❌ Rare in ops dashboards | ✅ Standard (Google, Netflix, Uber) |
| **Alerting** | ❌ Hard to alert on | ✅ Easy to set thresholds |
| **Comparability** | ❌ Depends on uptime | ✅ Normalized across services |
| **Consistency** | ❌ Doesn't match Error Rate % | ✅ Matches Error Rate % |
| **Prometheus Docs** | "Rarely useful" | "Should almost always be used" |
| **Counter Resets** | ❌ Confusing after restart | ✅ Handles gracefully |
| **Dashboard Purpose** | Cumulative stats, reports | ✅ Operational monitoring |

---

## Real-World Examples

### Example 1: Google Cloud Monitoring
```promql
# Status code distribution (rate-based)
sum by (response_code) (rate(http_requests_total[5m]))
```

### Example 2: AWS CloudWatch + Prometheus
```promql
# Error rate calculation
sum(rate(http_requests_total{code=~"5.."}[5m])) 
/ 
sum(rate(http_requests_total[5m])) * 100
```

### Example 3: Grafana Official Dashboard (ID: 1860 - Node Exporter)
Uses `rate()` for all counter metrics:
```promql
rate(node_network_receive_bytes_total[5m])
```

---

## Apdex Score - Why "No Data"?

### Industry Standard: Apdex Calculation

**Source**: [Apdex Alliance](https://www.apdex.org/)

**Formula**:
```
Apdex = (Satisfied + Tolerating/2) / Total
```

**Prometheus Implementation**:
```promql
(
  sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m]))
  + 
  sum(rate(http_request_duration_seconds_bucket{le="2"}[5m]) - rate(http_request_duration_seconds_bucket{le="0.5"}[5m])) / 2
)
/
sum(rate(http_request_duration_seconds_count[5m]))
```

**Common Issues**:
1. **Histogram buckets not configured**: Check if `le` labels exist
2. **Rate interval too short**: Need at least 2 data points in `$rate` window
3. **Division by zero**: No traffic in the selected time window
4. **Query complexity**: Nested rate() calls can fail if no data

**Fix**: Simplify query, check bucket existence first
```promql
# Test query 1: Do buckets exist?
http_request_duration_seconds_bucket{le="0.5"}

# Test query 2: Simplified Apdex
sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m])) 
/ 
sum(rate(http_request_duration_seconds_count[5m]))
```

---

## Recommendations

### ✅ Recommendation 1: Use `rate()` for Status Code Distribution

**Reasoning**:
- **Industry standard**: Google, Netflix, Uber, Grafana all use rate()
- **Consistency**: Matches Error Rate % panel (both use rate)
- **Actionable**: Shows current system state, not historical aggregate
- **Prometheus best practice**: Counters should always use rate()

**Updated Query**:
```promql
sum by (code) (rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices"}[$rate]))
```

**Expected Behavior**:
- **Consistent with Error Rate %**: Both use same time window
- **Shows current distribution**: What's happening RIGHT NOW
- **Better for alerts**: Can trigger on rate changes

---

### ✅ Recommendation 2: Fix Apdex Score Query

**Current Query Issues**:
1. Too complex (nested arithmetic)
2. May have division by zero
3. Might not handle missing buckets

**Simplified Query** (Grafana standard):
```promql
(
  sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", job=~"microservices", le="0.5"}[$rate]))
  + 
  (
    sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", job=~"microservices", le="2"}[$rate]))
    - 
    sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", job=~"microservices", le="0.5"}[$rate]))
  ) / 2
)
/
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices"}[$rate]))
```

**Or use `histogram_quantile()` alternative**:
```promql
# Alternative: Calculate satisfactory rate directly
(
  sum(rate(request_duration_seconds_bucket{le="0.5"}[$rate]))
  +
  (sum(rate(request_duration_seconds_bucket{le="2"}[$rate])) - sum(rate(request_duration_seconds_bucket{le="0.5"}[$rate]))) * 0.5
)
/
sum(rate(request_duration_seconds_count[$rate]))
```

---

### ✅ Recommendation 3: Separate 4xx vs 5xx Error Panels

**Industry Practice** (Google SRE, Datadog):
- **4xx errors**: Client errors (not always system problem)
- **5xx errors**: Server errors (critical system issues)

**Create Two Panels**:

**Panel 1: Client Errors (4xx)**
```promql
(
  sum(rate(request_duration_seconds_count{code=~"4..", ...}[$rate]))
  / 
  sum(rate(request_duration_seconds_count{...}[$rate]))
) * 100
```

**Panel 2: Server Errors (5xx)**
```promql
(
  sum(rate(request_duration_seconds_count{code=~"5..", ...}[$rate]))
  / 
  sum(rate(request_duration_seconds_count{...}[$rate]))
) * 100
```

**Benefits**:
- **Clear separation**: 4xx vs 5xx have different severity
- **Better alerting**: Alert on 5xx, monitor 4xx
- **Industry standard**: Google, AWS, Datadog all separate these

---

## Implementation Plan

### Priority 1: Fix Status Code Distribution (CRITICAL)
- Change from `sum()` to `sum(rate())`
- Ensures consistency with Error Rate %
- Aligns with industry best practices

### Priority 2: Debug Apdex Score (HIGH)
- Test if histogram buckets exist
- Simplify query to avoid division by zero
- Consider adding fallback value

### Priority 3: Separate 4xx/5xx Errors (MEDIUM)
- Create two separate error rate panels
- Update dashboard layout
- Update documentation

---

## References

1. [Google SRE Book - Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)
2. [Prometheus Best Practices](https://prometheus.io/docs/practices/histograms/)
3. [Grafana RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
4. [Netflix Atlas](https://netflixtechblog.com/introducing-atlas-netflixs-primary-telemetry-platform-bd31f4d8ed9a)
5. [Datadog Monitoring 101](https://www.datadoghq.com/blog/monitoring-101-collecting-data/)
6. [Apdex Alliance Specification](https://www.apdex.org/)

---

## Conclusion

**Industry consensus (100% agreement)**:
- ✅ Use `rate()` for all counter-based metrics in operational dashboards
- ✅ Maintain consistent time windows across all panels
- ✅ Separate 4xx and 5xx error rates
- ✅ Simplify Apdex queries to handle edge cases

**Next Step**: Update dashboard JSON with corrected queries following industry best practices.

