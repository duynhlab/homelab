# Tài Liệu Metrics

> 🤖 **AI Agents**: See [AGENTS.md](../../AGENTS.md) for project overview and [.cursor/rules/](../../.cursor/rules/) for development guidelines

## Quick Summary

**Objectives:**
- Understand the 6 custom application metrics and Go runtime metrics
- Learn how to use metrics for monitoring and detecting issues (memory leaks, latency)
- Configure and query Prometheus metrics in Grafana dashboards

**Learning Outcomes:**
- Custom metrics: request_duration_seconds, requests_total, requests_in_flight, etc.
- Go runtime metrics: goroutines, memory, GC, etc.
- PromQL queries for percentiles, rates, and aggregations
- 32 Grafana dashboard panels across 5 row groups
- Memory leak detection patterns

**Keywords:**
Prometheus, Metrics, Histogram, Counter, Gauge, PromQL, Percentiles, Apdex, RPS, Latency, Memory Leak, Go Runtime Metrics, Grafana Dashboard

**Technologies:**
- Prometheus (metrics collection)
- Prometheus Go Client Library
- Grafana (visualization)
- PromQL (query language)

## Tổng Quan

Dự án này expose **6 custom application metrics** và tận dụng **Go runtime metrics** để cung cấp **32 Grafana dashboard panels trong 5 row groups** cho việc giám sát toàn diện, bao gồm phát hiện memory leak.

### Metrics Architecture

**Label Injection Strategy (v0.5.0+):**
- **Application level**: Chỉ emit metrics với labels: `method`, `path`, `code`
- **Prometheus level**: Auto-inject `app`, `namespace`, `job`, `instance` labels during scrape
- **Why**: Eliminates label duplication, follows Prometheus best practices, simplifies application code

**Service Discovery:**
- **Prometheus Operator**: Manages Prometheus via CRDs
- **ServiceMonitor**: Single resource for all microservices (namespace-based discovery)
- **Namespace selector**: `monitoring: enabled` label
- **Scalability**: Efficiently handles 1000+ pods without manual configuration

---

## Custom Application Metrics

### 1. `request_duration_seconds` (Histogram)

**Mô tả:** Độ trễ (latency) của HTTP requests tính bằng giây

**Loại:** Histogram với buckets được tối ưu hóa cho tính toán Apdex

**Buckets:** `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10`

**Labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `code` - HTTP status code (200, 404, 500)

**Note:** `app` and `namespace` labels are automatically added by Prometheus during scrape (via relabel_configs), not by the application.

**Công dụng:** Dùng để tính toán percentiles (p50, p95, p99) và Apdex score

---

### 2. `requests_total` (Counter)

**Mô tả:** Tổng số HTTP requests

**Loại:** Counter

**Labels:** `method`, `path`, `code` (giống với `request_duration_seconds`)

**Note:** `app` and `namespace` labels are automatically added by Prometheus during scrape.

**Công dụng:** Tính toán RPS (requests per second), tổng traffic

---

### 3. `requests_in_flight` (Gauge)

**Mô tả:** Số lượng requests đang được xử lý

**Loại:** Gauge

**Labels:**
- `method` - HTTP method
- `path` - Request path

**Note:** `app` and `namespace` labels are automatically added by Prometheus during scrape.

**Công dụng:** Theo dõi concurrent requests, phát hiện bottlenecks

---

### 4. `request_size_bytes` (Histogram)

**Mô tả:** Kích thước của HTTP requests tính bằng bytes

**Loại:** Histogram

**Buckets:** `100, 1000, 10000, 100000, 1000000`

**Labels:** `method`, `path`, `code`

**Note:** `app` and `namespace` labels are automatically added by Prometheus during scrape.

**Công dụng:** Giám sát kích thước request payload

---

### 5. `response_size_bytes` (Histogram)

**Mô tả:** Kích thước của HTTP responses tính bằng bytes

**Loại:** Histogram

**Buckets:** `100, 1000, 10000, 100000, 1000000`

**Labels:** `method`, `path`, `code`

**Note:** `app` and `namespace` labels are automatically added by Prometheus during scrape.

**Công dụng:** Giám sát kích thước response payload

---

### 6. `error_rate_total` (Counter)

**Mô tả:** Tổng số lỗi (5xx responses)

**Loại:** Counter

**Labels:** `method`, `path`, `code`

**Note:** `app` and `namespace` labels are automatically added by Prometheus during scrape.

**Công dụng:** Theo dõi lỗi ứng dụng

---

## 32 Dashboard Panels trong 5 Row Groups - Phân Tích Chi Tiết

### 📊 Row 1: Overview & Key Metrics (12 Stat Panels)

#### 1. **Response Time - p50 (median)**

**Query:**
```promql
histogram_quantile(0.5, sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace"}[$rate])) by (le))
```

**Phân tích:**
- **Ý nghĩa:** 50% requests có thời gian phản hồi dưới giá trị này
- **Aggregation:** Tổng hợp tất cả pods của app được chọn
- **Tốt:** < 100ms cho REST API
- **Cảnh báo:** > 500ms
- **Legend:** Hiển thị giá trị duy nhất (ms)

---

#### 2. **Response Time - p95**

**Query:**
```promql
histogram_quantile(0.95, sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace"}[$rate])) by (le))
```

**Phân tích:**
- **Ý nghĩa:** 95% requests có thời gian phản hồi dưới giá trị này
- **Aggregation:** Tổng hợp tất cả pods
- **Tốt:** < 200ms
- **Cảnh báo:** > 1s
- **Quan trọng:** Đây là metric quan trọng hơn p50 vì nó phản ánh "worst case" của phần lớn users

---

#### 3. **Response Time - p99**

**Query:**
```promql
histogram_quantile(0.99, sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace"}[$rate])) by (le))
```

**Phân tích:**
- **Ý nghĩa:** 99% requests có thời gian phản hồi dưới giá trị này
- **Aggregation:** Tổng hợp tất cả pods
- **Tốt:** < 500ms
- **Cảnh báo:** > 2s
- **Lưu ý:** Rất nhạy cảm với outliers, có thể tăng đột biến khi có slow queries

---

#### 4. **Total RPS (All Requests)**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))
```

**Phân tích:**
- **Ý nghĩa:** Tổng số requests mỗi giây bao gồm TẤT CẢ status codes (2xx, 4xx, 5xx)
- **Aggregation:** `sum()` - tổng hợp tất cả pods
- **Unit:** `reqps` (requests per second)
- **Quan trọng:** Metric cốt lõi để đánh giá tổng traffic volume
- **Filter:** Khi chọn "App = All" sẽ hiện tổng RPS của cả 3 versions (v1+v2+v3)
- **Expected:**
  - V1 (4 pods): ~3.8 RPS (228 req/min)
  - V2 (2 pods): ~3.2 RPS (194 req/min)
  - V3 (1 pod): ~3.2 RPS (194 req/min)
  - **Total: ~10.2 RPS** khi chọn "All"
- **Description:** "Total requests per second including all HTTP status codes (2xx, 4xx, 5xx). Use this to monitor overall traffic volume."

---

#### 5. **Success RPS (2xx)** ⭐ NEW

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", code=~"2.."}[$rate]))
```

**Phân tích:**
- **Ý nghĩa:** Số requests thành công mỗi giây (chỉ HTTP 2xx responses)
- **Aggregation:** `sum()` - tổng hợp tất cả pods
- **Unit:** `reqps` (requests per second)
- **Color:** Green (success)
- **Quan trọng:** Đại diện cho productive traffic - traffic có ích
- **Expected:**
  - V1 (4 pods): ~3.6 RPS (216 req/min) - 95% success rate
  - V2 (2 pods): ~3.0 RPS (180 req/min) - 95% success rate
  - V3 (1 pod): ~3.0 RPS (180 req/min) - 95% success rate
  - **Total: ~9.6 RPS** khi chọn "All"
- **Description:** "Successful requests per second (HTTP 2xx responses). This represents productive traffic."

---

#### 6. **Error RPS (4xx/5xx)** ⭐ NEW

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", code=~"4..|5.."}[$rate]))
```

**Phân tích:**
- **Ý nghĩa:** Số requests lỗi mỗi giây (HTTP 4xx và 5xx responses)
- **Aggregation:** `sum()` - tổng hợp tất cả pods
- **Unit:** `reqps` (requests per second)
- **Color:** Red (error)
- **Quan trọng:** Monitor để phát hiện issues nhanh chóng
- **Expected:**
  - V1 (4 pods): ~0.2 RPS (12 req/min) - 5% error rate
  - V2 (2 pods): ~0.2 RPS (12 req/min) - 5% error rate
  - V3 (1 pod): ~0.2 RPS (12 req/min) - 5% error rate
  - **Total: ~0.6 RPS** khi chọn "All"
- **Description:** "Failed requests per second (HTTP 4xx/5xx responses). Monitor this to detect issues quickly."

---

#### 7. **Success Rate %** ⭐ NEW

**Query:**
```promql
(
  sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", code=~"2.."}[$rate]))
  /
  sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))
) * 100
```

**Phân tích:**
- **Ý nghĩa:** Phần trăm requests thành công (2xx / total)
- **Aggregation:** `sum()` - tổng hợp tất cả pods
- **Unit:** `percent`
- **Color thresholds:**
  - Red: < 95% (critical)
  - Yellow: 95-99% (warning)
  - Green: ≥ 99% (good)
- **Quan trọng:** SLI chính cho SLO implementation
- **Expected:**
  - Target: ≥ 99% cho production systems
  - Current: ~95% (do có simulated errors)
- **Description:** "Percentage of successful requests (2xx / total). Target: ≥ 99% for production systems."

---

#### 8. **Total Request**

**Query:**
```promql
sum(increase(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$__range]))
```

**Phân tích:**
- **Ý nghĩa:** Tổng số requests **trong dashboard time range được chọn** (30m, 1h, 24h, etc)
- **Aggregation:** `sum()` - cộng tất cả pods
- **Dùng `increase()`:** Tự động xử lý pod restarts, tổng hợp data từ Prometheus
- **Lưu ý quan trọng:** 
  - Giá trị **thay đổi theo time range** được chọn
  - **Không bị reset** khi pod restart (Prometheus handle counter resets)
  - Time range 30m → hiện requests trong 30 phút
  - Time range 1h → hiện requests trong 1 giờ
- **Khác với "Total Requests by Endpoint":** Đều dùng `increase()` nhưng aggregate khác nhau
- **Filter:** Khi chọn "App = All" sẽ cộng tất cả pods của 3 versions
- **📚 Chi tiết:** Xem [PROMETHEUS_RATE_EXPLAINED.md](./PROMETHEUS_RATE_EXPLAINED.md) (same directory) (same directory) để hiểu về `increase()` vs raw counter

---

#### 6. **Apdex Score**

**Query:**
```promql
(sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", le="0.5"}[$rate])) + 
(sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", le="2"}[$rate])) - 
sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace", le="0.5"}[$rate]))) / 2) / 
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))
```

**Phân tích:**
- **Ý nghĩa:** Đo lường mức độ hài lòng của người dùng (0.0 - 1.0)
- **Công thức:**
  ```
  Apdex = (Satisfied + Tolerating/2) / Total
  - Satisfied: ≤ 0.5s (ngưỡng T)
  - Tolerating: 0.5s < t ≤ 2s (4T)
  - Frustrated: > 2s
  ```
- **Thang đo:**
  - 1.00 - 0.94: Xuất sắc (Excellent)
  - 0.93 - 0.85: Tốt (Good)
  - 0.84 - 0.70: Khá (Fair)
  - 0.69 - 0.50: Kém (Poor)
  - < 0.50: Không chấp nhận được (Unacceptable)
- **Aggregation:** Tính trên tất cả pods được chọn
- **Quan trọng:** Metric tổng hợp tốt nhất để đánh giá user experience

---

#### 7. **Error Rate**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", code=~"5.."}[$rate]))
```

**Phân tích:**
- **Ý nghĩa:** Tỷ lệ lỗi (5xx) mỗi giây
- **Filter:** Chỉ đếm status code 5xx (500, 502, 503, etc)
- **Aggregation:** Tổng tất cả pods
- **Tốt:** 0 errors/sec
- **Cảnh báo:** > 0.1 errors/sec
- **Quan trọng:** Phải luôn theo dõi để phát hiện vấn đề sớm

---

#### 8. **Restarts (1d)**

**Query:**
```promql
sum(kube_pod_container_status_restarts_total{namespace=~"$namespace", pod=~"^$app-[a-z0-9]+-[a-z0-9]+$"})
```

**Phân tích:**
- **Ý nghĩa:** Tổng số lần pods bị restart do crash
- **Nguồn:** `kube-state-metrics` - Kubernetes metric
- **Filter:** Dùng regex `^$app-[a-z0-9]+-[a-z0-9]+$` để match chính xác pod name format
  - `^$app-`: Bắt đầu bằng app name + dash
  - `[a-z0-9]+-`: ReplicaSet hash + dash
  - `[a-z0-9]+$`: Pod hash, kết thúc
  - **Quan trọng:** Pattern này tránh việc "auth" match cả "auth-v2" (nếu có) và các service khác
- **Lưu ý quan trọng:**
  - **Chỉ đếm container crashes**, không đếm:
    - Rolling updates (kubectl rollout)
    - Manual restarts (kubectl delete pod)
    - Pod evictions
  - Counter tích lũy từ khi deploy pod
- **Namespace filter:** Chỉ đếm pods trong namespace được chọn (exclude `kube-system`, `default`)
- **App filter:** ✅ Đã fix regex để filter chính xác:
  - Chọn `auth`: **Chỉ** hiện restarts của auth pods
  - Chọn `user`: **Chỉ** hiện restarts của user pods
  - Chọn `product`: **Chỉ** hiện restarts của product pods
  - Chọn `All`: Hiện tổng restarts của tất cả pods từ tất cả services
- **Expected theo pods hiện tại:**
  - V1 (4 pods): 0 restarts
  - V2 (2 pods): 2 restarts (1 restart/pod)
  - V3 (1 pod): 1 restart
  - **Total: 3 restarts**
- **Tốt:** 0 restarts
- **Cảnh báo:** > 0 restarts (cần kiểm tra logs)

---

### 📈 Hàng 2: Traffic & Phân Bố (4 Panels)

#### 9. **RPS Trend**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate])) by (code)
```

**Phân tích:**
- **Ý nghĩa:** RPS theo từng HTTP status code (time series)
- **Aggregation:** `by (code)` - phân tách theo status code
- **Legend:** `REST.{{code}}` → REST.200, REST.404, etc
- **Loại panel:** Time series graph
- **Giá trị:**
  - Nhìn thấy pattern của success (2xx) vs errors (4xx, 5xx)
  - Phát hiện spikes hoặc drops
  - So sánh tỷ lệ giữa các status codes

---

#### 10. **Status Code Distribution**

**Query:**
```promql
sum(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}) by (code)
```

**Phân tích:**
- **Ý nghĩa:** Tổng số requests theo từng status code **từ khi pod khởi động**
- **Loại panel:** Pie chart
- **Aggregation:** `by (code)` → separate slices cho 200, 404, etc
- **Legend:** 
  - Table format với columns: Name | Value | Percent
  - Ví dụ: `200 | 15432 | 92.5%`
- **Lưu ý:** 
  - Giá trị **tích lũy** từ pod start, không phải time range
  - Reset khi pod restart
- **Phân bố mong đợi:**
  - 200: ~98% (success)
  - 404: ~1% (not found từ edge cases)
  - 500: ~1% (simulated errors)

---

#### 11. **Total Requests by Endpoint**

**Query:**
```promql
sum(increase(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$__range])) by (path)
```

**Phân tích:**
- **Ý nghĩa:** Tổng requests cho mỗi endpoint **trong dashboard time range**
- **Loại panel:** Pie chart
- **Aggregation:** `by (path)` → `/api/users`, `/api/products`, `/health`
- **Dùng `increase()`:** Tổng hợp requests trong time range, không bị ảnh hưởng bởi pod restarts
- **Legend:** Table với Name | Value | Percent
- **Lưu ý:**
  - Giá trị **phụ thuộc vào time range** được chọn
  - **Khớp với "Total Request" panel** (cùng dùng `increase()`)
  - Phân bố % **ổn định** dù pods restart
- **Phân bố mong đợi:**
  - `/api/users`: ~40% (GET + POST)
  - `/api/products`: ~38% (GET + POST)
  - `/health`: ~20%
  - `/api/invalid`: ~2% (404s)
- **📚 Chi tiết:** Xem [PROMETHEUS_RATE_EXPLAINED.md](./PROMETHEUS_RATE_EXPLAINED.md) (same directory)

---

#### 12. **RPS per Pod**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$__interval])) by (app)
```

**Phân tích:**
- **Ý nghĩa:** RPS của từng app version (time series)
- **Loại panel:** Time series graph
- **Aggregation:** `by (app)` → 1 line per app
- **Legend:** `{{app}}` → auth, user, product, cart, order, review, notification, shipping, shipping-v2
- **Quan trọng:** Kiểm tra load balancing giữa các versions
- **Mong đợi:**
  - V1 line: ~3.8 RPS (cao nhất vì 4 pods)
  - V2 line: ~3.2 RPS
  - V3 line: ~3.2 RPS
- **Use case:** Phát hiện nếu 1 version không nhận traffic

---

#### 13. **Request Rate by Endpoint** ⭐ NEW

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate])) by (path)
```

**Phân tích:**
- **Ý nghĩa:** RPS (requests per second) cho từng endpoint theo thời gian
- **Loại panel:** Time Series (line chart)
- **Aggregation:** `by (path)` → `/api/users`, `/api/products`, `/health`, etc.
- **Dùng `rate()`:** Tính RPS tự động xử lý counter resets
- **Size:** Full width (24 units) - cho phép xem trend rõ ràng
- **Legend:** Table với Mean + Max values cho mỗi endpoint
- **So sánh với panel #11 "Total Requests by Endpoint":**
  
  | Panel | Type | Metric | Shows |
  |-------|------|--------|-------|
  | **Total Requests** (#11) | Pie Chart | `increase()` | Phân bố tĩnh (%) trong time range |
  | **Request Rate** (#13) | Time Series | `rate()` | Trend động (RPS over time) |

- **Use cases:**
  - 📈 Phát hiện traffic spike/drop patterns cho từng endpoint
  - 🔥 Identify hot endpoints theo thời gian thực
  - 🎯 Monitor traffic distribution changes
  - ⚡ Debug sudden traffic shifts (ví dụ: 1 endpoint tăng đột biến)
  - 🔍 Correlate với response time spikes

- **Giá trị mong đợi:**
  - `/api/users`: ~4.0 RPS (highest, vì có nhiều GET + POST)
  - `/api/products`: ~3.5 RPS
  - `/health`: ~2.0 RPS (health checks)
  - `/api/invalid`: ~0.2 RPS (404 errors)

- **4 Golden Signals:** Complete **Traffic** signal per endpoint ✅
- **Quan trọng:** Panel này bổ sung cho pie chart, cho phép thấy **WHEN** traffic thay đổi, không chỉ **WHAT** phân bố

---

### 🖥️ Hàng 3: Giám Sát Tài Nguyên (5 Panels)

#### 14. **Memory usage per pods**

**Query:**
```promql
sum(go_memstats_alloc_bytes{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Heap memory đang được allocated (bytes) của mỗi app
- **Nguồn:** Go runtime metrics
- **Loại panel:** Time series
- **Legend:** `{{app}}` → 1 line per app (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng memory của tất cả pods trong 1 app
  - **Lý do:** Capacity planning cần biết **total memory per service**, không phải per pod
  - **Ví dụ:** auth có 3 pods (8+9+8=25 MiB) → Show 1 line "auth: 25 MiB"
  - **Alternative:** Individual pods → 3 lines riêng lẻ (harder to read when scaling)
- **⚠️ Lưu ý quan trọng:**
  - **KHÔNG phải container memory** từ Kubernetes
  - Chỉ heap memory của Go app (không bao gồm stack, OS buffers, etc)
  - Giá trị thực tế thấp hơn container memory limit
- **Mong đợi:**
  - V1: ~25-35 MiB
  - V2: ~27-42 MiB
  - V3: ~16-28 MiB
- **Table legend:** Name | Mean | Max

---

#### 15. **CPU usage per pods**

**Query:**
```promql
sum(rate(process_cpu_seconds_total{app=~"$app", namespace=~"$namespace"}[5m])) by (app) * 100
```

**Phân tích:**
- **Ý nghĩa:** % CPU usage của Go process
- **Nguồn:** Go runtime metrics
- **Công thức:** `sum(rate([5m])) by (app) * 100` để chuyển sang phần trăm
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng CPU của tất cả pods trong 1 app
  - **Lý do:** Monitor **total CPU consumption per service** cho resource allocation
  - **Ví dụ:** V1 có 3 pods (0.8% + 0.9% + 0.7% = 2.4% total)
  - **Use case:** Capacity planning, cost optimization
- **⚠️ Lưu ý quan trọng:**
  - **KHÔNG phải container CPU** từ Kubernetes
  - Chỉ CPU của Go process
  - Giá trị < 100% vì chạy multi-core
- **Mong đợi:**
  - V1: ~0.8-1.1% (thấp vì traffic ít)
  - V2: ~1.0-1.15%
  - V3: ~0.6-0.7%

---

#### 16. **Total Network Traffic**

**Query:**
```promql
# TX (Transmit - Response)
sum(rate(response_size_bytes_sum{app=~"$app", namespace=~"$namespace"}[5m])) by (app)

# RX (Receive - Request)
sum(rate(request_size_bytes_sum{app=~"$app", namespace=~"$namespace"}[5m])) by (app)
```

**Phân tích:**
- **Ý nghĩa:** HTTP traffic (bytes/sec) của mỗi app
- **Nguồn:** Custom histogram metrics từ Go app
- **Loại panel:** Time series với 2 queries
- **Legend:** 
  - `{{app}} TX` → auth TX (outbound/response, aggregated)
  - `{{app}} RX` → auth RX (inbound/request, aggregated)
- **Aggregation:** ✅ `sum(rate(...)) by (app)` - Tổng HTTP traffic của tất cả pods
  - **Lý do:** Network bandwidth planning cần **total throughput per service**
  - **Ví dụ:** V1 có 3 pods → Show tổng TX/RX để monitor bandwidth usage
  - **Use case:** Capacity planning, cost estimation, bandwidth optimization
- **⚠️ LƯU Ý CỰC KỲ QUAN TRỌNG:**
  - **KHÔNG phải Kubernetes network traffic!**
  - Chỉ đo HTTP request/response **body size**
  - **Không bao gồm:**
    - TCP/IP headers
    - HTTP headers
    - TLS/SSL overhead
    - Health check traffic
    - Prometheus scraping traffic
  - **Khuyến nghị:** Nên đổi tên thành "HTTP Traffic" sẽ chính xác hơn
- **Use case:** Theo dõi HTTP payload sizes, phát hiện large requests/responses

---

#### 17. **Requests In Flight**

**Query:**
```promql
sum(requests_in_flight{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Số requests đang được xử lý đồng thời (concurrent)
- **Nguồn:** Custom Gauge metric
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng concurrent requests của tất cả pods
  - **Lý do:** Saturation monitoring cần **total concurrent capacity** của service
  - **Ví dụ:** V1 có 3 pods (5+7+6 = 18 concurrent requests total)
  - **Use case:** Phát hiện bottlenecks, validate service capacity, detect traffic spikes
  - **4 Golden Signals:** Complete **Saturation** signal ✅
- **Mong đợi:**
  - Thấp: 0-2 (traffic ít)
  - Trung bình: 5-20
  - Cao: >50 (có thể bottleneck)
- **Use case:**
  - Phát hiện traffic spikes
  - Xác định slow endpoints (high in-flight = xử lý chậm)
  - Kiểm tra xem app có bị quá tải không

---

#### 18. **Memory Allocations**

**Query:**
```promql
sum(go_memstats_frees_total{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Tổng số lần Go GC đã giải phóng memory objects
- **Nguồn:** Go runtime metrics
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng memory allocations của tất cả pods
  - **Lý do:** GC activity patterns cần nhìn **tổng thể service**, không phải individual pods
  - **Ví dụ:** V1 có 3 pods → Show tổng frees của cả service
  - **Use case:** Detect memory allocation patterns, phát hiện memory leaks
- **Lưu ý:**
  - Counter metric (tăng liên tục)
  - Giá trị lớn = nhiều GC activity
  - Kết hợp với "Go GC Performance" để phân tích
- **Use case:**
  - Theo dõi memory allocation patterns
  - Phát hiện memory leaks (frees không tăng = leak)

---

### 🔧 Row 4: Go Runtime & Memory (6 Panels) - Memory Leak Detection

**Mục đích:** Phát hiện memory leak toàn diện với 3 nhóm metrics: Memory Heap, Goroutines, và GC Performance

#### Sub-group 1: 💾 Memory Heap (3 panels MỚI)

#### 19. **Heap Allocated Memory** 🆕

**Query:**
```promql
sum(go_memstats_alloc_bytes{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Memory hiện tại được allocated trên heap (bytes)
- **Nguồn:** Go runtime metrics (`go_memstats_alloc_bytes`)
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated by app)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng heap memory của tất cả pods trong 1 app
- **Unit:** bytes
- **Memory Leak Pattern:**
  - ✅ **Healthy:** Tăng giảm theo pattern (sawtooth), giảm sau GC
  - ⚠️ **Warning:** Tăng dần, baseline tăng cao dần sau mỗi GC
  - 🔴 **Leak:** Tăng liên tục không giảm, đường thẳng lên
- **Use case:**
  - **Bằng chứng chính** của heap memory leak
  - Theo dõi sau GC - nếu không drop xuống → leak
  - Correlate với GC frequency và duration
- **Mong đợi:**
  - Normal: 20-50 MiB với pattern lên xuống
  - Leak: Tăng từ 50 MiB → 100 MiB → 200 MiB liên tục

---

#### 20. **Heap In-Use Memory** 🆕

**Query:**
```promql
sum(go_memstats_heap_inuse_bytes{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Heap memory đang được app sử dụng (bytes)
- **Nguồn:** Go runtime metrics (`go_memstats_heap_inuse_bytes`)
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated by app)
- **Aggregation:** ✅ `sum(...) by (app)`
- **Unit:** bytes
- **So sánh với Heap Allocated:**
  - `heap_inuse` ≥ `alloc` (inuse bao gồm fragmentation)
  - `heap_inuse` là heap **thực tế giữ**, `alloc` là **đang dùng**
- **Memory Leak Pattern:**
  - ✅ **Healthy:** Về baseline sau GC (ví dụ: 30 MiB baseline)
  - ⚠️ **Warning:** Baseline tăng dần: 30 MiB → 40 MiB → 50 MiB
  - 🔴 **Leak:** Không giảm về baseline, tăng liên tục
- **Use case:**
  - Xác nhận leak khi `alloc` tăng
  - Phát hiện **memory fragmentation** (inuse >> alloc)
  - Monitor heap capacity usage
- **Mong đợi:**
  - Healthy: Baseline ổn định (30-40 MiB)
  - Leak: Baseline tăng liên tục

---

#### 21. **Process Memory (RSS)** 🆕

**Query:**
```promql
sum(process_resident_memory_bytes{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Tổng physical memory (RAM) mà process đang dùng
- **Nguồn:** Process metrics (`process_resident_memory_bytes`)
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated by app)
- **Aggregation:** ✅ `sum(...) by (app)`
- **Unit:** bytes
- **So sánh với Heap metrics:**
  - `process_resident` > `heap_inuse` (bao gồm stack, Go runtime, off-heap)
  - RSS = Heap + Stack + Go runtime + CGO memory
- **Memory Leak Pattern:**
  - ✅ **Healthy:** Ổn định hoặc tăng/giảm nhẹ (< 20%)
  - ⚠️ **Warning:** Tăng dần theo thời gian (VD: 100 MB → 150 MB → 200 MB)
  - 🔴 **Leak:** Tăng liên tục không dừng, risk OOMKilled
- **Use case:**
  - **Bằng chứng vật lý** ở OS level
  - Phát hiện leak cả heap + off-heap (CGO, mmap)
  - Monitor OOM risk (so với pod memory limits)
  - Detect memory leak không phải từ Go heap
- **Mong đợi:**
  - Normal: 100-200 MiB, ổn định
  - Leak: Tăng liên tục, tiến tới memory limit
- **⚠️ OOM Risk:**
  - Nếu RSS → pod memory limit (ví dụ: 512 MiB) → OOMKilled sắp xảy ra

---

#### Sub-group 2: 🧵 Goroutines (1 panel - IMPROVED)

#### 22. **Goroutines & Threads** ♻️ (Improved)

**Query:**
```promql
# Goroutines
sum(go_goroutines{app=~"$app", namespace=~"$namespace"}) by (app)

# OS Threads
sum(go_threads{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Số goroutines và OS threads đang chạy
- **Nguồn:** Go runtime metrics
- **Loại panel:** Time series với 2 queries
- **Legend:**
  - `{{app}} Goroutines` → lightweight Go concurrency (aggregated)
  - `{{app}} Threads` → actual OS threads (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng goroutines/threads của tất cả pods
- **Goroutine Leak Pattern:**
  - ✅ **Healthy:** Ổn định, dao động theo load (50-200)
  - ⚠️ **Warning:** Tăng dần nhưng chậm (200 → 500 → 1000)
  - 🔴 **Leak:** Tăng liên tục không dừng (1000 → 5000 → 10,000+)
- **Nguyên nhân Goroutine Leak:**
  - Quên `defer cancel()` khi dùng context
  - Channel không được close
  - Goroutine chờ channel/lock vô hạn
  - HTTP client requests không có timeout
- **Use case:**
  - **Phát hiện goroutine leak** (leak pattern quan trọng)
  - Monitor concurrent request handling capacity
  - Detect blocking operations
- **Mong đợi:**
  - Goroutines: 10-200 (normal REST API under load)
  - Threads: 5-15 (thấp hơn nhiều so với goroutines)
- **Cảnh báo:**
  - Goroutines > 10,000 → **Goroutine leak confirmed**
  - Threads tăng liên tục → thread leak (rare)
- **Description (Updated):** "Goroutine and OS thread count. Steadily increasing goroutines indicates goroutine leak (forgotten defer, unclosed channels). Stable count is normal."

---

#### Sub-group 3: 🗑️ Garbage Collection (2 panels)

#### 23. **GC Duration** ♻️ (Improved)

**Query:**
```promql
sum(increase(go_gc_duration_seconds_sum{app=~"$app", namespace=~"$namespace"}[5m])) by (app) / 300
```

**Phân tích:**
- **Ý nghĩa:** Thời gian GC trung bình mỗi giây (giây)
- **Công thức:** `sum(increase([5m])) by (app) / 300s` = avg GC time per second
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng GC time của tất cả pods
- **GC Duration Pattern:**
  - ✅ **Healthy:** < 0.001s (1ms), ổn định
  - ⚠️ **Warning:** 0.001-0.01s (1-10ms), tăng dần
  - 🔴 **High Pressure:** > 0.01s (10ms+), GC pause ảnh hưởng latency
- **Correlate với Memory Leak:**
  - GC Duration ↑ + Heap Allocated ↑ = **Heap memory leak**
  - GC Duration ↑ + Heap Allocated ổn định = **High load** (not leak)
- **Use case:**
  - Monitor GC overhead impact on performance
  - Confirm leak khi correlate với heap metrics
  - Identify memory pressure requiring optimization
- **Mong đợi:**
  - Normal: < 0.001s với heap ổn định
  - Leak: > 0.01s với heap tăng liên tục
- **Description (Updated):** "GC pause duration. High values indicate memory pressure. Increases when heap is large."

---

#### 24. **GC Frequency** 🆕

**Query:**
```promql
sum(rate(go_gc_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[5m])) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Số lần GC chạy mỗi giây
- **Nguồn:** Go runtime metrics (`go_gc_duration_seconds_count`)
- **Loại panel:** Time series
- **Legend:** `{{app}}` (aggregated by app)
- **Aggregation:** ✅ `sum(...) by (app)`
- **Unit:** GC runs per second
- **GC Frequency Pattern:**
  - ✅ **Healthy:** 0.1-0.5 GC/s (GC mỗi 2-10 giây)
  - ⚠️ **Warning:** 0.5-1 GC/s (GC mỗi 1-2 giây)
  - 🔴 **High Pressure:** > 1 GC/s (GC liên tục)
- **Correlate với Memory Leak:**
  - GC Frequency ↑ + Heap ↑ = **Memory leak** (GC cố free memory nhưng không được)
  - GC Frequency ↑ + Heap ổn định = **High allocation rate** (not leak, cần optimize)
- **Use case:**
  - Phát hiện memory pressure sớm
  - Confirm heap leak pattern
  - Optimize allocation strategy nếu GC quá thường xuyên
- **Mong đợi:**
  - Normal: 0.1-0.3 GC/s
  - Leak: > 1 GC/s với heap không giảm
- **Description:** "GC runs per second. High frequency indicates memory pressure or insufficient heap size."

---

### 🖥️ Row 5: Resources & Infrastructure (5 Panels)

#### 25. **Memory usage per pods**

**Query:**
```promql
# Goroutines
sum(go_goroutines{app=~"$app", namespace=~"$namespace"}) by (app)

# OS Threads
sum(go_threads{app=~"$app", namespace=~"$namespace"}) by (app)
```

**Phân tích:**
- **Ý nghĩa:** Số goroutines và OS threads đang chạy
- **Nguồn:** Go runtime metrics
- **Loại panel:** Time series với 2 queries
- **Legend:**
  - `{{app}} Goroutines` → lightweight Go concurrency (aggregated)
  - `{{app}} Threads` → actual OS threads (aggregated)
- **Aggregation:** ✅ `sum(...) by (app)` - Tổng goroutines/threads của tất cả pods
  - **Lý do:** Concurrency behavior là **service-wide characteristic**
  - **Ví dụ:** V1 có 3 pods (120+115+130 goroutines = 365 total)
  - **Use case:** Detect goroutine leaks, monitor concurrent request handling capacity
- **Mong đợi:**
  - Goroutines: 10-50 (normal REST API)
  - Threads: 5-15 (thấp hơn nhiều so với goroutines)
- **Cảnh báo:**
  - Goroutines > 10,000 → có thể goroutine leak
  - Threads tăng liên tục → thread leak
- **Use case:**
  - Phát hiện goroutine/thread leaks
  - Theo dõi concurrency patterns

---

#### 21. **Response Time Distribution**

**Query:**
```promql
sum(rate(request_duration_seconds_bucket{app=~"$app", namespace=~"$namespace"}[$rate])) by (le)
```

**Phân tích:**
- **Ý nghĩa:** Phân bố requests theo các buckets thời gian
- **Loại panel:** Heatmap hoặc histogram
- **Aggregation:** `by (le)` → group by bucket boundaries
- **Buckets:** 0.005s, 0.01s, 0.025s, 0.05s, 0.1s, 0.25s, 0.5s, 1s, 2.5s, 5s, 10s
- **Legend:** `≤ {{le}}s` → ≤ 0.5s, ≤ 1s, etc
- **Use case:**
  - Xem có bao nhiêu % requests trong mỗi bucket
  - Phát hiện bimodal distribution (2 nhóm slow/fast)
  - Validate Apdex thresholds

---

### 📊 Hàng 5: Phân Tích Request (2 Panels)

#### 22. **Requests by Method**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate])) by (method)
```

**Phân tích:**
- **Ý nghĩa:** RPS theo từng HTTP method (time series)
- **Loại panel:** Time series
- **Aggregation:** `by (method)` → GET, POST, PUT, DELETE
- **Legend:** `{{method}}` → GET, POST
- **Phân bố mong đợi:**
  - GET: ~70% (list operations: GET /users, GET /products)
  - POST: ~30% (create operations)
  - PUT: 0% (đã loại bỏ khỏi load test)
  - DELETE: 0% (đã loại bỏ khỏi load test)
- **Use case:**
  - Xác minh load test pattern
  - Phát hiện phân bố method bất thường

---

#### 23. **Request Rate by Endpoint**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate])) by (path)
```

**Phân tích:**
- **Ý nghĩa:** Request rate (req/s) theo từng endpoint theo thời gian thực
- **Loại panel:** Time series
- **Aggregation:** `by (path)` → group theo endpoint
- **Legend:** `{{path}}` → /api/users, /api/products, /api/v3/users
- **Table legend:** Name | Mean | Max (sorted by Max descending)
- **Mong đợi:**
  - `/api/v3/users`: ~90 req/s (highest traffic)
  - `/api/v3/products`: ~85 req/s
  - `/api/products`: ~60 req/s
  - `/api/v2/orders`: ~50 req/s
  - `/api/users`: ~45 req/s
  - `/health`: ~3 req/s
- **Use case:**
  - Xem endpoint nào đang hot nhất
  - Theo dõi traffic trends theo thời gian
  - So sánh với panel #10 (Total Requests by Endpoint - pie chart)

---

#### 24. **Request Rate by Method and Endpoint** 🆕

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate])) by (method, path)
```

**Phân tích:**
- **Ý nghĩa:** Request rate breakdown theo **cả Method VÀ Endpoint**
- **Loại panel:** Time series
- **Aggregation:** `by (method, path)` → group theo cả HTTP method và endpoint
- **Legend:** `{{method}} {{path}}` → GET /api/users, POST /api/users
- **Table legend:** Name | Mean | Max (sorted by Max descending)
- **Width:** Full width (24 columns)
- **Description:** "Breakdown of request rate by HTTP method and endpoint. Use to identify read-heavy vs write-heavy patterns."
- **Mong đợi:**
  ```
  GET  /api/v3/users:     90 req/s  (read-heavy)
  POST /api/v3/users:      7 req/s  (write traffic)
  GET  /api/products:     60 req/s
  POST /api/products:      8 req/s
  ```

**Giá trị thêm:**
1. **Traffic Pattern Analysis:**
   - Phân biệt read (GET) vs write (POST) traffic
   - Tối ưu caching cho GET requests
   - Scale DB accordingly cho POST requests

2. **Detect Unusual Patterns:**
   - POST traffic spike → possible bot attack
   - GET spike → cache miss or viral content
   
3. **Capacity Planning:**
   - GET: fast, cacheable, low CPU
   - POST: slow, DB writes, high CPU

**So sánh với Panel #23:**
- Panel #23: Tổng requests per endpoint (không phân biệt method)
- Panel #24: Chi tiết hơn, biết được GET/POST/PUT/DELETE distribution

**Dựa trên:** Nginx monitoring best practices

---

#### 25. **Error Rate by Method and Endpoint** 🆕

**Query:**
```promql
(sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", code=~"4..|5.."}[$rate])) by (method, path) 
/ 
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate])) by (method, path)) * 100
```

**Phân tích:**
- **Ý nghĩa:** Error rate (%) cho từng **Method + Endpoint combination**
- **Filter:** `code=~"4..|5.."` → 4xx và 5xx errors
- **Loại panel:** Time series
- **Aggregation:** `by (method, path)` → group theo method và endpoint
- **Legend:** `{{method}} {{path}}` → POST /api/users, GET /api/products
- **Table legend:** Name | Mean | Max (sorted by Max descending)
- **Width:** Full width (24 columns)
- **Unit:** % (percentage)
- **Description:** "Error rate breakdown by HTTP method and endpoint. POST typically has higher error rates due to validation."
- **Thresholds:**
  - Green: 0-1% (OK)
  - Yellow: 1-5% (Warning)
  - Red: >5% (Critical)

**Mong đợi:**
```
GET  /api/users:      0.1%  ✅ Healthy
POST /api/users:      2.5%  ⚠️  Higher (validation errors)
POST /api/v2/orders:  3.8%  ⚠️  Expected
GET  /health:         0%    ✅ Never fails
```

**Giá trị thêm:**
1. **Pinpoint Exact Issue:**
   ```
   Dashboard cũ:  Error rate 3% overall ← Không biết đâu lỗi
   Dashboard mới: POST /api/orders: 15% errors ← Chính xác!
   ```

2. **Method-Specific Debugging:**
   ```
   GET  /api/products: 0.1% ✅ Read OK
   POST /api/products: 15%  🔴 Write failing
   → Root cause: POST validation có bug!
   ```

3. **SLA Monitoring:**
   - Track per-endpoint SLA compliance
   - Alert on specific method+endpoint violations

4. **Production Debugging Speed:**
   - **Trước:** Check logs 20+ phút để tìm lỗi
   - **Sau:** Nhìn panel 10 giây biết ngay endpoint nào lỗi

**So sánh với Panel #6 (Error Rate):**
- Panel #6: Tổng error rate toàn app
- Panel #25: Chi tiết lỗi ở đâu (method + endpoint)

**Dựa trên:** Nginx monitoring best practices

---

## Biến Filters & Multi-Namespace Support

Dashboard hỗ trợ **multi-namespace deployment** với 3 biến filters:

### `$app` - Application Filter
- **Loại:** Multi-select với tùy chọn "All"
- **Query:** `label_values(request_duration_seconds_count, app)`
- **Options:** `auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`, `shipping-v2`, `All`
- **Mặc định:** `All`
- **Regex filter:** `/^(?!kube-|default$).*/` (loại trừ system apps)
- **Use case:** Filter metrics theo app version cụ thể

### `$namespace` - Namespace Filter
- **Loại:** Multi-select
- **Query:** `label_values(kube_pod_info, namespace)`
- **Mặc định:** All namespaces (service namespaces: auth, user, product, etc., and `monitoring`)
- **Regex filter:** `/^(?!kube-|default$).*/` (loại trừ system namespaces)
- **Support:** Tất cả 25 panels đã filter theo `namespace=~"$namespace"`
- **Use case:** 
  - Tránh metrics từ system pods (kube-system)
  - Support multi-environment (dev, staging, prod trong cùng Prometheus)

**Cách hoạt động:**
```yaml
# Prometheus scrape config thêm namespace label:
static_configs:
- targets: ['auth.auth.svc.cluster.local:8080'] (example for auth)
  labels:
    app: 'auth'
    namespace: 'auth'  # ← Label này (service-specific namespace)
```

**Tất cả queries** đã include namespace filter:
```promql
# Before (không filter namespace):
sum(rate(request_duration_seconds_count{app=~"$app"}[$rate]))

# After (có filter namespace):
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))
```

### `$rate` - Rate Interval
- **Loại:** Custom interval cho tính toán rate()
- **Options:** `1m, 2m, 3m, 5m, 10m, 30m, 1h, 2h, 4h, 8h, 16h, 1d, 2d, 3d, 5d, 7d`
- **Mặc định:** `5m`
- **Use case:** Làm mượt biến động ngắn hạn vs xem chi tiết thay đổi
- **Khuyến nghị:**
  - High traffic: 1m-5m (responsive, real-time)
  - Low traffic: 30m-1h (smoother, less noise)

---

## 🔬 Memory Leak Detection Strategy

**Row 4 (Go Runtime & Memory)** cung cấp 6 panels để phát hiện memory leak một cách chính xác và toàn diện.

### Workflow: Phát hiện Memory Leak

#### **Step 1: Check Memory Heap Panels (3 panels)**

Xem 3 panels:
- **Heap Allocated** - Tăng liên tục?
- **Heap In-Use** - Tăng không về baseline sau GC?
- **Process RSS** - Tăng liên tục?

**Decision:**
```
Nếu CẢ 3 đều tăng đều = 🔴 HEAP MEMORY LEAK
```

**Ví dụ Heap Leak:**
```
Time      | Heap Alloc | Heap InUse | Process RSS
----------|------------|------------|------------
10:00     | 50 MiB     | 55 MiB     | 120 MiB
10:30     | 80 MiB     | 90 MiB     | 180 MiB
11:00     | 110 MiB    | 120 MiB    | 240 MiB
11:30     | 140 MiB    | 150 MiB    | 300 MiB ← Tăng liên tục

Diagnosis: HEAP MEMORY LEAK ✅
```

---

#### **Step 2: Check Goroutines Panel (1 panel)**

Xem 1 panel:
- **Goroutines & Threads** - Goroutines tăng liên tục không giảm?

**Decision:**
```
Nếu Goroutines tăng liên tục = 🔴 GOROUTINE LEAK
```

**Ví dụ Goroutine Leak:**
```
Time      | Goroutines | Threads
----------|------------|--------
10:00     | 120        | 12
10:30     | 500        | 14
11:00     | 1,200      | 16
11:30     | 5,000      | 18 ← Tăng không dừng

Diagnosis: GOROUTINE LEAK ✅
Likely cause: Forgotten defer cancel(), unclosed channels
```

---

#### **Step 3: Check GC Panels (2 panels)**

Xem 2 panels:
- **GC Duration** - Tăng cao?
- **GC Frequency** - Tăng cao?

**Decision:**
```
Nếu cả 2 tăng + Heap tăng = 🔴 Heap leak
Nếu cả 2 tăng + Heap OK   = ⚠️ High load (không phải leak)
```

**Ví dụ GC confirming Heap Leak:**
```
Time      | Heap Alloc | GC Duration | GC Frequency
----------|------------|-------------|-------------
10:00     | 50 MiB     | 0.001s      | 0.2 GC/s
10:30     | 100 MiB    | 0.005s      | 0.5 GC/s
11:00     | 150 MiB    | 0.010s      | 1.0 GC/s
11:30     | 200 MiB    | 0.015s      | 1.5 GC/s ← GC tăng nhưng không free được memory

Diagnosis: Heap leak + GC không thể free ✅
```

**Ví dụ High Load (NOT leak):**
```
Time      | Heap Alloc | GC Duration | GC Frequency
----------|------------|-------------|-------------
10:00     | 40 MiB     | 0.001s      | 0.3 GC/s
10:30     | 45 MiB     | 0.008s      | 0.8 GC/s
11:00     | 42 MiB     | 0.006s      | 0.7 GC/s
11:30     | 44 MiB     | 0.005s      | 0.6 GC/s ← Heap stable, GC temporary spike

Diagnosis: High load period, NOT leak ✅
```

---

### Decision Matrix: Leak Detection

| Heap | Goroutines | GC | Diagnosis | Action |
|------|------------|-----|-----------|--------|
| ↑↑↑ | → | ↑↑ | **Heap Memory Leak** | Check code for: data structures holding references, global caches, unclosed resources |
| →/↑ | ↑↑↑ | → | **Goroutine Leak** | Check code for: forgotten `defer cancel()`, unclosed channels, blocking operations |
| ↑↓ | ↑↓ | ↑↑ | **High Load** (OK) | Normal - traffic increased, app handling load |
| → | → | → | **Healthy** | No action needed |

---

### Common Leak Causes & Fixes

#### **1. Heap Memory Leak**

**Causes:**
- Global maps/slices growing indefinitely
- Cache without eviction policy
- HTTP client không reuse connections
- Unclosed file descriptors

**Example Leak Code:**
```go
// ❌ BAD: Global cache growing forever
var userCache = make(map[string]*User)

func GetUser(id string) *User {
    if user, ok := userCache[id]; ok {
        return user
    }
    user := fetchUserFromDB(id)
    userCache[id] = user  // ← Never removed!
    return user
}
```

**Fixed Code:**
```go
// ✅ GOOD: LRU cache with size limit
var userCache = lru.New(1000)  // Max 1000 items

func GetUser(id string) *User {
    if val, ok := userCache.Get(id); ok {
        return val.(*User)
    }
    user := fetchUserFromDB(id)
    userCache.Add(id, user)  // ← Auto evicts old entries
    return user
}
```

---

#### **2. Goroutine Leak**

**Causes:**
- Context không cancel
- Channel không close
- HTTP request không timeout
- Goroutine chờ vô hạn

**Example Leak Code:**
```go
// ❌ BAD: Goroutine leak
func ProcessUsers() {
    ctx := context.Background()
    for _, user := range users {
        go func(u User) {
            // Goroutine chạy mãi, không bao giờ exit!
            for {
                select {
                case <-ctx.Done():
                    return  // ← ctx.Done() never called
                default:
                    processUser(u)
                    time.Sleep(1 * time.Second)
                }
            }
        }(user)
    }
}
```

**Fixed Code:**
```go
// ✅ GOOD: Proper context cancellation
func ProcessUsers() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()  // ← Ensures all goroutines exit
    
    for _, user := range users {
        go func(u User) {
            for {
                select {
                case <-ctx.Done():
                    return  // ← Now properly exits
                default:
                    processUser(u)
                    time.Sleep(1 * time.Second)
                }
            }
        }(user)
    }
}
```

---

### Monitoring Best Practices

1. **Set up alerts:**
   ```yaml
   # Alert when heap grows > 500MB
   - alert: HeapMemoryLeak
     expr: go_memstats_alloc_bytes > 500_000_000
     for: 30m
     annotations:
       summary: "Potential heap memory leak detected"
   
   # Alert when goroutines > 10,000
   - alert: GoroutineLeak
     expr: go_goroutines > 10000
     for: 15m
     annotations:
       summary: "Goroutine leak detected"
   ```

2. **Monitor trends over days/weeks:**
   - Set time range to 7d or 30d
   - Check if baseline is increasing

3. **Correlate metrics:**
   - Heap ↑ + GC ↑ = Leak likely
   - Goroutines ↑ + Requests ↑ = Normal (if proportional)

4. **Use pprof when leak detected:**
   ```bash
   # Get heap profile
   curl http://localhost:6060/debug/pprof/heap > heap.prof
   go tool pprof -http=:8080 heap.prof
   
   # Get goroutine profile
   curl http://localhost:6060/debug/pprof/goroutine > goroutine.prof
   go tool pprof -http=:8080 goroutine.prof
   ```

---

## Lưu Ý Quan Trọng

### ⚠️ Giới Hạn Của Metrics

1. **Memory & CPU panels:** 
   - Hiển thị Go process metrics, **KHÔNG phải Kubernetes container metrics**
   - Để có K8s metrics chuẩn cần scrape cAdvisor (phức tạp trong Kind)

**Giải thích chi tiết: Tại sao cần cAdvisor?**

#### **cAdvisor là gì?**
- **cAdvisor** (Container Advisor) là công cụ của Google để monitor container resources
- Được tích hợp sẵn trong **kubelet** (mỗi Kubernetes node)
- Expose metrics về CPU, Memory, Network, Disk của **từng container**

#### **So sánh: Go Process Metrics vs Kubernetes Container Metrics**

| Aspect | Go Process Metrics | K8s Container Metrics (cAdvisor) |
|--------|-------------------|----------------------------------|
| **Nguồn** | Go runtime (`runtime.Memstats`) | cAdvisor trong kubelet |
| **Scope** | Chỉ Go process | Toàn bộ container (app + OS) |
| **Memory** | Heap allocated của Go | Container RSS, cache, buffers |
| **CPU** | Go process CPU time | Container CPU usage vs limits |
| **Network** | ❌ Không có | ✅ TX/RX bytes/sec |
| **Disk I/O** | ❌ Không có | ✅ Read/write bytes |
| **Metrics endpoint** | `/metrics` của app | Kubelet port 10250 |

#### **Ví dụ cụ thể:**

**Memory:**
- Go metrics: `go_memstats_alloc_bytes = 25 MiB` (chỉ heap)
- Container metrics: `container_memory_working_set_bytes = 45 MiB` (heap + stack + OS)

**CPU:**
- Go metrics: `process_cpu_seconds_total` (chỉ Go process)
- Container metrics: `container_cpu_usage_seconds_total` (toàn bộ container)

**Network:**
- Go metrics: `response_size_bytes` (chỉ HTTP body)
- Container metrics: `container_network_transmit_bytes_total` (tất cả TCP/IP traffic)

#### **Tại sao phức tạp trong Kind?**

1. **Authentication:** Kubelet cần TLS cert để scrape
   ```bash
   # Prometheus cần ServiceAccount với RBAC permissions
   # Cần mount kubelet CA cert vào Prometheus pod
   ```

2. **Network:** Kubelet metrics ở mỗi node IP:10250
   ```yaml
   # Prometheus cần discover tất cả nodes
   kubernetes_sd_configs:
   - role: node
   ```

3. **Configuration phức tạp:**
   ```yaml
   # Cần config relabeling, TLS, bearer token
   - job_name: 'kubernetes-cadvisor'
     scheme: https
     tls_config:
       ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
     bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
   ```

4. **Kind-specific issues:**
   - Nodes là Docker containers, network phức tạp
   - Certificate paths khác với production clusters
   - Cần mount thêm volumes vào Prometheus

#### **Giải pháp hiện tại (Go metrics):**

**Ưu điểm:**
- ✅ Đơn giản, không cần RBAC phức tạp
- ✅ Hoạt động ngay trong Kind
- ✅ Đủ cho development và monitoring app-level metrics
- ✅ Chính xác cho Go runtime behavior

**Nhược điểm:**
- ❌ Không phản ánh container limits
- ❌ Thiếu network/disk metrics
- ❌ Không thấy overhead của OS/sidecar

#### **Khi nào cần cAdvisor?**

**Cần cAdvisor khi:**
- Monitor container resource limits vs actual usage
- Cần network/disk I/O metrics
- Production environment với nhiều containers
- Cần alerts dựa trên container limits (80% memory used)

**Go metrics đủ khi:**
- Development environment
- Focus vào application performance
- Monitor Go-specific behavior (GC, goroutines)
- Không cần infrastructure-level metrics

2. **Total Network Traffic panel:**
   - Chỉ đo HTTP body size, **không phải total pod network**
   - Thiếu: TCP headers, HTTP headers, TLS overhead, health checks
   - **Khuyến nghị:** Nên đổi tên thành "HTTP Traffic" cho chính xác

3. **Restarts panel:**
   - Chỉ đếm container crashes
   - Không đếm rolling updates hay manual restarts
   - **Đã fix:** Giờ filter đúng theo app được chọn

4. **Counter metrics đã được fix:**
   - ✅ **Panels đã fix:** "Total Request", "Total Requests by Endpoint"
   - ✅ **Dùng `increase([$__range])`** thay vì raw counter
   - ✅ **Không bị reset** khi pod restart (Prometheus handle counter resets)
   - ✅ **Giá trị theo time range** được chọn (30m, 1h, 24h)
   - 📚 **Chi tiết:** Xem [PROMETHEUS_RATE_EXPLAINED.md](./PROMETHEUS_RATE_EXPLAINED.md) để hiểu cách `increase()` và `rate()` xử lý counter resets

### ✅ Best Practices

1. **Theo dõi cả 4 golden signals:**
   - Latency: p50, p95, p99
   - Traffic: RPS
   - Errors: Error Rate
   - Saturation: Requests In Flight

2. **Dùng Apdex Score** cho đánh giá tổng thể health

3. **Filter theo namespace** để tránh metrics từ system pods

4. **Điều chỉnh biến `$rate`** dựa trên traffic pattern:
   - High traffic: 1m-5m (responsive)
   - Low traffic: 30m-1h (mượt hơn)

5. **So sánh "Total Request" vs "Total Requests by Endpoint"** 
   - Phải khớp nhau (cùng metric source)

---