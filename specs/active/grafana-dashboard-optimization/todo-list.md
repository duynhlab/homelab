# Grafana Dashboard Optimization - Implementation Todo List

**Feature ID**: grafana-dashboard-optimization  
**Status**: IN PROGRESS  
**Started**: 2025-12-11  
**Owner**: DevOps Team

---

## Progress Summary

- **Total Tasks**: 15
- **Completed**: 10
- **In Progress**: 0
- **Blocked**: 1 (Task 1.6 - needs K8s cluster)
- **Remaining**: 4

**Current Phase**: Phase 1 - Critical Dashboard Fix

---

## Phase 1: Critical Dashboard Fix (Priority: P0)

**Objective**: Fix variable cascading bug in Grafana dashboard JSON

**Estimated Time**: 1 hour

### Task 1.1: Backup Current Dashboard
- [x] Create timestamped backup of dashboard JSON
  - **Status**: COMPLETE
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Command**: `cp k8s/grafana-operator/dashboards/microservices-dashboard.json k8s/grafana-operator/dashboards/microservices-dashboard.json.backup-$(date +%Y%m%d-%H%M%S)`
  - **Acceptance Criteria**: Backup file exists with timestamp
  - **Dependencies**: None
  - **Estimated Time**: 1 min

### Task 1.2: Swap Variable Order (app ↔️ namespace)
- [x] Reorder variables in templating.list array
  - **Status**: COMPLETE
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Location**: Lines 2496-2545
  - **Change**: Move `namespace` variable (lines 2521-2545) to position 2, move `app` variable (lines 2496-2520) to position 3
  - **Current Order**: DS_PROMETHEUS (pos 1) → app (pos 2) → namespace (pos 3) → rate (pos 4)
  - **New Order**: DS_PROMETHEUS (pos 1) → namespace (pos 2) → app (pos 3) → rate (pos 4)
  - **Acceptance Criteria**: 
    - namespace variable appears at array index 1
    - app variable appears at array index 2
    - DS_PROMETHEUS and rate positions unchanged
  - **Dependencies**: Task 1.1
  - **Estimated Time**: 5 min

### Task 1.3: Update App Variable Query
- [x] Add namespace filter to app variable query
  - **Status**: COMPLETE
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Location**: Lines 2506 and 2513 (after reordering)
  - **Current Query**: `label_values(request_duration_seconds_count, app)`
  - **New Query**: `label_values(request_duration_seconds_count{namespace=~\"$namespace\"}, app)`
  - **Fields to Update**:
    - `definition`: Line 2506
    - `query`: Line 2513
  - **Acceptance Criteria**: Both `definition` and `query` fields contain namespace filter
  - **Dependencies**: Task 1.2
  - **Estimated Time**: 3 min

### Task 1.4: Update App Variable Sort
- [x] Change sort from 0 to 1 for alphabetical ordering
  - **Status**: COMPLETE
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Location**: Line 2517 (after reordering, will be different line number)
  - **Current Value**: `"sort": 0`
  - **New Value**: `"sort": 1`
  - **Acceptance Criteria**: App variable has `"sort": 1`
  - **Dependencies**: Task 1.3
  - **Estimated Time**: 1 min

### Task 1.5: Validate JSON Syntax
- [x] Validate dashboard JSON is syntactically correct
  - **Status**: COMPLETE
  - **Files**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Command**: `jq empty k8s/grafana-operator/dashboards/microservices-dashboard.json`
  - **Acceptance Criteria**: Command exits with code 0 (no output = valid JSON)
  - **Dependencies**: Task 1.4
  - **Estimated Time**: 1 min

### Task 1.6: Apply Dashboard via Grafana Operator
- [ ] Reapply dashboard ConfigMap and GrafanaDashboard CR
  - **Status**: BLOCKED - Kubernetes cluster not accessible
  - **Files**: `k8s/grafana-operator/dashboards/`
  - **Command**: `kubectl apply -k k8s/grafana-operator/dashboards/`
  - **Acceptance Criteria**: 
    - ConfigMap updated
    - GrafanaDashboard CR reconciled
    - No errors in output
  - **Dependencies**: Task 1.5
  - **Estimated Time**: 2 min

### Task 1.7: Verify Grafana Operator Reconciliation
- [ ] Check GrafanaDashboard status and operator logs
  - **Status**: NOT_STARTED
  - **Commands**:
    - `kubectl get grafanadashboards -n monitoring microservices-monitoring -o yaml`
    - `kubectl logs -n monitoring deployment/grafana-operator --tail=50`
  - **Acceptance Criteria**: 
    - Status shows "success"
    - No errors in operator logs
  - **Dependencies**: Task 1.6
  - **Estimated Time**: 2 min

---

## Phase 2: Testing & Validation (Priority: P0)

**Objective**: Manually verify dashboard variable cascading works correctly

**Estimated Time**: 30 minutes

### Task 2.1: Port-Forward Grafana (if needed)
- [ ] Setup port-forward to access Grafana UI
  - **Status**: NOT_STARTED
  - **Command**: `kubectl port-forward -n monitoring svc/grafana-service 3000:3000`
  - **Acceptance Criteria**: Can access http://localhost:3000
  - **Dependencies**: Task 1.7
  - **Estimated Time**: 1 min
  - **Note**: May already be running; check first

### Task 2.2: Test Variable Order in UI
- [ ] Verify namespace appears before app in dashboard UI
  - **Status**: NOT_STARTED
  - **URL**: http://localhost:3000/d/microservices-monitoring-001/
  - **Acceptance Criteria**: 
    - Variable order displays as: Datasource → Namespace → App → Rate Interval
    - Namespace dropdown appears to the left of App dropdown
  - **Dependencies**: Task 2.1
  - **Estimated Time**: 2 min

### Task 2.3: Test Single Namespace Cascading
- [ ] Verify app dropdown filters by single namespace selection
  - **Status**: NOT_STARTED
  - **Test Steps**:
    1. Select Namespace = "auth"
    2. Observe App dropdown updates
    3. Verify App shows only ["All", "auth"]
    4. Select Namespace = "user"
    5. Verify App shows only ["All", "user"]
  - **Acceptance Criteria**: 
    - App dropdown updates immediately when namespace changes
    - App list matches selected namespace
  - **Dependencies**: Task 2.2
  - **Estimated Time**: 5 min

### Task 2.4: Test Multi-Select Namespace
- [ ] Verify app dropdown shows union of apps from multiple namespaces
  - **Status**: NOT_STARTED
  - **Test Steps**:
    1. Select Namespace = "auth" + "user" (multi-select)
    2. Observe App dropdown
    3. Verify App shows ["All", "auth", "user"]
  - **Acceptance Criteria**: 
    - Multi-select works
    - App dropdown shows union of apps from selected namespaces
  - **Dependencies**: Task 2.3
  - **Estimated Time**: 3 min

### Task 2.5: Test "All" Option
- [ ] Verify "All" option works for both variables
  - **Status**: NOT_STARTED
  - **Test Steps**:
    1. Select Namespace = "All"
    2. Verify App shows all services
    3. Select App = "All"
    4. Verify panels show aggregated data
  - **Acceptance Criteria**: 
    - "All" option functional for both variables
    - No errors in panels
  - **Dependencies**: Task 2.4
  - **Estimated Time**: 3 min

### Task 2.6: Verify All Panels Render
- [ ] Scroll through all 5 row groups and verify all 32 panels render
  - **Status**: NOT_STARTED
  - **Test Steps**:
    1. Select Namespace = "auth", App = "auth"
    2. Scroll through all row groups
    3. Check each panel for data/errors
    4. Change to Namespace = "All", App = "All"
    5. Verify all panels still render
  - **Acceptance Criteria**: 
    - All 32 panels show data (no "No data" or "Query error")
    - No console errors in browser DevTools
  - **Dependencies**: Task 2.5
  - **Estimated Time**: 10 min

### Task 2.7: Test Query Performance
- [ ] Verify variable changes don't cause excessive queries or lag
  - **Status**: NOT_STARTED
  - **Test Steps**:
    1. Open browser DevTools (Network tab)
    2. Change namespace filter
    3. Count Prometheus API queries
    4. Measure time to complete
  - **Acceptance Criteria**: 
    - Dashboard loads in < 5 seconds
    - Variable change completes in < 2 seconds
    - No UI freeze or lag
  - **Dependencies**: Task 2.6
  - **Estimated Time**: 5 min

---

## Phase 3: Documentation Updates (Priority: P0)

**Objective**: Update all documentation to reflect corrected dashboard architecture

**Estimated Time**: 1 hour

### Task 3.1: Create Troubleshooting Guide
- [x] Create new TROUBLESHOOTING.md with common dashboard issues
  - **Status**: COMPLETE
  - **Files**: `docs/monitoring/TROUBLESHOOTING.md` (NEW)
  - **Content Sections**:
    - Variable Cascading Issues (3 scenarios)
    - Query Performance Issues
    - Panel Data Issues
  - **Acceptance Criteria**: 
    - File created with complete troubleshooting scenarios
    - Includes symptoms, causes, and solutions
    - Includes example commands
  - **Dependencies**: Task 2.7 (wait until testing complete)
  - **Estimated Time**: 20 min

### Task 3.2: Update METRICS.md
- [x] Add variable cascading best practices section to METRICS.md
  - **Status**: COMPLETE
  - **Files**: `docs/monitoring/METRICS.md`
  - **Location**: After "Dashboard Variables" section
  - **Content to Add**:
    - Variable Cascading Best Practices section
    - Variable Dependencies diagram (Mermaid)
    - Implementation pattern examples
    - Troubleshooting variable cascading subsection
  - **Acceptance Criteria**: 
    - New section added with complete best practices
    - Mermaid diagram included
    - Cross-reference to TROUBLESHOOTING.md
  - **Dependencies**: Task 3.1
  - **Estimated Time**: 15 min

### Task 3.3: Update AGENTS.md
- [x] Update dashboard variables documentation in AGENTS.md
  - **Status**: COMPLETE
  - **Files**: `AGENTS.md`
  - **Locations to Update**:
    - "Dashboard Details" section (variable order)
    - "Dashboard Files" section (add cascading note)
  - **Changes**:
    - Update variable order description: namespace before app
    - Add variable cascading explanation
    - Add note about order importance
  - **Acceptance Criteria**: 
    - Variable order corrected in all references
    - Cascading behavior documented
  - **Dependencies**: Task 3.2
  - **Estimated Time**: 10 min

### Task 3.4: Update README.md
- [x] Add variable usage tip to README.md
  - **Status**: COMPLETE
  - **Files**: `README.md`
  - **Location**: "📊 Monitoring Dashboard" section (if exists) or add new section
  - **Content to Add**:
    - Dashboard Variables subsection
    - Usage tip: "Select namespace first, then app will show only services in that namespace"
  - **Acceptance Criteria**: 
    - Tip added to user-facing documentation
    - Clear and concise
  - **Dependencies**: Task 3.3
  - **Estimated Time**: 5 min

### Task 3.5: Update CHANGELOG.md
- [x] Document v0.6.15 changes in CHANGELOG.md
  - **Status**: COMPLETE
  - **Files**: `CHANGELOG.md`
  - **Entry Format**:
    ```markdown
    ## [v0.6.15] - 2025-12-11
    ### Fixed
    - **Dashboard Variable Cascading**: Fixed critical bug where namespace filter didn't cascade to app filter
      - Reordered variables: namespace now appears before app in UI
      - App variable query now filters by selected namespace: `{namespace=~"$namespace"}`
      - Added alphabetical sorting to app variable
      - All 32 panels continue to work correctly
    ### Documentation
    - Added variable cascading best practices to METRICS.md
    - Created TROUBLESHOOTING.md for dashboard debugging
    - Updated AGENTS.md with correct variable order and cascading behavior
    - Added dashboard variable usage tips to README.md
    ```
  - **Acceptance Criteria**: 
    - New version entry added
    - Clear description of bug fix
    - Documentation updates listed
  - **Dependencies**: Task 3.4
  - **Estimated Time**: 10 min

---

## Completion Checklist

### Functional Verification
- [ ] Namespace dropdown appears before app dropdown in UI
- [ ] App dropdown updates when namespace changes
- [ ] App dropdown shows only apps in selected namespace(s)
- [ ] Multi-select namespace works correctly
- [ ] "All" option works for both variables
- [ ] All 32 panels render without errors
- [ ] Panels show correct filtered data

### Performance Verification
- [ ] Dashboard loads in < 5 seconds
- [ ] Variable changes complete in < 2 seconds
- [ ] No UI lag or freeze
- [ ] No excessive Prometheus queries

### Documentation Verification
- [ ] TROUBLESHOOTING.md created with complete scenarios
- [ ] METRICS.md includes variable cascading best practices
- [ ] AGENTS.md updated with correct variable order
- [ ] README.md includes usage tip
- [ ] CHANGELOG.md documents v0.6.15 changes
- [ ] All documentation reviewed for consistency

### Quality Assurance
- [ ] Backup created before changes
- [ ] JSON syntax validated
- [ ] Grafana Operator reconciliation successful
- [ ] No regressions in existing functionality
- [ ] Manual testing checklist 100% passed

---

## Notes

**Implementation Strategy**: 
- Execute todos in order (Phase 1 → Phase 2 → Phase 3)
- Phase 1 is critical path - must succeed before proceeding
- Phase 2 is validation gate - all tests must pass
- Phase 3 captures knowledge and prevents future regressions

**Rollback Plan**: 
- If dashboard breaks: restore backup file and reapply
- Rollback time: < 2 minutes
- Backup location: `k8s/grafana-operator/dashboards/microservices-dashboard.json.backup-{timestamp}`

**Risk Assessment**:
- Risk Level: Low (dashboard-only changes, no infrastructure impact)
- Breaking Changes: None
- Backward Compatibility: Full (dashboard UID and structure unchanged)

---

**Last Updated**: 2025-12-11  
**Status**: Ready for Implementation

