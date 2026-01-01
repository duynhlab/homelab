# PromQL Guide - Counter Metrics, rate(), increase(), and Time Intervals

## Quick Summary

**Objectives:**
- Understand Prometheus Counter metrics and their behavior
- Learn the difference between `rate()` and `increase()` functions
- Understand Time Range vs Rate Interval in Grafana dashboards
- Handle counter resets correctly in queries
- Optimize dashboard settings for different use cases

**Learning Outcomes:**
- Counter metric characteristics (monotonic, resets on restart)
- `rate()` function: calculates per-second rate
- `increase()` function: calculates total increase over time range
- Time Range: controls how far back to display data
- Rate Interval: controls calculation granularity
- Handling counter resets in PromQL queries
- Best practices for counter metrics and dashboard configuration

**Keywords:**
Prometheus Counter, rate(), increase(), Counter Reset, Monotonic, Per-second Rate, Time Range, Rate Interval, PromQL Functions, Grafana Dashboard

**Technologies:**
- Prometheus (counter metrics)
- PromQL (rate, increase functions)
- Grafana (dashboard settings)

---

## 📚 Nguồn Tham Khảo

Tài liệu này dựa trên:
- [Prometheus Official Documentation - rate()](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate)
- [Prometheus Counter Best Practices](https://prometheus.io/docs/practices/instrumentation/#counter)
- [Stack Overflow: Handling Counter Resets](https://stackoverflow.com/questions/58069711/how-to-sum-prometheus-counters-when-k8s-pods-restart)
- [SignOz: Handling Counters on Servers](https://signoz.io/guides/how-to-handle-counters-on-servers-in-prometheus/)
- [Grafana Time Range Documentation](https://grafana.com/docs/grafana/latest/dashboards/time-range-controls/)

---

## 🔢 Counter Metric - Cơ Bản

### Counter là gì?
- Metric type trong Prometheus
- **Chỉ tăng**, không giảm (monotonic increasing)
- Reset về 0 khi:
  - Process restart
  - Pod restart (K8s)
  - Application crash/redeploy

### Ví dụ:
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

## ⚠️ Vấn Đề: Query Trực Tiếp Counter

### Query:
```promql
request_duration_seconds_count{app="auth"}
```

### Grafana hiển thị:
```
Before restart: 6,000 requests
After restart:  0 requests    ← Nhảy về 0!
5 min later:    300 requests
```

### Vấn đề:
1. ❌ **Mất data** khi pod restart
2. ❌ **Graph bị gián đoạn** (drop to 0)
3. ❌ **Không tổng hợp** history từ Prometheus
4. ❌ **Instant value** - không phản ánh rate/trend

---

## ✅ Giải Pháp 1: `rate()` Function

### `rate()` là gì?
- Tính **tốc độ tăng trung bình** (per second)
- **Tự động xử lý** counter resets
- Dùng cho: Calculating rates (RPS, error rate, etc)

### Công thức:
```
rate(counter[time_range]) = (value_end - value_start) / time_range_seconds
```

### Query:
```promql
rate(request_duration_seconds_count{app="auth"}[5m])
```

### Cách Prometheus xử lý counter reset:

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

### Đặc điểm:
✅ **Auto-detect resets:** Prometheus phát hiện khi value giảm  
✅ **Smooth graph:** Chỉ có 1 dip nhỏ khi restart  
✅ **Per-second rate:** Dễ hiểu (5.2 req/s)  
✅ **Extrapolation:** Prometheus ngoại suy cho first/last points

### Use case:
- RPS (Requests Per Second)
- Error rate
- CPU usage rate
- Network throughput

---

## ✅ Giải Pháp 2: `increase()` Function

### `increase()` là gì?
- Tính **tổng số tăng** trong time range
- **Tự động xử lý** counter resets
- Dùng cho: Calculating totals over time range

### Công thức:
```
increase(counter[time_range]) = rate(counter[time_range]) * time_range_seconds
```

### Query:
```promql
increase(request_duration_seconds_count{app="auth"}[$__range])
```

### Cách Prometheus xử lý:

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

### Đặc điểm:
✅ **Auto-detect resets:** Giống rate()  
✅ **Shows totals:** Tổng requests trong time window  
✅ **Dashboard time range:** Dùng `$__range` cho full dashboard range  
✅ **No per-second conversion:** Giá trị thô

### Use case:
- Total requests in time range
- Total errors in last hour
- Cumulative metrics for dashboards

---

## 🆚 So Sánh Chi Tiết

### 1. Raw Counter (Không có rate/increase)

**Query:**
```promql
sum(request_duration_seconds_count{app="auth"})
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

### 2. rate() Function

**Query:**
```promql
sum(rate(request_duration_seconds_count{app="auth"}[5m]))
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

### 3. increase() Function

**Query:**
```promql
sum(increase(request_duration_seconds_count{app="auth"}[$__range]))
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

## 📅 Time Range vs Rate Interval

Trong Grafana dashboard, có 2 khái niệm quan trọng ảnh hưởng đến cách hiển thị dữ liệu:

1. **Time Range** (Khoảng thời gian hiển thị) - Kiểm soát "xem bao xa về quá khứ"
2. **Rate Interval** (Độ mịn tính toán) - Kiểm soát "độ chi tiết của rate calculation"

### Time Range (Khoảng thời gian hiển thị) 📅

**Định nghĩa:**
Time Range là khoảng thời gian mà dashboard hiển thị dữ liệu, từ thời điểm bắt đầu đến hiện tại.

**Cách thay đổi:**
- Click vào dropdown ở góc trên bên phải dashboard
- Chọn "Last 5 minutes", "Last 30 minutes", "Last 6 hours", etc.
- Hoặc chọn "Custom" để nhập thời gian cụ thể

**Các giá trị phổ biến:**
- **Last 5 minutes** - Debug real-time
- **Last 30 minutes** - Hoạt động gần đây
- **Last 6 hours** - Monitoring bình thường
- **Last 24 hours** - Review hàng ngày
- **Last 7 days** - Xu hướng dài hạn

**Queries bị ảnh hưởng:**
- `$__range` variable
- `increase()` function
- Time series X-axis

---

### Rate Interval (Độ mịn tính toán) ⏱️

**Định nghĩa:**
Rate Interval (`$rate` variable) là khoảng thời gian để tính **rate** (tốc độ thay đổi) trong Prometheus queries.

**Cách thay đổi:**
- Click vào dropdown "Rate" ở góc trên bên trái dashboard
- Chọn "1m", "5m", "30m", "1h", etc.

**Các giá trị phổ biến:**
- **1m** - Chi tiết cao, nhạy cảm
- **5m** - Cân bằng detail vs smoothness
- **30m** - Mịn, bỏ noise
- **1h** - Xu hướng dài hạn

**Queries bị ảnh hưởng:**
- `$rate` variable
- `rate()` function
- Độ mịn của time series graphs

---

## 📊 Ví Dụ Thực Tế

### Panel "Total Request" - KHÔNG thay đổi với $rate

**Query:**
```promql
sum(increase(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$__range]))
```

**Giải thích:**
- Sử dụng `$__range` (Time Range)
- **KHÔNG** sử dụng `$rate`
- Tính tổng requests trong toàn bộ Time Range

**Ví dụ:**
```
Time Range: Last 6 hours
$rate: 30m → Total Request = 21,600 requests
$rate: 5m  → Total Request = 21,600 requests (KHÔNG ĐỔI)
```

---

### Panel "Total RPS" - THAY ĐỔI với $rate

**Query:**
```promql
sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))
```

**Giải thích:**
- Sử dụng `$rate` (Rate Interval)
- **KHÔNG** sử dụng `$__range`
- Tính RPS dựa trên window này

**Ví dụ:**
```
Time Range: Last 6 hours
$rate: 30m → RPS = 60 (trung bình 30 phút)
$rate: 5m  → RPS = 65 (trung bình 5 phút, nhạy hơn)
```

---

### Panel "Success Rate %" - THAY ĐỔI với $rate

**Query:**
```promql
(
  sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace", code=~"2.."}[$rate]))
  /
  sum(rate(request_duration_seconds_count{app=~"$app", namespace=~"$namespace"}[$rate]))
) * 100
```

**Giải thích:**
- Cả numerator và denominator đều dùng `$rate`
- Đảm bảo consistency trong calculation
- Thay đổi khi đổi $rate

---

### Bảng so sánh

| Panel Name | Query Function | Uses Time Range? | Uses Rate Interval? | Changes with $rate? |
|------------|----------------|------------------|---------------------|---------------------|
| Total Request | `increase($__range)` | ✅ | ❌ | ❌ |
| Total RPS | `rate($rate)` | ❌ | ✅ | ✅ |
| Success Rate % | `rate($rate)` | ❌ | ✅ | ✅ |
| Error Rate % | `rate($rate)` | ❌ | ✅ | ✅ |
| Response Time p95 | `rate($rate)` | ❌ | ✅ | ✅ |
| Memory usage | `rate($rate)` | ❌ | ✅ | ✅ |
| CPU usage | `rate($rate)` | ❌ | ✅ | ✅ |

---

## 🎯 Best Practices

### Khi nào dùng Raw Counter?
```promql
request_duration_seconds_count{...}
```
❌ **KHÔNG nên** dùng trong dashboard panels  
✅ **CHỈ dùng** cho:
- Debug instant state
- Testing/development
- Khi chắc chắn không có restarts

---

### Khi nào dùng rate()?
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

### Khi nào dùng increase()?
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

### Rule of Thumb: Time Range vs Rate Interval

```
Rate Interval ≈ 1/10 to 1/20 của Time Range
```

### Các combination được khuyến nghị

| Time Range | Recommended $rate | Use Case |
|------------|-------------------|----------|
| Last 5 minutes | 1m | Real-time debugging |
| Last 30 minutes | 5m | Recent activity |
| Last 6 hours | 30m | Normal monitoring |
| Last 24 hours | 1h | Daily trends |
| Last 7 days | 6h | Weekly patterns |

### Ví dụ cụ thể

**Time Range = 6 hours (360 minutes)**
- Recommended $rate = 18-36 minutes
- Chọn 30m là hợp lý ✅

**Time Range = 24 hours (1440 minutes)**
- Recommended $rate = 72-144 minutes
- Chọn 1h (60m) hoặc 2h (120m) ✅

---

## 📈 Prometheus Counter Reset Detection

### Cách Prometheus phát hiện reset:

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

## 🔧 Fix Cho Dashboard Hiện Tại

### Panel: "Total Request" (Stat)

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

### Panel: "Total Requests by Endpoint" (Pie)

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

## 📊 Scenarios Thực Tế

### Scenario 1: Troubleshooting Spike 🔍

**Mục tiêu:** Tìm chính xác thời điểm xảy ra spike

**Settings:**
- Time Range: Last 1 hour (narrow down)
- Rate Interval: 5m (chi tiết cao)

**Kết quả:**
- Thấy được spike xảy ra lúc nào
- RPS panels nhạy cảm, thấy rõ pattern
- Total Request vẫn chính xác

---

### Scenario 2: Daily Review 📊

**Mục tiêu:** Hiểu patterns trong ngày

**Settings:**
- Time Range: Last 24 hours
- Rate Interval: 1h (smooth trends)

**Kết quả:**
- Thấy được peak hours
- Trends mịn, dễ đọc
- Không bị noise làm rối

---

### Scenario 3: Capacity Planning 📈

**Mục tiêu:** Lập kế hoạch capacity dài hạn

**Settings:**
- Time Range: Last 7 days hoặc 30 days
- Rate Interval: 6h hoặc 1d

**Kết quả:**
- Thấy được xu hướng tăng trưởng
- Patterns tuần/tháng
- Dữ liệu cho capacity planning

---

## ⚡ Performance Notes

### Query Complexity:

| Query | Complexity | Explanation |
|-------|-----------|-------------|
| Raw counter | O(1) | Instant query, fastest |
| rate([5m]) | O(n) | Scan 5m window, moderate |
| increase([$__range]) | O(n) | Scan full time range, slowest* |

*Slowest khi time range lớn (1d, 7d), nhưng vẫn acceptable

### Khuyến nghị:
- Dashboards thường dùng 30m-1h time range → `increase([$__range])` OK
- Nếu dùng 7d+ time range → Consider limiting với `[1d]` thay vì `[$__range]`

---

## ❓ FAQ

### Q: Tại sao Total Request không đổi khi tôi thay $rate?
**A:** Vì Total Request dùng `increase($__range)`, chỉ phụ thuộc vào Time Range, không phụ thuộc vào $rate.

### Q: Tại sao RPS thay đổi khi tôi thay $rate?
**A:** Vì RPS dùng `rate($rate)`, tính rate dựa trên window $rate. Window nhỏ hơn → nhạy hơn.

### Q: Nên chọn $rate bao nhiêu?
**A:** Theo rule of thumb: $rate ≈ 1/10 đến 1/20 của Time Range. Ví dụ: Time Range = 6h → $rate = 30m.

### Q: Time Range và $rate có liên quan gì?
**A:** Chúng độc lập nhau nhưng nên chọn hợp lý. Time Range = "xem bao xa", $rate = "độ chi tiết".

### Q: Khi nào nên giảm $rate?
**A:** Khi troubleshooting spike, cần thấy chi tiết. Giảm $rate để thấy pattern rõ hơn.

### Q: Khi nào nên tăng $rate?
**A:** Khi xem trends dài hạn, muốn graph mịn. Tăng $rate để bỏ noise.

---

## 🛠️ Troubleshooting Tips

### Problem: Graph quá nhạy, nhiều noise
**Solution:** Tăng $rate (5m → 30m)

### Problem: Không thấy spike chi tiết
**Solution:** Giảm $rate (30m → 5m)

### Problem: Total Request thay đổi khi đổi $rate
**Solution:** Kiểm tra query, có thể dùng `$rate` thay vì `$__range`

### Problem: RPS không thay đổi khi đổi $rate
**Solution:** Kiểm tra query, có thể dùng `$__range` thay vì `$rate`

---

## ✅ Kết Luận

### Key Takeaways:

1. ⚠️ **KHÔNG** query raw counter trong dashboards
2. ✅ **LUÔN** dùng `rate()` hoặc `increase()`
3. 🔄 `rate()` → cho rates (req/s)
4. 📊 `increase()` → cho totals (count)
5. 🎯 `increase([$__range])` → best cho dashboard stat panels
6. 🚀 Prometheus **tự động** handle counter resets
7. 📅 Time Range và Rate Interval độc lập nhưng nên chọn hợp lý
8. 📏 Rule of thumb: $rate ≈ 1/10 đến 1/20 của Time Range

### Dashboard Update:
- Fix "Total Request" panel → dùng `increase([$__range])`
- Fix "Total Requests by Endpoint" → dùng `increase([$__range])`
- Keep "RPS" panels → đã dùng `rate()` đúng rồi ✅

---

## 🔗 Tài Liệu Tham Khảo

1. **Prometheus Official:**
   - [rate() function](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate)
   - [increase() function](https://prometheus.io/docs/prometheus/latest/querying/functions/#increase)
   - [Counter metric type](https://prometheus.io/docs/concepts/metric_types/#counter)

2. **Best Practices:**
   - [Prometheus Instrumentation](https://prometheus.io/docs/practices/instrumentation/)
   - [Naming Conventions](https://prometheus.io/docs/practices/naming/)

3. **Grafana:**
   - [Time Range Controls](https://grafana.com/docs/grafana/latest/dashboards/time-range-controls/)
   - [Dashboard Variables](https://grafana.com/docs/grafana/latest/dashboards/variables/)

4. **Community Resources:**
   - [Stack Overflow: Counter Resets](https://stackoverflow.com/questions/58069711/how-to-sum-prometheus-counters-when-k8s-pods-restart)
   - [SignOz Guide](https://signoz.io/guides/how-to-handle-counters-on-servers-in-prometheus/)

---

**Last Updated**: 2026-01-01  
**Version**: 1.0  
**Maintainer**: SRE Team
