# Command Reference

Complete reference for deployment scripts, Helm commands, kubectl shortcuts, and access points.

---

## Deployment Scripts

Numbered scripts (01-12) execute in order. See [`docs/guides/SETUP.md`](SETUP.md) for deployment guide.

| Script | Command | Purpose | Order |
|--------|---------|---------|-------|
| Create cluster | `./scripts/01-create-kind-cluster.sh` | Create Kind Kubernetes cluster | 1 |
| Deploy monitoring | `./scripts/02-deploy-monitoring.sh` | Deploy Prometheus, Grafana, metrics | 2 |
| Deploy APM | `./scripts/03-deploy-apm.sh` | Deploy all APM components (BEFORE apps) | 3 |
| Deploy databases | `./scripts/04-deploy-databases.sh` | Deploy PostgreSQL operators, clusters, poolers | 4 |
| Deploy services | `./scripts/06-deploy-microservices.sh` | Deploy from OCI registry (images built by GitHub Actions) | 5 |
| Deploy k6 | `./scripts/07-deploy-k6.sh` | Deploy k6 load generators (AFTER apps) | 6 |
| Deploy SLO | `./scripts/08-deploy-slo.sh` | Deploy Sloth Operator and SLO CRDs | 7 |
| Setup access | `./scripts/09-setup-access.sh` | Setup port-forwarding | 8 |
| Reload dashboard | `./scripts/10-reload-dashboard.sh` | Reapply Grafana dashboards | - |
| Diagnose latency | `./scripts/11-diagnose-latency.sh` | Analyze latency issues | - |
| Error budget alert | `./scripts/12-error-budget-alert.sh` | Respond to error budget alerts | - |

**Detailed Deployment Guide**: See [`docs/guides/SETUP.md`](SETUP.md)

---

## Helm Commands

| Command | Purpose |
|---------|---------|
| `helm list -A` | List all Helm releases |
| `helm upgrade --install <name> charts/ -f charts/values/<service>.yaml -n <ns>` | Install/upgrade service |
| `helm uninstall <name> -n <namespace>` | Uninstall a service |
| `helm pull oci://ghcr.io/duynhne/charts/microservice` | Pull chart from OCI registry |

**Example:**
```bash
# Install/upgrade auth service
helm upgrade --install auth charts/ -f charts/values/auth.yaml -n auth --create-namespace

# List all releases
helm list -A

# Uninstall a service
helm uninstall auth -n auth
```

---

## kubectl Shortcuts

| Command | Purpose |
|---------|---------|
| `kubectl get pods -n {namespace}` | List pods in namespace |
| `kubectl logs -l app={service-name} -n {namespace}` | View service logs |
| `kubectl port-forward -n monitoring svc/grafana-service 3000:3000` | Port-forward Grafana |
| `kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090` | Port-forward Prometheus |
| `kubectl port-forward -n monitoring svc/jaeger-all-in-one 16686:16686` | Port-forward Jaeger UI |
| `kubectl rollout restart deployment/{name} -n {namespace}` | Restart deployment |

**Examples:**
```bash
# List all pods in auth namespace
kubectl get pods -n auth

# View auth service logs
kubectl logs -l app=auth -n auth -f

# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana-service 3000:3000

# Restart auth deployment
kubectl rollout restart deployment/auth -n auth
```

---

## Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger UI | http://localhost:16686 | - |
| Tempo | http://localhost:3200 | - |
| API (via port-forward) | http://localhost:8080 | - |

**Setup Access:**
```bash
# Run setup script to port-forward all services
./scripts/09-setup-access.sh

# Or manually port-forward specific service
kubectl port-forward -n auth svc/auth 8080:8080
```

---

## Quick Commands by Task

### Check Service Status
```bash
# List pods in namespace
kubectl get pods -n {namespace}

# Check pod logs
kubectl logs -l app={service-name} -n {namespace} -f

# Describe pod for troubleshooting
kubectl describe pod {pod-name} -n {namespace}
```

### Deploy Service
```bash
# Deploy single service
helm upgrade --install {service} charts/ -f charts/values/{service}.yaml -n {service} --create-namespace

# Deploy all services
./scripts/06-deploy-microservices.sh
```

### Access Monitoring
```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana-service 3000:3000

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Port-forward Jaeger
kubectl port-forward -n monitoring svc/jaeger-all-in-one 16686:16686
```

### Troubleshooting
```bash
# Check deployment status
kubectl get deployment {service-name} -n {namespace}

# View events
kubectl get events -n {namespace} --sort-by='.lastTimestamp'

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus targets
# Access Prometheus UI and navigate to Status > Targets
```

---

## Related Documentation

- **[AGENTS.md](../../AGENTS.md)** - Main agent guide with workflow
- **[SETUP.md](SETUP.md)** - Complete deployment guide
- **[TROUBLESHOOTING.md](../monitoring/TROUBLESHOOTING.md)** - Common issues and solutions

