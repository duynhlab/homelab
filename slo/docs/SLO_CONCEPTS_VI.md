# SLO/SLI/Error Budget - Khái niệm cơ bản

## Tổng quan

Tài liệu này giải thích các khái niệm cơ bản về SLO (Service Level Objective), SLI (Service Level Indicator), và Error Budget bằng tiếng Việt, với ví dụ thực tế từ hệ thống monitoring Go API hiện tại.

---

## Phần 1: Giới thiệu cơ bản

### SLI là gì? (Service Level Indicator)

**SLI** là **chỉ số đo lường** - một con số cụ thể cho biết service đang hoạt động như thế nào.

**Ví dụ thực tế:**
- 99.5% requests thành công (không bị lỗi 5xx)
- 95% requests phản hồi trong vòng 500ms
- 99% requests không bị lỗi 4xx/5xx

**Đặc điểm của SLI:**
- ✅ **Có thể đo được** - có tool để thu thập data
- ✅ **Có ý nghĩa** - liên quan đến trải nghiệm người dùng
- ✅ **Ổn định** - không thay đổi liên tục
- ✅ **Có thể cải thiện** - team có thể tác động được

### SLO là gì? (Service Level Objective)

**SLO** là **mục tiêu** - con số mà chúng ta muốn đạt được cho SLI.

**Ví dụ từ Go API:**
- **Availability SLO**: 99.5% (30 ngày), 99.0% (7 ngày)
- **Latency SLO**: 95% (30 ngày), 90% (7 ngày)  
- **Error Rate SLO**: 99% (30 ngày), 98% (7 ngày)

**Đặc điểm của SLO:**
- 🎯 **Tham vọng nhưng thực tế** - không quá dễ, không quá khó
- 📊 **Có thời hạn** - 30 ngày, 7 ngày, 1 ngày
- 🔄 **Có thể đánh giá** - có data để so sánh
- 📈 **Hướng tới cải thiện** - thúc đẩy team làm tốt hơn

### SLA là gì? (Service Level Agreement)

**SLA** là **thỏa thuận pháp lý** với khách hàng - cam kết về chất lượng service.

**Ví dụ:**
- "Nếu availability < 99.5% trong tháng, chúng tôi sẽ bồi thường 10% phí dịch vụ"
- "Nếu latency > 500ms cho 95% requests, khách hàng có quyền hủy hợp đồng"

**Khác biệt quan trọng:**
- **SLO** = mục tiêu nội bộ (team tự đặt)
- **SLA** = cam kết với khách hàng (có hậu quả pháp lý)

### Mối quan hệ giữa SLI, SLO, SLA

```
SLI (đo lường) → SLO (mục tiêu) → SLA (cam kết)
     ↓              ↓              ↓
  "99.5%"      "Phải đạt 99.5%"  "Nếu < 99.5% thì bồi thường"
```

**Quy trình:**
1. **Chọn SLI** phù hợp (availability, latency, error rate)
2. **Đặt SLO** dựa trên khả năng và nhu cầu
3. **Thương lượng SLA** với khách hàng (thường thấp hơn SLO)

---

## Phần 2: SLI Deep Dive

### Cách chọn SLI phù hợp

**4 loại SLI chính:**

#### 1. **Availability** (Tính khả dụng)
- **Đo gì**: Phần trăm requests thành công
- **Khi nào dùng**: Khi muốn biết service có "sống" không
- **Ví dụ**: 99.5% requests không bị lỗi 5xx

#### 2. **Latency** (Độ trễ)
- **Đo gì**: Thời gian phản hồi của requests
- **Khi nào dùng**: Khi quan tâm đến tốc độ
- **Ví dụ**: 95% requests < 500ms

#### 3. **Throughput** (Thông lượng)
- **Đo gì**: Số requests xử lý được trong 1 giây
- **Khi nào dùng**: Khi quan tâm đến khả năng xử lý
- **Ví dụ**: 1000 requests/giây

#### 4. **Error Rate** (Tỷ lệ lỗi)
- **Đo gì**: Phần trăm requests bị lỗi
- **Khi nào dùng**: Khi muốn biết chất lượng xử lý
- **Ví dụ**: 1% requests bị lỗi 4xx/5xx

### SLI Specification (Cách mô tả SLI)

Mỗi SLI cần trả lời 4 câu hỏi:

#### **What** - Đo cái gì?
- "Tỷ lệ requests thành công"
- "Thời gian phản hồi của requests"

#### **Where** - Đo ở đâu?
- "Tất cả requests đến API"
- "Chỉ requests từ mobile app"
- "Requests đến endpoint /api/users"

#### **How** - Đo như thế nào?
- "Đếm số requests 5xx / tổng requests"
- "Đo thời gian từ lúc nhận request đến lúc trả response"

#### **Good/Bad Threshold** - Ngưỡng tốt/xấu?
- "Good: >= 99.5%, Bad: < 99.5%"
- "Good: < 500ms, Bad: >= 500ms"

### Ví dụ thực tế từ Go API

#### **Availability SLI**
```
What: Tỷ lệ requests thành công
Where: Tất cả requests đến Go API (v1, v2, v3)
How: 1 - (số requests 5xx / tổng requests)
Good: >= 99.5%, Bad: < 99.5%
```

**PromQL Query:**
```promql
1 - (
  sum(rate(request_duration_seconds_count{code=~"5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count[30d]))
)
```

#### **Latency SLI**
```
What: Thời gian phản hồi requests
Where: Tất cả requests đến Go API
How: Phần trăm requests < 500ms
Good: >= 95%, Bad: < 95%
```

**PromQL Query:**
```promql
sum(rate(request_duration_seconds_bucket{le="0.5"}[30d]))
/
sum(rate(request_duration_seconds_count[30d]))
```

#### **Error Rate SLI**
```
What: Tỷ lệ requests bị lỗi
Where: Tất cả requests đến Go API
How: Số requests 4xx/5xx / tổng requests
Good: <= 1%, Bad: > 1%
```

**PromQL Query:**
```promql
1 - (
  sum(rate(request_duration_seconds_count{code=~"4..|5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count[30d]))
)
```

---

## Phần 3: Error Budget

### Error Budget là gì?

**Error Budget** = **ngân sách lỗi được phép** - số lượng lỗi tối đa mà service được phép có trong một khoảng thời gian.

**Tại sao cần Error Budget?**
- 🎯 **Định hướng team** - biết được "còn bao nhiêu lỗi được phép"
- 🚀 **Quyết định deploy** - có nên deploy feature mới không?
- 📊 **Đo lường rủi ro** - feature này có làm tăng lỗi không?
- 🔄 **Cân bằng tốc độ vs chất lượng** - deploy nhanh nhưng vẫn đảm bảo SLO

### Cách tính Error Budget

**Công thức cơ bản:**
```
Error Budget = 1 - SLO Target
```

**Ví dụ cụ thể:**
```
SLO Target: 99.5%
Error Budget = 1 - 0.995 = 0.5% = 0.005
```

**Chuyển đổi sang số liệu thực tế:**

**Với 10M requests/tháng:**
```
Total requests: 10,000,000
Error Budget: 0.5%
Allowed errors: 10,000,000 × 0.005 = 50,000 requests
```

**Với 720 giờ/tháng:**
```
Total hours: 720
Error Budget: 0.5%
Allowed downtime: 720 × 0.005 = 3.6 giờ/tháng
```

### Error Budget Policy

**Deployment Gates dựa trên Error Budget:**

#### **Budget > 50%** - 🟢 **Normal Operations**
- Deploy thoải mái
- Thử nghiệm features mới
- Không cần approval đặc biệt

#### **Budget 20-50%** - 🟡 **Caution Mode**
- Deploy cần approval
- Ưu tiên bug fixes
- Monitor chặt chẽ

#### **Budget < 20%** - 🟠 **Warning Mode**
- Pause tất cả deployments
- Chỉ deploy hotfixes
- Tập trung vào stability

#### **Budget < 10%** - 🔴 **Emergency Mode**
- Stop mọi thay đổi
- Rollback nếu cần
- Page on-call engineer

### Error Budget Tracking

**Cách theo dõi Error Budget:**

#### **Budget Consumed** (Đã sử dụng)
```
Budget Consumed = Actual Errors / Allowed Errors
```

#### **Budget Remaining** (Còn lại)
```
Budget Remaining = 1 - Budget Consumed
```

**Ví dụ:**
```
Allowed errors: 50,000
Actual errors: 20,000
Budget Consumed: 20,000 / 50,000 = 40%
Budget Remaining: 100% - 40% = 60%
```

---

## Phần 4: Burn Rate

### Burn Rate là gì?

**Burn Rate** = **tốc độ tiêu thụ Error Budget** - cho biết budget đang bị "đốt" nhanh hay chậm.

**Công thức:**
```
Burn Rate = Current Error Rate / Target Error Rate
```

**Ví dụ:**
```
Target error rate: 0.5%
Current error rate: 1%
Burn Rate = 1% / 0.5% = 2x
```

**Ý nghĩa:**
- **Burn Rate = 1x**: Bình thường, budget hết đúng hạn
- **Burn Rate = 2x**: Nhanh gấp đôi, budget hết trong 15 ngày
- **Burn Rate = 10x**: Rất nhanh, budget hết trong 3 ngày

### Multi-window Burn Rate

**Tại sao cần nhiều cửa sổ thời gian?**

#### **1-hour window** - Phát hiện sự cố nhanh
- Phát hiện incident đang xảy ra
- Alert ngay lập tức
- Phản ứng kịp thời

#### **6-hour window** - Xác nhận xu hướng
- Loại bỏ false positive
- Xác nhận có vấn đề thực sự
- Có thời gian điều tra

#### **3-day window** - Phát hiện vấn đề dài hạn
- Phát hiện performance degradation
- Vấn đề tích lũy theo thời gian
- Cần action dài hạn

### Burn Rate Thresholds

**Các ngưỡng quan trọng:**

#### **Critical (15x burn rate)**
- Budget hết trong 2 ngày
- Cần action ngay lập tức
- Page on-call engineer
- Stop tất cả deployments

#### **Warning (4x burn rate)**
- Budget hết trong 7 ngày
- Cần điều tra nguyên nhân
- Pause non-critical deployments
- Tăng cường monitoring

#### **Info (1x burn rate)**
- Bình thường
- Tiếp tục operations
- Monitor định kỳ

### Time to Exhaustion

**Công thức:**
```
Time to Exhaustion = Error Budget Hours / Burn Rate
```

**Ví dụ:**
```
Error Budget: 3.6 giờ/tháng
Burn Rate: 2x
Time to Exhaustion: 3.6 / 2 = 1.8 giờ
```

**Ý nghĩa:**
- Nếu burn rate tiếp tục 2x, budget sẽ hết trong 1.8 giờ
- Cần action trước khi hết budget
- Có thể rollback hoặc fix issue

---

## Tóm tắt

### Key Takeaways

1. **SLI** = Chỉ số đo lường (99.5% availability)
2. **SLO** = Mục tiêu (phải đạt 99.5%)
3. **SLA** = Cam kết với khách hàng (nếu < 99.5% thì bồi thường)
4. **Error Budget** = Ngân sách lỗi được phép (0.5% = 3.6h downtime/tháng)
5. **Burn Rate** = Tốc độ tiêu thụ budget (2x = hết trong 15 ngày)

### Next Steps

- Đọc [SLO_EXAMPLES_VI.md](./SLO_EXAMPLES_VI.md) để xem các tình huống thực tế
- Đọc [SLO_CALCULATIONS_VI.md](./SLO_CALCULATIONS_VI.md) để hiểu chi tiết cách tính toán
- Đọc [SLO_ALERT_RESPONSE_VI.md](./SLO_ALERT_RESPONSE_VI.md) để biết cách xử lý khi có alert

---

## References

- [Google SRE Book - Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook - Chapter 2: Implementing SLOs](https://sre.google/workbook/implementing-slos/)
- [The Art of SLOs](https://cloud.google.com/blog/products/devops-sre/sre-fundamentals-sli-vs-slo-vs-sla)
