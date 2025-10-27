# /implement Command

## Purpose
Execute implementation following best practices

## Instructions
1. Follow plan from `/plan`
2. For dashboard changes: update `grafana-dashboard.json`, apply ConfigMap, restart Grafana
3. For Prometheus changes: update `k8s/prometheus/configmap.yaml`, validate with `promtool`, restart Prometheus
4. For k8s changes: apply manifests, verify pod status
5. For SLO changes: update rules in `slo/k8s/`, run `slo/scripts/deploy-slo.sh`
6. Always test changes before marking complete

## Implementation Steps

### Dashboard Changes
1. Edit `grafana-dashboard.json`
2. Apply ConfigMap: `kubectl create configmap grafana-dashboard-json --from-file=go-monitoring-demo.json=grafana-dashboard.json -n monitoring-demo --dry-run=client -o yaml | kubectl apply -f -`
3. Restart Grafana: `kubectl rollout restart deployment/grafana -n monitoring-demo`

### Prometheus Changes
1. Edit `k8s/prometheus/configmap.yaml`
2. Validate: `promtool check config k8s/prometheus/configmap.yaml`
3. Apply: `kubectl apply -f k8s/prometheus/configmap.yaml`
4. Restart: `kubectl rollout restart deployment/prometheus -n monitoring-demo`

### Kubernetes Changes
1. Edit relevant YAML files in `k8s/`
2. Apply: `kubectl apply -f k8s/{component}/`
3. Verify: `kubectl get pods -n monitoring-demo`
4. Check logs: `kubectl logs -l app={name} -n monitoring-demo`

### SLO Changes
1. Edit rules in `slo/k8s/`
2. Run deploy script: `./slo/scripts/deploy-slo.sh`
3. Verify rules loaded: `kubectl exec -n monitoring-demo deployment/prometheus -- promtool query instant 'slo:availability:error_budget_remaining_30d'`

## Testing
- Always verify changes work before marking complete
- Check for "No data" in panels
- Verify metrics are available in Prometheus
- Test port-forwarding if needed
