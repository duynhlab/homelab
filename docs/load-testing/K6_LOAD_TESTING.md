# k6 Load Testing

## Overview

k6 runs as **continuous load generators** to create traffic for all microservices (V1, V2) for monitoring and load testing. The k6 deployment is managed via Helm, similar to the microservices.

## Architecture

k6 is deployed using:
- **Helm Chart**: Reuses the same generic chart (`charts/`) used for microservices
- **Docker Images**: Built from unified `k6/Dockerfile` with ARG-based script selection
- **Namespace**: Dedicated `k6` namespace for all k6 deployments
- **GitHub Actions**: Automated image builds via `.github/workflows/build-k6-images.yml`

## Files

- **k6/Dockerfile** - Unified Dockerfile (ARG `SCRIPT_NAME` to select test script)
- **k6/load-test.js** - Legacy test (random testing all services)
- **k6/load-test-multiple-scenarios.js** - Multiple scenarios test (5 user personas)
- **charts/values/k6-legacy.yaml** - Helm values for legacy test
- **charts/values/k6-scenarios.yaml** - Helm values for scenarios test
- **scripts/07-deploy-k6.sh** - Deployment script (supports 3 modes)

## Deploy Modes

### 1. All (default) - Run both variants

```bash
./scripts/07-deploy-k6.sh
# or explicitly:
# ./scripts/07-deploy-k6.sh all
```

**Result:**
- 2 pods running in parallel (in `k6` namespace)
- Legacy pod: Random testing (100 VUs peak)
- Scenarios pod: 5 user personas (100 VUs total: 40+30+15+10+5)
- **Total load: ~200 VUs**

### 2. Legacy Only - Random testing only

```bash
./scripts/07-deploy-k6.sh legacy
```

**Result:**
- 1 pod: Random testing all services
- Peak: 100 VUs
- Duration: 21 minutes (then restarts)

### 3. Scenarios Only - User personas only

```bash
./scripts/07-deploy-k6.sh scenarios
```

**Result:**
- 1 pod: 5 user scenarios
- Peak: 100 VUs (40 browser + 30 shopping + 15 registered + 10 API + 5 admin)
- Duration: 21 minutes (then restarts)

## Verify

```bash
# Check pods
kubectl get pods -n k6

# View legacy logs
kubectl logs -n k6 -l app=k6-legacy -f

# View scenarios logs
kubectl logs -n k6 -l app=k6-scenarios -f

# Check Helm releases
helm list -n k6
```

## Load Test Details

### Legacy Test (`load-test.js`)

**Virtual Users:**
- Ramp-up: 1m→20, 2m→50, 5m→100 VUs
- Sustained: 10m at 100 VUs
- Ramp-down: 2m→50, 1m→0
- **Duration: 21 minutes** (auto-restart)

**Traffic:**
- Tests all 9 microservices (equal distribution)
- 70-80% GET, 20-30% POST
- Think time: 0.1-0.2s between requests
- Health checks: Only 10% of iterations (monitoring, not load testing)
  - Prometheus/Kubernetes probes already handle health monitoring
  - Reduces noise in Grafana metrics by 90%
  - Focuses load testing on actual business API endpoints

**Thresholds:**
- p95 < 500ms, p99 < 1000ms
- Error rate < 5%
- Request rate > 50 req/s

### Multiple Scenarios Test (`load-test-multiple-scenarios.js`)

**5 User Personas:**
1. **Browser User (40%)** - Browse products, read reviews
2. **Shopping User (30%)** - Complete shopping flow (cart → checkout)
3. **Registered User (15%)** - Authenticated actions (profile, orders)
4. **API Client (10%)** - High-volume API calls
5. **Admin User (5%)** - Management operations

**Virtual Users:**
- Same stages as legacy (peak: 100 VUs total)
- Distribution: 40 + 30 + 15 + 10 + 5 VUs
- Each scenario có flow riêng

**Traffic:**
- Health checks: Only 10% of iterations per scenario (monitoring, not load testing)
  - Prometheus/Kubernetes probes already handle health monitoring
  - Reduces noise in Grafana metrics by 90%
  - Focuses load testing on actual business API endpoints
- Note: `/metrics` endpoint is NOT tested by k6 (only Prometheus scrapes it)

**Thresholds:**
- Per-scenario thresholds (API client: p95 < 300ms)
- Shopping flow: p95 < 1000ms (có thể chậm hơn)

## Metrics Flow

1. **k6** → Generates HTTP traffic
2. **Go apps** → Export metrics (duration, RPS, errors, etc.)
3. **Prometheus** → Scrapes metrics mỗi 15s
4. **Grafana** → Visualizes trong dashboard (32 panels)

## Troubleshooting

**Pods not running:**
```bash
kubectl logs -n k6 -l app=k6-legacy
kubectl logs -n k6 -l app=k6-scenarios
kubectl describe pod -n k6
```

**No traffic in Grafana:**
- Check pods are running: `kubectl get pods -n k6`
- Check service URLs in test scripts
- Check Prometheus scrape config
- Verify microservices are running in their respective namespaces

**High resource usage:**
- Reduce VUs in test scripts (edit `k6/*.js`)
- Scale down specific deployment:
  - `kubectl scale deployment k6-legacy --replicas=0 -n k6`
  - `kubectl scale deployment k6-scenarios --replicas=0 -n k6`
- Or uninstall specific release:
  - `helm uninstall k6-legacy -n k6`
  - `helm uninstall k6-scenarios -n k6`

## Update Test Scripts

1. Edit `k6/load-test.js` or `k6/load-test-multiple-scenarios.js`
2. Rebuild k6 images: `./scripts/05-build-microservices.sh` (includes k6 builds)
3. Redeploy: `./scripts/07-deploy-k6.sh`
4. Pods will automatically use new images (ImagePullPolicy: Never for local images)
