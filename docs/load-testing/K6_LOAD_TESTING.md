# k6 Load Testing

## Overview

k6 chạy như **continuous load generator** để tạo traffic cho tất cả microservices (V1, V2, V3) phục vụ monitoring và load testing.

## Files

- **k8s/k6/load-test.js** - Legacy test (random testing tất cả services)
- **k8s/k6/load-test-multiple-scenarios.js** - Multiple scenarios test (5 user personas)
- **k8s/k6/deployment-legacy.yaml** - Deployment cho legacy test
- **k8s/k6/deployment-multiple-scenarios.yaml** - Deployment cho multiple scenarios test
- **scripts/07-deploy-k6-testing.sh** - Script deploy (hỗ trợ 3 modes)

## Deploy Modes

### 1. Both (default) - Chạy cả 2 cùng lúc

```bash
./scripts/07-deploy-k6-testing.sh both
# hoặc
./scripts/07-deploy-k6-testing.sh
```

**Kết quả:**
- 2 pods chạy song song
- Legacy pod: Random testing (100 VUs peak)
- Scenarios pod: 5 user personas (100 VUs total: 40+30+15+10+5)
- **Total load: ~200 VUs**

### 2. Legacy Only - Chỉ random testing

```bash
./scripts/07-deploy-k6-testing.sh legacy
```

**Kết quả:**
- 1 pod: Random testing tất cả services
- Peak: 100 VUs
- Duration: 21 minutes (rồi restart)

### 3. Multiple Scenarios Only - Chỉ user personas

```bash
./scripts/07-deploy-k6-testing.sh multiple
```

**Kết quả:**
- 1 pod: 5 user scenarios
- Peak: 100 VUs (40 browser + 30 shopping + 15 registered + 10 API + 5 admin)
- Duration: 21 minutes (rồi restart)

## Verify

```bash
# Check pods
kubectl get pods -n monitoring -l 'app in (k6-load-generator-legacy,k6-load-generator-scenarios)'

# View legacy logs
kubectl logs -n monitoring -l app=k6-load-generator-legacy -f

# View scenarios logs
kubectl logs -n monitoring -l app=k6-load-generator-scenarios -f
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

**Pod không chạy:**
```bash
kubectl logs -n monitoring -l app=k6-load-generator-legacy
kubectl logs -n monitoring -l app=k6-load-generator-scenarios
```

**No traffic trong Grafana:**
- Check pods đang running
- Check service URLs trong test script
- Check Prometheus scrape config

**High resource usage:**
- Reduce VUs trong test script
- Scale down: `kubectl scale deployment k6-load-generator-legacy --replicas=0 -n monitoring`

## Update Test Script

1. Edit `k8s/k6/load-test.js` hoặc `k8s/k6/load-test-multiple-scenarios.js`
2. Redeploy: `./scripts/07-deploy-k6-testing.sh both`
3. ConfigMap tự động update, pods sẽ restart
