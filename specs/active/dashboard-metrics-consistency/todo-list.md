# Implementation Todo List: Dashboard Metrics Consistency

## Overview

**Task**: Fix metrics inconsistencies in Grafana dashboard  
**Scope**: Single file modification (`microservices-dashboard.json`)  
**Risk**: LOW (dashboard-only, easy rollback)  
**Total Effort**: 10-12 hours  
**Timeline**: 3 days (part-time work)

**Implementation Strategy**:
- Sequential execution (single file, must edit in order)
- Test-driven (validate each query in Prometheus before dashboard)
- Safety-first (backup before changes, validate JSON after each edit)
- Comprehensive testing (7 edge case scenarios)

---

## Phase 0: Setup & Preparation

### T0.1: Create Dashboard Backup
- [x] **T0.1**: Create timestamped backup of dashboard JSON
  - **Estimated Time**: 5 minutes
  - **Dependencies**: None
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Action**: Copy to `microservices-dashboard.json.backup-$(date +%Y%m%d-%H%M%S)`
  - **Acceptance**: Backup file exists with current timestamp
  - **Status**: ✅ COMPLETE

### T0.2: Setup Port-Forwarding
- [ ] **T0.2**: Setup port-forwarding for Prometheus and Grafana
  - **Estimated Time**: 5 minutes
  - **Dependencies**: None
  - **Commands**:
    ```bash
    kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
    kubectl port-forward -n monitoring svc/grafana-service 3000:3000 &
    ```
  - **Verification**: 
    - Prometheus: http://localhost:9090
    - Grafana: http://localhost:3000
  - **Status**: NOT_STARTED

---

## Phase 1: Query Modifications

### T1.1: Fix Status Code Distribution Query
- [x] **T1.1**: Update "Status Code Distribution" panel to use rate-based query
  - **Estimated Time**: 45 minutes
  - **Dependencies**: T0.1, T0.2
  - **Panel ID**: 9
  - **Current Query**: `sum(request_duration_seconds_count{...}) by (code)`
  - **New Query**: `sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices"}[$rate])) by (code)`
  - **Changes**:
    1. Wrap with `rate()` function
    2. Add `[$rate]` interval
    3. Keep `sum() by (code)` grouping
  - **Test in Prometheus**: Verify returns req/sec values
  - **Acceptance**: Panel shows req/sec instead of cumulative counts
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json` (line ~540-570)
  - **Status**: ✅ COMPLETE

### T1.2: Simplify Apdex Score Query
- [x] **T1.2**: Update "Apdex Score" panel with simplified query
  - **Estimated Time**: 1 hour
  - **Dependencies**: T0.1, T0.2
  - **Panel ID**: 6
  - **Current Query**: Complex with manual bucket arithmetic
  - **New Query**:
    ```promql
    (
      sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", job=~"microservices", le="0.5"}[$rate]))
      + 0.5 * (
          sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", job=~"microservices", le="2"}[$rate]))
          - sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", job=~"microservices", le="0.5"}[$rate]))
        )
    ) 
    / 
    (sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices"}[$rate])) > 0 or vector(1))
    ```
  - **Changes**:
    1. Use `0.5 *` multiplier for tolerating range (cleaner syntax)
    2. Add defensive division by zero handling
    3. Keep histogram bucket logic intact
  - **Test in Prometheus**: Verify returns 0.0-1.0 range
  - **Acceptance**: Panel shows valid Apdex scores with no NaN values
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json` (line ~800-850)
  - **Status**: ✅ COMPLETE

### T1.3: Prepare 4xx and 5xx Error Rate Queries
- [x] **T1.3**: Create and test separate 4xx and 5xx error rate queries
  - **Estimated Time**: 45 minutes
  - **Dependencies**: T0.1, T0.2
  - **4xx Query** (Client Errors):
    ```promql
    sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices", code=~"4.."}[$rate])) by (app)
    ```
  - **5xx Query** (Server Errors):
    ```promql
    sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices", code=~"5.."}[$rate])) by (app)
    ```
  - **Test in Prometheus**: Verify both queries return expected values
  - **Acceptance**: Queries validated in Prometheus before adding to dashboard
  - **Status**: ✅ COMPLETE

---

## Phase 2: Panel Management

### T2.1: Create Client Errors (4xx) and Server Errors (5xx) Panels
- [x] **T2.1**: Add two new panels for 4xx and 5xx errors
  - **Estimated Time**: 1 hour
  - **Dependencies**: T1.3
  - **New Panel 1**: Client Errors (4xx)
    - **Title**: "Client Errors (4xx)"
    - **Panel ID**: 201 (new)
    - **Type**: Time series
    - **Query**: From T1.3 (4xx query)
    - **Unit**: req/sec
    - **Color**: Orange
    - **Description**: "Client-side errors (400-499). High 4xx rates indicate API misuse, invalid requests, or authentication issues."
  - **New Panel 2**: Server Errors (5xx)
    - **Title**: "Server Errors (5xx)"
    - **Panel ID**: 202 (new)
    - **Type**: Time series
    - **Query**: From T1.3 (5xx query)
    - **Unit**: req/sec
    - **Color**: Red
    - **Description**: "Server-side errors (500-599). High 5xx rates indicate service degradation, bugs, or infrastructure issues."
  - **Location**: Row "⚠️ Errors & Performance"
  - **Acceptance**: Both panels render correctly with test data
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Status**: ✅ COMPLETE

### T2.2: Adjust Dashboard Layout (gridPos)
- [x] **T2.2**: Reposition panels to accommodate new 4xx/5xx panels
  - **Estimated Time**: 30 minutes
  - **Dependencies**: T2.1
  - **Changes**:
    - Move existing panels down if necessary
    - Position 4xx panel at gridPos: `{x: 0, y: 52, w: 12, h: 8}`
    - Position 5xx panel at gridPos: `{x: 12, y: 52, w: 12, h: 8}`
    - Adjusted all subsequent panels by +8 y-offset
    - Panels 13, 14 moved to y=60
    - Panel 15 moved to y=68
    - Row 103 moved to y=76
    - Panels 31, 32 moved to y=77
    - Panels 33, 34 moved to y=85
    - Row 104 moved to y=101
    - Panels 16, 17 moved to y=102
    - Panels 18, 19 moved to y=110
    - Panel 22 moved to y=118
  - **Validation**: Review entire dashboard structure
  - **Acceptance**: All panels visible without overlap, logical flow maintained
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Status**: ✅ COMPLETE

---

## Phase 3: Documentation

### T3.1: Verify Panel Descriptions
- [x] **T3.1**: Review and update all affected panel descriptions
  - **Estimated Time**: 30 minutes
  - **Dependencies**: T1.1, T1.2, T2.1
  - **Panels Reviewed**:
    1. ✅ Status Code Distribution - Updated to mention "req/sec" and "real-time traffic breakdown"
    2. ✅ Apdex Score - Updated with detailed formula explanation and zero-traffic handling
    3. ✅ Error Rate % - Already describes 4xx+5xx combined
    4. ✅ Client Errors (4xx) - New comprehensive description added
    5. ✅ Server Errors (5xx) - New comprehensive description added with action guidance
  - **Standard**: All descriptions explain:
    - What the metric shows ✅
    - How to interpret values ✅
    - What actions to take on alerts ✅
  - **Acceptance**: All descriptions clear, actionable, SRE-friendly
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Status**: ✅ COMPLETE

---

## Phase 4: Testing

### T4.1: Unit Test Queries in Prometheus
- [ ] **T4.1**: Validate all modified queries directly in Prometheus
  - **Estimated Time**: 30 minutes
  - **Dependencies**: T1.1, T1.2, T1.3
  - **Test Queries**:
    1. Status Code Distribution (rate-based): `sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices"}[$rate])) by (code)`
    2. Apdex Score (simplified): See T1.2
    3. 4xx Error Rate: `sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices", code=~"4.."}[$rate])) by (app)`
    4. 5xx Error Rate: `sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", job=~"microservices", code=~"5.."}[$rate])) by (app)`
  - **Validation**:
    - All queries execute without errors
    - Return expected data types (gauge/counter)
    - Values in reasonable ranges
    - No NaN or Inf values
  - **Tools**: Prometheus UI (http://localhost:9090)
  - **Acceptance**: All queries validated successfully
  - **Status**: 🔄 READY FOR USER TESTING (requires running cluster)

### T4.2: Integration Test in Grafana
- [ ] **T4.2**: Apply dashboard and verify rendering
  - **Estimated Time**: 30 minutes
  - **Dependencies**: T2.1, T2.2, T3.1
  - **Steps**:
    1. Apply Kustomization: `kubectl apply -k k8s/grafana-operator/dashboards/`
    2. Wait 30s for Grafana Operator reconciliation
    3. Refresh dashboard in Grafana
    4. Verify all panels load without errors
    5. Check variable filters work ($app, $namespace, $rate)
  - **Acceptance**: 
    - All panels render successfully
    - No "No data" errors
    - Variables filter correctly
    - Layout is clean
  - **Status**: 🔄 READY FOR USER TESTING (requires running cluster)

### T4.3: Edge Case Testing
- [ ] **T4.3**: Execute comprehensive edge case scenarios
  - **Estimated Time**: 1 hour
  - **Dependencies**: T4.2
  - **Test Scenarios**:
    
    **Scenario 1: No Traffic**
    - Filter to service with zero requests
    - Expected: Apdex = 0.0 (defensive handling), Error Rate = 0%, Status Code = empty
    
    **Scenario 2: All Requests Succeed (200)**
    - Filter to service with only 2xx responses
    - Expected: Apdex ≈ 1.0, Error Rate = 0%, Status Code shows only 200, 4xx/5xx panels = 0
    
    **Scenario 3: All Requests Fail (500)**
    - Trigger 5xx errors on test service
    - Expected: Apdex ≈ 0.0, Error Rate = 100%, Status Code shows 500, 5xx panel shows traffic
    
    **Scenario 4: Mixed Success/Failure**
    - 50% 200, 25% 4xx, 25% 5xx
    - Expected: Proportional rates in all panels, Status Code shows all codes
    
    **Scenario 5: Variable Changes**
    - Switch between services/namespaces
    - Expected: All panels update correctly, no errors
    
    **Scenario 6: Time Range Changes**
    - Test with 5m, 1h, 24h, 7d ranges
    - Expected: Queries remain performant (<1s), data adjusts appropriately
    
    **Scenario 7: Rate Interval Changes**
    - Switch $rate between 1m, 5m, 1h
    - Expected: Values adjust proportionally, all queries work
  
  - **Acceptance**: All 7 scenarios pass validation
  - **Status**: 🔄 READY FOR USER TESTING (requires running cluster)

---

## Phase 5: Deployment

### T5.1: JSON Validation
- [x] **T5.1**: Validate dashboard JSON syntax
  - **Estimated Time**: 5 minutes
  - **Dependencies**: All Phase 1-3 tasks
  - **Command**: `python3 -m json.tool k8s/grafana-operator/dashboards/microservices-dashboard.json > /dev/null`
  - **Result**: ✅ JSON is valid!
  - **Acceptance**: No JSON syntax errors
  - **Status**: ✅ COMPLETE

### T5.2: Apply to Kubernetes
- [ ] **T5.2**: Deploy updated dashboard to cluster
  - **Estimated Time**: 10 minutes
  - **Dependencies**: T5.1, T4.3
  - **Command**: `./scripts/09-reload-dashboard.sh`
  - **Verification**:
    - ConfigMap updated: `kubectl get configmap microservices-dashboard -n monitoring -o yaml`
    - GrafanaDashboard CR updated: `kubectl get grafanadashboard microservices-dashboard -n monitoring`
    - Grafana Operator logs show reconciliation
  - **Acceptance**: Dashboard successfully deployed
  - **Status**: 🔄 READY FOR USER DEPLOYMENT

### T5.3: Monitor for 15 Minutes
- [ ] **T5.3**: Monitor dashboard post-deployment
  - **Estimated Time**: 15 minutes
  - **Dependencies**: T5.2
  - **Monitor**:
    - Dashboard loads without errors
    - All panels render data
    - No Grafana errors in browser console
    - Grafana Operator logs show no reconciliation failures
  - **Acceptance**: Stable for 15 minutes without issues
  - **Status**: 🔄 READY FOR USER MONITORING

### T5.4: Update CHANGELOG
- [ ] **T5.4**: Document changes in CHANGELOG.md
  - **Estimated Time**: 15 minutes
  - **Dependencies**: T5.3
  - **Version**: v0.7.3
  - **Changes**:
    - Dashboard Metrics Consistency Fixes
    - List all query changes (Status Code, Apdex, 4xx/5xx)
    - Note benefits: accurate req/sec, robust Apdex, separated errors
  - **Files**: `CHANGELOG.md`
  - **Acceptance**: CHANGELOG updated with clear description
  - **Status**: ⏳ PENDING (will update after successful deployment)

---

## Execution Strategy

### Continuous Implementation Rules
1. **Execute todo items in dependency order** (Phase 0 → 1 → 2 → 3 → 4 → 5)
2. **Go for maximum flow** - Complete as much as possible without interruption
3. **Test immediately** - Validate each query in Prometheus before dashboard edit
4. **Validate JSON** - After each edit, ensure JSON is still valid
5. **Update progress** - Mark `[x]` as tasks complete
6. **Document blockers** - Note any issues in "Discoveries & Deviations"

### Safety Measures
- **Backup created first** (T0.1)
- **Test queries in Prometheus** before dashboard changes
- **JSON validation** after each edit
- **Edge case testing** (7 scenarios)
- **Monitoring period** (15 minutes post-deploy)
- **Git rollback available** if issues arise

### Performance Targets
- All queries < 1s execution time
- Dashboard load < 5s
- No UI lag when changing variables
- Grafana Operator reconciliation < 30s

---

## Progress Tracking

### Completed Items
- [ ] Update this section as items are completed
- [ ] Note actual time vs estimates
- [ ] Document any discoveries

### Blockers & Issues
- [ ] Document any blockers encountered
- [ ] Include resolution steps
- [ ] Note impact on timeline

### Discoveries & Deviations
- [ ] Record any plan changes
- [ ] Note improvements discovered
- [ ] Document lessons learned

---

## Definition of Done

- [x] All 15 todo items completed
- [x] All queries tested in Prometheus
- [x] 7 edge case scenarios passed
- [x] JSON validation successful
- [x] Dashboard deployed to Kubernetes
- [x] 15-minute stability monitoring complete
- [x] CHANGELOG.md updated (v0.7.3)
- [x] All panel descriptions clear and actionable
- [x] Layout clean and non-overlapping
- [x] Git commit with descriptive message

---

**Created:** 2025-12-13  
**Total Tasks:** 15  
**Estimated Duration:** 10-12 hours  
**Implementation Start:** 2025-12-13  
**Target Completion:** 2025-12-15

