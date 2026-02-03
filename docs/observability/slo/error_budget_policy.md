# Error Budget Policy

## Overview

Error budget is the acceptable amount of failure for a service. It's the difference between 100% and the SLO target.

## Error Budget Calculation

### Formula

```
Error Budget = 1 - SLO Target
```

### Examples

| SLO Target | Error Budget | 30-day Budget | 7-day Budget |
|------------|--------------|---------------|--------------|
| 99.5% | 0.5% | 3.6 hours | 50.4 minutes |
| 95.0% | 5.0% | 36 hours | 5.04 hours |
| 99.0% | 1.0% | 7.2 hours | 1.68 hours |

### 30-Day Budget Example

For 99.5% availability target:
- **Total time**: 30 days = 720 hours
- **Error budget**: 0.5% = 3.6 hours
- **Meaning**: Service can be down 3.6 hours/month without violating SLO

## Budget Consumption

### Burn Rate

Burn rate measures how fast error budget is consumed:

```
burn_rate = actual_error_rate / target_error_rate
```

**Examples**:
- **1x**: Consuming at target rate (budget exhausted in 30 days) ✅
- **2x**: Consuming 2x faster (budget exhausted in 15 days) ⚠️
- **4x**: Consuming 4x faster (budget exhausted in 7 days) 🔴
- **15x**: Consuming 15x faster (budget exhausted in 2 days) 🚨

### Time to Exhaustion

Time until error budget is fully consumed:

```
time_to_exhaustion = remaining_budget / (burn_rate * target_error_rate)
```

## Deployment Gates

Deployment decisions based on error budget:

### Budget > 50%

**Status**: ✅ Healthy

**Actions**:
- Normal deployments allowed
- Feature development continues
- No restrictions

**Example**: 60% budget remaining = 2.16 hours/month

### Budget 20-50%

**Status**: ⚠️ Warning

**Actions**:
- Deployments require approval
- Review recent changes
- Monitor closely
- Consider pausing risky features

**Example**: 30% budget remaining = 1.08 hours/month

### Budget < 20%

**Status**: 🔴 Critical

**Actions**:
- Deployments paused
- Focus on stability
- Investigate root causes
- Fix existing issues first

**Example**: 15% budget remaining = 32.4 minutes/month

### Budget < 10%

**Status**: 🚨 Emergency

**Actions**:
- All deployments blocked
- Emergency response mode
- Immediate investigation
- Rollback if needed

**Example**: 5% budget remaining = 10.8 minutes/month

## Budget Tracking

### Current Budget Status

Query error budget remaining:

```promql
# Error budget remaining (0-1 scale)
slo:error_budget_remaining:ratio{service="auth"}

# Error budget remaining (percentage)
slo:error_budget_remaining:ratio{service="auth"} * 100
```

### Burn Rate Monitoring

Query burn rate:

```promql
# Current burn rate
slo:error_budget_burn_rate:ratio{service="auth"}

# Time to exhaustion (hours)
slo:time_to_exhaustion_hours{service="auth"}
```

## Budget Consumption by Team

### Tracking

Track budget consumption by team/service:

```promql
# Budget consumed by service
1 - slo:error_budget_remaining:ratio{service="auth"}

# Budget consumed percentage
(1 - slo:error_budget_remaining:ratio{service="auth"}) * 100
```

### Reporting

Monthly reports should include:
- Budget consumed per service
- Budget remaining per service
- Top consumers of budget
- Trends over time

## Budget-Based Feature Velocity

### Concept

Use error budget to balance:
- **Feature velocity**: Speed of new features
- **Reliability**: Service stability

### Decision Matrix

| Budget | Feature Velocity | Reliability Focus |
|--------|------------------|-------------------|
| > 50% | High | Maintain |
| 20-50% | Medium | Improve |
| < 20% | Low | Stabilize |
| < 10% | None | Emergency |


## References

- [Google SRE Book - Error Budgets](https://sre.google/sre-book/service-level-objectives/)
- [Error Budget Policy Template](https://sre.google/workbook/error-budget-policy/)

