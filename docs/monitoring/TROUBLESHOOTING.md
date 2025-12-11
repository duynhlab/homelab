# Grafana Dashboard Troubleshooting

**Last Updated**: 2025-12-11  
**Applies To**: Grafana Dashboard v10.x with Prometheus datasource

---

## Table of Contents

1. [Variable Cascading Issues](#variable-cascading-issues)
2. [Query Performance Issues](#query-performance-issues)
3. [Panel Data Issues](#panel-data-issues)
4. [Grafana Operator Issues](#grafana-operator-issues)

---

## Variable Cascading Issues

### Issue 1: Namespace filter stuck on "All"

**Symptoms**:
- Namespace dropdown only shows "All"
- Cannot select specific namespaces
- Dropdown appears disabled or unresponsive

**Causes**:
1. Variable order incorrect in dashboard JSON
2. App variable defined before namespace variable in templating list
3. Grafana variable evaluation order issue

**Solution**:

1. **Check variable order in dashboard JSON**:
   ```bash
   cd /Users/duyne/work/Github/monitoring
   jq '.templating.list[] | {name, label}' k8s/grafana-operator/dashboards/microservices-dashboard.json
   ```

2. **Expected order**:
   ```json
   {
     "name": "DS_PROMETHEUS",
     "label": "Datasource"
   }
   {
     "name": "namespace",
     "label": "Namespace"
   }
   {
     "name": "app",
     "label": "App"
   }
   {
     "name": "rate",
     "label": "Rate Interval"
   }
   ```

3. **If order is wrong, fix in JSON**:
   - Open `k8s/grafana-operator/dashboards/microservices-dashboard.json`
   - Locate `templating.list` array (around line 2476)
   - Reorder so `namespace` appears at index 1, `app` at index 2
   - Reapply: `kubectl apply -k k8s/grafana-operator/dashboards/`

4. **Force Grafana refresh**:
   ```bash
   # Restart Grafana pod to force reload
   kubectl rollout restart deployment/grafana-deployment -n monitoring
   
   # Wait for rollout
   kubectl rollout status deployment/grafana-deployment -n monitoring
   ```

---

### Issue 2: App dropdown doesn't update when namespace changes

**Symptoms**:
- Change namespace, but app dropdown shows all apps
- App list doesn't filter by namespace
- Variables appear independent (not cascading)

**Causes**:
- App variable query missing namespace filter
- No `refresh` trigger on app variable
- Query doesn't reference `$namespace` variable

**Solution**:

1. **Check app variable query**:
   ```bash
   jq '.templating.list[] | select(.name=="app") | {name, query, definition}' \
     k8s/grafana-operator/dashboards/microservices-dashboard.json
   ```

2. **Expected query** (CORRECT):
   ```json
   {
     "name": "app",
     "query": "label_values(request_duration_seconds_count{namespace=~\"$namespace\"}, app)",
     "definition": "label_values(request_duration_seconds_count{namespace=~\"$namespace\"}, app)"
   }
   ```

3. **Incorrect query** (WRONG - no namespace filter):
   ```json
   {
     "name": "app",
     "query": "label_values(request_duration_seconds_count, app)",
     "definition": "label_values(request_duration_seconds_count, app)"
   }
   ```

4. **Fix the query**:
   - Edit dashboard JSON
   - Update both `query` and `definition` fields to include `{namespace=~\"$namespace\"}`
   - Ensure `refresh: 1` is set on app variable
   - Reapply dashboard

5. **Verify cascading works**:
   - Open dashboard: http://localhost:3000/d/microservices-monitoring-001/
   - Select namespace = "auth"
   - App dropdown should update to show only "auth"

**Quick Fix Script**:
```bash
# Backup current dashboard
cp k8s/grafana-operator/dashboards/microservices-dashboard.json \
   k8s/grafana-operator/dashboards/microservices-dashboard.json.backup-$(date +%Y%m%d)

# Apply corrected dashboard (if you have the fixed version)
kubectl apply -k k8s/grafana-operator/dashboards/
```

---

### Issue 3: App dropdown shows services from other namespaces

**Symptoms**:
- Select namespace = "auth"
- App dropdown shows: `["All", "auth", "cart", "notification", "order", "product", "review", "shipping", "user"]`
- Expected: Should show only `["All", "auth"]`

**Causes**:
- Same as Issue 2 - app variable query missing namespace filter
- This is the most common symptom of broken cascading

**Solution**:
- Follow Solution steps from Issue 2 above
- Key fix: Add `{namespace=~\"$namespace\"}` to app variable query

**Verification**:
```bash
# Check if app variable filters by namespace
jq '.templating.list[] | select(.name=="app") | .query' \
  k8s/grafana-operator/dashboards/microservices-dashboard.json

# Should output:
# "label_values(request_duration_seconds_count{namespace=~\"$namespace\"}, app)"
```

---

## Query Performance Issues

### Issue 4: Dashboard slow to load

**Symptoms**:
- Dashboard takes > 10 seconds to load
- Browser tab freezes or becomes unresponsive
- "Loading..." spinner persists

**Causes**:
- Too many time series queried (high cardinality)
- Large time range selected (e.g., 7 days with 1m resolution)
- Prometheus overloaded or slow to respond
- Network latency to Prometheus

**Solution**:

1. **Reduce scope with filters**:
   - Use namespace filter to limit to specific namespaces
   - Select specific app instead of "All"
   - This reduces time series from ~1000s to ~10s

2. **Reduce time range**:
   - Click time picker (top right)
   - Select shorter range: "Last 30 minutes" or "Last 1 hour"

3. **Increase rate interval**:
   - Change `$rate` variable from "1m" to "5m" or "10m"
   - Fewer data points = faster queries

4. **Check Prometheus performance**:
   ```bash
   # Port-forward Prometheus
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   
   # Open Prometheus UI
   # http://localhost:9090/graph
   
   # Run test query and check execution time
   rate(request_duration_seconds_count{app=~"auth", namespace=~"auth", job=~"microservices"}[5m])
   ```

5. **Check Prometheus resource usage**:
   ```bash
   # Check Prometheus pod resources
   kubectl top pod -n monitoring -l app.kubernetes.io/name=prometheus
   
   # Check if CPU/memory limits reached
   kubectl describe pod -n monitoring -l app.kubernetes.io/name=prometheus | grep -A 5 "Limits"
   ```

6. **Optimize queries** (if needed):
   - Use recording rules for frequently used queries
   - Increase Prometheus scrape interval (trade-off: less granularity)
   - Scale Prometheus (increase replicas or resources)

---

### Issue 5: Panels show "Timeout" error

**Symptoms**:
- Panels display "Timeout" or "Gateway Timeout" error
- Query execution time > 30 seconds
- Error message: "Query timeout exceeded"

**Causes**:
- Query timeout (default 30s)
- Prometheus query too complex
- High cardinality metrics
- Prometheus under heavy load

**Solution**:

1. **Increase query timeout in Grafana datasource**:
   ```bash
   # Edit Grafana datasource (via UI)
   # 1. Go to Configuration → Data Sources → Prometheus
   # 2. Scroll to "HTTP" section
   # 3. Set "Timeout" to 60s or 120s
   # 4. Click "Save & test"
   ```

2. **Optimize query**:
   - Reduce time range
   - Increase rate interval ($rate)
   - Add more specific label filters
   - Use recording rules

3. **Check Prometheus query performance**:
   ```bash
   # Port-forward Prometheus
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   
   # Test query directly in Prometheus
   # http://localhost:9090/graph
   # Look for "Execution time" in results
   ```

4. **Scale Prometheus resources**:
   ```yaml
   # Edit k8s/prometheus/values.yaml
   prometheus:
     prometheusSpec:
       resources:
         requests:
           cpu: 2000m
           memory: 4Gi
         limits:
           cpu: 4000m
           memory: 8Gi
   
   # Apply changes
   helm upgrade prometheus-kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n monitoring \
     -f k8s/prometheus/values.yaml
   ```

---

## Panel Data Issues

### Issue 6: Panels show no data after filtering

**Symptoms**:
- Select namespace/app, panels go blank
- "No data" message in panels
- Charts show empty graphs

**Causes**:
1. No services running in selected namespace
2. Services not exposing /metrics endpoint
3. Prometheus not scraping services
4. Incorrect label filters in query

**Solution**:

1. **Check services are running**:
   ```bash
   # List pods in namespace
   kubectl get pods -n auth
   
   # Check pod status
   kubectl describe pod -n auth -l app=auth
   ```

2. **Check ServiceMonitor**:
   ```bash
   # List ServiceMonitors
   kubectl get servicemonitors -n monitoring
   
   # Check microservices ServiceMonitor
   kubectl get servicemonitor -n monitoring microservices-api -o yaml
   
   # Verify namespaceSelector includes your namespace
   ```

3. **Check Prometheus targets**:
   ```bash
   # Port-forward Prometheus
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   
   # Open targets page
   # http://localhost:9090/targets
   
   # Look for services with label job="microservices"
   # Check if targets are "UP" or "DOWN"
   ```

4. **Check metrics endpoint directly**:
   ```bash
   # Port-forward service
   kubectl port-forward -n auth svc/auth-service 8080:8080
   
   # Curl metrics endpoint
   curl http://localhost:8080/metrics
   
   # Should see Prometheus metrics format:
   # request_duration_seconds_count{method="GET",path="/api/v1/login",code="200"} 42
   ```

5. **Verify label consistency**:
   ```bash
   # Query Prometheus to see actual labels
   # http://localhost:9090/graph
   
   # Run query:
   request_duration_seconds_count
   
   # Check labels match dashboard query:
   # - app label exists
   # - namespace label exists
   # - job="microservices"
   ```

---

### Issue 7: Panels show data from wrong namespace

**Symptoms**:
- Select namespace = "auth"
- Panels show data from multiple namespaces
- Aggregations include services you didn't select

**Causes**:
- Panel queries don't use `$namespace` variable
- Variable filter not applied in PromQL query
- Missing label filter in query

**Solution**:

1. **Check panel query uses variables**:
   - Edit dashboard → Edit panel → Query tab
   - Verify query includes: `{app=~"$app", namespace=~"$namespace", job=~"microservices"}`

2. **Standard panel query pattern**:
   ```promql
   rate(
     request_duration_seconds_count{
       app=~"$app",
       namespace=~"$namespace",
       job=~"microservices"
     }[$rate]
   )
   ```

3. **Fix all panel queries**:
   - All 34 queries should use `$app`, `$namespace`, `$rate` variables
   - Use consistent label filters across all panels

---

## Grafana Operator Issues

### Issue 8: Dashboard not updating after JSON changes

**Symptoms**:
- Edit dashboard JSON file
- Apply with `kubectl apply -k`
- Dashboard in Grafana UI unchanged

**Causes**:
- Grafana Operator not reconciling
- ConfigMap updated but GrafanaDashboard CR not synced
- Grafana cache not cleared

**Solution**:

1. **Check GrafanaDashboard CR status**:
   ```bash
   kubectl get grafanadashboards -n monitoring microservices-monitoring -o yaml
   
   # Look for status.message field
   # Should say "success" or similar
   ```

2. **Check Grafana Operator logs**:
   ```bash
   kubectl logs -n monitoring deployment/grafana-operator --tail=50 -f
   
   # Look for errors or "Dashboard reconciled successfully"
   ```

3. **Force reconciliation**:
   ```bash
   # Delete and recreate GrafanaDashboard CR
   kubectl delete grafanadashboard -n monitoring microservices-monitoring
   kubectl apply -k k8s/grafana-operator/dashboards/
   ```

4. **Restart Grafana pod**:
   ```bash
   # Force Grafana to reload dashboards
   kubectl rollout restart deployment/grafana-deployment -n monitoring
   
   # Wait for rollout
   kubectl rollout status deployment/grafana-deployment -n monitoring
   ```

5. **Verify ConfigMap updated**:
   ```bash
   # Check ConfigMap contains your changes
   kubectl get configmap -n monitoring grafana-dashboards-microservices -o yaml | grep -A 5 "namespace"
   ```

---

### Issue 9: GrafanaDashboard CR fails to create

**Symptoms**:
- `kubectl apply` returns error
- GrafanaDashboard CR not created
- Error message: "admission webhook denied"

**Causes**:
- Invalid dashboard JSON
- Missing required fields
- Grafana Operator validation failed

**Solution**:

1. **Validate JSON syntax**:
   ```bash
   jq empty k8s/grafana-operator/dashboards/microservices-dashboard.json
   
   # No output = valid JSON
   # Error = invalid JSON (fix syntax)
   ```

2. **Check dashboard JSON structure**:
   - Ensure `uid` field present and unique
   - Ensure `title` field present
   - Ensure `version` field present (integer)

3. **Check Grafana Operator logs for validation errors**:
   ```bash
   kubectl logs -n monitoring deployment/grafana-operator --tail=100
   ```

4. **Test dashboard JSON manually**:
   - Port-forward Grafana
   - Go to Dashboards → Import
   - Paste JSON and try to import
   - Grafana will show specific validation errors

---

## Quick Reference

### Essential Commands

```bash
# Check Grafana access
kubectl port-forward -n monitoring svc/grafana-service 3000:3000

# Check Prometheus access
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Restart Grafana
kubectl rollout restart deployment/grafana-deployment -n monitoring

# Reapply dashboards
kubectl apply -k k8s/grafana-operator/dashboards/

# Check GrafanaDashboard status
kubectl get grafanadashboards -n monitoring

# Check Grafana Operator logs
kubectl logs -n monitoring deployment/grafana-operator --tail=50

# Validate JSON
jq empty k8s/grafana-operator/dashboards/microservices-dashboard.json

# Check Prometheus targets
# http://localhost:9090/targets

# Check Prometheus queries
# http://localhost:9090/graph
```

### Common Fixes

| Issue | Quick Fix |
|-------|-----------|
| Variable cascading broken | Fix variable order + add namespace filter to app query |
| Dashboard slow | Reduce time range, increase $rate, use filters |
| No data in panels | Check Prometheus targets, verify metrics endpoint |
| Dashboard not updating | Restart Grafana pod, check Operator logs |
| Query timeout | Increase datasource timeout, optimize query |

---

## Related Documentation

- [METRICS.md](METRICS.md) - Complete metrics documentation
- [AGENTS.md](../../AGENTS.md) - Dashboard variable best practices
- [README.md](../../README.md) - Project overview
- [ServiceMonitor](../../k8s/prometheus/servicemonitor-microservices.yaml) - Prometheus service discovery

---

**Need more help?**
- Check [Grafana documentation](https://grafana.com/docs/grafana/latest/)
- Check [Prometheus documentation](https://prometheus.io/docs/)
- Review [Grafana Operator docs](https://grafana-operator.github.io/grafana-operator/)

