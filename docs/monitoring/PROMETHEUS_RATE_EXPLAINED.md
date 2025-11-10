# Prometheus: Counter, rate() và increase() - Giải Thích Chi Tiết

## 📚 **Nguồn Tham Khảo**

Tài liệu này dựa trên:
- [Prometheus Official Documentation - rate()](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate)
- [Prometheus Counter Best Practices](https://prometheus.io/docs/practices/instrumentation/#counter)
- [Stack Overflow: Handling Counter Resets](https://stackoverflow.com/questions/58069711/how-to-sum-prometheus-counters-when-k8s-pods-restart)
- [SignOz: Handling Counters on Servers](https://signoz.io/guides/how-to-handle-counters-on-servers-in-prometheus/)

---

## 🔢 **Counter Metric - Cơ Bản**

### **Counter là gì?**
- Metric type trong Prometheus
- **Chỉ tăng**, không giảm (monotonic increasing)
- Reset về 0 khi:
  - Process restart
  - Pod restart (K8s)
  - Application crash/redeploy

### **Ví dụ:**
```
Time    Counter Value   Event
10:00   5,000
10:05   5,500           +500 requests
10:10   6,000           +500 requests
10:15   0               ← POD RESTART
10:20   300             +300 requests (from 0)
10:25   600             +300 requests
```

---

## ⚠️ **Vấn Đề: Query Trực Tiếp Counter**

### **Query:**
```promql
request_duration_seconds_count{app="auth-service"}
```

### **Grafana hiển thị:**
```
Before restart: 6,000 requests
After restart:  0 requests    ← Nhảy về 0!
5 min later:    300 requests
```

### **Vấn đề:**
1. ❌ **Mất data** khi pod restart
2. ❌ **Graph bị gián đoạn** (drop to 0)
3. ❌ **Không tổng hợp** history từ Prometheus
4. ❌ **Instant value** - không phản ánh rate/trend

---

## ✅ **Giải Pháp 1: `rate()` Function**

### **rate() là gì?**
- Tính **tốc độ tăng trung bình** (per second)
- **Tự động xử lý** counter resets
- Dùng cho: Calculating rates (RPS, error rate, etc)

### **Công thức:**
```
rate(counter[time_range]) = (value_end - value_start) / time_range_seconds
```

### **Query:**
```promql
rate(request_duration_seconds_count{app="auth-service"}[5m])
```

### **Cách Prometheus xử lý counter reset:**

**Time Series Data:**
```
10:00 → 5,000
10:05 → 5,500   rate = (5,500 - 5,000) / 300s = 1.67 req/s
10:10 → 6,000   rate = (6,000 - 5,500) / 300s = 1.67 req/s
[RESTART DETECTED]
10:15 → 0       rate = 0 / 300s = 0 (Prometheus ignores negative delta)
10:20 → 300     rate = 300 / 300s = 1.0 req/s
10:25 → 600     rate = (600 - 300) / 300s = 1.0 req/s
```

**Grafana Graph:**
```
RPS
 2.0 ┤ ███████████
     │            ╲
 1.5 ┤             ╲
     │              ╲___
 1.0 ┤                  █████
     │
 0.5 ┤
     └────────────────────────> Time
               ↑
           restart (1 dip, tự phục hồi)
```

### **Đặc điểm:**
✅ **Auto-detect resets:** Prometheus phát hiện khi value giảm  
✅ **Smooth graph:** Chỉ có 1 dip nhỏ khi restart  
✅ **Per-second rate:** Dễ hiểu (5.2 req/s)  
✅ **Extrapolation:** Prometheus ngoại suy cho first/last points

### **Use case:**
- RPS (Requests Per Second)
- Error rate
- CPU usage rate
- Network throughput

---

## ✅ **Giải Pháp 2: `increase()` Function**

### **increase() là gì?**
- Tính **tổng số tăng** trong time range
- **Tự động xử lý** counter resets
- Dùng cho: Calculating totals over time range

### **Công thức:**
```
increase(counter[time_range]) = rate(counter[time_range]) * time_range_seconds
```

### **Query:**
```promql
increase(request_duration_seconds_count{app="auth-service"}[5m])
```

### **Cách Prometheus xử lý:**

**Time Series Data:**
```
10:00 → 5,000
10:05 → 5,500   increase = 5,500 - 5,000 = 500
10:10 → 6,000   increase = 6,000 - 5,500 = 500
[RESTART]
10:15 → 0       increase = 0 (ignores reset)
10:20 → 300     increase = 300 - 0 = 300
10:25 → 600     increase = 600 - 300 = 300
```

**Grafana Graph:**
```
Requests (5m window)
 600 ┤ ███████████
     │            ╲
 500 ┤             ╲___
     │                 ████
 300 ┤
     │
 100 ┤
     └────────────────────────> Time
               ↑
           restart (smooth transition)
```

### **Đặc điểm:**
✅ **Auto-detect resets:** Giống rate()  
✅ **Shows totals:** Tổng requests trong time window  
✅ **Dashboard time range:** Dùng `$__range` cho full dashboard range  
✅ **No per-second conversion:** Giá trị thô

### **Use case:**
- Total requests in time range
- Total errors in last hour
- Cumulative metrics for dashboards

---

## 🆚 **So Sánh Chi Tiết**

### **1. Raw Counter (Không có rate/increase)**

**Query:**
```promql
sum(request_duration_seconds_count{app="auth-service"})
```

| Aspect | Value |
|--------|-------|
| **Hiển thị** | Instant value (6,000) |
| **Unit** | Count (absolute number) |
| **Pod restart** | ❌ Jump to 0 |
| **Time range** | ❌ Ignores dashboard time selector |
| **Prometheus history** | ❌ Không dùng |
| **Use case** | Debug, instant snapshots |

**Grafana Output:**
```
Total Requests: 6,000
[After restart]
Total Requests: 0      ← Mất hết!
```

---

### **2. rate() Function**

**Query:**
```promql
sum(rate(request_duration_seconds_count{app="auth-service"}[5m]))
```

| Aspect | Value |
|--------|-------|
| **Hiển thị** | Per-second rate (5.2 req/s) |
| **Unit** | req/s (rate) |
| **Pod restart** | ✅ Auto-handled (1 small dip) |
| **Time range** | Uses `[5m]` window |
| **Prometheus history** | ✅ Full history |
| **Use case** | RPS, throughput monitoring |

**Grafana Output:**
```
RPS: 5.2 req/s
[After restart]
RPS: 0 req/s (1 point)
RPS: 4.8 req/s         ← Tự phục hồi!
```

---

### **3. increase() Function**

**Query:**
```promql
sum(increase(request_duration_seconds_count{app="auth-service"}[$__range]))
```

| Aspect | Value |
|--------|-------|
| **Hiển thị** | Total in time range (15,432) |
| **Unit** | Count (total) |
| **Pod restart** | ✅ Auto-handled (tổng hợp qua restarts) |
| **Time range** | ✅ Respects dashboard selector (30m, 1h, etc) |
| **Prometheus history** | ✅ Full history |
| **Use case** | Dashboard totals, SLO monitoring |

**Grafana Output:**
```
Total Requests (last 30m): 15,432
[After restart still in 30m window]
Total Requests (last 30m): 15,432  ← Giữ nguyên!
```

---

## 📊 **Ví Dụ Thực Tế**

### **Scenario: Pod Restart trong Dashboard Time Range**

**Dashboard time range:** Last 1 hour (11:00 - 12:00)  
**Pod restart:** 11:30

**Time Series:**
```
11:00 → 10,000
11:15 → 12,000  (+2,000)
11:30 → 15,000  (+3,000)
[RESTART at 11:30]
11:45 → 1,500   (+1,500 from 0)
12:00 → 3,000   (+1,500)
```

**Query Results:**

| Query Type | Result | Explanation |
|------------|--------|-------------|
| **Raw Counter** | `3,000` | Chỉ hiện instant value (sau restart) |
| **rate([5m])** | `1.67 req/s` | Average rate (smooth qua restart) |
| **increase([1h])** | `10,000` | Total = 2k + 3k + 1.5k + 1.5k + extrapolation |

---

## 🎯 **Best Practices**

### **1. Khi nào dùng Raw Counter?**
```promql
request_duration_seconds_count{...}
```
❌ **KHÔNG nên** dùng trong dashboard panels  
✅ **CHỈ dùng** cho:
- Debug instant state
- Testing/development
- Khi chắc chắn không có restarts

---

### **2. Khi nào dùng rate()?**
```promql
rate(request_duration_seconds_count{...}[5m])
```
✅ **Dùng** cho:
- RPS panels (Requests Per Second)
- Error rate panels
- Any "per second" metrics
- Time series graphs showing rates

**Recommended time range:** `[5m]` hoặc `[$rate]` variable

---

### **3. Khi nào dùng increase()?**
```promql
increase(request_duration_seconds_count{...}[$__range])
```
✅ **Dùng** cho:
- Total counters in dashboards
- Stat panels showing totals
- Pie charts (distribution over time)
- SLO monitoring (total errors in 1h)

**Recommended time range:** `[$__range]` (dashboard time selector)

---

## 🔧 **Fix Cho Dashboard Hiện Tại**

### **Panel: "Total Request" (Stat)**

**CŨ (SAI):**
```promql
sum(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"})
```
→ Nhảy về 0 khi pod restart

**MỚI (ĐÚNG):**
```promql
sum(increase(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$__range]))
```
→ Tổng requests trong dashboard time range

---

### **Panel: "Total Requests by Endpoint" (Pie)**

**CŨ (SAI):**
```promql
sum(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}) by (path, code)
```
→ Phân bố instant, mất data khi restart

**MỚI (ĐÚNG):**
```promql
sum(increase(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$__range])) by (path)
```
→ Phân bố trong time range, tổng hợp qua restarts

---

## 📈 **Prometheus Counter Reset Detection**

### **Cách Prometheus phát hiện reset:**

1. **Scrape liên tục:**
   ```
   t1: counter = 5,000
   t2: counter = 5,500  → delta = +500 ✅
   t3: counter = 6,000  → delta = +500 ✅
   t4: counter = 0      → delta = -6,000 ❌ (RESET DETECTED!)
   t5: counter = 300    → delta = +300 ✅
   ```

2. **rate()/increase() handling:**
   - Nếu `delta < 0` → Assume counter reset
   - Bỏ qua data point có negative delta
   - Tiếp tục tính từ value mới

3. **Extrapolation:**
   - Prometheus ngoại suy first/last points
   - Assumes counter bắt đầu từ 0 nếu không có data trước đó

---

## ⚡ **Performance Notes**

### **Query Complexity:**

| Query | Complexity | Explanation |
|-------|-----------|-------------|
| Raw counter | O(1) | Instant query, fastest |
| rate([5m]) | O(n) | Scan 5m window, moderate |
| increase([$__range]) | O(n) | Scan full time range, slowest* |

*Slowest khi time range lớn (1d, 7d), nhưng vẫn acceptable

### **Khuyến nghị:**
- Dashboards thường dùng 30m-1h time range → `increase([$__range])` OK
- Nếu dùng 7d+ time range → Consider limiting với `[1d]` thay vì `[$__range]`

---

## 🔗 **Tài Liệu Tham Khảo**

1. **Prometheus Official:**
   - [rate() function](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate)
   - [increase() function](https://prometheus.io/docs/prometheus/latest/querying/functions/#increase)
   - [Counter metric type](https://prometheus.io/docs/concepts/metric_types/#counter)

2. **Best Practices:**
   - [Prometheus Instrumentation](https://prometheus.io/docs/practices/instrumentation/)
   - [Naming Conventions](https://prometheus.io/docs/practices/naming/)

3. **Community Resources:**
   - [Stack Overflow: Counter Resets](https://stackoverflow.com/questions/58069711/how-to-sum-prometheus-counters-when-k8s-pods-restart)
   - [SignOz Guide](https://signoz.io/guides/how-to-handle-counters-on-servers-in-prometheus/)

---

## ✅ **Kết Luận**

### **Key Takeaways:**

1. ⚠️ **KHÔNG** query raw counter trong dashboards
2. ✅ **LUÔN** dùng `rate()` hoặc `increase()`
3. 🔄 `rate()` → cho rates (req/s)
4. 📊 `increase()` → cho totals (count)
5. 🎯 `increase([$__range])` → best cho dashboard stat panels
6. 🚀 Prometheus **tự động** handle counter resets

### **Dashboard Update:**
- Fix "Total Request" panel → dùng `increase([$__range])`
- Fix "Total Requests by Endpoint" → dùng `increase([$__range])`
- Keep "RPS" panels → đã dùng `rate()` đúng rồi ✅

