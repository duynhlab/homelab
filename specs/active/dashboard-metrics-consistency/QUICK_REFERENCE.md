# Quick Reference: Dashboard Metrics Consistency

> **Implementation Status**: ✅ Ready for User Testing  
> **Date**: 2025-12-13  
> **Time Required**: 2 hours (testing + deployment)

---

## 🚀 Quick Start (5 Minutes)

```bash
# 1. Deploy dashboard
cd /path/to/monitoring
./scripts/09-reload-dashboard.sh

# 2. Wait 30 seconds
sleep 30

# 3. Open Grafana
open http://localhost:3000
# Or: kubectl port-forward -n monitoring svc/grafana-service 3000:3000
```

---

## ✅ What to Verify

### In Grafana Dashboard

1. **Status Code Distribution** (Panel ID: 9)
   - Should show req/sec values (not cumulative totals)
   - Pie chart with percentage breakdown
   - Expected: ~95% code 2xx

2. **Apdex Score** (Panel ID: 6)
   - Should show 0.0-1.0 range
   - No NaN values (even with zero traffic)
   - Expected: > 0.9 for healthy services

3. **Client Errors (4xx)** (Panel ID: 201) - NEW!
   - Time series showing 4xx req/sec by service
   - Orange/yellow colors
   - Location: "⚠️ Errors & Performance" row, left panel

4. **Server Errors (5xx)** (Panel ID: 202) - NEW!
   - Time series showing 5xx req/sec by service
   - Red/orange colors
   - Location: "⚠️ Errors & Performance" row, right panel

### In Prometheus (http://localhost:9090)

Test each query individually:

**Query 1: Status Code Distribution**
```promql
sum(rate(request_duration_seconds_count{app=~"auth|user", namespace=~"auth|user", job=~"microservices"}[5m])) by (code)
```
Expected: Returns req/sec values grouped by status code

**Query 2: Apdex Score**
```promql
(sum(rate(request_duration_seconds_bucket{app=~"auth", namespace=~"auth", job=~"microservices", le="0.5"}[5m])) + 0.5 * (sum(rate(request_duration_seconds_bucket{app=~"auth", namespace=~"auth", job=~"microservices", le="2"}[5m])) - sum(rate(request_duration_seconds_bucket{app=~"auth", namespace=~"auth", job=~"microservices", le="0.5"}[5m])))) / (sum(rate(request_duration_seconds_count{app=~"auth", namespace=~"auth", job=~"microservices"}[5m])) > 0 or vector(1))
```
Expected: Returns 0.0-1.0 value (no NaN even with zero traffic)

**Query 3: Client Errors (4xx)**
```promql
sum(rate(request_duration_seconds_count{app=~"auth|user", namespace=~"auth|user", job=~"microservices", code=~"4.."}[5m])) by (app)
```
Expected: Returns 4xx error rate per service (0 if no errors)

**Query 4: Server Errors (5xx)**
```promql
sum(rate(request_duration_seconds_count{app=~"auth|user", namespace=~"auth|user", job=~"microservices", code=~"5.."}[5m])) by (app)
```
Expected: Returns 5xx error rate per service (0 if no errors)

---

## 🧪 Edge Case Testing (1 Hour)

### Scenario 1: Zero Traffic Service
1. Filter dashboard to service with no requests
2. ✅ Apdex = 0.0 (not NaN)
3. ✅ Error Rate = 0%
4. ✅ Status Code Distribution = empty
5. ✅ 4xx/5xx panels = 0

### Scenario 2: All Success (2xx)
1. Filter to healthy service
2. ✅ Apdex ≈ 1.0 (fast responses)
3. ✅ Error Rate = 0%
4. ✅ Status Code shows only 200
5. ✅ 4xx/5xx panels = 0

### Scenario 3: All Failure (5xx)
1. Trigger errors on test service
2. ✅ Apdex ≈ 0.0 (slow/failed)
3. ✅ Error Rate = 100%
4. ✅ Status Code shows 500
5. ✅ 5xx panel shows traffic

### Scenario 4: Mixed Traffic
1. Service with varied responses
2. ✅ Proportional status code distribution
3. ✅ 4xx and 5xx panels show correct split
4. ✅ Apdex reflects response times

### Scenario 5: Variable Changes
1. Switch $app filter (auth → user)
2. ✅ All panels update
3. Switch $namespace filter
4. ✅ All panels update
5. Switch $rate interval (5m → 1h)
6. ✅ Values adjust proportionally

### Scenario 6: Time Range Changes
1. Test ranges: 5m, 1h, 24h, 7d
2. ✅ All queries execute < 1s
3. ✅ Panels render correctly

### Scenario 7: Rate Interval Changes
1. Test intervals: 1m, 5m, 1h
2. ✅ Values scale appropriately
3. ✅ No query errors

---

## 📊 Performance Targets

| Metric | Target | Actual |
|--------|--------|--------|
| Query Execution | < 1s | _______ |
| Dashboard Load | < 5s | _______ |
| Variable Change | < 2s | _______ |
| Operator Reconcile | < 30s | _______ |

---

## 🔍 Troubleshooting

### Dashboard Not Updating
```bash
# Check Grafana Operator
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana-operator

# Check GrafanaDashboard CR
kubectl get grafanadashboard -n monitoring

# Force reconciliation
kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana-operator
```

### Panels Show "No Data"
```bash
# Check Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Test query in Prometheus UI
open http://localhost:9090/graph
```

### Apdex Shows 0.0
- ✅ This is correct for zero-traffic services (defensive handling)
- Check if service has traffic: `kubectl logs -n <namespace> -l app=<service>`

### 4xx/5xx Panels Empty
- ✅ This is normal if no errors (good!)
- Generate test errors to verify panels work

---

## 🎯 Success Checklist

**Before Deployment:**
- [x] JSON syntax validated
- [x] Backup created
- [x] Panel IDs unique
- [x] No overlapping panels

**After Deployment:**
- [ ] Dashboard deployed successfully
- [ ] All 4 queries tested in Prometheus
- [ ] All panels render in Grafana
- [ ] Variables work correctly
- [ ] 7 edge cases pass
- [ ] 15-minute stability monitoring
- [ ] CHANGELOG.md updated

---

## 📝 Final Steps

### 1. Monitor Dashboard (15 Minutes)
- Watch for errors in browser console
- Check Grafana Operator logs: `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-operator -f`
- Verify panels update in real-time

### 2. Update CHANGELOG.md
```bash
# Copy draft entry
cat specs/active/dashboard-metrics-consistency/CHANGELOG_DRAFT.md

# Add to CHANGELOG.md as version 0.7.3
nano CHANGELOG.md  # Or your preferred editor
```

### 3. Mark Tasks Complete
```bash
# Update progress.md
nano specs/active/dashboard-metrics-consistency/progress.md

# Mark remaining tasks complete in todo-list.md
nano specs/active/dashboard-metrics-consistency/todo-list.md
```

### 4. Git Commit
```bash
git add k8s/grafana-operator/dashboards/microservices-dashboard.json
git add CHANGELOG.md
git commit -m "feat(dashboard): fix metrics consistency (v0.7.3)

- Status Code Distribution now shows req/sec (was cumulative)
- Apdex Score handles zero traffic gracefully (no NaN)
- Added separate 4xx/5xx error panels for faster debugging
- All queries use consistent rate() pattern
- 34 panels total (added 2 new error panels)

Closes: dashboard-metrics-consistency
"
```

---

## 📞 Need Help?

**Files to Review:**
- Full details: `specs/active/dashboard-metrics-consistency/IMPLEMENTATION_SUMMARY.md`
- Task list: `specs/active/dashboard-metrics-consistency/todo-list.md`
- Progress: `specs/active/dashboard-metrics-consistency/progress.md`

**Common Questions:**

Q: Why is Apdex 0.0?  
A: Correct for zero-traffic services (defensive handling prevents NaN)

Q: Why are 4xx/5xx panels empty?  
A: Good! No errors = healthy service

Q: Queries slow (> 1s)?  
A: Check Prometheus retention, increase $rate interval (5m → 15m)

---

**Ready to Deploy?** Run `./scripts/09-reload-dashboard.sh` 🚀


