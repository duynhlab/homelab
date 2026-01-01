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

Dự án này expose **6 custom application metrics** và tận dụng **Go runtime metrics** để cung cấp **34 Grafana dashboard panels trong 5 row groups** cho việc giám sát toàn diện, bao gồm phát hiện memory leak.

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

## Go Runtime Metrics

The dashboard leverages Go runtime metrics exposed automatically by the Prometheus Go client library. These metrics provide insights into:

- **Memory**: Heap allocations, in-use memory, process RSS
- **Goroutines**: Active goroutines and OS threads
- **Garbage Collection**: GC duration and frequency

**Key Metrics:**
- `go_memstats_alloc_bytes` - Currently allocated heap memory
- `go_memstats_heap_inuse_bytes` - Heap memory spans in use
- `process_resident_memory_bytes` - Process RSS (physical memory)
- `go_goroutines` - Active goroutines
- `go_threads` - OS threads
- `go_gc_duration_seconds` - GC pause duration
- `go_gc_duration_seconds_count` - GC cycles count

**See Also:**
- [Grafana Dashboard Guide](../guides/GRAFANA_DASHBOARD.md) - Complete panel reference with queries and troubleshooting
- [Memory Leak Detection Strategy](#memory-leak-detection-strategy) - Using Go runtime metrics for leak detection

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
> **📖 See [Troubleshooting Guide](./TROUBLESHOOTING.md)** for common variable cascading issues and solutions.

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
- **[Metrics Label Solutions](./METRICS_LABEL_SOLUTIONS.md)** - Label injection strategy, ServiceMonitor configuration, and auto-discovery

### Troubleshooting
- **[Troubleshooting Guide](./TROUBLESHOOTING.md)** - Common issues, variable cascading problems, and solutions

---

**Last Updated**: 2026-01-01  
**Version**: 1.0  
**Maintainer**: SRE Team
