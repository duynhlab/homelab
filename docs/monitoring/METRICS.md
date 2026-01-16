# Metrics

## Quick Summary

**Objectives:**
- Understand all metrics used in the monitoring system (custom application, Go runtime, Kubernetes)
- Learn how to use metrics for monitoring and detecting issues (memory leaks, latency)
- Configure and query Prometheus metrics in Grafana dashboards

**Learning Outcomes:**
- Custom application metrics: request_duration_seconds (histogram with _bucket, _count), requests_in_flight, request/response size
- Go runtime metrics: goroutines, memory, GC, etc.
- Kubernetes metrics: up, pod restarts
- PromQL queries for percentiles, rates, and aggregations
- 34 Grafana dashboard panels across 5 row groups
- Memory leak detection patterns

**Keywords:**
Prometheus, Metrics, Histogram, Counter, Gauge, PromQL, Percentiles, Apdex, RPS, Latency, Memory Leak, Go Runtime Metrics, Grafana Dashboard

**Technologies:**
- Prometheus (metrics collection)
- Prometheus Go Client Library
- Grafana (visualization)
- PromQL (query language)

## Tổng Quan

Dự án này expose **6 custom application metrics** và tận dụng **Go runtime metrics** cùng **Kubernetes metrics** để cung cấp **34 Grafana dashboard panels trong 5 row groups** cho việc giám sát toàn diện, bao gồm phát hiện memory leak.

### Metrics Architecture

**Label Injection Strategy (v0.5.0+):**
- **Application level**: Chỉ emit metrics với labels: `method`, `path`, `code`
- **Prometheus level**: Auto-inject `app`, `namespace`, `job`, `instance` labels during scrape
- **Why**: Eliminates label duplication, follows Prometheus best practices, simplifies application code

**Infrastructure Endpoint Filtering (v0.6.14+):**
- **Filtered paths**: `/health`, `/metrics`, `/readiness`, `/liveness`
- **Why**: Separate infrastructure monitoring from business metrics
- **Benefits**:
  - Metrics reflect actual user traffic (not polluted by health checks)
  - Lower cardinality (fewer unique path combinations)
  - Storage efficiency (~75% reduction in datapoints)
  - Accurate response time percentiles
- **Implementation**: Early return in Prometheus middleware before metric collection
- **Note**: Infrastructure endpoints still functional, just not metrified

**Service Discovery:**
- **Prometheus Operator**: Manages Prometheus via CRDs
- **ServiceMonitor**: Single resource for all microservices (namespace-based discovery)
  - **Location**: In [`kubernetes/infra/configs/monitoring/servicemonitors/microservices.yaml`](../../kubernetes/infra/configs/monitoring/servicemonitors/microservices.yaml)
  - **Deployment**: Automatically deployed via Flux Operator
  - **Reconciliation**: `flux reconcile kustomization configs-local --with-source`
- **Namespace selector**: Matches 8 namespaces (auth, user, product, cart, order, review, notification, shipping)
- **Scalability**: Efficiently handles 1000+ pods without manual configuration

---

## Complete Metrics Reference

Tất cả metrics được sử dụng trong hệ thống, được tổ chức theo loại: Custom Application Metrics, Go Runtime Metrics, và Kubernetes Metrics.

### All Metrics Summary

| Metric | Category | Type | Labels | Purpose |
|--------|----------|------|--------|---------|
| `request_duration_seconds` | Custom Application | Histogram | app, method, path, code | Response time percentiles (P50, P95, P99), Apdex score |
| `request_duration_seconds_bucket` | Custom Application | Histogram Bucket | app, method, path, code, le | Percentile calculation (histogram_quantile) |
| `request_duration_seconds_count` | Custom Application | Counter | app, method, path, code | RPS calculation, total requests |
| `requests_total` | Custom Application | Counter | app, method, path, code | Request counts & RPS calculation |
| `requests_in_flight` | Custom Application | Gauge | app, method, path | Concurrent requests, saturation monitoring |
| `request_size_bytes` | Custom Application | Histogram | app, method, path, code | Request body size |
| `request_size_bytes_sum` | Custom Application | Histogram Sum | app, method, path, code | Network RX traffic (bytes/sec) |
| `response_size_bytes` | Custom Application | Histogram | app, method, path, code | Response body size |
| `response_size_bytes_sum` | Custom Application | Histogram Sum | app, method, path, code | Network TX traffic (bytes/sec) |
| `error_rate_total` | Custom Application | Counter | app, method, path, code | Error tracking (4xx/5xx) |
| `go_memstats_alloc_bytes` | Go Runtime | Gauge | app, namespace, job, instance | Heap allocated memory, memory leak detection |
| `go_memstats_heap_inuse_bytes` | Go Runtime | Gauge | app, namespace, job, instance | Heap in-use memory, memory leak detection |
| `process_resident_memory_bytes` | Go Runtime | Gauge | app, namespace, job, instance | Process RSS, OS-level memory monitoring |
| `go_goroutines` | Go Runtime | Gauge | app, namespace, job, instance | Active goroutines, goroutine leak detection |
| `go_threads` | Go Runtime | Gauge | app, namespace, job, instance | OS threads, concurrency monitoring |
| `go_gc_duration_seconds_sum` | Go Runtime | Counter | app, namespace, job, instance | GC duration, memory pressure detection |
| `go_gc_duration_seconds_count` | Go Runtime | Counter | app, namespace, job, instance | GC frequency, memory pressure detection |
| `go_memstats_frees_total` | Go Runtime | Counter | app, namespace, job, instance | Memory frees, GC activity monitoring |
| `process_cpu_seconds_total` | Go Runtime | Counter | app, namespace, job, instance | CPU usage, service-level resource monitoring |
| `up` | Kubernetes | Gauge | job, app, namespace, instance | Service availability, instance health monitoring |
| `kube_pod_container_status_restarts_total` | Kubernetes | Counter | namespace, pod, container | Container restarts, OOM/crash detection |

**Note:** The `app` and `namespace` labels are automatically injected by Prometheus during scrape (not by application code), but included in the table for completeness since they appear in final metrics.

---

### Custom Application Metrics

Các metrics được emit bởi application code thông qua Prometheus middleware.

#### 1. `request_duration_seconds` (Histogram)

**Mô tả:** Độ trễ (latency) của HTTP requests tính bằng giây. Histogram này tự động tạo ra 3 loại metrics: `_bucket`, `_count`, và `_sum`.

**Loại:** Histogram với buckets được tối ưu hóa cho tính toán Apdex

**Buckets:** `0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10`

**Labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `code` - HTTP status code (200, 404, 500)

**Note:** 
- `app` and `namespace` labels are automatically added by Prometheus during scrape (via relabel_configs), not by the application
- Histogram tự động tạo ra:
  - `request_duration_seconds_bucket{le="..."}` - Buckets cho percentiles
  - `request_duration_seconds_count` - Counter cho tổng số requests
  - `request_duration_seconds_sum` - Sum của tất cả durations (không dùng trong dashboard)

**Công dụng:** 
- Tính toán percentiles (p50, p95, p99) từ `_bucket`
- Tính toán RPS từ `_count` với `rate()`
- Tính toán Apdex score từ `_bucket`
- Tính toán total requests từ `_count` với `increase()`

**Tại sao lại cần metrics này:**
- Histogram là metric type phù hợp nhất cho latency measurements
- Cho phép tính percentiles chính xác mà không cần lưu trữ từng giá trị
- Buckets được tối ưu cho Apdex calculation (0.5s satisfying, 2s tolerating threshold)

---

#### 1a. `request_duration_seconds_bucket` (Histogram Bucket)

**Mô tả:** Các buckets của histogram `request_duration_seconds`, được sử dụng để tính toán percentiles.

**Loại:** Histogram bucket (một phần của Histogram metric)

**Labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `code` - HTTP status code (200, 404, 500)
- `le` - Bucket boundary (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10)
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:** 
- Đây là một phần của histogram `request_duration_seconds`, không phải metric độc lập
- Được sử dụng với hàm `histogram_quantile()` để tính percentiles
- Mỗi bucket chứa số lượng requests có duration <= bucket boundary

**Công dụng:**
- Tính toán 99th percentile response time (P99) - phát hiện worst-case latency
- Tính toán 95th percentile response time (P95) - metric quan trọng cho user experience
- Tính toán 50th percentile response time (P50) - median response time
- Tính toán Apdex score (dựa trên buckets <= 0.5s và <= 2s)

**Tại sao lại cần metrics này:**
- Percentiles cho phép hiểu rõ distribution của response time, không chỉ average
- P99 giúp phát hiện outliers và worst-case scenarios
- P95 là metric tiêu chuẩn trong SRE để đánh giá user experience
- P50 (median) đại diện cho typical user experience

---

#### 1b. `request_duration_seconds_count` (Counter)

**Mô tả:** Tổng số HTTP requests đã được xử lý. Đây là counter tự động được tạo bởi Prometheus client library cho mỗi histogram.

**Loại:** Counter (một phần của Histogram metric)

**Labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `code` - HTTP status code (200, 404, 500)
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là counter metric tự động được tạo bởi Prometheus client library cho mỗi histogram
- Được sử dụng với hàm `rate()` để tính requests per second (RPS)
- Được sử dụng với hàm `increase()` để tính total requests trong time range

**Công dụng:**
- Tính toán Total RPS (tất cả requests, mọi status code)
- Tính toán Success RPS (chỉ requests 2xx)
- Tính toán Error RPS (requests 4xx/5xx)
- Tính toán Success Rate % (2xx / total * 100)
- Tính toán Error Rate % (4xx/5xx / total * 100)
- Tính toán Apdex Score (dựa trên response time buckets)
- Tính toán Total Requests trong time range được chọn
- Phân tích traffic distribution theo status codes và endpoints

**Tại sao lại cần metrics này:**
- RPS là một trong 4 Golden Signals (traffic metric)
- Success/Error rates giúp đánh giá health của service
- Total requests giúp correlate với traffic spikes hoặc incidents
- Apdex score cung cấp single number để đánh giá user satisfaction
- Traffic analysis giúp identify hot paths và capacity planning

---

#### 2. `requests_in_flight` (Gauge)

**Mô tả:** Số lượng requests đang được xử lý concurrently tại thời điểm scrape.

**Loại:** Gauge

**Labels:**
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:** 
- `app` and `namespace` labels are automatically added by Prometheus during scrape
- Được increment khi request bắt đầu, decrement khi request kết thúc
- High values = saturation (một trong 4 Golden Signals)

**Công dụng:** 
- Theo dõi concurrent requests, phát hiện bottlenecks
- Monitor service saturation
- Validate service capacity
- Service-level aggregation để xem total concurrent requests của tất cả pods

**Tại sao lại cần metrics này:**
- Requests in flight là một trong 4 Golden Signals (saturation metric)
- High values indicate service saturation và potential bottlenecks
- Quan trọng cho capacity validation: "Service có đủ capacity không?"
- Giúp detect khi service đang bị overload

---

#### 3. `request_size_bytes` (Histogram)

**Mô tả:** Kích thước của HTTP request bodies tính bằng bytes. Histogram này tự động tạo ra `_bucket`, `_count`, và `_sum`.

**Loại:** Histogram

**Buckets:** `100, 1000, 10000, 100000, 1000000`

**Labels:** 
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `code` - HTTP status code (200, 404, 500)
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:** 
- `app` and `namespace` labels are automatically added by Prometheus during scrape
- Chỉ đo HTTP body size, không bao gồm TCP/IP overhead, HTTP headers, TLS overhead

**Công dụng:** 
- Giám sát kích thước request payload
- Service-level aggregation để tính total RX (receive) traffic
- Bandwidth planning và cost estimation

**Tại sao lại cần metrics này:**
- Monitor request payload sizes để detect unusual patterns
- Estimate network ingress costs
- Bandwidth planning: "Service này receive bao nhiêu traffic?"
- Note: Chỉ đo HTTP body, không phải total pod network (cần cAdvisor cho total network)

---

#### 3a. `request_size_bytes_sum` (Histogram Sum)

**Mô tả:** Tổng kích thước (tính bằng bytes) của HTTP request bodies.

**Loại:** Histogram sum (một phần của Histogram metric)

**Labels:** Giống với `request_size_bytes`

**Note:**
- Được sử dụng với `rate()` để tính bytes per second (RX - receive)
- Được aggregate bằng `sum() by (app)` để có total RX của tất cả pods trong service

**Công dụng:**
- Total Network Traffic per Service panel: Monitor total HTTP traffic (RX) by ALL pods in the service
- Bandwidth planning và cost estimation

**Tại sao lại cần metrics này:**
- Service-level network view giúp estimate bandwidth requirements
- Cost analysis: Estimate network ingress costs
- Bandwidth planning: "Service này receive bao nhiêu traffic?"

---

#### 4. `response_size_bytes` (Histogram)

**Mô tả:** Kích thước của HTTP response bodies tính bằng bytes. Histogram này tự động tạo ra `_bucket`, `_count`, và `_sum`.

**Loại:** Histogram

**Buckets:** `100, 1000, 10000, 100000, 1000000`

**Labels:** 
- `method` - HTTP method (GET, POST, PUT, DELETE)
- `path` - Request path (/api/users, /api/products)
- `code` - HTTP status code (200, 404, 500)
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:** 
- `app` and `namespace` labels are automatically added by Prometheus during scrape
- Chỉ đo HTTP body size, không bao gồm TCP/IP overhead, HTTP headers, TLS overhead

**Công dụng:** 
- Giám sát kích thước response payload
- Service-level aggregation để tính total TX (transmit) traffic
- Bandwidth planning và cost estimation

**Tại sao lại cần metrics này:**
- Monitor response payload sizes để detect unusual patterns
- Estimate network egress costs
- Bandwidth planning: "Service này generate bao nhiêu traffic?"
- Note: Chỉ đo HTTP body, không phải total pod network (cần cAdvisor cho total network)

---

#### 4a. `response_size_bytes_sum` (Histogram Sum)

**Mô tả:** Tổng kích thước (tính bằng bytes) của HTTP response bodies.

**Loại:** Histogram sum (một phần của Histogram metric)

**Labels:** Giống với `response_size_bytes`

**Note:**
- Được sử dụng với `rate()` để tính bytes per second (TX - transmit)
- Được aggregate bằng `sum() by (app)` để có total TX của tất cả pods trong service

**Công dụng:**
- Total Network Traffic per Service panel: Monitor total HTTP traffic (TX) by ALL pods in the service
- Bandwidth planning và cost estimation

**Tại sao lại cần metrics này:**
- Service-level network view giúp estimate bandwidth requirements
- Cost analysis: Estimate network egress costs
- Bandwidth planning: "Service này generate bao nhiêu traffic?"

---

### Go Runtime Metrics

Các metrics tự động được expose bởi Prometheus Go client library từ Go runtime. Không cần code application để emit các metrics này.

#### 1. `go_memstats_alloc_bytes` (Gauge)

**Mô tả:** Số bytes hiện đang được allocated trên heap. Đây là memory đang được sử dụng bởi application.

**Loại:** Gauge

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Giá trị này chỉ tăng, không bao giờ giảm (chỉ tăng khi allocate, không giảm khi free)
- Được sử dụng để detect memory leaks: nếu tăng liên tục không giảm sau GC = leak
- Được aggregate bằng `sum() by (app)` cho service-level view

**Công dụng:**
- Heap Allocated Memory panel: Monitor memory allocation over time (Row 4)
- Total Memory per Service panel: Service-level aggregation (Row 5)
- Phát hiện memory leaks khi giá trị tăng liên tục không giảm sau GC

**Tại sao lại cần metrics này:**
- Memory leak detection: Nếu giá trị tăng liên tục mà không giảm sau GC, có thể là memory leak
- Capacity planning: Hiểu memory usage patterns giúp plan resource allocation
- Performance optimization: High memory usage có thể dẫn đến frequent GC, ảnh hưởng performance
- Service-level view giúp đánh giá total resource consumption

---

#### 2. `go_memstats_heap_inuse_bytes` (Gauge)

**Mô tả:** Số bytes của heap memory spans đang được sử dụng bởi application. Đây là memory thực sự đang được sử dụng, không phải reserved.

**Loại:** Gauge

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Khác với `go_memstats_alloc_bytes`: metric này có thể giảm sau GC
- Nên return về baseline sau GC, nếu không = có thể là memory leak

**Công dụng:**
- Heap In-Use Memory panel: Monitor heap memory in use over time (Row 4)
- Phát hiện memory leaks: Nếu không return về baseline sau GC = leak

**Tại sao lại cần metrics này:**
- Chính xác hơn `go_memstats_alloc_bytes` để detect leaks vì có thể giảm sau GC
- Steady growth sau GC cycles là indicator rõ ràng của memory leak
- Giúp phân biệt giữa high memory usage (OK) và memory leak (BAD)

---

#### 3. `process_resident_memory_bytes` (Gauge)

**Mô tả:** Total physical memory (RSS - Resident Set Size) được sử dụng bởi process tại OS level. Bao gồm heap, stack, và OS overhead.

**Loại:** Gauge

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là metric từ process_exporter hoặc Prometheus Go client library
- RSS bao gồm heap, stack, code, và OS overhead
- Continuously increasing = memory leak at OS level (không chỉ Go heap)

**Công dụng:**
- Process Memory (RSS) panel: Monitor total physical memory usage (Row 4)
- Phát hiện memory leaks ở OS level (không chỉ Go heap)

**Tại sao lại cần metrics này:**
- Cung cấp view toàn diện về memory usage, không chỉ Go heap
- Phát hiện leaks ở OS level (ví dụ: CGO code, system calls)
- Quan trọng cho container memory limits và OOM prevention

---

#### 4. `go_goroutines` (Gauge)

**Mô tả:** Số lượng goroutines đang active trong Go runtime.

**Loại:** Gauge

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Steadily increasing goroutines = goroutine leak (forgotten defer cancel(), unclosed channels)

**Công dụng:**
- Goroutines & Threads panel: Monitor goroutine count over time (Row 4)
- Phát hiện goroutine leaks khi số lượng tăng liên tục không giảm

**Tại sao lại cần metrics này:**
- Goroutine leaks là vấn đề phổ biến trong Go applications
- High goroutine count có thể dẫn đến memory pressure và performance degradation
- Phát hiện sớm giúp tránh resource exhaustion

---

#### 5. `go_threads` (Gauge)

**Mô tả:** Số lượng OS threads được sử dụng bởi Go runtime.

**Loại:** Gauge

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Go runtime quản lý OS threads để run goroutines
- Stable count là normal, tăng đột biến có thể indicate issues

**Công dụng:**
- Goroutines & Threads panel: Monitor OS thread count over time (Row 4)
- So sánh với goroutine count để hiểu thread utilization

**Tại sao lại cần metrics này:**
- High thread count có thể indicate blocking operations
- Quan trọng cho understanding Go runtime behavior
- Giúp optimize concurrency patterns

---

#### 6. `go_gc_duration_seconds_sum` (Counter)

**Mô tả:** Tổng thời gian (tính bằng giây) mà Go runtime đã dành cho garbage collection cycles.

**Loại:** Counter

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Được sử dụng với `increase()` và chia cho time window để tính average GC duration
- High values = memory pressure, GC phải làm việc nhiều hơn

**Công dụng:**
- GC Duration panel: Monitor average GC pause duration over time (Row 4)
- Phát hiện memory pressure khi GC duration tăng cao

**Tại sao lại cần metrics này:**
- GC pauses ảnh hưởng trực tiếp đến application latency
- High GC duration thường correlate với large heap size
- Quan trọng cho performance tuning và memory optimization

---

#### 7. `go_gc_duration_seconds_count` (Counter)

**Mô tả:** Tổng số lần garbage collection cycles đã được thực hiện.

**Loại:** Counter

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Được sử dụng với `rate()` để tính GC frequency (GC runs per second)
- High frequency = memory pressure hoặc insufficient heap size

**Công dụng:**
- GC Frequency panel: Monitor GC runs per second over time (Row 4)
- Phát hiện memory pressure khi GC frequency tăng cao

**Tại sao lại cần metrics này:**
- High GC frequency có thể indicate memory pressure
- Frequent GC cycles có thể ảnh hưởng đến CPU usage
- Quan trọng cho understanding memory allocation patterns

---

#### 8. `go_memstats_frees_total` (Counter)

**Mô tả:** Tổng số lần memory đã được freed (deallocated).

**Loại:** Counter

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là Go runtime metric tự động được expose bởi Prometheus Go client library
- Được aggregate bằng `sum() by (app)` để có total memory frees của tất cả pods trong service
- Indicates GC activity: high values = frequent GC cycles

**Công dụng:**
- Total Memory Allocations per Service panel: Monitor total memory frees by ALL pods in the service (Row 5)
- Indicates GC activity và memory pressure

**Tại sao lại cần metrics này:**
- High memory frees indicate frequent GC activity
- Correlate với GC Duration panel để detect memory pressure
- Service-level view giúp understand overall GC behavior
- Quan trọng cho memory optimization và GC tuning

---

#### 9. `process_cpu_seconds_total` (Counter)

**Mô tả:** Tổng CPU time (tính bằng giây) mà process đã sử dụng.

**Loại:** Counter

**Labels:**
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `job` - Prometheus job name (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là metric từ process_exporter hoặc Prometheus Go client library
- Được sử dụng với `rate()` để tính CPU usage percentage
- Được aggregate bằng `sum() by (app)` để có total CPU của tất cả pods trong service
- Nhân với 100 để có percentage (1 CPU core = 100%)

**Công dụng:**
- Total CPU per Service panel: Monitor total CPU usage by ALL pods in the service (Row 5)
- Scaling decisions: "Should we add more pods?"

**Tại sao lại cần metrics này:**
- Service-level CPU view giúp đánh giá total compute resources needed
- Quan trọng cho horizontal scaling decisions
- High values indicate need for more pods (horizontal scaling)
- Cost analysis: Estimate compute costs

---

### Kubernetes Metrics

Các metrics từ Kubernetes infrastructure, được scrape từ kube-state-metrics hoặc Prometheus.

#### 1. `up` (Gauge)

**Mô tả:** Trạng thái availability của service instances, cho biết instance có đang hoạt động và respond được với Prometheus scrape hay không.

**Loại:** Gauge

**Labels:**
- `job` - Prometheus job name (microservices)
- `app` - Application name (auto-injected by Prometheus)
- `namespace` - Kubernetes namespace (auto-injected by Prometheus)
- `instance` - Pod instance (auto-injected by Prometheus)

**Note:**
- Đây là metric tự động được tạo bởi Prometheus, không phải custom metric
- Giá trị: 1 = up, 0 = down
- Được sử dụng với hàm `count()` để đếm số instances đang up

**Công dụng:**
- Up Instances panel: Hiển thị số lượng healthy application instances (Row 1)
- Monitor scaling và failures
- Phát hiện khi instances bị down

**Tại sao lại cần metrics này:**
- Biết được số lượng instances đang hoạt động giúp đánh giá capacity
- Phát hiện nhanh khi có instances bị crash hoặc không respond
- Quan trọng cho horizontal scaling decisions

---

#### 2. `kube_pod_container_status_restarts_total` (Counter)

**Mô tả:** Tổng số lần container restart, được sử dụng để phát hiện OOM (Out of Memory) hoặc crashes.

**Loại:** Counter

**Labels:**
- `namespace` - Kubernetes namespace
- `pod` - Pod name (filtered by app name pattern)
- `container` - Container name

**Note:**
- Đây là metric từ Kubernetes, không phải custom application metric
- Được scrape từ kube-state-metrics
- Panel sử dụng regex pattern để filter pods theo app: `^$app-[a-z0-9]+-[a-z0-9]+$`

**Công dụng:**
- Restarts panel: Hiển thị số lần pod restart trong time range (Row 1)
- Phát hiện frequent restarts (indicator của OOM hoặc crashes)
- Monitor stability của pods

**Tại sao lại cần metrics này:**
- Frequent restarts thường là dấu hiệu của memory leaks hoặc crashes
- Giúp phát hiện sớm các vấn đề về stability
- Quan trọng cho reliability monitoring

---

## Dashboard Metrics Usage by Group

Dashboard được tổ chức thành 5 row groups. Mỗi group sử dụng các metrics từ phần "Complete Metrics Reference" ở trên để hiển thị thông tin giám sát. Phần này mô tả cách các metrics được sử dụng trong từng group.

### Row 1: Overview & Key Metrics

Row này hiển thị các metrics tổng quan và quan trọng nhất của hệ thống.

**Metrics được sử dụng:**
- `request_duration_seconds_bucket` - Tính P50, P95, P99 cho successful requests (2xx)
- `request_duration_seconds_count` - Tính RPS, success/error rates, Apdex, total requests
- `up` - Đếm số healthy instances
- `kube_pod_container_status_restarts_total` - Đếm pod restarts

**Panels (12 panels):**
- 99th Percentile Response Success - `histogram_quantile(0.99, ...)` từ `request_duration_seconds_bucket` với `code=~"2.."`
- 95th Percentile Response Success - `histogram_quantile(0.95, ...)` từ `request_duration_seconds_bucket` với `code=~"2.."`
- 50th Percentile Response Success - `histogram_quantile(0.5, ...)` từ `request_duration_seconds_bucket` với `code=~"2.."`
- Total RPS (All Requests) - `rate(request_duration_seconds_count[...])`
- Success RPS (2xx) - `rate(request_duration_seconds_count{code=~"2.."}[...])`
- Error RPS (4xx/5xx) - `rate(request_duration_seconds_count{code=~"4..|5.."}[...])`
- Success Rate % - `(success_rps / total_rps) * 100`
- Error Rate % - `(error_rps / total_rps) * 100`
- Apdex Score - Tính từ `request_duration_seconds_bucket` với buckets <= 0.5s và <= 2s
- Total Request - `increase(request_duration_seconds_count[$__range])`
- Up Instances - `count(up{...})`
- Restarts - `sum(kube_pod_container_status_restarts_total{...})`

**Xem chi tiết:** Tất cả metrics này đã được document đầy đủ trong phần "Complete Metrics Reference" ở trên.

---

### Row 2: Traffic & Requests

Row này phân tích traffic patterns và request distribution theo status codes và endpoints.

**Metrics được sử dụng:**
- `request_duration_seconds_count` - Phân tích traffic distribution theo code và path

**Panels (4 panels):**
- Status Code Distribution - `rate(request_duration_seconds_count[...]) by (code)` (pie chart)
- Total Requests by Endpoint - `increase(request_duration_seconds_count[$__range]) by (path)` (pie chart)
- Request Rate by Endpoint - `rate(request_duration_seconds_count[...]) by (path)` (time series)
- RPS by Endpoint - Tương tự Request Rate by Endpoint (time series)

**Xem chi tiết:** Metric `request_duration_seconds_count` đã được document trong phần "Complete Metrics Reference" → Custom Application Metrics → `request_duration_seconds` → `request_duration_seconds_count`.

---

### Row 3: Errors & Performance

Row này tập trung vào error analysis và performance metrics theo method và endpoint.

**Metrics được sử dụng:**
- `request_duration_seconds_count` - Tính error rates theo method và endpoint
- `request_duration_seconds_bucket` - Tính response time percentiles theo endpoint

**Panels (8 panels):**
- Request Rate by Method and Endpoint - `rate(request_duration_seconds_count[...]) by (method, path)`
- Error Rate by Method and Endpoint - `(error_rps / total_rps) * 100` by (method, path)
- Client Errors (4xx) - `rate(request_duration_seconds_count{code=~"4.."}[...]) by (app)`
- Server Errors (5xx) - `rate(request_duration_seconds_count{code=~"5.."}[...]) by (app)`
- Response time 95th percentile - `histogram_quantile(0.95, ...)` by (path, code)
- Response time 50th percentile - `histogram_quantile(0.50, ...)` by (path, code)
- Response time 99th percentile - `histogram_quantile(0.99, ...)` by (path, code)

**Xem chi tiết:** 
- `request_duration_seconds_count` → "Complete Metrics Reference" → Custom Application Metrics → `request_duration_seconds` → `request_duration_seconds_count`
- `request_duration_seconds_bucket` → "Complete Metrics Reference" → Custom Application Metrics → `request_duration_seconds` → `request_duration_seconds_bucket`

---

### Row 4: Go Runtime & Memory

Row này cung cấp insights về Go runtime health, memory usage, và garbage collection để phát hiện memory leaks.

**Metrics được sử dụng:**
- `go_memstats_alloc_bytes` - Heap allocated memory
- `go_memstats_heap_inuse_bytes` - Heap in-use memory
- `process_resident_memory_bytes` - Process RSS
- `go_goroutines` - Active goroutines
- `go_threads` - OS threads
- `go_gc_duration_seconds_sum` - GC duration
- `go_gc_duration_seconds_count` - GC frequency

**Panels (6 panels):**
- Heap Allocated Memory - `go_memstats_alloc_bytes` by (app)
- Heap In-Use Memory - `go_memstats_heap_inuse_bytes` by (app)
- Process Memory (RSS) - `process_resident_memory_bytes` by (app)
- Goroutines & Threads - `go_goroutines` và `go_threads` by (app)
- GC Duration - `increase(go_gc_duration_seconds_sum[5m]) / 300` by (app)
- GC Frequency - `rate(go_gc_duration_seconds_count[5m])` by (app)

**Xem chi tiết:** Tất cả metrics này đã được document đầy đủ trong phần "Complete Metrics Reference" → Go Runtime Metrics.

---

### Row 5: Resources & Infrastructure (Service-Level)

Row này cung cấp service-level aggregation của resources và infrastructure metrics, hữu ích cho capacity planning và cost analysis.

**Metrics được sử dụng:**
- `go_memstats_alloc_bytes` - Total memory per service (aggregated)
- `process_cpu_seconds_total` - Total CPU per service
- `response_size_bytes_sum` - Network TX
- `request_size_bytes_sum` - Network RX
- `requests_in_flight` - Concurrent requests per service
- `go_memstats_frees_total` - Memory allocations per service

**Panels (5 panels):**
- Total Memory per Service - `sum(go_memstats_alloc_bytes) by (app)`
- Total CPU per Service - `sum(rate(process_cpu_seconds_total[5m])) by (app) * 100`
- Total Network Traffic per Service - `sum(rate(response_size_bytes_sum[5m])) by (app)` (TX) và `sum(rate(request_size_bytes_sum[5m])) by (app)` (RX)
- Total Requests In Flight per Service - `sum(requests_in_flight) by (app)`
- Total Memory Allocations per Service - `sum(go_memstats_frees_total) by (app)`

**Xem chi tiết:** 
- Custom Application Metrics: `requests_in_flight`, `response_size_bytes_sum`, `request_size_bytes_sum`
- Go Runtime Metrics: `go_memstats_alloc_bytes`, `process_cpu_seconds_total`, `go_memstats_frees_total`

---

## Metrics Collection Implementation

### Prometheus Middleware with Filtering (v0.6.14+)

**Location:** `services/pkg/middleware/prometheus.go`

**Key Functions:**

1. **shouldCollectMetrics(path string) bool**
   - Filters infrastructure endpoints before metric collection
   - Prevents metric pollution from health checks and monitoring endpoints
   - Returns `false` for: `/health`, `/metrics`, `/readiness`, `/liveness`

2. **PrometheusMiddleware() gin.HandlerFunc**
   - Gin middleware that collects HTTP request metrics
   - Early return pattern for infrastructure endpoints (no overhead)
   - Collects 6 custom metrics for business traffic only

**Implementation:**

```go
// Filter infrastructure endpoints
func shouldCollectMetrics(path string) bool {
	infrastructurePaths := []string{
		"/health",
		"/metrics",
		"/readiness",
		"/liveness",
	}
	
	for _, skipPath := range infrastructurePaths {
		if strings.HasPrefix(path, skipPath) {
			return false
		}
	}
	
	return true
}

// Prometheus middleware with filtering
func PrometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip metrics collection for infrastructure endpoints
		if !shouldCollectMetrics(c.Request.URL.Path) {
			c.Next()
			return
		}
		
		// Collect metrics for business traffic only
		start := time.Now()
		method := c.Request.Method
		path := c.Request.URL.Path
		
		// Increment in-flight requests
		requestsInFlight.WithLabelValues(method, path).Inc()
		
		// ... rest of metric collection logic
	}
}
```

**Why This Matters:**

Before v0.6.14:
- Health checks accounted for 79% of total requests
- Metrics were skewed by fast infrastructure calls
- P95/P99 percentiles didn't reflect actual user experience
- High cardinality from `/health` paths

After v0.6.14:
- 100% business traffic in metrics
- Accurate response time distributions
- Lower storage costs (~75% reduction)
- Clean, actionable metrics

**Consistency:**

This pattern matches the existing tracing middleware:
- `tracing.go` already filters infrastructure endpoints for distributed tracing
- Prometheus middleware now uses same approach for metrics
- Logging middleware could adopt this pattern in future

---

## Dashboard Overview

The Grafana dashboard contains **34 panels** organized in **5 row groups**:

1. **Row 1: Overview & Key Metrics** (12 panels)
   - Response time percentiles (P50, P95, P99)
   - RPS metrics (Total, Success, Error)
   - Success/Error rates
   - Apdex score
   - Up instances and restarts

2. **Row 2: Traffic & Requests** (4 panels)
   - Status code distribution
   - Request rate by endpoint
   - Total requests by endpoint

3. **Row 3: Errors & Performance** (8 panels)
   - Client errors (4xx)
   - Server errors (5xx)
   - Error rate by method and endpoint
   - Response time by endpoint

4. **Row 4: Go Runtime & Memory** (6 panels)
   - Heap allocated memory
   - Heap in-use memory
   - Process memory (RSS)
   - Goroutines & threads
   - GC duration and frequency

5. **Row 5: Resources & Infrastructure** (5 panels)
   - Total memory per service
   - Total CPU per service
   - Network traffic
   - Requests in flight
   - Memory allocations

**Complete Panel Reference:**
> **📖 See [Grafana Dashboard Guide](../guides/GRAFANA_DASHBOARD.md)** for detailed query analysis, troubleshooting scenarios, and SRE best practices for all 34 panels.

---

## Dashboard Variables Overview

The dashboard uses **4 variables** for filtering and customization:

1. **`$DS_PROMETHEUS`** - Datasource selector
2. **`$namespace`** - Kubernetes namespace filter (multi-select)
3. **`$app`** - Application/service filter (multi-select, cascades from namespace)
4. **`$rate`** - Rate interval for calculations (default: 5m)

**Variable Cascading:**
- `$namespace` filters `$app` options dynamically
- Variable order in dashboard JSON determines evaluation order
- All panel queries include both `namespace=~"$namespace"` and `app=~"$app"` filters

**Complete Variable Reference:**
> **📖 See [Variables & Regex Guide](./VARIABLES_REGEX.md)** for detailed variable configuration, regex patterns, and cascading best practices.

**Troubleshooting:**
> **📖 See [Grafana Dashboard Guide](../guides/GRAFANA_DASHBOARD.md)** for troubleshooting dashboard issues.

---

## 🔬 Memory Leak Detection Strategy

**Row 4 (Go Runtime & Memory)** cung cấp 6 panels để phát hiện memory leak một cách chính xác và toàn diện.

### Workflow: Phát hiện Memory Leak

#### **Step 1: Check Memory Heap Panels (3 panels)**

Xem 3 panels:
- **Heap Allocated** (`go_memstats_alloc_bytes`) - Tăng liên tục?
- **Heap In-Use** (`go_memstats_heap_inuse_bytes`) - Tăng không về baseline sau GC?
- **Process RSS** (`process_resident_memory_bytes`) - Tăng liên tục?

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
- **Goroutines & Threads** (`go_goroutines`) - Goroutines tăng liên tục không giảm?

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
- **GC Duration** (`go_gc_duration_seconds_sum`) - Tăng cao?
- **GC Frequency** (`go_gc_duration_seconds_count`) - Tăng cao?

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

---

#### **2. Goroutine Leak**

**Causes:**
- Context không cancel
- Channel không close
- HTTP request không timeout
- Goroutine chờ vô hạn

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
   - 📚 **Chi tiết:** Xem [PromQL Guide](./PROMQL_GUIDE.md) để hiểu cách `increase()` và `rate()` xử lý counter resets

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

## Related Documentation

### Dashboard & Visualization
- **[Grafana Dashboard Guide](../guides/GRAFANA_DASHBOARD.md)** - Complete reference for all 34 panels with queries, troubleshooting, and SRE best practices

### Variables & Configuration
- **[Variables & Regex Guide](./VARIABLES_REGEX.md)** - Dashboard variables, regex patterns, and cascading configuration
- **[PromQL Guide](./PROMQL_GUIDE.md)** - Complete guide to PromQL functions, time range vs rate interval, and counter handling

### PromQL & Queries

### Architecture & Labels
- **[Metrics Labels](./METRICS_LABEL.md)** - Label injection strategy, ServiceMonitor configuration, and auto-discovery

### Troubleshooting
- **[Grafana Dashboard Guide](../guides/GRAFANA_DASHBOARD.md)** - Dashboard troubleshooting and best practices

---

**Last Updated**: 2026-01-04  
**Version**: 2.0  
**Maintainer**: SRE Team
