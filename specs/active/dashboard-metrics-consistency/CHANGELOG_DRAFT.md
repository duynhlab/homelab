# DRAFT CHANGELOG Entry for v0.7.3

> **Status**: DRAFT - To be added to CHANGELOG.md after successful user testing  
> **Date**: 2025-12-13  
> **Version**: v0.7.3

---

## [0.7.3] - 2025-12-13

### Fixed

**Dashboard Metrics Consistency:**
- Fixed metrics inconsistencies in main Grafana dashboard for accurate operational monitoring
- **Issue**: Status Code Distribution showed cumulative counts, Apdex score had division-by-zero issues, 4xx/5xx errors combined
- **Solution**: Standardized all metrics to rate-based queries, added defensive handling, separated error categories

**Query Changes:**
1. **Status Code Distribution** (Panel ID: 9)
   - **Before**: `sum(request_duration_seconds_count{...}) by (code)` (cumulative counter)
   - **After**: `sum(rate(request_duration_seconds_count{...}[$rate])) by (code)` (req/sec)
   - **Impact**: Now shows real-time traffic distribution instead of ever-increasing totals
   - **Panel Description**: Updated to clarify "req/sec" and "real-time traffic breakdown"

2. **Apdex Score** (Panel ID: 6)
   - **Before**: Division without zero-traffic handling → returned NaN
   - **After**: Simplified formula with `0.5 *` multiplier + defensive division: `/ (total > 0 or vector(1))`
   - **Impact**: Handles zero traffic gracefully (returns 0.0 instead of NaN)
   - **Panel Description**: Enhanced with formula explanation and edge case handling

3. **Error Rate Panels** (New Panels 201, 202)
   - **Added**: "Client Errors (4xx)" panel
     - Query: `sum(rate(request_duration_seconds_count{code=~"4.."}[$rate])) by (app)`
     - Thresholds: Green → Yellow (1 req/s) → Orange (5 req/s)
     - Description: Client-side errors (400-499) with actionable guidance
   - **Added**: "Server Errors (5xx)" panel
     - Query: `sum(rate(request_duration_seconds_count{code=~"5.."}[$rate])) by (app)`
     - Thresholds: Green → Orange (0.5 req/s) → Red (2 req/s)
     - Description: Server-side errors (500-599) requiring immediate investigation
   - **Impact**: Clear separation of client vs server errors for faster debugging

**Dashboard Layout:**
- Adjusted all panels from y=52 onwards by +8 to accommodate new 4xx/5xx panels
- 15+ panels repositioned (no overlaps, maintained logical flow)
- New panels placed in "⚠️ Errors & Performance" row at y=52 (side-by-side)

**Files Changed:**
- `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - 3 query modifications
  - 2 new panels added (IDs: 201, 202)
  - 15+ panel positions adjusted
  - JSON validated (67KB, within Grafana limits)

### Benefits

1. **Operational Accuracy**
   - Status Code Distribution now shows req/sec (industry standard, SRE-friendly)
   - Apdex Score robust against zero traffic (no NaN errors)
   - All metrics use consistent `rate()` function

2. **Error Visibility**
   - Separate 4xx/5xx panels enable faster root cause analysis
   - Client errors (4xx): API misuse, auth issues, invalid requests
   - Server errors (5xx): Service degradation, bugs, infrastructure issues

3. **SRE Best Practices**
   - Rate-based metrics (Google SRE, Prometheus documentation)
   - Defensive queries handle edge cases gracefully
   - Comprehensive panel descriptions with actionable guidance

### Testing

- ✅ JSON syntax validated
- ✅ Panel IDs unique (no conflicts)
- ✅ No overlapping gridPos coordinates
- ✅ 7 edge case scenarios tested (zero traffic, all success, all failure, mixed, variables, time ranges, rate intervals)
- ✅ Query performance < 1s (tested with 9 services)

### Technical Details

**Apdex Formula (New)**:
```promql
(
  sum(rate(request_duration_seconds_bucket{le="0.5"}[$rate]))
  + 0.5 * (
      sum(rate(request_duration_seconds_bucket{le="2"}[$rate]))
      - sum(rate(request_duration_seconds_bucket{le="0.5"}[$rate]))
    )
) 
/ 
(sum(rate(request_duration_seconds_count{...}[$rate])) > 0 or vector(1))
```

**Key Improvements**:
- Cleaner `0.5 *` multiplier (was `/ 2`)
- Defensive division: `(... > 0 or vector(1))` prevents NaN
- Returns 0.0 for zero-traffic services (correct behavior)

**Error Query Patterns**:
- 4xx: `code=~"4.."` (matches 400-499)
- 5xx: `code=~"5.."` (matches 500-599)
- Rate-based: `rate(...)[$rate]` for per-second values
- Service-level: `by (app)` grouping

### Migration Notes

**No Breaking Changes**: Dashboard-only modifications, zero downtime

**Deployment**:
```bash
./scripts/09-reload-dashboard.sh
```

**Rollback** (if needed):
```bash
# Restore from backup
cd k8s/grafana-operator/dashboards
cp microservices-dashboard.json.backup-* microservices-dashboard.json
./scripts/09-reload-dashboard.sh
```

**Verification**:
1. Dashboard loads: http://localhost:3000
2. All panels render correctly
3. New 4xx/5xx panels visible in "⚠️ Errors & Performance" row
4. Apdex score shows 0.0-1.0 range (no NaN)
5. Status Code Distribution shows req/sec values

### References

- **Specification**: `specs/active/dashboard-metrics-consistency/spec.md`
- **Research**: `specs/active/dashboard-metrics-consistency/research.md`
- **Implementation Plan**: `specs/active/dashboard-metrics-consistency/plan.md`
- **Task Breakdown**: `specs/active/dashboard-metrics-consistency/tasks.md`
- **Todo List**: `specs/active/dashboard-metrics-consistency/todo-list.md`
- **Implementation Summary**: `specs/active/dashboard-metrics-consistency/IMPLEMENTATION_SUMMARY.md`

**Industry Standards Referenced**:
- Google SRE Workbook: Rate-based metrics for operational dashboards
- Prometheus Best Practices: Using `rate()` for counters
- Grafana Documentation: Defensive PromQL queries
- Apdex Specification: T=0.5s (satisfying), 4T=2s (tolerating)

---

**Implementation Time**: 1 hour 54 minutes (AI phase) + 2 hours (user testing phase)  
**Total Tasks**: 15 (8 AI automated, 7 user validation)  
**Files Modified**: 1 (dashboard JSON)  
**Panel Count**: 34 (was 32, added 2 new error panels)  
**Dashboard Size**: 67KB (within Grafana 10MB limit)


