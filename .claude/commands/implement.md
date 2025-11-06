# /implement Command

## Purpose
Execute implementation following best practices

## Instructions
1. Follow plan from `/plan`
2. For dashboard changes: update `grafana-dashboard.json`, use reload script
3. For Prometheus changes: update `k8s/prometheus/configmap.yaml`, validate with `promtool`, restart Prometheus
4. For k8s changes: apply manifests, verify pod status
5. For SLO changes: update definitions in `slo/definitions/`, use deployment script
6. Always test changes before marking complete

## Implementation Steps

### Dashboard Changes
1. Edit `grafana-dashboard.json`
2. Use reload script: `./scripts/08-reload-dashboard.sh`
   - Script handles ConfigMap creation/update and Grafana restart
3. Verify: Access Grafana at http://localhost:3000 and check dashboard UID: `microservices-monitoring-001`

### Prometheus Changes
1. Edit `k8s/prometheus/configmap.yaml`
2. Validate: `promtool check config <(kubectl get configmap prometheus-config -n monitoring -o jsonpath='{.data.prometheus\.yml}')`
3. Apply: `kubectl apply -f k8s/prometheus/configmap.yaml`
4. Restart: `kubectl rollout restart deployment/prometheus -n monitoring`
5. Verify: Check Prometheus targets at http://localhost:9090/targets

### Kubernetes Changes

**Service Deployment**
1. Edit relevant YAML files in `k8s/{service-name}/`
2. Apply: `kubectl apply -f k8s/{service-name}/`
3. Verify: `kubectl get pods -n {namespace}` (e.g., `kubectl get pods -n auth`)
4. Check logs: `kubectl logs -l app={service-name} -n {namespace}`

**Monitoring Components**
1. Edit relevant YAML files in `k8s/prometheus/`, `k8s/grafana/`, or `k8s/k6/`
2. Apply: `kubectl apply -f k8s/{component}/`
3. Verify: `kubectl get pods -n monitoring`
4. Check logs: `kubectl logs -l app={component-name} -n monitoring`

### SLO Changes
1. Edit SLO definitions in `slo/definitions/{service-name}.yaml`
2. Validate: `./scripts/09-validate-slo.sh`
3. Generate rules: `./scripts/10-generate-slo-rules.sh`
4. Deploy: `./scripts/11-deploy-slo.sh`
   - Script validates, generates, and deploys SLO rules
5. Verify rules loaded:
   ```bash
   kubectl exec -n monitoring deployment/prometheus -- promtool query instant 'slo:availability:error_budget_remaining_30d'
   ```
6. Check Prometheus rules: http://localhost:9090/api/v1/rules

### Service-Specific Changes

**Adding New Service**
1. Create service code: `cmd/{service-name}/main.go`, `internal/{service-name}/`
2. Create K8s manifests: `k8s/{service-name}/deployment.yaml`, `service.yaml`
3. Add namespace: Update `k8s/namespaces.yaml`
4. Create SLO definition: `slo/definitions/{service-name}.yaml`
5. Update build script: Add service to `scripts/03-build-microservices.sh`
6. Update deploy script: Add service to `scripts/04-deploy-microservices.sh`

## Testing
- Always verify changes work before marking complete
- Check for "No data" in Grafana panels
- Verify metrics are available in Prometheus
- Test port-forwarding if needed
- Check service health endpoints: `curl http://localhost:8080/health`
