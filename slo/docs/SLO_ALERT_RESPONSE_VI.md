# SLO/SLI - Hướng dẫn xử lý cảnh báo

## Tổng quan

Tài liệu này hướng dẫn chi tiết cách xử lý các cảnh báo SLO, từ phân loại mức độ nghiêm trọng đến các bước phản ứng cụ thể.

---

## Phần 1: Phân loại mức độ nghiêm trọng

### SEV1 - Critical (Nghiêm trọng) 🔴

#### **Điều kiện kích hoạt**
- Burn rate ≥ 15x (budget hết trong 2 ngày)
- Time to exhaustion < 24 giờ
- Error budget < 10%
- Availability < 99.0%

#### **Ví dụ thực tế**
```
Availability: 98.5%
Error Budget: -20% (đã vượt)
Burn Rate: 15x
Time to Exhaustion: 2 giờ
```

#### **Action ngay lập tức (0-15 phút)**
1. **🚨 Page on-call engineer** - Gọi ngay người on-call
2. **🛑 Stop tất cả deployments** - Không deploy gì cả
3. **📞 Escalate to management** - Báo cáo cấp trên
4. **🔍 Check system status** - Kiểm tra tình trạng hệ thống

#### **Action ngắn hạn (15-60 phút)**
1. **🔄 Rollback to last stable version** - Về version ổn định
2. **⚡ Scale up resources** - Tăng tài nguyên nếu cần
3. **📢 Notify stakeholders** - Thông báo các bên liên quan
4. **🔍 Start root cause analysis** - Bắt đầu điều tra nguyên nhân

#### **Action dài hạn (1-24 giờ)**
1. **🔧 Fix underlying issue** - Sửa vấn đề gốc
2. **📊 Post-incident review** - Họp rút kinh nghiệm
3. **📝 Update runbooks** - Cập nhật tài liệu
4. **🔄 Implement preventive measures** - Thực hiện biện pháp phòng ngừa

### SEV2 - Warning (Cảnh báo) 🟡

#### **Điều kiện kích hoạt**
- Burn rate 4x-15x (budget hết trong 7 ngày)
- Error budget 10-30%
- Availability 99.0-99.5%
- Time to exhaustion 24-168 giờ

#### **Ví dụ thực tế**
```
Availability: 99.2%
Error Budget: 15%
Burn Rate: 4x
Time to Exhaustion: 7 ngày
```

#### **Action ngay lập tức (0-30 phút)**
1. **📊 Tăng cường monitoring** - Theo dõi chặt chẽ hơn
2. **🛑 Pause non-critical deployments** - Dừng deploy không quan trọng
3. **📞 Notify team** - Thông báo team
4. **🔍 Start investigation** - Bắt đầu điều tra

#### **Action ngắn hạn (30 phút-4 giờ)**
1. **🔍 Root cause analysis** - Điều tra nguyên nhân
2. **📈 Analyze error patterns** - Phân tích pattern lỗi
3. **⚡ Implement quick fixes** - Áp dụng fix nhanh
4. **📊 Monitor improvement** - Theo dõi cải thiện

#### **Action dài hạn (4-24 giờ)**
1. **🔧 Implement permanent fix** - Sửa vấn đề vĩnh viễn
2. **📝 Document findings** - Ghi lại kết quả điều tra
3. **🔄 Update monitoring** - Cải thiện monitoring
4. **📚 Share learnings** - Chia sẻ kinh nghiệm

### SEV3 - Info (Thông tin) 🟢

#### **Điều kiện kích hoạt**
- Burn rate 1x-4x (bình thường đến cao)
- Error budget 30-50%
- Availability > 99.5%
- Time to exhaustion > 168 giờ

#### **Ví dụ thực tế**
```
Availability: 99.6%
Error Budget: 40%
Burn Rate: 1.5x
Time to Exhaustion: 20 ngày
```

#### **Action ngay lập tức (0-60 phút)**
1. **📊 Monitor closely** - Theo dõi chặt chẽ
2. **📝 Log for review** - Ghi lại để xem xét
3. **🔍 Check trends** - Kiểm tra xu hướng
4. **📅 Schedule investigation** - Lên lịch điều tra

#### **Action ngắn hạn (1-8 giờ)**
1. **🔍 Investigate if trend continues** - Điều tra nếu xu hướng tiếp tục
2. **📊 Analyze patterns** - Phân tích patterns
3. **⚡ Apply preventive measures** - Áp dụng biện pháp phòng ngừa
4. **📈 Monitor improvement** - Theo dõi cải thiện

---

## Phần 2: Root Cause Analysis

### Bước 1: Thu thập thông tin

#### **System Status**
```bash
# Check pod status
kubectl get pods -n monitoring-demo

# Check recent deployments
kubectl rollout history deployment/demo-go-api -n monitoring-demo

# Check resource usage
kubectl top pods -n monitoring-demo
```

#### **Error Patterns**
```bash
# Check error rate by endpoint
curl "http://localhost:9090/api/v1/query?query=sum(rate(request_duration_seconds_count{code=~\"5..\"}[1h])) by (path)"

# Check error rate by time
curl "http://localhost:9090/api/v1/query?query=sum(rate(request_duration_seconds_count{code=~\"5..\"}[5m]))"

# Check specific error codes
curl "http://localhost:9090/api/v1/query?query=sum(rate(request_duration_seconds_count{code=~\"500\"}[1h]))"
```

#### **System Metrics**
```bash
# Check CPU usage
curl "http://localhost:9090/api/v1/query?query=avg(rate(process_cpu_seconds_total[5m]))"

# Check memory usage
curl "http://localhost:9090/api/v1/query?query=avg(go_memstats_alloc_bytes)"

# Check GC activity
curl "http://localhost:9090/api/v1/query?query=avg(rate(go_gc_duration_seconds_sum[5m]))"
```

### Bước 2: Phân tích nguyên nhân

#### **Recent Changes**
1. **Check deployment history** - Có deploy gì gần đây?
2. **Check configuration changes** - Có thay đổi config không?
3. **Check infrastructure changes** - Có thay đổi infrastructure không?
4. **Check external dependencies** - Dependencies có thay đổi không?

#### **Error Analysis**
1. **Error distribution** - Lỗi tập trung ở đâu?
2. **Error timing** - Lỗi xảy ra khi nào?
3. **Error correlation** - Lỗi có liên quan đến gì?
4. **Error trends** - Xu hướng lỗi như thế nào?

#### **System Analysis**
1. **Resource utilization** - CPU, memory, disk có bất thường?
2. **Network issues** - Có vấn đề network không?
3. **Database issues** - Database có vấn đề không?
4. **External services** - External services có vấn đề không?

### Bước 3: Xác định nguyên nhân gốc

#### **Common Root Causes**

1. **Code Issues**
   - Bug trong code mới
   - Memory leak
   - Infinite loop
   - Race condition

2. **Configuration Issues**
   - Wrong configuration
   - Missing environment variables
   - Incorrect resource limits

3. **Infrastructure Issues**
   - Node failure
   - Network partition
   - Storage issues
   - Resource exhaustion

4. **External Dependencies**
   - Database down
   - External API down
   - DNS issues
   - Certificate expiration

5. **Load Issues**
   - Traffic spike
   - DDoS attack
   - Resource exhaustion
   - Cascading failure

---

## Phần 3: Response Playbooks

### Playbook 1: High Error Rate

#### **Symptoms**
- Availability < 99.5%
- Error rate > 0.5%
- Burn rate > 2x

#### **Immediate Actions**
1. **Check recent deployments** - Có phải do deploy mới?
2. **Check error patterns** - Endpoint nào lỗi nhiều?
3. **Check system metrics** - CPU, memory có bất thường?
4. **Check logs** - Có error messages gì?

#### **Investigation Steps**
1. **Identify affected endpoints** - Endpoint nào bị ảnh hưởng?
2. **Check error codes** - Lỗi 500, 502, 503, 504?
3. **Check timing** - Lỗi xảy ra khi nào?
4. **Check correlation** - Có liên quan đến gì?

#### **Resolution Steps**
1. **Rollback if needed** - Rollback nếu cần
2. **Fix code issues** - Sửa lỗi code
3. **Scale resources** - Tăng tài nguyên
4. **Monitor improvement** - Theo dõi cải thiện

### Playbook 2: High Latency

#### **Symptoms**
- Latency SLI < 95%
- Response time > 500ms
- Availability OK

#### **Immediate Actions**
1. **Check slow endpoints** - Endpoint nào chậm?
2. **Check database queries** - Query có chậm không?
3. **Check external calls** - External API có chậm không?
4. **Check resource usage** - CPU, memory có cao không?

#### **Investigation Steps**
1. **Profile slow endpoints** - Profile endpoint chậm
2. **Check database performance** - Kiểm tra DB performance
3. **Check external dependencies** - Kiểm tra external services
4. **Check code performance** - Kiểm tra code performance

#### **Resolution Steps**
1. **Optimize slow queries** - Optimize queries chậm
2. **Add caching** - Thêm caching
3. **Optimize code** - Optimize code
4. **Scale resources** - Tăng tài nguyên

### Playbook 3: Resource Exhaustion

#### **Symptoms**
- High CPU usage
- High memory usage
- Pod restarts
- OOMKilled

#### **Immediate Actions**
1. **Check resource usage** - Kiểm tra resource usage
2. **Check pod status** - Kiểm tra pod status
3. **Check logs** - Kiểm tra logs
4. **Scale up resources** - Tăng tài nguyên

#### **Investigation Steps**
1. **Check memory leaks** - Kiểm tra memory leaks
2. **Check CPU-intensive operations** - Kiểm tra operations tốn CPU
3. **Check resource limits** - Kiểm tra resource limits
4. **Check garbage collection** - Kiểm tra GC

#### **Resolution Steps**
1. **Fix memory leaks** - Sửa memory leaks
2. **Optimize CPU usage** - Optimize CPU usage
3. **Adjust resource limits** - Điều chỉnh resource limits
4. **Tune garbage collection** - Tune GC

---

## Phần 4: Communication

### Internal Communication

#### **SEV1 - Critical**
1. **Immediate notification** - Thông báo ngay lập tức
2. **Management escalation** - Báo cáo cấp trên
3. **Team notification** - Thông báo team
4. **Status updates** - Cập nhật tình trạng

#### **SEV2 - Warning**
1. **Team notification** - Thông báo team
2. **Regular updates** - Cập nhật định kỳ
3. **Progress reports** - Báo cáo tiến độ
4. **Resolution updates** - Cập nhật giải pháp

#### **SEV3 - Info**
1. **Log for review** - Ghi lại để xem xét
2. **Weekly review** - Xem xét hàng tuần
3. **Trend analysis** - Phân tích xu hướng
4. **Preventive measures** - Biện pháp phòng ngừa

### External Communication

#### **Customer Notification**
1. **Status page updates** - Cập nhật status page
2. **Email notifications** - Thông báo qua email
3. **Social media updates** - Cập nhật social media
4. **Direct communication** - Giao tiếp trực tiếp

#### **Stakeholder Updates**
1. **Management reports** - Báo cáo cấp trên
2. **Board updates** - Cập nhật hội đồng
3. **Investor communications** - Giao tiếp nhà đầu tư
4. **Media relations** - Quan hệ truyền thông

---

## Phần 5: Post-Incident Review

### Immediate Post-Incident (0-24 giờ)

#### **Documentation**
1. **Incident timeline** - Timeline sự cố
2. **Actions taken** - Các hành động đã thực hiện
3. **Root cause** - Nguyên nhân gốc
4. **Resolution** - Giải pháp

#### **Communication**
1. **Internal debrief** - Họp nội bộ
2. **External communication** - Giao tiếp bên ngoài
3. **Status updates** - Cập nhật tình trạng
4. **Follow-up actions** - Hành động tiếp theo

### Short-term Post-Incident (1-7 ngày)

#### **Analysis**
1. **Root cause analysis** - Phân tích nguyên nhân gốc
2. **Impact assessment** - Đánh giá tác động
3. **Timeline analysis** - Phân tích timeline
4. **Response analysis** - Phân tích phản ứng

#### **Improvements**
1. **Process improvements** - Cải thiện quy trình
2. **Tool improvements** - Cải thiện công cụ
3. **Training improvements** - Cải thiện đào tạo
4. **Monitoring improvements** - Cải thiện monitoring

### Long-term Post-Incident (1-4 tuần)

#### **Prevention**
1. **Preventive measures** - Biện pháp phòng ngừa
2. **Process changes** - Thay đổi quy trình
3. **Tool enhancements** - Nâng cấp công cụ
4. **Training programs** - Chương trình đào tạo

#### **Documentation**
1. **Runbook updates** - Cập nhật runbook
2. **Process documentation** - Tài liệu quy trình
3. **Training materials** - Tài liệu đào tạo
4. **Best practices** - Thực hành tốt nhất

---

## Tóm tắt

### Key Principles

1. **Respond quickly** - Phản ứng nhanh chóng
2. **Communicate clearly** - Giao tiếp rõ ràng
3. **Document everything** - Ghi lại mọi thứ
4. **Learn from incidents** - Học hỏi từ sự cố
5. **Improve continuously** - Cải thiện liên tục

### Best Practices

1. **Have clear escalation paths** - Có đường dẫn escalation rõ ràng
2. **Practice incident response** - Luyện tập phản ứng sự cố
3. **Keep runbooks updated** - Giữ runbook cập nhật
4. **Train team regularly** - Đào tạo team định kỳ
5. **Review and improve** - Xem xét và cải thiện

---

## Next Steps

- Thực hành với [SLO_EXAMPLES_VI.md](./SLO_EXAMPLES_VI.md) scenarios
- Đọc [SLO_CALCULATIONS_VI.md](./SLO_CALCULATIONS_VI.md) để hiểu cách tính toán
- Sử dụng [SLO_QUICK_REFERENCE.md](./SLO_QUICK_REFERENCE.md) làm cheat sheet
