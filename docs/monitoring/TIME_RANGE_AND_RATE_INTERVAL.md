# Time Range vs Rate Interval - Hướng dẫn chi tiết

## Tổng quan

Trong Grafana dashboard, có 2 khái niệm quan trọng ảnh hưởng đến cách hiển thị dữ liệu:

1. **Time Range** (Khoảng thời gian hiển thị) - Kiểm soát "xem bao xa về quá khứ"
2. **Rate Interval** (Độ mịn tính toán) - Kiểm soát "độ chi tiết của rate calculation"

Hiểu rõ 2 khái niệm này giúp bạn:
- Tối ưu dashboard cho từng use case
- Troubleshoot chính xác hơn
- Chọn settings phù hợp cho monitoring

---

## 1. Time Range (Khoảng thời gian hiển thị) 📅

### Định nghĩa
Time Range là khoảng thời gian mà dashboard hiển thị dữ liệu, từ thời điểm bắt đầu đến hiện tại.

### Cách thay đổi
- Click vào dropdown ở góc trên bên phải dashboard
- Chọn "Last 5 minutes", "Last 30 minutes", "Last 6 hours", etc.
- Hoặc chọn "Custom" để nhập thời gian cụ thể

### Các giá trị phổ biến
- **Last 5 minutes** - Debug real-time
- **Last 30 minutes** - Hoạt động gần đây
- **Last 6 hours** - Monitoring bình thường
- **Last 24 hours** - Review hàng ngày
- **Last 7 days** - Xu hướng dài hạn

### Queries bị ảnh hưởng
- `$__range` variable
- `increase()` function
- Time series X-axis

---

## 2. Rate Interval (Độ mịn tính toán) ⏱️

### Định nghĩa
Rate Interval ($rate variable) là khoảng thời gian để tính **rate** (tốc độ thay đổi) trong Prometheus queries.

### Cách thay đổi
- Click vào dropdown "Rate" ở góc trên bên trái dashboard
- Chọn "1m", "5m", "30m", "1h", etc.

### Các giá trị phổ biến
- **1m** - Chi tiết cao, nhạy cảm
- **5m** - Cân bằng detail vs smoothness
- **30m** - Mịn, bỏ noise
- **1h** - Xu hướng dài hạn

### Queries bị ảnh hưởng
- `$rate` variable
- `rate()` function
- Độ mịn của time series graphs

---

## 3. Ví dụ thực tế

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

## 4. Bảng so sánh

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

## 5. Best Practices

### Rule of Thumb
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

## 6. Scenarios thực tế

### Scenario 1: Troubleshooting Spike 🔍

**Mục tiêu:** Tìm chính xác thời điểm xảy ra spike

**Settings:**
- Time Range: Last 1 hour (narrow down)
- Rate Interval: 5m (chi tiết cao)

**Kết quả:**
- Thấy được spike xảy ra lúc nào
- RPS panels nhạy cảm, thấy rõ pattern
- Total Request vẫn chính xác

### Scenario 2: Daily Review 📊

**Mục tiêu:** Hiểu patterns trong ngày

**Settings:**
- Time Range: Last 24 hours
- Rate Interval: 1h (smooth trends)

**Kết quả:**
- Thấy được peak hours
- Trends mịn, dễ đọc
- Không bị noise làm rối

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

## 7. Visual Examples

### Time Range vs Rate Interval

```
Time Range: Last 6 hours
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
|                                        |
|  <------- 6 hours data -------->      |
|                                        |
|  Total Request = Tổng tất cả requests |
|  (KHÔNG phụ thuộc $rate)              |
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Rate Interval ($rate):
┌─────────┐ ← 30m window
│ rate()  │ → Tính RPS trong window này
└─────────┘

┌───┐ ← 5m window  
│rate│ → Nhạy hơn, chi tiết hơn
└───┘
```

### Graph Smoothness

```
$rate = 30m:
RPS
  |     ╭─╮
  |   ╭─╯  ╰─╮
  | ╭─╯      ╰─╮
  |╱            ╲
  └──────────────→ Time
  (Smooth, less noise)

$rate = 5m:
RPS
  |  ╭╮  ╭╮  ╭╮
  | ╱  ╲╱  ╲╱  ╲
  |╱    ╲  ╱    ╲
  └──────────────→ Time
  (Sensitive, more detail)
```

---

## 8. Prometheus Query Details

### `rate()` function
```promql
rate(metric[$rate])
```
- Tính per-second rate
- Trong window $rate
- Tự động handle counter resets
- **Ảnh hưởng bởi $rate**

### `increase()` function
```promql
increase(metric[$__range])
```
- Tính total increase
- Trong Time Range
- **KHÔNG ảnh hưởng bởi $rate**

### `histogram_quantile()` function
```promql
histogram_quantile(0.95, sum(rate(...[$rate])) by (le))
```
- Tính percentile
- Sử dụng `rate()` bên trong
- **Ảnh hưởng bởi $rate**

---

## 9. FAQ

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

## 10. Troubleshooting Tips

### Problem: Graph quá nhạy, nhiều noise
**Solution:** Tăng $rate (5m → 30m)

### Problem: Không thấy spike chi tiết
**Solution:** Giảm $rate (30m → 5m)

### Problem: Total Request thay đổi khi đổi $rate
**Solution:** Kiểm tra query, có thể dùng `$rate` thay vì `$__range`

### Problem: RPS không thay đổi khi đổi $rate
**Solution:** Kiểm tra query, có thể dùng `$__range` thay vì `$rate`

---

## 11. Kết luận

- **Time Range**: Kiểm soát "xem bao xa về quá khứ"
- **Rate Interval**: Kiểm soát "độ chi tiết của rate calculation"
- Chúng độc lập nhưng nên chọn hợp lý
- Hiểu rõ giúp optimize dashboard cho từng use case
- Rule of thumb: $rate ≈ 1/10 đến 1/20 của Time Range

---

## 12. References

- [Prometheus rate() function](https://prometheus.io/docs/prometheus/latest/querying/functions/#rate)
- [Prometheus increase() function](https://prometheus.io/docs/prometheus/latest/querying/functions/#increase)
- [Grafana Time Range](https://grafana.com/docs/grafana/latest/dashboards/time-range-controls/)
- [Grafana Variables](https://grafana.com/docs/grafana/latest/dashboards/variables/)
