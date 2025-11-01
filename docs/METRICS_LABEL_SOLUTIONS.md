# 3 Giải Pháp Fix Metrics App Label

## Vấn Đề Hiện Tại

**Root Cause**: Go application hardcode `app="demo-go-api"` trong metrics, trong khi dashboard filter theo tên service mới (`user-service`, `product-service`, etc.)

**Impact**: 
- ✅ Go runtime metrics có data (vì không dùng custom `app` label)
- ❌ Custom metrics (request_duration_seconds) "No data" vì label mismatch
- ❌ Chỉ 2/5 row groups hiển thị data

**Hiện tại**:
```promql
# Metrics từ app
request_duration_seconds_count{app="demo-go-api", exported_app="demo-go-api"}

# Dashboard query
request_duration_seconds_count{app=~"$app"}  # $app = "user-service"
# → No match → No data
```

---

## Giải Pháp 1: Kubernetes Downward API ⭐ (RECOMMENDED)

### Mô tả
Sử dụng Kubernetes Downward API để tự động inject pod labels vào environment variables.

### Ưu điểm
- ✅ **Tự động**: Không cần hardcode tên service
- ✅ **Scalable**: Mọi service mới tự động work
- ✅ **Consistent**: Lấy từ label Kubernetes đã có sẵn
- ✅ **Zero maintenance**: Không cần update khi thêm service mới
- ✅ **Cloud-native best practice**: Sử dụng Kubernetes native features

### Nhược điểm
- ⚠️ Cần update 5 deployments (one-time change)
- ⚠️ Pods phải restart để apply changes

### Chi tiết Implementation

#### Step 1: Update Deployments

**File**: `k8s/user-service-v1/deployment.yaml` (và tương tự cho 4 services khác)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service-v1
  namespace: user
  labels:
    app: user-service  # ← Label này
    version: v1
spec:
  template:
    metadata:
      labels:
        app: user-service  # ← Label này
    spec:
      containers:
      - name: user-service
        image: user-service-v1:latest
        env:
        - name: APP_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['app']  # ← Tự động lấy từ label
        ports:
        - containerPort: 8080
```

**Giải thích**:
- `fieldPath: metadata.labels['app']` → Kubernetes tự động đọc label `app` từ pod metadata
- Mỗi pod sẽ có `APP_NAME` = giá trị label `app` của nó
- User service → `APP_NAME=user-service`
- Product service → `APP_NAME=product-service`

#### Step 2: Apply Changes

```bash
# Update tất cả deployments
kubectl apply -f k8s/user-service-v1/deployment.yaml
kubectl apply -f k8s/product-service-v1/deployment.yaml
kubectl apply -f k8s/checkout-service-v1/deployment.yaml
kubectl apply -f k8s/order-service-v2/deployment.yaml
kubectl apply -f k8s/unified-service-v3/deployment.yaml

# Wait for rollout
kubectl rollout status deployment/user-service-v1 -n user
kubectl rollout status deployment/product-service-v1 -n product
kubectl rollout status deployment/checkout-service-v1 -n checkout
kubectl rollout status deployment/order-service-v2 -n order
kubectl rollout status deployment/unified-service-v3 -n unified
```

#### Step 3: Verify

```bash
# Check pod có env var đúng không
kubectl exec -n user deployment/user-service-v1 -- env | grep APP_NAME
# Output: APP_NAME=user-service

# Check metrics
curl -s "http://localhost:9090/api/v1/query?query=request_duration_seconds_count" | jq '.data.result[0].metric.app'
# Output: "user-service" ✅
```

### Expected Result
- Pods restart với env var mới
- Metrics có label `app="user-service"`, `app="product-service"`, etc.
- Dashboard queries match → All panels show data ✅

### Files to Change
- `k8s/user-service-v1/deployment.yaml`
- `k8s/product-service-v1/deployment.yaml`
- `k8s/checkout-service-v1/deployment.yaml`
- `k8s/order-service-v2/deployment.yaml`
- `k8s/unified-service-v3/deployment.yaml`

**Total**: 5 files, ~10 minutes work

---

## Giải Pháp 2: Remove App Label from Application Code ⚡ (SIMPLEST)

### Mô tả
Xóa label `app` khỏi Go metrics, để ServiceMonitor tự động add từ Kubernetes.

### Ưu điểm
- ✅ **Simplest**: Chỉ sửa 1 file Go code
- ✅ **No deployment changes**: Không cần update K8s manifests
- ✅ **Truly dynamic**: Label `app` hoàn toàn từ Kubernetes
- ✅ **Less error-prone**: Không thể hardcode sai tên

### Nhược điểm
- ⚠️ Cần rebuild Docker images (5 images)
- ⚠️ ServiceMonitor relabeling phải hoạt động đúng
- ⚠️ Phụ thuộc vào Kubernetes labels (không work nếu run ngoài K8s)

### Chi tiết Implementation

#### Step 1: Update Go Middleware

**File**: `pkg/middleware/prometheus.go`

**Before**:
```go
RequestLatency = promauto.NewHistogramVec(
    prometheus.HistogramOpts{
        Name: "request_duration_seconds",
        Help: "Latency of HTTP requests in seconds",
        Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
    },
    []string{"app", "method", "path", "code"},  // ← Có "app"
)

// Usage
RequestLatency.WithLabelValues(appName, r.Method, r.URL.Path, statusCode).Observe(duration)
```

**After**:
```go
RequestLatency = promauto.NewHistogramVec(
    prometheus.HistogramOpts{
        Name: "request_duration_seconds",
        Help: "Latency of HTTP requests in seconds",
        Buckets: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
    },
    []string{"method", "path", "code"},  // ← Xóa "app"
)

// Usage
RequestLatency.WithLabelValues(r.Method, r.URL.Path, statusCode).Observe(duration)
```

**Changes**:
- Remove `"app"` from label arrays
- Remove `appName` parameter from `WithLabelValues()`
- Remove `getAppName()` function (không cần nữa)

Apply to all 6 metrics:
1. `RequestLatency` (request_duration_seconds)
2. `RequestTotal` (requests_total)
3. `RequestsInFlight` (requests_in_flight)
4. `RequestSize` (request_size_bytes)
5. `ResponseSize` (response_size_bytes)
6. `ErrorRateTotal` (error_rate_total)

#### Step 2: Verify ServiceMonitor Config

**File**: `k8s/monitoring/servicemonitors.yaml`

Đảm bảo có `metricRelabelings`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: microservices-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      component: api
  namespaceSelector:
    matchNames:
    - user
    - product
    - checkout
    - order
    - unified
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
    metricRelabelings:
    - sourceLabels: [__meta_kubernetes_service_label_app]
      targetLabel: app  # ← ServiceMonitor add label này
    - sourceLabels: [__meta_kubernetes_service_label_version]
      targetLabel: version
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
```

**How it works**:
1. App exports metrics **without** `app` label
2. Prometheus scrapes metrics qua ServiceMonitor
3. ServiceMonitor đọc Service label `app: user-service`
4. `metricRelabelings` add `app="user-service"` vào metrics
5. Metrics trong Prometheus có đủ label ✅

#### Step 3: Rebuild & Redeploy

```bash
# Rebuild all images using unified Dockerfile
docker build --build-arg SERVICE_NAME=user-service -f Dockerfile -t user-service:latest .
docker build --build-arg SERVICE_NAME=product-service -f Dockerfile -t product-service:latest .
docker build --build-arg SERVICE_NAME=cart-service -f Dockerfile -t cart-service:latest .
docker build --build-arg SERVICE_NAME=order-service -f Dockerfile -t order-service:latest .
docker build --build-arg SERVICE_NAME=review-service -f Dockerfile -t review-service:latest .

# Load into Kind
kind load docker-image user-service-v1:latest --name monitoring-demo
kind load docker-image product-service-v1:latest --name monitoring-demo
kind load docker-image checkout-service-v1:latest --name monitoring-demo
kind load docker-image order-service-v2:latest --name monitoring-demo
kind load docker-image unified-service-v3:latest --name monitoring-demo

# Restart deployments
kubectl rollout restart deployment/user-service-v1 -n user
kubectl rollout restart deployment/product-service-v1 -n product
kubectl rollout restart deployment/checkout-service-v1 -n checkout
kubectl rollout restart deployment/order-service-v2 -n order
kubectl rollout restart deployment/unified-service-v3 -n unified
```

#### Step 4: Verify

```bash
# Check metrics từ pod (không có app label)
kubectl port-forward -n user deployment/user-service-v1 8080:8080
curl -s http://localhost:8080/metrics | grep request_duration_seconds_count | head -1
# Output: request_duration_seconds_count{method="GET",path="/health",code="200"} 10

# Check metrics trong Prometheus (có app label từ ServiceMonitor)
curl -s "http://localhost:9090/api/v1/query?query=request_duration_seconds_count" | jq '.data.result[0].metric'
# Output: {"app":"user-service","method":"GET","path":"/health","code":"200",...}
```

### Expected Result
- Metrics từ app: Không có `app` label
- Metrics trong Prometheus: Có `app` label (added by ServiceMonitor)
- Dashboard queries match → All panels show data ✅

### Files to Change
- `pkg/middleware/prometheus.go` (1 file)

**Total**: 1 file, rebuild 5 images, ~20 minutes work

---

## Giải Pháp 3: Add Static APP_NAME Environment Variable 📝 (EXPLICIT)

### Mô tả
Thêm hardcoded `APP_NAME` env var vào mỗi deployment.

### Ưu điểm
- ✅ **Explicit**: Rõ ràng, dễ debug
- ✅ **No code changes**: Không sửa Go code
- ✅ **No rebuild**: Không rebuild images
- ✅ **Works everywhere**: Local, Docker, Kubernetes

### Nhược điểm
- ❌ **Not scalable**: Phải update deployment cho mỗi service mới
- ❌ **Error-prone**: Có thể gõ sai tên service
- ❌ **Maintenance overhead**: Phải nhớ set APP_NAME mỗi lần
- ❌ **Duplicated config**: Tên service ở 3 chỗ (deployment name, label, env var)

### Chi tiết Implementation

#### Step 1: Update Deployments

**File**: `k8s/user-service-v1/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service-v1
  namespace: user
  labels:
    app: user-service
    version: v1
spec:
  template:
    spec:
      containers:
      - name: user-service
        image: user-service-v1:latest
        env:
        - name: APP_NAME
          value: "user-service"  # ← Hardcode
        ports:
        - containerPort: 8080
```

Tương tự cho:
- `product-service-v1` → `APP_NAME=product-service`
- `checkout-service-v1` → `APP_NAME=checkout-service`
- `order-service-v2` → `APP_NAME=order-service`
- `unified-service-v3` → `APP_NAME=unified-service`

#### Step 2: Apply Changes

```bash
kubectl apply -f k8s/user-service-v1/deployment.yaml
kubectl apply -f k8s/product-service-v1/deployment.yaml
kubectl apply -f k8s/checkout-service-v1/deployment.yaml
kubectl apply -f k8s/order-service-v2/deployment.yaml
kubectl apply -f k8s/unified-service-v3/deployment.yaml

# Wait for rollout
kubectl rollout status deployment/user-service-v1 -n user
kubectl rollout status deployment/product-service-v1 -n product
kubectl rollout status deployment/checkout-service-v1 -n checkout
kubectl rollout status deployment/order-service-v2 -n order
kubectl rollout status deployment/unified-service-v3 -n unified
```

#### Step 3: Verify

```bash
# Check env var
kubectl exec -n user deployment/user-service-v1 -- env | grep APP_NAME
# Output: APP_NAME=user-service

# Check metrics
curl -s "http://localhost:9090/api/v1/query?query=request_duration_seconds_count{app='user-service'}"
```

### Expected Result
- Pods restart với env var mới
- Metrics có label `app="user-service"` (từ Go code)
- Dashboard queries match → All panels show data ✅

### Files to Change
- `k8s/user-service-v1/deployment.yaml`
- `k8s/product-service-v1/deployment.yaml`
- `k8s/checkout-service-v1/deployment.yaml`
- `k8s/order-service-v2/deployment.yaml`
- `k8s/unified-service-v3/deployment.yaml`

**Total**: 5 files, ~5 minutes work

### Future Service Example

```yaml
# k8s/payment-service-v1/deployment.yaml
env:
- name: APP_NAME
  value: "payment-service"  # ← Phải nhớ set này mỗi lần
```

---

## So Sánh 3 Giải Pháp

| Tiêu chí | Solution 1: Downward API | Solution 2: Remove Label | Solution 3: Static Env Var |
|---------|-------------------------|-------------------------|---------------------------|
| **Complexity** | 🟡 Medium | 🟢 Low | 🟢 Low |
| **Files to change** | 5 deployments | 1 Go file | 5 deployments |
| **Rebuild images** | ❌ No | ✅ Yes | ❌ No |
| **Restart pods** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Scalability** | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐ Poor |
| **Maintenance** | ⭐⭐⭐⭐⭐ Zero | ⭐⭐⭐⭐ Low | ⭐⭐ High |
| **Error-prone** | ⭐⭐⭐⭐⭐ Very safe | ⭐⭐⭐⭐ Safe | ⭐⭐ Easy to typo |
| **Cloud-native** | ⭐⭐⭐⭐⭐ Best practice | ⭐⭐⭐⭐ Good | ⭐⭐⭐ OK |
| **Works outside K8s** | ⭐⭐ K8s only | ⭐⭐ K8s only | ⭐⭐⭐⭐⭐ Everywhere |
| **Time to implement** | ~10 min | ~20 min | ~5 min |
| **Recommended for** | Production | Greenfield project | Quick fix |

---

## Recommendation Matrix

### Chọn Solution 1 (Downward API) nếu:
- ✅ Bạn muốn giải pháp **production-ready**
- ✅ Có kế hoạch thêm nhiều services trong tương lai
- ✅ Muốn follow Kubernetes best practices
- ✅ Không muốn maintain hardcoded values

**Best for**: Long-term production systems

### Chọn Solution 2 (Remove Label) nếu:
- ✅ Bạn thích **simplicity** và **clean code**
- ✅ Chỉ chạy trong Kubernetes (không local Docker)
- ✅ Muốn metrics hoàn toàn dynamic
- ✅ OK với việc rebuild images

**Best for**: Kubernetes-only deployments, greenfield projects

### Chọn Solution 3 (Static Env) nếu:
- ✅ Bạn cần **quick fix ngay**
- ✅ Không có thời gian rebuild images
- ✅ Chỉ có vài services (< 10)
- ✅ Cần work cả local và K8s

**Best for**: Quick fixes, small projects, POCs

---

## My Recommendation: Solution 1 (Downward API) ⭐

**Lý do**:
1. **Zero maintenance**: Thêm service mới chỉ cần copy deployment template
2. **No typos**: Không thể gõ sai tên service (lấy từ label)
3. **Kubernetes-native**: Sử dụng feature có sẵn của K8s
4. **Scalable**: Works với 5 services hay 500 services
5. **No rebuild**: Chỉ cần update YAML và apply

**Trade-off chấp nhận được**:
- Pods phải restart (chấp nhận, chỉ 1 lần)
- Chỉ work trong K8s (OK, ta đang deploy trên K8s)

---

## Implementation Guide - Solution 1

### Quick Start

```bash
# 1. Add env var to all deployments (see detailed YAML above)

# 2. Apply changes
for service in user product checkout order unified; do
  kubectl apply -f k8s/${service}-service*/deployment.yaml
done

# 3. Wait for rollout
for ns in user product checkout order unified; do
  kubectl rollout status deployment -n $ns --timeout=60s
done

# 4. Verify
curl -s "http://localhost:9090/api/v1/label/app/values" | jq

# 5. Refresh Grafana dashboard
# All panels should show data now! ✅
```

### Testing

```bash
# Test 1: Check env var in pod
kubectl exec -n user deployment/user-service-v1 -- printenv | grep APP_NAME
# Expected: APP_NAME=user-service

# Test 2: Check metrics
curl -s "http://localhost:9090/api/v1/query?query=request_duration_seconds_count" | jq '.data.result[] | .metric.app' | sort -u
# Expected: 
# "checkout-service"
# "order-service"
# "product-service"
# "unified-service"
# "user-service"

# Test 3: Verify dashboard
# Go to http://localhost:3000
# All 32 panels should show data
```

---

## Rollback Plan (If Needed)

Nếu có vấn đề, rollback về version trước:

```bash
# Solution 1 & 3: Rollback deployments
kubectl rollout undo deployment/user-service-v1 -n user
kubectl rollout undo deployment/product-service-v1 -n product
kubectl rollout undo deployment/checkout-service-v1 -n checkout
kubectl rollout undo deployment/order-service-v2 -n order
kubectl rollout undo deployment/unified-service-v3 -n unified

# Solution 2: Rollback + redeploy old images
git checkout HEAD~1 pkg/middleware/prometheus.go
# Rebuild and redeploy images
```

---

## FAQ

**Q: Tại sao Go runtime metrics có data nhưng custom metrics không?**
A: Go runtime metrics (go_memstats, go_goroutines) không có custom `app` label, nên không bị ảnh hưởng bởi mismatch.

**Q: ServiceMonitor metricRelabelings có hoạt động không?**
A: Có, nhưng nó chỉ **add thêm** labels, không **overwrite** labels có sẵn từ app. Nếu app export `app="demo-go-api"`, Prometheus sẽ giữ nguyên.

**Q: Giải pháp nào nhanh nhất?**
A: Solution 3 (Static Env) - 5 phút. Nhưng không scalable.

**Q: Giải pháp nào tốt nhất long-term?**
A: Solution 1 (Downward API) - Zero maintenance, Kubernetes-native.

**Q: Có thể combine solutions không?**
A: Có thể. Ví dụ: Dùng Solution 1 cho production, Solution 3 cho local development.

---

## Next Steps

1. **Review** 3 giải pháp ở trên
2. **Choose** giải pháp phù hợp với project
3. **Implement** theo guide chi tiết
4. **Verify** metrics và dashboard
5. **Update** documentation

Bạn chọn giải pháp nào? Tôi sẽ implement ngay!
