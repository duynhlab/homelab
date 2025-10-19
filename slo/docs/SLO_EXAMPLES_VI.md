# SLO/SLI - Các tình huống thực tế

## Tổng quan

Tài liệu này mô tả 4 tình huống thực tế khi vận hành hệ thống với SLO, giúp bạn hiểu cách phản ứng khi có các vấn đề khác nhau.

---

## Scenario 1: Hoạt động bình thường 🟢

### Tình huống
Hệ thống đang hoạt động tốt, không có vấn đề gì đặc biệt.

### Metrics hiện tại
```
✅ Availability: 99.8% (trên target 99.5%)
✅ Error Budget Remaining: 60%
✅ Burn Rate: 0.8x (chậm hơn bình thường)
✅ Latency: 97% requests < 500ms (trên target 95%)
```

### Phân tích
- **Availability cao hơn target** → Service đang hoạt động tốt
- **Error Budget còn nhiều** → Có thể deploy features mới
- **Burn Rate thấp** → Ít lỗi hơn dự kiến
- **Latency tốt** → User experience tốt

### Action Plan
1. **✅ Deploy bình thường** - Không cần hạn chế
2. **✅ Thử nghiệm features mới** - Có đủ budget
3. **✅ Monitor định kỳ** - Không cần tăng cường
4. **✅ Tiếp tục phát triển** - Focus vào innovation

### Dashboard hiển thị
- **SLO Compliance**: 🟢 99.8% (tốt)
- **Error Budget**: 🟢 60% (an toàn)
- **Burn Rate**: 🟢 0.8x (chậm)
- **Time to Exhaustion**: 🟢 > 30 ngày

---

## Scenario 2: Tăng lỗi nhẹ 🟡

### Tình huống
Có vấn đề nhẹ, error rate tăng nhưng chưa nghiêm trọng.

### Metrics hiện tại
```
⚠️ Availability: 99.2% (dưới target 99.5%)
⚠️ Error Budget Remaining: 15%
⚠️ Burn Rate: 4x (budget hết trong 7 ngày)
✅ Latency: 96% requests < 500ms (vẫn OK)
```

### Phân tích
- **Availability dưới target** → Có vấn đề cần xử lý
- **Error Budget còn ít** → Cần cẩn thận khi deploy
- **Burn Rate cao** → Lỗi đang tăng nhanh
- **Latency vẫn OK** → Vấn đề chưa ảnh hưởng tốc độ

### Action Plan
1. **🛑 Pause non-critical deployments** - Chỉ deploy hotfixes
2. **🔍 Investigate root cause** - Tìm nguyên nhân lỗi tăng
3. **📊 Tăng cường monitoring** - Theo dõi chặt chẽ hơn
4. **📞 Thông báo team** - Alert team về tình trạng

### Root Cause Analysis
1. **Check recent deployments** - Có phải do deploy mới?
2. **Analyze error patterns** - Endpoint nào lỗi nhiều?
3. **Review system metrics** - CPU, memory có bất thường?
4. **Check dependencies** - Database, external services OK?

### Dashboard hiển thị
- **SLO Compliance**: 🟡 99.2% (cảnh báo)
- **Error Budget**: 🟡 15% (thấp)
- **Burn Rate**: 🟡 4x (cao)
- **Time to Exhaustion**: 🟡 7 ngày

---

## Scenario 3: Sự cố nghiêm trọng 🔴

### Tình huống
Hệ thống gặp sự cố nghiêm trọng, error rate rất cao.

### Metrics hiện tại
```
🚨 Availability: 98.5% (rất thấp)
🚨 Error Budget Remaining: -20% (đã vượt budget)
🚨 Burn Rate: 15x (budget hết trong 2 ngày)
🚨 Latency: 80% requests < 500ms (rất tệ)
```

### Phân tích
- **Availability rất thấp** → Service gần như không hoạt động
- **Error Budget âm** → Đã vượt quá giới hạn cho phép
- **Burn Rate cực cao** → Lỗi tăng theo cấp số nhân
- **Latency tệ** → User experience rất kém

### Action Plan
1. **🚨 Page on-call engineer** - Gọi ngay người on-call
2. **🛑 Stop tất cả deployments** - Không deploy gì cả
3. **🔄 Rollback ngay lập tức** - Về version ổn định trước đó
4. **📞 Escalate to management** - Báo cáo cấp trên
5. **🔍 Emergency investigation** - Tìm nguyên nhân ngay

### Emergency Response
1. **Immediate actions** (0-15 phút):
   - Page on-call engineer
   - Stop all deployments
   - Check system status

2. **Short-term actions** (15-60 phút):
   - Rollback to last stable version
   - Scale up resources if needed
   - Notify stakeholders

3. **Long-term actions** (1-24 giờ):
   - Root cause analysis
   - Fix underlying issue
   - Post-incident review

### Dashboard hiển thị
- **SLO Compliance**: 🔴 98.5% (critical)
- **Error Budget**: 🔴 -20% (vượt budget)
- **Burn Rate**: 🔴 15x (cực cao)
- **Time to Exhaustion**: 🔴 < 2 ngày

---

## Scenario 4: Vấn đề Latency 🟠

### Tình huống
Availability OK nhưng latency cao, ảnh hưởng user experience.

### Metrics hiện tại
```
✅ Availability: 99.6% (tốt)
✅ Error Budget Remaining: 70% (OK)
✅ Burn Rate: 1.2x (bình thường)
❌ Latency: 85% requests < 500ms (dưới target 95%)
```

### Phân tích
- **Availability tốt** → Service không bị lỗi
- **Error Budget OK** → Không lo về lỗi
- **Burn Rate bình thường** → Không có vấn đề lỗi
- **Latency tệ** → User experience kém, cần optimize

### Action Plan
1. **🔍 Identify slow endpoints** - Tìm endpoints chậm nhất
2. **📊 Analyze performance** - CPU, memory, database queries
3. **⚡ Optimize code** - Fix performance bottlenecks
4. **🔄 Deploy optimizations** - Deploy các cải tiến
5. **📈 Monitor improvement** - Theo dõi cải thiện

### Performance Analysis
1. **Top slow endpoints**:
   - `/api/users` - 2.5s average
   - `/api/products` - 1.8s average
   - `/api/orders` - 1.2s average

2. **System bottlenecks**:
   - Database queries chậm
   - Memory usage cao
   - GC pressure

3. **Optimization actions**:
   - Add database indexes
   - Optimize queries
   - Add caching
   - Tune GC settings

### Dashboard hiển thị
- **SLO Compliance**: 🟢 99.6% (tốt)
- **Error Budget**: 🟢 70% (OK)
- **Burn Rate**: 🟢 1.2x (bình thường)
- **Latency SLI**: 🟠 85% (cần cải thiện)

---

## Tổng kết các tình huống

### Decision Matrix

| Scenario | Availability | Error Budget | Burn Rate | Action |
|----------|-------------|--------------|-----------|---------|
| **Normal** | > 99.5% | > 50% | < 2x | Deploy freely |
| **Warning** | 99.0-99.5% | 20-50% | 2-4x | Pause deploys, investigate |
| **Critical** | < 99.0% | < 20% | > 4x | Stop all, rollback |
| **Latency** | > 99.5% | > 50% | < 2x | Optimize performance |

### Key Learnings

1. **Monitor multiple SLIs** - Không chỉ availability
2. **Set appropriate thresholds** - Cảnh báo sớm nhưng không spam
3. **Have clear action plans** - Biết phải làm gì khi có vấn đề
4. **Practice incident response** - Luyện tập xử lý sự cố
5. **Learn from incidents** - Rút kinh nghiệm sau mỗi lần

### Best Practices

1. **Proactive monitoring** - Phát hiện vấn đề trước khi nghiêm trọng
2. **Clear escalation** - Ai làm gì khi có alert
3. **Regular reviews** - Đánh giá SLO định kỳ
4. **Team training** - Huấn luyện team về SLO
5. **Continuous improvement** - Cải thiện liên tục

---

## Next Steps

- Đọc [SLO_CALCULATIONS_VI.md](./SLO_CALCULATIONS_VI.md) để hiểu cách tính toán chi tiết
- Đọc [SLO_ALERT_RESPONSE_VI.md](./SLO_ALERT_RESPONSE_VI.md) để biết cách xử lý alerts
- Thực hành với [SLO_QUICK_REFERENCE.md](./SLO_QUICK_REFERENCE.md) cheat sheet
