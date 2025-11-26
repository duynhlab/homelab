# SLI Definitions

## Overview

Service Level Indicators (SLIs) are quantitative measures of service behavior. Each SLI answers the question: "What is the quality of service from the user's perspective?"

## SLI Types

### 1. Availability SLI

**What**: Ratio of successful requests (non-5xx) to total requests

**How**: PromQL query
```promql
# Error rate (5xx only)
sum(rate(request_duration_seconds_count{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices",
  code=~"5.."
}[5m]))

# Total requests
sum(rate(request_duration_seconds_count{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices"
}[5m]))

# Availability = 1 - (error_rate / total_rate)
```

**Why**: 
- 5xx errors indicate server failures (not client errors)
- Critical for measuring service reliability
- Directly impacts user experience

**SLO Target**: 99.5% (30-day), 99.0% (7-day)

**Example**:
- 1000 requests/minute
- 5 requests return 500 errors
- Availability = 99.5% ✅ (meets SLO)

### 2. Latency SLI

**What**: Ratio of requests faster than threshold (500ms) to total requests

**How**: PromQL query using histogram buckets
```promql
# Requests slower than 500ms
sum(rate(request_duration_seconds_count{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices"
}[5m]))
-
sum(rate(request_duration_seconds_bucket{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices",
  le="0.5"
}[5m]))

# Total requests
sum(rate(request_duration_seconds_count{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices"
}[5m]))

# Latency success rate = fast_requests / total_requests
```

**Why**:
- 500ms is a common threshold for REST APIs
- Users notice delays > 500ms
- Critical for user experience

**SLO Target**: 95% requests < 500ms (30-day), 90% requests < 500ms (7-day)

**Example**:
- 1000 requests/minute
- 50 requests > 500ms
- Latency success rate = 95% ✅ (meets SLO)

### 3. Error Rate SLI

**What**: Ratio of successful requests (non-4xx/5xx) to total requests

**How**: PromQL query
```promql
# Error rate (4xx + 5xx)
sum(rate(request_duration_seconds_count{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices",
  code=~"4..|5.."
}[5m]))

# Total requests
sum(rate(request_duration_seconds_count{
  app="<service>",
  namespace="<namespace>",
  job=~"microservices"
}[5m]))

# Success rate = 1 - (error_rate / total_rate)
```

**Why**:
- Includes both client errors (4xx) and server errors (5xx)
- Measures overall request quality
- Important for API reliability

**SLO Target**: 99% success rate (30-day), 98% success rate (7-day)

**Example**:
- 1000 requests/minute
- 10 requests return errors (4xx or 5xx)
- Success rate = 99% ✅ (meets SLO)

## SLI Selection Criteria

### For HTTP APIs (Recommended)

1. **Availability** (5xx errors)
   - Best for: Server reliability
   - Excludes: Client errors (4xx)
   - Use case: Infrastructure monitoring

2. **Latency** (p95 < threshold)
   - Best for: User experience
   - Threshold: 500ms for REST APIs
   - Use case: Performance monitoring

3. **Error Rate** (4xx + 5xx)
   - Best for: Overall quality
   - Includes: Both client and server errors
   - Use case: End-to-end reliability

## Metric Labels

All queries use these labels:

- `app`: Service name (e.g., "auth")
- `namespace`: Kubernetes namespace (e.g., "auth")
- `job`: Prometheus job name (must be "microservices")
- `code`: HTTP status code (e.g., "200", "404", "500")
- `method`: HTTP method (e.g., "GET", "POST")
- `path`: Request path (e.g., "/api/users")

## Time Windows

- **5m**: Short-term SLI (real-time monitoring)
- **30m**: Medium-term SLI (trend analysis)
- **7d**: Short-term SLO window (weekly review)
- **30d**: Long-term SLO window (monthly review)

## Best Practices

1. **Start with historical data**: Analyze past performance before setting SLOs
2. **Set achievable targets**: SLOs should be challenging but realistic
3. **Review quarterly**: Adjust SLOs based on business needs and team capacity
4. **Use multiple SLIs**: Combine availability, latency, and error rate for comprehensive monitoring
5. **Filter by job**: Always include `job=~"microservices"` to avoid conflicts

## References

- [Google SRE Book - SLIs, SLOs, and SLAs](https://sre.google/sre-book/service-level-objectives/)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/naming/)

