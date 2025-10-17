# k6 Load Testing Integration

## Overview

k6 is integrated as a **continuous load generator** running alongside CronJob load tests. It generates realistic traffic patterns to all API endpoints (V1, V2, V3) for comprehensive application monitoring.

## Architecture

```
┌─────────────────┐
│ k6 Pod          │ (Continuous Load Generator)
│ (Deployment)    │ - 5-10 Virtual Users
└────────┬────────┘ - Realistic scenarios
         │
         ├─► demo-go-api:8080 (V1)
         │   └─ /api/users, /api/v1/checkout
         │
         ├─► demo-go-api-v2:8080 (V2)
         │   └─ /api/products, /api/v2/orders
         │
         └─► demo-go-api-v3:8080 (V3)
             └─ /api/v3/users, /api/v3/products, /api/v3/orders, /api/v3/checkout
```

## Implementation

### Files

1. **k6/load-test.js** - Main test script
2. **k6/Dockerfile** - Custom k6 image with script embedded
3. **k8s/k6/deployment.yaml** - Kubernetes Deployment

### Load Test Characteristics

**Virtual Users (VUs):**
- Ramp-up: 30s to reach 5 VUs
- Sustained: 5 minutes at 5 VUs
- Peak: 30s to reach 10 VUs
- Sustained peak: 10 minutes at 10 VUs
- Ramp-down: 30s back to 5 VUs
- Cool-down: 5 minutes at 5 VUs
- Total duration: 22 minutes (then restarts)

**Traffic Distribution:**
- 33% traffic to V1 APIs (users, checkout)
- 33% traffic to V2 APIs (products, orders)
- 34% traffic to V3 APIs (all endpoints)

**Request Patterns:**
- 80% GET requests (read-heavy)
- 20% POST requests (writes)
- Think time: 1-3 seconds between iterations
- Health checks before each test

**Thresholds:**
- p95 response time < 1000ms
- p99 response time < 2000ms
- Error rate < 15%
- Request rate > 5 req/s

## Deployment

### Build & Deploy

```bash
# Build k6 image with script
docker build -t k6-prometheus:v2 -f k6/Dockerfile k6/

# Load into Kind
kind load docker-image k6-prometheus:v2 --name monitoring-demo

# Deploy k6
kubectl apply -f k8s/k6/deployment.yaml
```

### Verify

```bash
# Check k6 pod
kubectl get pods -l app=k6-load-generator -n monitoring-demo

# View logs
kubectl logs -l app=k6-load-generator -n monitoring-demo --tail=50

# Expected output:
# running (05m30s), 10/10 VUs, 450 complete and 0 interrupted iterations
# default   [  25% ] 10/10 VUs  05m30s/22m00.0s
```

## Metrics

### k6 Generates Load
k6 continuously generates realistic HTTP traffic to all API endpoints.

### Go App Exports Metrics
All performance metrics are exported by the Go application:
- Request duration (p50, p95, p99)
- Request rate (RPS)
- Error rate
- Requests in flight
- Network traffic
- Go runtime metrics

### Prometheus Collects
Prometheus scrapes metrics from Go app pods every 15s.

### Grafana Visualizes
Dashboard displays all 25 panels with real-time metrics.

## Benefits

### vs CronJob Load Tests

| Aspect | CronJob (curl) | k6 |
|--------|----------------|-----|
| **Pattern** | Fixed intervals (every 1 min) | Continuous with ramping |
| **Realism** | Simple requests | Complex user journeys |
| **Scenarios** | Basic | Advanced (80% GET, 20% POST) |
| **Virtual Users** | N/A | 5-10 concurrent VUs |
| **Think Time** | None | 1-3 seconds |
| **Control** | Limited | Full (stages, thresholds) |

### Coexistence

- **CronJobs**: Continue as-is (additional background traffic)
- **k6**: Advanced continuous load with realistic patterns
- **Combined**: Comprehensive traffic simulation

## Resource Usage

```yaml
resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
```

**Typical usage:**
- Memory: ~150-200Mi
- CPU: ~0.1-0.2 cores

## Scaling

### Increase Load

**Option 1: More VUs**
```javascript
// In k6/load-test.js
stages: [
  { duration: '30s', target: 20 },  // 5 → 20 VUs
  { duration: '10m', target: 20 },  // Stay at 20
]
```

**Option 2: More Replicas**
```yaml
# In k8s/k6/deployment.yaml
spec:
  replicas: 2  # Run 2 k6 pods
```

**Option 3: Remove Think Time**
```javascript
// In k6/load-test.js
// sleep(Math.random() * 2 + 1);  // Comment out for max load
```

### Decrease Load

**Option 1: Fewer VUs**
```javascript
stages: [
  { duration: '30s', target: 2 },  // Only 2 VUs
  { duration: '10m', target: 2 },
]
```

**Option 2: Scale to Zero**
```bash
kubectl scale deployment k6-load-generator --replicas=0 -n monitoring-demo
```

## Troubleshooting

### k6 Pod CrashLoopBackOff

**Check logs:**
```bash
kubectl logs -l app=k6-load-generator -n monitoring-demo
```

**Common issues:**
- Threshold syntax errors → Fix in `k6/load-test.js`
- Service not reachable → Check service names
- OOM → Increase memory limits

### High Resource Usage

**Check resource consumption:**
```bash
kubectl top pod -l app=k6-load-generator -n monitoring-demo
```

**Solutions:**
- Reduce VUs in test script
- Increase think time
- Scale down replicas

### No Traffic Visible

**Verify k6 is running:**
```bash
kubectl logs -l app=k6-load-generator -n monitoring-demo | grep "running"
```

**Check Go app metrics:**
```bash
curl http://localhost:9090/api/v1/query?query=rate(request_duration_seconds_count[1m])
```

## Modifying Load Tests

### Edit Test Script

1. Update `k6/load-test.js`
2. Rebuild image: `docker build -t k6-prometheus:v2 -f k6/Dockerfile k6/`
3. Load to Kind: `kind load docker-image k6-prometheus:v2 --name monitoring-demo`
4. Restart k6: `kubectl delete pod -l app=k6-load-generator -n monitoring-demo`

### Quick Changes

For testing without rebuilding image, you can temporarily use ConfigMap approach (not recommended for production).

## Best Practices

1. **Match Production Patterns**: Adjust GET/POST ratio to match real traffic
2. **Realistic Think Time**: Include delays between requests
3. **Gradual Ramp-up**: Avoid sudden spikes
4. **Monitor Resources**: Watch for OOM or CPU throttling
5. **Set Reasonable Thresholds**: Based on SLAs
6. **Test Incrementally**: Start small, scale up gradually

## Comparison with Alternatives

### k6 vs JMeter
- ✅ k6: Lighter, JavaScript-based, better for CI/CD
- ❌ JMeter: Heavier, GUI-based, more enterprise features

### k6 vs Locust
- ✅ k6: Better performance, built-in thresholds
- ❌ Locust: Python-based, easier for Python teams

### k6 vs Gatling
- ✅ k6: Simpler, better Prometheus integration
- ❌ Gatling: Scala-based, more powerful reports

## Future Enhancements

1. **Multiple Scenarios**: Separate tests for different user types
2. **Data-Driven Tests**: Load test data from files
3. **Custom Metrics**: Add business-specific metrics
4. **Distributed Load**: Run k6 across multiple pods
5. **Scheduled Tests**: Run specific scenarios at specific times

## References

- k6 Documentation: https://k6.io/docs/
- k6 Best Practices: https://k6.io/docs/misc/fine-tuning-os/
- Prometheus Integration: https://k6.io/docs/results-output/real-time/prometheus-remote-write/

---

**Status**: ✅ Active  
**Last Updated**: 2025-10-15  
**Maintained By**: DevOps Team

