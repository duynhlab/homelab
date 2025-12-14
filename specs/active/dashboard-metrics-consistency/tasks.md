# Task Breakdown: Dashboard Metrics Consistency

> **Status**: Ready for Implementation  
> **Created**: 2025-12-13  
> **Specification**: [spec.md](./spec.md)  
> **Plan**: [plan.md](./plan.md)  
> **Total Effort**: 10-12 hours (3 days, 3-4 hours/day)

---

## Table of Contents

1. [Task Summary](#task-summary)
2. [Phase 0: Setup & Preparation](#phase-0-setup--preparation)
3. [Phase 1: Query Modifications](#phase-1-query-modifications)
4. [Phase 2: Panel Management](#phase-2-panel-management)
5. [Phase 3: Documentation](#phase-3-documentation)
6. [Phase 4: Testing](#phase-4-testing)
7. [Phase 5: Deployment](#phase-5-deployment)
8. [Progress Tracking](#progress-tracking)
9. [Risk & Blockers](#risk--blockers)

---

## Task Summary

### Overview

**Total Tasks**: 15  
**Estimated Effort**: 10-12 hours  
**Timeline**: 3 days (part-time work)  
**Risk Level**: LOW (dashboard-only, easy rollback)

### By Phase

| Phase | Tasks | Effort | Status |
|-------|-------|--------|--------|
| Phase 0: Setup | 2 | 1 hour | ⬜ Not Started |
| Phase 1: Query Modifications | 3 | 3 hours | ⬜ Not Started |
| Phase 2: Panel Management | 2 | 2 hours | ⬜ Not Started |
| Phase 3: Documentation | 1 | 1 hour | ⬜ Not Started |
| Phase 4: Testing | 3 | 2 hours | ⬜ Not Started |
| Phase 5: Deployment | 4 | 2 hours | ⬜ Not Started |
| **Total** | **15** | **11 hours** | **0% Complete** |

### By Priority

| Priority | Count | Description |
|----------|-------|-------------|
| P0 (Critical) | 8 | Core functionality, must complete |
| P1 (High) | 5 | Important, should complete |
| P2 (Medium) | 2 | Nice to have, can defer |

### Critical Path

```
Setup (0.1, 0.2) 
  → Query Fixes (1.1, 1.2, 1.3) 
  → Panel Split (2.1, 2.2) 
  → Descriptions (3.1) 
  → Testing (4.1, 4.2, 4.3) 
  → Deployment (5.1, 5.2, 5.3, 5.4)
```

**Estimated Timeline**: 3 days if worked sequentially, 3-4 hours per day

---

## Phase 0: Setup & Preparation

**Goal**: Prepare environment and create safety backups before modifications  
**Duration**: 1 hour  
**Parallelizable**: No (sequential setup)

---

### Task 0.1: Backup Dashboard and Validate Environment

**ID**: `T0.1`  
**Priority**: P0 (Critical)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Create backups of current dashboard and validate environment is ready for modifications.

**Acceptance Criteria**:
- [ ] Dashboard JSON backed up with timestamp: `microservices-dashboard.json.YYYYMMDD-HHMMSS`
- [ ] Git repository is clean (no uncommitted changes)
- [ ] kubectl access to monitoring namespace verified
- [ ] Grafana Operator is running and healthy
- [ ] Current dashboard accessible at http://localhost:3000/d/microservices-monitoring-001/

**Steps**:
1. Navigate to dashboard directory:
   ```bash
   cd k8s/grafana-operator/dashboards/
   ```

2. Create timestamped backup:
   ```bash
   cp microservices-dashboard.json microservices-dashboard.json.$(date +%Y%m%d-%H%M%S)
   ```

3. Verify Git status:
   ```bash
   git status
   # Should show clean working tree
   ```

4. Check kubectl access:
   ```bash
   kubectl get pods -n monitoring
   # Should show Grafana Operator running
   ```

5. Verify Grafana Operator health:
   ```bash
   kubectl get grafanadashboards -n monitoring
   kubectl logs -n monitoring deployment/grafana-operator --tail=20
   ```

6. Test dashboard access:
   ```bash
   kubectl port-forward -n monitoring svc/grafana-service 3000:3000
   # Open http://localhost:3000/d/microservices-monitoring-001/
   ```

**Dependencies**: None

**Output**:
- Backup file: `microservices-dashboard.json.YYYYMMDD-HHMMSS`
- Environment validated and ready

---

### Task 0.2: Setup Testing Tools and Access

**ID**: `T0.2`  
**Priority**: P1 (High)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Setup port-forwarding for Prometheus and Grafana, prepare testing scripts.

**Acceptance Criteria**:
- [ ] Prometheus UI accessible at http://localhost:9090
- [ ] Grafana UI accessible at http://localhost:3000
- [ ] k6 load generator running and generating traffic
- [ ] Test queries prepared in text file for quick testing

**Steps**:
1. Port-forward Prometheus:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
   ```

2. Port-forward Grafana (if not already):
   ```bash
   kubectl port-forward -n monitoring svc/grafana-service 3000:3000 &
   ```

3. Verify k6 load generator:
   ```bash
   kubectl get pods -n k6
   kubectl logs -n k6 -l app=k6-scenarios --tail=10
   # Should show load test running
   ```

4. Create test queries file:
   ```bash
   cat > /tmp/test-queries.promql << 'EOF'
   # Status Code Distribution (New)
   sum by (code) (rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))
   
   # Apdex Score (New)
   (sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="0.5"}[5m])) + (sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="2"}[5m])) - sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="0.5"}[5m]))) * 0.5) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))
   
   # Client Errors 4xx (New)
   (sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices", code=~"4.."}[5m])) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))) * 100
   
   # Server Errors 5xx (New)
   (sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices", code=~"5.."}[5m])) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))) * 100
   EOF
   ```

**Dependencies**: Task 0.1

**Output**:
- Prometheus UI accessible
- Grafana UI accessible
- Test queries file ready

---

## Phase 1: Query Modifications

**Goal**: Update PromQL queries for Status Code Distribution, Apdex Score, and Error Rate panels  
**Duration**: 3 hours  
**Parallelizable**: No (single JSON file, sequential edits)

---

### Task 1.1: Fix Status Code Distribution Query (FR-001)

**ID**: `T1.1`  
**Priority**: P0 (Critical)  
**Effort**: 1 hour  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Convert Status Code Distribution panel from cumulative `sum()` to rate-based `sum(rate())`.

**Acceptance Criteria**:
- [ ] Query updated from `sum() by (code)` to `sum by (code) (rate()[$rate])`
- [ ] Query tested in Prometheus UI with real data
- [ ] Query execution time < 1 second
- [ ] Panel description updated to mention rate-based calculation
- [ ] JSON syntax validated

**Steps**:
1. Open dashboard JSON:
   ```bash
   code k8s/grafana-operator/dashboards/microservices-dashboard.json
   ```

2. Search for "Status Code Distribution" panel (~line 805)

3. Locate current query:
   ```json
   "expr": "sum(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\"}) by (code)"
   ```

4. Replace with new query:
   ```json
   "expr": "sum by (code) (rate(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\"}[$rate]))"
   ```

5. Update panel description (~line 807):
   ```json
   "description": "HTTP status code distribution over selected time window ($rate). Shows current traffic patterns, not cumulative since pod start. Expected: ~95% codes 2xx during normal operation."
   ```

6. Test query in Prometheus UI (http://localhost:9090):
   ```promql
   sum by (code) (rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))
   ```

7. Validate JSON syntax:
   ```bash
   jq . microservices-dashboard.json > /dev/null && echo "✅ Valid JSON" || echo "❌ Invalid JSON"
   ```

**Dependencies**: Task 0.1, Task 0.2

**Output**:
- Updated query in dashboard JSON
- Query tested and validated
- Panel description updated

**Reference**: See plan.md Phase 1 for detailed query explanation

---

### Task 1.2: Simplify Apdex Score Query (FR-002)

**ID**: `T1.2`  
**Priority**: P0 (Critical)  
**Effort**: 1.5 hours  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Simplify Apdex Score query with explicit formatting and multiplication by 0.5 for clarity.

**Acceptance Criteria**:
- [ ] Query reformatted with explicit line breaks (`\n`)
- [ ] Division by 2 changed to multiplication by 0.5
- [ ] Query tested in Prometheus UI
- [ ] Panel displays score 0.0-1.0 (not "No data")
- [ ] Zero traffic test passed (shows 0.0, not error)
- [ ] Color thresholds configured: Red (< 0.5), Yellow (0.5-0.7), Green (> 0.7)
- [ ] Panel description updated with Apdex formula

**Steps**:
1. Search for "Apdex Score" panel (~line 560)

2. Replace complex query with formatted version:
   ```json
   "expr": "(\n  sum(rate(request_duration_seconds_bucket{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\", le=\"0.5\"}[$rate]))\n  + \n  (\n    sum(rate(request_duration_seconds_bucket{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\", le=\"2\"}[$rate]))\n    - \n    sum(rate(request_duration_seconds_bucket{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\", le=\"0.5\"}[$rate]))\n  ) * 0.5\n)\n/\nsum(rate(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\"}[$rate]))"
   ```

3. Update panel description (~line 562):
   ```json
   "description": "User satisfaction score (0-1) based on Apdex standard. Satisfied: < 0.5s (100%), Tolerating: 0.5s-2s (50%), Frustrated: > 2s (0%). Green: > 0.7, Yellow: 0.5-0.7, Red: < 0.5."
   ```

4. Update color thresholds in fieldConfig:
   ```json
   "thresholds": {
     "mode": "absolute",
     "steps": [
       { "color": "red", "value": null },
       { "color": "yellow", "value": 0.5 },
       { "color": "green", "value": 0.7 }
     ]
   }
   ```

5. Test query in Prometheus UI:
   ```promql
   # Normal traffic
   (sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="0.5"}[5m])) + (sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="2"}[5m])) - sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="0.5"}[5m]))) * 0.5) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))
   ```

6. Test zero traffic scenario:
   ```bash
   # Stop k6
   kubectl scale deployment -n k6 k6-scenarios --replicas=0
   
   # Wait 10 minutes, test query again
   # Should return empty (Grafana shows 0.0)
   
   # Restart k6
   kubectl scale deployment -n k6 k6-scenarios --replicas=1
   ```

7. Validate JSON syntax:
   ```bash
   jq . microservices-dashboard.json > /dev/null && echo "✅ Valid JSON" || echo "❌ Invalid JSON"
   ```

**Dependencies**: Task 1.1

**Output**:
- Simplified Apdex query with clear formatting
- Color thresholds configured
- Zero traffic handling tested
- Panel description updated

**Reference**: See plan.md Phase 2 for Apdex formula breakdown

---

### Task 1.3: Split Error Rate Panel Queries (FR-003 Part 1)

**ID**: `T1.3`  
**Priority**: P0 (Critical)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Prepare queries for splitting combined Error Rate % into Client Errors (4xx) and Server Errors (5xx).

**Acceptance Criteria**:
- [ ] Client Errors (4xx) query created and tested
- [ ] Server Errors (5xx) query created and tested
- [ ] Both queries return percentage values
- [ ] Queries tested in Prometheus UI
- [ ] Sum of 4xx + 5xx matches old combined Error Rate %

**Steps**:
1. Search for current "Error Rate %" panel (search for `code=~"4..|5.."`)

2. Note current query structure (will be modified in Task 2.1)

3. Test Client Errors (4xx) query in Prometheus UI:
   ```promql
   (sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices", code=~"4.."}[5m])) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))) * 100
   ```

4. Test Server Errors (5xx) query in Prometheus UI:
   ```promql
   (sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices", code=~"5.."}[5m])) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))) * 100
   ```

5. Verify consistency:
   ```bash
   # In Prometheus UI, compare:
   # - Old combined query (4..|5..)
   # - Sum of new 4xx + 5xx queries
   # Should match within 0.1%
   ```

6. Document panel IDs and gridPos for next task:
   ```bash
   # Note current Error Rate % panel:
   # - Panel ID: [RECORD THIS]
   # - gridPos: { h: X, w: Y, x: Z, y: W }
   ```

**Dependencies**: Task 1.2

**Output**:
- 4xx and 5xx queries tested and validated
- Current panel location documented
- Ready for panel creation in Task 2.1

**Reference**: See plan.md Phase 3 for query details

---

## Phase 2: Panel Management

**Goal**: Create separate 4xx/5xx panels and adjust dashboard layout  
**Duration**: 2 hours  
**Parallelizable**: No (layout adjustments depend on panel creation)

---

### Task 2.1: Create Client Errors (4xx) and Server Errors (5xx) Panels (FR-003 Part 2)

**ID**: `T2.1`  
**Priority**: P0 (Critical)  
**Effort**: 1.5 hours  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Convert existing Error Rate % panel to Client Errors (4xx) and create new Server Errors (5xx) panel.

**Acceptance Criteria**:
- [ ] Old "Error Rate %" panel converted to "Client Errors (4xx)"
- [ ] New "Server Errors (5xx)" panel created with unique ID
- [ ] 4xx panel has yellow/orange thresholds (5%, 10%)
- [ ] 5xx panel has red thresholds (0.1%, 1%)
- [ ] Both panels show percentage with 2 decimal places
- [ ] Panel descriptions explain error types
- [ ] gridPos values set for adjacent positioning

**Steps**:
1. Find max panel ID:
   ```bash
   grep -o '"id": [0-9]*' microservices-dashboard.json | \
   awk -F': ' '{print $2}' | sort -n | tail -1
   # Let's say max ID is 150
   ```

2. Locate current "Error Rate %" panel

3. Modify to become "Client Errors (4xx)":
   ```json
   {
     "id": <EXISTING_ID>,
     "title": "Client Errors (4xx)",
     "type": "stat",
     "description": "Client error rate (%) - requests rejected due to client issues (404 Not Found, 401 Unauthorized, etc.). Usually caused by incorrect URLs or missing auth tokens. Normal baseline: < 5%.",
     "targets": [
       {
         "expr": "(\n  sum(rate(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\", code=~\"4..\"}[$rate]))\n  /\n  sum(rate(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\"}[$rate]))\n) * 100"
       }
     ],
     "fieldConfig": {
       "defaults": {
         "unit": "percent",
         "decimals": 2,
         "thresholds": {
           "mode": "absolute",
           "steps": [
             { "color": "green", "value": null },
             { "color": "yellow", "value": 5 },
             { "color": "orange", "value": 10 }
           ]
         }
       }
     },
     "gridPos": { "h": 4, "w": 2, "x": <CURRENT_X>, "y": <CURRENT_Y> }
   }
   ```

4. Clone panel for "Server Errors (5xx)" (insert after 4xx panel):
   ```json
   {
     "id": <MAX_ID + 1>,
     "title": "Server Errors (5xx)",
     "type": "stat",
     "description": "Server error rate (%) - requests failed due to server issues (500 Internal Server, 503 Service Unavailable, etc.). Indicates system problems. Critical threshold: > 0.1%.",
     "targets": [
       {
         "expr": "(\n  sum(rate(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\", code=~\"5..\"}[$rate]))\n  /\n  sum(rate(request_duration_seconds_count{app=~\"$app\", namespace=~\"$namespace\", job=~\"microservices\"}[$rate]))\n) * 100"
       }
     ],
     "fieldConfig": {
       "defaults": {
         "unit": "percent",
         "decimals": 2,
         "thresholds": {
           "mode": "absolute",
           "steps": [
             { "color": "green", "value": null },
             { "color": "yellow", "value": 0.1 },
             { "color": "red", "value": 1 }
           ]
         }
       }
     },
     "gridPos": { "h": 4, "w": 2, "x": <CURRENT_X + 2>, "y": <CURRENT_Y> }
   }
   ```

5. Validate JSON syntax:
   ```bash
   jq . microservices-dashboard.json > /dev/null && echo "✅ Valid JSON" || echo "❌ Invalid JSON"
   ```

**Dependencies**: Task 1.3

**Output**:
- Client Errors (4xx) panel created
- Server Errors (5xx) panel created
- Both panels positioned adjacently

**Reference**: See plan.md Phase 3 for panel JSON structure

---

### Task 2.2: Adjust Dashboard Layout (gridPos)

**ID**: `T2.2`  
**Priority**: P1 (High)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Adjust panel widths and positions to accommodate new 5xx panel in Overview row.

**Acceptance Criteria**:
- [ ] Total row width = 24 units (no overflow)
- [ ] All panels in Overview row visible
- [ ] Panels aligned horizontally
- [ ] No overlapping panels
- [ ] Dashboard loads without layout errors

**Steps**:
1. Calculate current Overview row width:
   ```
   P50(3) + P95(3) + P99(3) + RPS(2) + Success(2) + 4xx(2) + 5xx(2) + Apdex(2) + Total(3) + Up(2) + Restarts(2) = 28 units
   ```
   ⚠️ **Overflow by 4 units**

2. Choose layout strategy:

   **Option A** (Recommended): Reduce Total Requests from 3 to 2, move Restarts to next row:
   ```
   Row 1: P50(3) + P95(3) + P99(3) + RPS(2) + Success(2) + 4xx(2) + 5xx(2) + Apdex(2) + Total(2) + Up(2) = 24
   ```

   **Option B**: Wrap Restarts to next row:
   ```
   Row 1: P50(3) + P95(3) + P99(3) + RPS(2) + Success(2) + 4xx(2) + 5xx(2) + Apdex(2) + Total(2) + Up(2) = 24
   Row 2: Restarts(2) + [next row panels...]
   ```

3. Implement Option A (reduce Total Requests width):
   - Find "Total Requests" panel
   - Change `gridPos.w` from 3 to 2
   - Update x positions for "Up Instances" and subsequent panels

4. Update gridPos for affected panels:
   ```json
   // Example adjustments
   "gridPos": { "h": 4, "w": 2, "x": <NEW_X>, "y": <Y> }
   ```

5. Verify layout in Grafana UI:
   - All panels visible
   - No horizontal scrolling
   - No overlapping

**Dependencies**: Task 2.1

**Output**:
- Dashboard layout adjusted to 24-unit width
- All panels visible and properly aligned

**Reference**: See plan.md Section "Dashboard Modifications" for layout details

---

## Phase 3: Documentation

**Goal**: Update panel descriptions to reflect new behavior  
**Duration**: 1 hour  
**Parallelizable**: No (already done in previous tasks, this is verification)

---

### Task 3.1: Verify and Finalize Panel Descriptions (FR-005)

**ID**: `T3.1`  
**Priority**: P2 (Medium)  
**Effort**: 1 hour  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Verify all panel descriptions are updated and accurate. Add any missing descriptions.

**Acceptance Criteria**:
- [ ] Status Code Distribution description mentions $rate variable
- [ ] Apdex Score description explains Satisfied/Tolerating/Frustrated
- [ ] Client Errors (4xx) description explains client-side issues
- [ ] Server Errors (5xx) description explains server-side issues
- [ ] All descriptions include expected baselines
- [ ] Descriptions visible in Grafana UI (hover over info icon)

**Steps**:
1. Review panel descriptions in JSON:

   **Status Code Distribution**:
   ```json
   "description": "HTTP status code distribution over selected time window ($rate). Shows current traffic patterns, not cumulative since pod start. Expected: ~95% codes 2xx during normal operation."
   ```

   **Apdex Score**:
   ```json
   "description": "User satisfaction score (0-1) based on Apdex standard. Satisfied: < 0.5s (100%), Tolerating: 0.5s-2s (50%), Frustrated: > 2s (0%). Green: > 0.7, Yellow: 0.5-0.7, Red: < 0.5."
   ```

   **Client Errors (4xx)**:
   ```json
   "description": "Client error rate (%) - requests rejected due to client issues (404 Not Found, 401 Unauthorized, etc.). Usually caused by incorrect URLs or missing auth tokens. Normal baseline: < 5%."
   ```

   **Server Errors (5xx)**:
   ```json
   "description": "Server error rate (%) - requests failed due to server issues (500 Internal Server, 503 Service Unavailable, etc.). Indicates system problems. Critical threshold: > 0.1%."
   ```

2. Check for any other panels that need description updates

3. Test descriptions in Grafana UI:
   - Port-forward Grafana
   - Open dashboard
   - Hover over info icon on each panel
   - Verify descriptions display correctly

**Dependencies**: Task 2.2

**Output**:
- All panel descriptions verified
- Descriptions visible in Grafana UI

**Note**: Most descriptions were already updated in Tasks 1.1, 1.2, and 2.1. This task is verification only.

---

## Phase 4: Testing

**Goal**: Comprehensive testing of all changes before deployment  
**Duration**: 2 hours  
**Parallelizable**: No (testing requires deployed changes)

---

### Task 4.1: Unit Test Queries in Prometheus UI

**ID**: `T4.1`  
**Priority**: P0 (Critical)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Test all modified queries individually in Prometheus UI to verify correctness and performance.

**Acceptance Criteria**:
- [ ] All 4 queries return valid data
- [ ] Query execution time < 1 second (P95)
- [ ] No syntax errors
- [ ] Results match expected values
- [ ] Zero traffic scenario handled gracefully

**Steps**:
1. Port-forward Prometheus:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```

2. Test Status Code Distribution query:
   ```promql
   sum by (code) (rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))
   ```
   - Expected: Distribution of status codes (200, 404, etc.)
   - Check execution time in Prometheus UI

3. Test Apdex Score query:
   ```promql
   (sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="0.5"}[5m])) + (sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="2"}[5m])) - sum(rate(request_duration_seconds_bucket{app="auth", namespace="auth", job="microservices", le="0.5"}[5m]))) * 0.5) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))
   ```
   - Expected: Score between 0.0 and 1.0

4. Test Client Errors (4xx) query:
   ```promql
   (sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices", code=~"4.."}[5m])) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))) * 100
   ```
   - Expected: Percentage of 4xx errors

5. Test Server Errors (5xx) query:
   ```promql
   (sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices", code=~"5.."}[5m])) / sum(rate(request_duration_seconds_count{app="auth", namespace="auth", job="microservices"}[5m]))) * 100
   ```
   - Expected: Percentage of 5xx errors

6. Document results:
   ```
   Query | Execution Time | Result | Pass/Fail
   ------|----------------|--------|----------
   Status Code Distribution | Xms | {...} | ✅
   Apdex Score | Xms | 0.XX | ✅
   Client Errors (4xx) | Xms | XX.XX% | ✅
   Server Errors (5xx) | Xms | XX.XX% | ✅
   ```

**Dependencies**: Task 3.1 (all modifications complete)

**Output**:
- All queries tested and validated
- Performance targets met
- Test results documented

---

### Task 4.2: Integration Test Dashboard in Grafana

**ID**: `T4.2`  
**Priority**: P0 (Critical)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Test complete dashboard after applying changes to verify all panels work together.

**Acceptance Criteria**:
- [ ] Dashboard loads without errors
- [ ] All 4 modified panels display data
- [ ] Panel layout looks correct (no overlapping)
- [ ] $rate variable affects all panels
- [ ] Color thresholds work correctly
- [ ] Panel descriptions visible

**Steps**:
1. Apply dashboard changes (preliminary test):
   ```bash
   kubectl apply -k k8s/grafana-operator/dashboards/
   ```

2. Wait for Grafana Operator reconciliation (~30 seconds)

3. Port-forward Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/grafana-service 3000:3000
   ```

4. Open dashboard:
   ```
   http://localhost:3000/d/microservices-monitoring-001/
   ```

5. Hard refresh (clear cache):
   ```
   Ctrl + Shift + R (Windows/Linux)
   Cmd + Shift + R (Mac)
   ```

6. Test panels:
   - **Status Code Distribution**: Shows pie chart with current distribution
   - **Apdex Score**: Shows score 0.0-1.0 with correct color
   - **Client Errors (4xx)**: Shows percentage with yellow/orange color
   - **Server Errors (5xx)**: Shows percentage with red color (if errors exist)

7. Test $rate variable:
   - Change $rate from 5m to 15m
   - Verify all 4 panels update
   - Change back to 5m

8. Test panel descriptions:
   - Hover over info icon on each panel
   - Verify descriptions display correctly

9. Check layout:
   - All panels visible
   - No horizontal scrolling in Overview row
   - No overlapping panels

**Dependencies**: Task 4.1

**Output**:
- Dashboard fully functional
- All panels display correctly
- Integration test passed

---

### Task 4.3: Execute Edge Case Tests

**ID**: `T4.3`  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Execute 7 edge case test scenarios from plan.md to ensure robustness.

**Acceptance Criteria**:
- [ ] TC-001: Metric consistency verified
- [ ] TC-002: Apdex displays valid score
- [ ] TC-003: 4xx/5xx separation works
- [ ] TC-004: $rate variable updates all panels
- [ ] TC-005: Counter reset handling works
- [ ] TC-006: Query performance meets targets
- [ ] TC-007: Zero traffic handled gracefully

**Steps**:

**TC-001: Metric Consistency Test**
1. Open dashboard with $rate=5m
2. Note Error Rate % calculation: `(4xx% + 5xx%)`
3. Check Status Code Distribution pie chart
4. Calculate % of error codes (4xx + 5xx)
5. Compare values (should match within 0.1%)

**TC-002: Apdex Score Display Test**
1. Check Apdex Score with normal traffic (should be 0.7-1.0)
2. Stop k6: `kubectl scale deployment -n k6 k6-scenarios --replicas=0`
3. Wait 10 minutes
4. Check Apdex Score (should be 0.0, not "No data")
5. Restart k6: `kubectl scale deployment -n k6 k6-scenarios --replicas=1`

**TC-003: 4xx/5xx Separation Test**
1. Note current 4xx and 5xx values
2. Generate 404 errors (client errors) - k6 should do this automatically
3. Verify 4xx panel increases, 5xx stays low
4. Check color: 4xx should be yellow/orange

**TC-004: $rate Variable Test**
1. Set $rate to 5m, note values
2. Change $rate to 1h, note values
3. Verify all 4 panels updated
4. Values should be more stable with 1h window

**TC-005: Counter Reset Handling Test**
1. Open dashboard with $rate=5m
2. Note current values (Status Code Distribution, Apdex)
3. Restart auth pod: `kubectl rollout restart deployment -n auth auth`
4. Watch panels during restart
5. Verify no spikes, drops, or negative values

**TC-006: Query Performance Test**
1. Open Prometheus UI
2. Run each query 10 times
3. Note execution times
4. Calculate P50 and P95
5. Verify: P50 < 500ms, P95 < 1s

**TC-007: Zero Traffic Edge Case**
1. Stop k6: `kubectl scale deployment -n k6 k6-scenarios --replicas=0`
2. Wait 10 minutes
3. Open dashboard
4. Check all panels:
   - Status Code Distribution: Empty or "No data"
   - Apdex Score: 0.0 (not error)
   - Client Errors (4xx): 0.00%
   - Server Errors (5xx): 0.00%
5. Verify no error boxes or query failures
6. Restart k6: `kubectl scale deployment -n k6 k6-scenarios --replicas=1`

**Document Results**:
```
Test Case | Expected | Actual | Pass/Fail
----------|----------|--------|----------
TC-001 | Metrics match within 0.1% | ... | ✅/❌
TC-002 | Apdex shows 0.0 | ... | ✅/❌
TC-003 | 4xx/5xx separate | ... | ✅/❌
TC-004 | $rate updates all | ... | ✅/❌
TC-005 | No spikes on restart | ... | ✅/❌
TC-006 | P95 < 1s | ... | ✅/❌
TC-007 | Zero traffic graceful | ... | ✅/❌
```

**Dependencies**: Task 4.2

**Output**:
- All 7 edge cases tested
- Test results documented
- Any issues identified and logged

**Reference**: See plan.md Section "Testing Strategy" for detailed test cases

---

## Phase 5: Deployment

**Goal**: Deploy changes to production and monitor  
**Duration**: 2 hours  
**Parallelizable**: No (sequential deployment steps)

---

### Task 5.1: Validate JSON and Commit Changes

**ID**: `T5.1`  
**Priority**: P0 (Critical)  
**Effort**: 30 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Final validation of dashboard JSON and commit to Git with proper message.

**Acceptance Criteria**:
- [ ] JSON syntax validated
- [ ] Dashboard structure verified
- [ ] Git commit created with descriptive message
- [ ] Commit includes all changes
- [ ] Backup file excluded from commit

**Steps**:
1. Final JSON validation:
   ```bash
   cd k8s/grafana-operator/dashboards/
   jq . microservices-dashboard.json > /dev/null && echo "✅ Valid JSON" || echo "❌ Invalid JSON"
   ```

2. Verify changes:
   ```bash
   git diff microservices-dashboard.json
   ```

3. Review changes:
   - Status Code Distribution query updated
   - Apdex Score query simplified
   - Error Rate panel split into 4xx/5xx
   - Panel descriptions updated
   - Layout adjusted

4. Add and commit:
   ```bash
   git add microservices-dashboard.json
   
   git commit -m "feat(dashboard): Fix metrics consistency (FR-001 to FR-005)

- FR-001: Convert Status Code Distribution to rate-based query
  * Changed from cumulative sum() to sum(rate()[$rate]) by (code)
  * Panel now shows current traffic patterns instead of historical
  * Handles counter resets automatically via rate()

- FR-002: Simplify Apdex Score query and handle edge cases
  * Reformatted query with explicit line breaks for readability
  * Changed division by 2 to multiplication by 0.5 (clearer intent)
  * Added color thresholds: Green (>0.7), Yellow (0.5-0.7), Red (<0.5)
  * Zero traffic now shows 0.0 instead of 'No data' error

- FR-003: Split Error Rate into Client (4xx) and Server (5xx) panels
  * Created separate panel for Client Errors (4xx) with yellow/orange thresholds
  * Created separate panel for Server Errors (5xx) with red thresholds
  * Enables faster incident triage (client vs server issues)

- FR-004: Ensure consistent \$rate variable usage across all panels
  * All modified panels use [\$rate] parameter consistently
  * Single dropdown controls time window for all panels

- FR-005: Update panel descriptions
  * Status Code Distribution: Mentions rate-based calculation
  * Apdex Score: Explains Satisfied/Tolerating/Frustrated formula
  * Client Errors (4xx): Explains client-side issues and baselines
  * Server Errors (5xx): Explains server-side issues and thresholds

Breaking Change: Status Code Distribution now shows current traffic 
patterns instead of cumulative counts since pod start.

Testing:
- All queries tested in Prometheus UI (execution time < 1s)
- Edge cases validated (zero traffic, pod restarts, counter resets)
- Integration tested in Grafana dashboard
- 7 test scenarios passed (TC-001 to TC-007)

Closes: dashboard-metrics-consistency
Refs: specs/active/dashboard-metrics-consistency/spec.md
"
   ```

5. Verify commit:
   ```bash
   git log -1 --stat
   git show HEAD
   ```

6. Push to remote:
   ```bash
   git push origin main
   ```

**Dependencies**: Task 4.3 (all testing complete)

**Output**:
- Git commit created
- Changes pushed to remote
- Ready for deployment

---

### Task 5.2: Apply to Kubernetes Cluster

**ID**: `T5.2`  
**Priority**: P0 (Critical)  
**Effort**: 15 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Apply dashboard changes to Kubernetes using kubectl and Kustomize.

**Acceptance Criteria**:
- [ ] Kustomize build succeeds
- [ ] ConfigMap updated
- [ ] GrafanaDashboard CR updated
- [ ] kubectl apply succeeds
- [ ] No errors in kubectl output

**Steps**:
1. Build Kustomization (dry-run):
   ```bash
   kubectl kustomize k8s/grafana-operator/dashboards/
   # Review output
   ```

2. Apply to cluster:
   ```bash
   kubectl apply -k k8s/grafana-operator/dashboards/
   ```

3. Expected output:
   ```
   configmap/grafana-dashboards-xxxxx configured
   grafanadashboard.grafana.integreatly.org/microservices-monitoring-001 configured
   ```

4. Verify resources:
   ```bash
   kubectl get configmaps -n monitoring -l app=grafana
   kubectl get grafanadashboards -n monitoring
   ```

**Dependencies**: Task 5.1

**Output**:
- Dashboard applied to Kubernetes
- ConfigMap and GrafanaDashboard CR updated

---

### Task 5.3: Verify Grafana Operator Reconciliation

**ID**: `T5.3`  
**Priority**: P0 (Critical)  
**Effort**: 15 minutes  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Monitor Grafana Operator reconciliation and verify dashboard update in Grafana UI.

**Acceptance Criteria**:
- [ ] GrafanaDashboard CR status shows "Synced"
- [ ] Grafana Operator logs show successful reconciliation
- [ ] Dashboard updated in Grafana UI (hard refresh)
- [ ] All 4 modified panels display correctly
- [ ] No errors in Grafana logs

**Steps**:
1. Check GrafanaDashboard CR status:
   ```bash
   kubectl get grafanadashboard -n monitoring microservices-monitoring-001 -o yaml | grep -A 5 status
   ```
   - Look for `phase: "Synced"`

2. Watch Grafana Operator logs:
   ```bash
   kubectl logs -n monitoring deployment/grafana-operator -f --tail=50
   ```
   - Look for: "Dashboard reconciled successfully" or similar

3. Wait for reconciliation (~30 seconds)

4. Port-forward Grafana:
   ```bash
   kubectl port-forward -n monitoring svc/grafana-service 3000:3000
   ```

5. Open dashboard in browser:
   ```
   http://localhost:3000/d/microservices-monitoring-001/
   ```

6. Hard refresh to clear cache:
   ```
   Ctrl + Shift + R (Windows/Linux)
   Cmd + Shift + R (Mac)
   ```

7. Verify changes:
   - Status Code Distribution: Pie chart shows rate-based distribution
   - Apdex Score: Shows valid score with color
   - Client Errors (4xx): New panel visible with yellow/orange
   - Server Errors (5xx): New panel visible (green or red depending on errors)
   - Panel layout: All panels fit in row, no overflow

8. Check Grafana logs for errors:
   ```bash
   kubectl logs -n monitoring deployment/grafana-operator --tail=100 | grep -i error
   # Should be empty or only historical errors
   ```

**Dependencies**: Task 5.2

**Output**:
- Grafana Operator reconciliation successful
- Dashboard updated and verified in UI

---

### Task 5.4: Monitor and Document Deployment

**ID**: `T5.4`  
**Priority**: P1 (High)  
**Effort**: 1 hour  
**Assignee**: [TBD]  
**Status**: ⬜ todo

**Description**:
Monitor dashboard for 30 minutes post-deployment and document results.

**Acceptance Criteria**:
- [ ] Dashboard monitored for 30 minutes
- [ ] No errors or "No data" states
- [ ] Prometheus scraping continues normally
- [ ] Query performance acceptable
- [ ] Team notified of deployment
- [ ] CHANGELOG.md updated

**Steps**:
1. Monitor dashboard (30 minutes):
   - Refresh every 5 minutes
   - Check all 4 modified panels
   - Note any anomalies

2. Check Prometheus targets:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Open http://localhost:9090/targets
   # Verify all microservices targets are UP
   ```

3. Check query performance in Prometheus:
   - Navigate to http://localhost:9090/graph
   - Run queries, note execution times
   - All should be < 1 second

4. Update CHANGELOG.md:
   ```bash
   cd /path/to/monitoring/
   vim CHANGELOG.md
   ```

   Add entry:
   ```markdown
   ## [0.7.3] - 2025-12-13

   ### Fixed

   **Dashboard Metrics Consistency:**
   - Fixed Status Code Distribution panel to use rate-based query (FR-001)
     * Changed from cumulative sum() to sum(rate()[$rate]) by (code)
     * Panel now shows current traffic patterns instead of historical data
     * Handles pod restarts and counter resets automatically
   
   - Simplified Apdex Score query for better edge case handling (FR-002)
     * Reformatted query with explicit line breaks for readability
     * Fixed division by zero handling (shows 0.0 instead of "No data")
     * Added color thresholds: Green (>0.7), Yellow (0.5-0.7), Red (<0.5)
   
   - Split Error Rate into Client (4xx) and Server (5xx) panels (FR-003)
     * Separate Client Errors (4xx) panel with yellow/orange thresholds
     * Separate Server Errors (5xx) panel with red thresholds
     * Enables faster incident triage (distinguish client vs server issues)
   
   - Ensured consistent $rate variable usage across all panels (FR-004)
   
   - Updated panel descriptions to reflect rate-based calculations (FR-005)

   **Breaking Change:** Status Code Distribution panel now shows current 
   traffic distribution over selected time window, not cumulative since 
   pod start.

   **Testing:** All queries tested, edge cases validated, 7 test scenarios passed.

   **References:**
   - Specification: specs/active/dashboard-metrics-consistency/spec.md
   - Implementation Plan: specs/active/dashboard-metrics-consistency/plan.md
   - Research: specs/active/dashboard-metrics-consistency/research.md
   ```

5. Commit CHANGELOG update:
   ```bash
   git add CHANGELOG.md
   git commit -m "docs(changelog): Add v0.7.3 entry for dashboard metrics consistency"
   git push origin main
   ```

6. Notify team (Slack/email):
   ```
   Subject: Dashboard Updated - Metrics Consistency Fixes

   Hi team,

   The microservices monitoring dashboard has been updated with important 
   metrics consistency fixes:

   1. Status Code Distribution now shows current traffic patterns (rate-based)
   2. Apdex Score simplified and handles zero traffic gracefully
   3. Error Rate split into Client (4xx) and Server (5xx) panels
   4. All panels use consistent time window ($rate variable)

   Breaking Change: Status Code Distribution panel values will be different 
   (shows current traffic, not cumulative since pod start). This is expected 
   and aligns with industry best practices.

   Dashboard: http://localhost:3000/d/microservices-monitoring-001/
   Docs: specs/active/dashboard-metrics-consistency/

   Please report any issues in #monitoring channel.

   Thanks!
   ```

7. Document final status:
   - Create `specs/active/dashboard-metrics-consistency/IMPLEMENTATION_COMPLETE.md`
   - Summarize implementation
   - Note any deviations from plan
   - Archive task

**Dependencies**: Task 5.3

**Output**:
- Dashboard monitored and stable
- CHANGELOG.md updated
- Team notified
- Implementation documented

---

## Progress Tracking

### Overall Progress

**Total Tasks**: 15  
**Completed**: 0 (0%)  
**In Progress**: 0  
**Blocked**: 0  
**Remaining**: 15

### Phase Progress

| Phase | Tasks Complete | Status |
|-------|----------------|--------|
| Phase 0 | 0 / 2 | ⬜ Not Started |
| Phase 1 | 0 / 3 | ⬜ Not Started |
| Phase 2 | 0 / 2 | ⬜ Not Started |
| Phase 3 | 0 / 1 | ⬜ Not Started |
| Phase 4 | 0 / 3 | ⬜ Not Started |
| Phase 5 | 0 / 4 | ⬜ Not Started |

### Task Status

| Task ID | Task Name | Status | Effort | Owner |
|---------|-----------|--------|--------|-------|
| T0.1 | Backup Dashboard | ⬜ todo | 30m | [TBD] |
| T0.2 | Setup Testing Tools | ⬜ todo | 30m | [TBD] |
| T1.1 | Fix Status Code Distribution | ⬜ todo | 1h | [TBD] |
| T1.2 | Simplify Apdex Score | ⬜ todo | 1.5h | [TBD] |
| T1.3 | Split Error Rate Queries | ⬜ todo | 30m | [TBD] |
| T2.1 | Create 4xx/5xx Panels | ⬜ todo | 1.5h | [TBD] |
| T2.2 | Adjust Layout | ⬜ todo | 30m | [TBD] |
| T3.1 | Verify Descriptions | ⬜ todo | 1h | [TBD] |
| T4.1 | Unit Test Queries | ⬜ todo | 30m | [TBD] |
| T4.2 | Integration Test Dashboard | ⬜ todo | 30m | [TBD] |
| T4.3 | Execute Edge Case Tests | ⬜ todo | 1h | [TBD] |
| T5.1 | Validate and Commit | ⬜ todo | 30m | [TBD] |
| T5.2 | Apply to Kubernetes | ⬜ todo | 15m | [TBD] |
| T5.3 | Verify Reconciliation | ⬜ todo | 15m | [TBD] |
| T5.4 | Monitor and Document | ⬜ todo | 1h | [TBD] |

### Milestones

- [ ] **Milestone 1**: Setup Complete (Phase 0) - Target: Day 1 Hour 1
- [ ] **Milestone 2**: Queries Fixed (Phase 1) - Target: Day 1 Hour 4
- [ ] **Milestone 3**: Panels Ready (Phase 2) - Target: Day 2 Hour 2
- [ ] **Milestone 4**: Testing Complete (Phase 4) - Target: Day 2 Hour 4
- [ ] **Milestone 5**: Deployed to Production (Phase 5) - Target: Day 3 Hour 2

---

## Risk & Blockers

### Current Risks

**Risk 1: Team Confusion from Changed Values**
- **Impact**: MEDIUM
- **Probability**: HIGH
- **Mitigation**: 
  - Announce in team meeting 1 week before deployment
  - Update documentation with before/after examples
  - Add dashboard annotation: "Rate-based metrics (2025-12-13)"
- **Status**: Not Started

**Risk 2: Query Performance Issues**
- **Impact**: HIGH
- **Probability**: LOW
- **Mitigation**:
  - Load test in staging first (if available)
  - Monitor Prometheus query duration after deployment
  - Rollback plan ready (< 5 minutes)
- **Status**: Not Started

**Risk 3: Apdex Still Shows "No Data"**
- **Impact**: MEDIUM
- **Probability**: MEDIUM
- **Mitigation**:
  - Test query extensively in Prometheus UI before deployment
  - Verify histogram buckets exist (le="0.5", le="2")
  - Document troubleshooting in runbook
- **Status**: Not Started

### Current Blockers

**No blockers at this time.**

### Dependencies

**External Dependencies:**
- Kubernetes cluster access
- Grafana Operator running
- Prometheus collecting metrics
- k6 load generator running

**Internal Dependencies:**
- All tasks are sequential (single file modification)
- Critical path: Setup → Queries → Panels → Testing → Deployment

---

## Notes

### Implementation Guidelines

1. **JSON Editing**: Use VS Code or similar editor with JSON validation
2. **Testing First**: Always test queries in Prometheus UI before adding to dashboard
3. **Backup Always**: Keep timestamped backups before any changes
4. **Incremental Changes**: Test after each phase before proceeding
5. **Validation**: Run `jq` validation after every JSON edit

### Rollback Procedure

If any issues arise:
1. Revert to backup: `cp microservices-dashboard.json.backup microservices-dashboard.json`
2. Reapply: `kubectl apply -k k8s/grafana-operator/dashboards/`
3. Grafana Operator reconciles in ~30 seconds
4. Notify team

**Timeline**: < 5 minutes from decision to rollback

### Success Criteria

**All functional requirements met:**
- ✅ FR-001: Status Code Distribution uses rate()
- ✅ FR-002: Apdex Score simplified
- ✅ FR-003: Error Rate split into 4xx/5xx
- ✅ FR-004: Consistent $rate usage
- ✅ FR-005: Panel descriptions updated

**All non-functional requirements met:**
- ✅ Query performance < 1s (P95)
- ✅ Counter resets handled
- ✅ Zero traffic handled
- ✅ Cross-service comparable

---

## References

- **Specification**: [spec.md](./spec.md)
- **Implementation Plan**: [plan.md](./plan.md)
- **Research**: [research.md](./research.md)
- **Dashboard JSON**: `k8s/grafana-operator/dashboards/microservices-dashboard.json`
- **AGENTS.md**: Dashboard update workflow
- **Prometheus Best Practices**: https://prometheus.io/docs/practices/

---

**Task Breakdown Version**: 1.0  
**Last Updated**: 2025-12-13  
**Ready for Implementation**: ✅ Yes

