# Troubleshooting

## "No data" in Panel
**Symptoms**: Panel shows "No data" message
**Causes**:
- Metric doesn't exist in Prometheus
- Query syntax error
- Time range too short
- Pod not running

**Solutions**:
1. Check Prometheus targets: `kubectl exec -n monitoring-demo deployment/prometheus -- promtool query instant 'up'`
2. Verify metric exists: `kubectl exec -n monitoring-demo deployment/prometheus -- promtool query instant 'request_duration_seconds_count'`
3. Check pod status: `kubectl get pods -n monitoring-demo`
4. Check logs: `kubectl logs -l app=demo-go-api -n monitoring-demo`

## "Datasource not found"
**Symptoms**: Dashboard shows "Datasource prometheus not found"
**Causes**:
- Hardcoded datasource UID
- Datasource not configured
- Grafana not restarted after config change

**Solutions**:
1. Check datasource UID in dashboard JSON (should be `${DS_PROMETHEUS}`)
2. Verify Grafana datasource config: `kubectl get configmap grafana-datasources -n monitoring-demo -o yaml`
3. Restart Grafana: `kubectl rollout restart deployment/grafana -n monitoring-demo`

## ConfigMap Not Updated
**Symptoms**: Changes not reflected after editing ConfigMap
**Causes**:
- Deployment not restarted
- ConfigMap not applied
- Volume mount issue

**Solutions**:
1. Apply ConfigMap: `kubectl apply -f k8s/grafana/configmap-dashboard-json.yaml`
2. Restart deployment: `kubectl rollout restart deployment/grafana -n monitoring-demo`
3. Check volume mount: `kubectl describe deployment grafana -n monitoring-demo`

## k6 OOMKilled
**Symptoms**: k6 pod shows OOMKilled status
**Causes**:
- Insufficient memory limits
- Too many VUs
- Memory leak in k6 script

**Solutions**:
1. Increase memory limits in `k8s/k6/deployment.yaml`
2. Reduce VUs in `k6/load-test.js`
3. Check k6 logs: `kubectl logs -l app=k6-load-generator -n monitoring-demo`

## Prometheus Rules Not Loading
**Symptoms**: SLO metrics not appearing
**Causes**:
- Syntax error in rules
- Rules not applied
- Prometheus not restarted

**Solutions**:
1. Validate rules: `promtool check config k8s/prometheus/configmap.yaml`
2. Apply rules: `kubectl apply -f k8s/prometheus/configmap.yaml`
3. Restart Prometheus: `kubectl rollout restart deployment/prometheus -n monitoring-demo`

## Dashboard Not Auto-Loading
**Symptoms**: Dashboard not appearing in Grafana
**Causes**:
- ConfigMap not mounted
- JSON syntax error
- Grafana not restarted

**Solutions**:
1. Check volume mount: `kubectl describe deployment grafana -n monitoring-demo`
2. Validate JSON: `jq . grafana-dashboard.json`
3. Restart Grafana: `kubectl rollout restart deployment/grafana -n monitoring-demo`

## Port Forward Issues
**Symptoms**: Cannot access services locally
**Causes**:
- Port already in use
- Service not running
- Wrong service name

**Solutions**:
1. Check service: `kubectl get svc -n monitoring-demo`
2. Use different port: `kubectl port-forward -n monitoring-demo svc/grafana 3001:3000`
3. Check if port is in use: `netstat -tulpn | grep 3000`
