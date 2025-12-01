# SLO Targets per Service

## Overview

This document specifies SLO targets for all microservices. Targets are based on Google SRE recommendations and historical performance baselines.

## SLO Targets

All services have the same SLO targets for consistency:

| SLO Type | 30-day Target | 7-day Target | Rationale |
|----------|---------------|--------------|-----------|
| **Availability** | 99.5% | 99.0% | Allows 0.5% downtime (3.6 hours/month) |
| **Latency** | 95% < 500ms | 90% < 500ms | 5% of requests can be slower |
| **Error Rate** | 99% success | 98% success | 1% error rate acceptable |

## Per-Service Targets

### auth
- **Availability**: 99.5% (critical for authentication)
- **Latency**: 95% < 500ms (auth should be fast)
- **Error Rate**: 99% success

### user
- **Availability**: 99.5%
- **Latency**: 95% < 500ms
- **Error Rate**: 99% success

### product
- **Availability**: 99.5%
- **Latency**: 95% < 500ms (read-heavy, should be fast)
- **Error Rate**: 99% success

### cart
- **Availability**: 99.5%
- **Latency**: 95% < 500ms
- **Error Rate**: 99% success

### order
- **Availability**: 99.5% (critical for business)
- **Latency**: 95% < 500ms
- **Error Rate**: 99% success

### review
- **Availability**: 99.5%
- **Latency**: 95% < 500ms
- **Error Rate**: 99% success

### notification
- **Availability**: 99.5%
- **Latency**: 95% < 500ms (can tolerate slightly higher latency)
- **Error Rate**: 99% success

### shipping
- **Availability**: 99.5%
- **Latency**: 95% < 500ms
- **Error Rate**: 99% success

### shipping-v2
- **Availability**: 99.5%
- **Latency**: 95% < 500ms
- **Error Rate**: 99% success

## Rationale

### Why 99.5% Availability?

- **Industry standard**: Common target for production APIs
- **Error budget**: Allows 0.5% downtime (14.4 hours/month)
- **Achievable**: Realistic for well-maintained services
- **Business impact**: Minimal user impact at this level

### Why 500ms Latency Threshold?

- **User experience**: Users notice delays > 500ms
- **REST API best practice**: Common threshold for APIs
- **Realistic**: Achievable for most endpoints
- **Business impact**: Fast responses improve user satisfaction

### Why 99% Success Rate?

- **Quality standard**: 1% error rate is acceptable
- **Includes 4xx**: Client errors are part of overall quality
- **Realistic**: Accounts for validation errors, edge cases
- **Business impact**: 99% success is excellent for APIs

## Historical Baseline

To establish baseline, monitor services for 1-2 weeks and analyze:

```promql
# Current availability (30-day)
1 - (
  sum(rate(request_duration_seconds_count{app="auth", code=~"5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count{app="auth"}[30d]))
)

# Current latency success rate (30-day)
sum(rate(request_duration_seconds_bucket{app="auth", le="0.5"}[30d]))
/
sum(rate(request_duration_seconds_count{app="auth"}[30d]))

# Current error rate (30-day)
1 - (
  sum(rate(request_duration_seconds_count{app="auth", code=~"4..|5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count{app="auth"}[30d]))
)
```

## Adjusting Targets

If current performance is significantly different from targets:

1. **Analyze historical data**: Check 30-day trends
2. **Identify bottlenecks**: Slow endpoints, high error rates
3. **Optimize**: Improve performance before adjusting targets
4. **Set realistic targets**: Based on achievable performance
5. **Document rationale**: Explain why targets were adjusted

## Review Process

SLO targets should be reviewed:

- **Quarterly**: Regular review based on performance
- **After major changes**: New features, infrastructure changes
- **When targets are consistently missed**: May need adjustment
- **When targets are too easy**: May need to increase ambition

## References

- [Google SRE Book - Choosing SLO Targets](https://sre.google/sre-book/service-level-objectives/)
- [SLO Best Practices](https://sre.google/workbook/slo-document/)

