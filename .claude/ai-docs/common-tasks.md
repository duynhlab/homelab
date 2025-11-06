# Common Tasks

## Update Dashboard
1. Edit `grafana-dashboard.json`
2. Apply ConfigMap: `kubectl create configmap grafana-dashboard-json --from-file=go-monitoring-demo.json=grafana-dashboard.json -n monitoring-demo --dry-run=client -o yaml | kubectl apply -f -`
3. Restart Grafana: `kubectl rollout restart deployment/grafana -n monitoring-demo`

## Add Prometheus Rule
1. Edit `k8s/prometheus/configmap.yaml`
2. Validate: `promtool check config k8s/prometheus/configmap.yaml`
3. Apply: `kubectl apply -f k8s/prometheus/configmap.yaml`
4. Restart: `kubectl rollout restart deployment/prometheus -n monitoring-demo`

## Add Panel
1. Copy existing panel in `grafana-dashboard.json`
2. Modify query, title, and description
3. Adjust `gridPos` for layout
4. Apply dashboard changes (see "Update Dashboard")

## Deploy App
1. Build image: `docker build -t demo-go-api:latest .`
2. Load to Kind: `kind load docker-image demo-go-api:latest --name monitoring-demo`
3. Apply deployment: `kubectl apply -f k8s/go-app/`
4. Verify: `kubectl get pods -n monitoring-demo`

## Check Logs
- **App logs**: `kubectl logs -l app=demo-go-api -n monitoring-demo`
- **Prometheus logs**: `kubectl logs -l app=prometheus -n monitoring-demo`
- **Grafana logs**: `kubectl logs -l app=grafana -n monitoring-demo`
- **k6 logs**: `kubectl logs -l app=k6-load-generator -n monitoring-demo`

## Port Forward
- **Grafana**: `kubectl port-forward -n monitoring-demo svc/grafana 3000:3000`
- **Prometheus**: `kubectl port-forward -n monitoring-demo svc/prometheus 9090:9090`
- **API**: `kubectl port-forward -n monitoring-demo svc/demo-go-api 8080:8080`

## Deploy SLO
1. Update SLO definitions in `slo/definitions/`
2. Run deploy script: `./scripts/11-deploy-slo.sh`
3. Verify: `kubectl exec -n monitoring-demo deployment/prometheus -- promtool query instant 'slo:availability:error_budget_remaining_30d'`

## Restart Deployments
```bash
kubectl rollout restart deployment/grafana -n monitoring-demo
kubectl rollout restart deployment/prometheus -n monitoring-demo
kubectl rollout restart deployment/demo-go-api -n monitoring-demo
```
