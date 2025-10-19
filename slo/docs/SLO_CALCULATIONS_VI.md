# SLO/SLI - Công thức tính toán chi tiết

## Tổng quan

Tài liệu này giải thích chi tiết cách tính toán các metrics SLO/SLI/Error Budget, với ví dụ cụ thể và công thức PromQL.

---

## Phần 1: Error Budget Calculation

### Công thức cơ bản

```
Error Budget = 1 - SLO Target
```

### Ví dụ cụ thể

#### **SLO Target: 99.5%**
```
Error Budget = 1 - 0.995 = 0.005 = 0.5%
```

#### **SLO Target: 99.9%**
```
Error Budget = 1 - 0.999 = 0.001 = 0.1%
```

#### **SLO Target: 95%**
```
Error Budget = 1 - 0.95 = 0.05 = 5%
```

### Chuyển đổi sang số liệu thực tế

#### **Với 10M requests/tháng**
```
Total requests: 10,000,000
Error Budget: 0.5%
Allowed errors: 10,000,000 × 0.005 = 50,000 requests
```

#### **Với 720 giờ/tháng**
```
Total hours: 720
Error Budget: 0.5%
Allowed downtime: 720 × 0.005 = 3.6 giờ/tháng
```

#### **Với 1M requests/ngày**
```
Total requests/day: 1,000,000
Error Budget: 0.5%
Allowed errors/day: 1,000,000 × 0.005 = 5,000 requests
```

### PromQL Implementation

#### **Error Budget Remaining (30-day)**
```promql
# Calculate error budget consumed
(
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[30d]))
)
/
# Target error rate (0.5% for 99.5% SLO)
0.005
```

#### **Error Budget Remaining (7-day)**
```promql
(
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[7d]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[7d]))
)
/
0.01  # 1% for 99% SLO
```

---

## Phần 2: Burn Rate Calculation

### Công thức cơ bản

```
Burn Rate = Current Error Rate / Target Error Rate
```

### Ví dụ cụ thể

#### **Scenario 1: Bình thường**
```
Target error rate: 0.5%
Current error rate: 0.4%
Burn Rate = 0.4% / 0.5% = 0.8x
```

#### **Scenario 2: Có vấn đề**
```
Target error rate: 0.5%
Current error rate: 1.0%
Burn Rate = 1.0% / 0.5% = 2x
```

#### **Scenario 3: Sự cố nghiêm trọng**
```
Target error rate: 0.5%
Current error rate: 7.5%
Burn Rate = 7.5% / 0.5% = 15x
```

### Time to Exhaustion

```
Time to Exhaustion = Error Budget Hours / Burn Rate
```

#### **Ví dụ:**
```
Error Budget: 3.6 giờ/tháng
Burn Rate: 2x
Time to Exhaustion: 3.6 / 2 = 1.8 giờ
```

#### **Ví dụ khác:**
```
Error Budget: 3.6 giờ/tháng
Burn Rate: 15x
Time to Exhaustion: 3.6 / 15 = 0.24 giờ = 14.4 phút
```

### PromQL Implementation

#### **1-hour Burn Rate**
```promql
(
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[1h]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[1h]))
)
/
0.005  # Target error rate
```

#### **6-hour Burn Rate**
```promql
(
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[6h]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[6h]))
)
/
0.005
```

#### **3-day Burn Rate**
```promql
(
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[3d]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[3d]))
)
/
0.005
```

---

## Phần 3: SLI Calculations

### Availability SLI

#### **Công thức**
```
Availability = 1 - (Error Requests / Total Requests)
```

#### **Ví dụ cụ thể**
```
Total requests: 1,000,000
Error requests (5xx): 2,000
Availability = 1 - (2,000 / 1,000,000) = 1 - 0.002 = 0.998 = 99.8%
```

#### **PromQL Implementation**
```promql
1 - (
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[30d]))
)
```

### Latency SLI

#### **Công thức**
```
Latency SLI = (Requests < Threshold) / Total Requests
```

#### **Ví dụ cụ thể**
```
Total requests: 1,000,000
Requests < 500ms: 950,000
Latency SLI = 950,000 / 1,000,000 = 0.95 = 95%
```

#### **PromQL Implementation**
```promql
sum(rate(request_duration_seconds_bucket{app=~"demo-go-api.*", le="0.5"}[30d]))
/
sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[30d]))
```

### Error Rate SLI

#### **Công thức**
```
Error Rate SLI = 1 - (Error Requests / Total Requests)
```

#### **Ví dụ cụ thể**
```
Total requests: 1,000,000
Error requests (4xx/5xx): 5,000
Error Rate SLI = 1 - (5,000 / 1,000,000) = 1 - 0.005 = 0.995 = 99.5%
```

#### **PromQL Implementation**
```promql
1 - (
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"4..|5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[30d]))
)
```

---

## Phần 4: Advanced Calculations

### Multi-window Analysis

#### **Tại sao cần nhiều cửa sổ thời gian?**

1. **1-hour window**: Phát hiện sự cố nhanh
2. **6-hour window**: Xác nhận xu hướng
3. **3-day window**: Phát hiện vấn đề dài hạn

#### **Công thức tổng quát**
```promql
# Burn rate cho window W
(
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[W]))
  /
  sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[W]))
)
/
0.005  # Target error rate
```

### Error Budget Hours

#### **Công thức**
```
Error Budget Hours = Total Hours × Error Budget Percentage
```

#### **Ví dụ cụ thể**
```
30-day period: 30 × 24 = 720 hours
Error Budget: 0.5%
Error Budget Hours: 720 × 0.005 = 3.6 hours
```

#### **PromQL Implementation**
```promql
# Error budget hours remaining
(
  720 * 0.005  # Total error budget hours
  -
  (
    sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[30d]))
    /
    sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[30d]))
  ) * 720
)
```

### Time to Exhaustion

#### **Công thức**
```
Time to Exhaustion = Error Budget Hours / Burn Rate
```

#### **PromQL Implementation**
```promql
# Time to exhaustion in hours
(
  720 * 0.005  # Error budget hours
  -
  (
    sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[30d]))
    /
    sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[30d]))
  ) * 720
)
/
(
  (
    sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[1h]))
    /
    sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[1h]))
  )
  /
  0.005
)
```

---

## Phần 5: Practical Examples

### Example 1: Normal Operation

#### **Input Data**
```
Total requests (30d): 10,000,000
Error requests (5xx): 20,000
SLO Target: 99.5%
```

#### **Calculations**
```
Availability = 1 - (20,000 / 10,000,000) = 99.8%
Error Budget = 1 - 0.995 = 0.5%
Allowed errors = 10,000,000 × 0.005 = 50,000
Budget consumed = 20,000 / 50,000 = 40%
Budget remaining = 100% - 40% = 60%
```

#### **Result**
- ✅ Availability: 99.8% (above target)
- ✅ Budget remaining: 60% (healthy)
- ✅ Status: Normal operations

### Example 2: High Error Rate

#### **Input Data**
```
Total requests (30d): 10,000,000
Error requests (5xx): 80,000
SLO Target: 99.5%
```

#### **Calculations**
```
Availability = 1 - (80,000 / 10,000,000) = 99.2%
Error Budget = 1 - 0.995 = 0.5%
Allowed errors = 10,000,000 × 0.005 = 50,000
Budget consumed = 80,000 / 50,000 = 160%
Budget remaining = 100% - 160% = -60%
```

#### **Result**
- ❌ Availability: 99.2% (below target)
- ❌ Budget remaining: -60% (exceeded)
- 🚨 Status: Critical - budget exceeded

### Example 3: Burn Rate Analysis

#### **Input Data**
```
Current error rate (1h): 1.0%
Target error rate: 0.5%
Error budget hours: 3.6
```

#### **Calculations**
```
Burn Rate = 1.0% / 0.5% = 2x
Time to exhaustion = 3.6 / 2 = 1.8 hours
```

#### **Result**
- ⚠️ Burn Rate: 2x (high)
- ⚠️ Time to exhaustion: 1.8 hours
- 🚨 Action: Investigate immediately

---

## Phần 6: Troubleshooting Calculations

### Common Issues

#### **Issue 1: No Data**
```
Problem: Query returns "No data"
Cause: Time range too short, no metrics available
Solution: Use longer time range, check metric collection
```

#### **Issue 2: Negative Values**
```
Problem: Budget remaining shows negative
Cause: Error rate exceeds SLO target
Solution: This is expected - indicates budget exceeded
```

#### **Issue 3: Infinite Burn Rate**
```
Problem: Burn Rate shows infinity
Cause: Target error rate is 0
Solution: Add small offset (0.001) to prevent division by zero
```

### Validation Queries

#### **Check if metrics exist**
```promql
count(request_duration_seconds_count{app=~"demo-go-api.*"})
```

#### **Check time range**
```promql
max(request_duration_seconds_count{app=~"demo-go-api.*"}) - min(request_duration_seconds_count{app=~"demo-go-api.*"})
```

#### **Check error rate**
```promql
sum(rate(request_duration_seconds_count{app=~"demo-go-api.*", code=~"5.."}[1h]))
/
sum(rate(request_duration_seconds_count{app=~"demo-go-api.*"}[1h]))
```

---

## Tóm tắt

### Key Formulas

1. **Error Budget** = 1 - SLO Target
2. **Burn Rate** = Current Error Rate / Target Error Rate
3. **Availability** = 1 - (Error Requests / Total Requests)
4. **Latency SLI** = (Requests < Threshold) / Total Requests
5. **Time to Exhaustion** = Error Budget Hours / Burn Rate

### Best Practices

1. **Use appropriate time ranges** - 30d for SLOs, 1h for burn rate
2. **Handle edge cases** - Division by zero, negative values
3. **Validate calculations** - Cross-check with multiple queries
4. **Monitor trends** - Don't just look at current values
5. **Set realistic targets** - Based on historical data

---

## Next Steps

- Thực hành với [SLO_EXAMPLES_VI.md](./SLO_EXAMPLES_VI.md) scenarios
- Đọc [SLO_ALERT_RESPONSE_VI.md](./SLO_ALERT_RESPONSE_VI.md) để biết cách xử lý alerts
- Sử dụng [SLO_QUICK_REFERENCE.md](./SLO_QUICK_REFERENCE.md) làm cheat sheet
