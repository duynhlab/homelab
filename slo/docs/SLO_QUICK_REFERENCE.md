# SLO/SLI - Quick Reference

## 🚀 Cheat Sheet - Tóm tắt nhanh

### Khái niệm cơ bản

| Khái niệm | Định nghĩa | Ví dụ |
|-----------|------------|-------|
| **SLI** | Chỉ số đo lường | 99.5% requests thành công |
| **SLO** | Mục tiêu | Phải đạt 99.5% availability |
| **SLA** | Cam kết khách hàng | Nếu < 99.5% thì bồi thường |
| **Error Budget** | Ngân sách lỗi | 0.5% = 3.6h downtime/tháng |
| **Burn Rate** | Tốc độ tiêu budget | 2x = hết trong 15 ngày |

---

## 📊 Công thức quan trọng

### Error Budget
```
Error Budget = 1 - SLO Target
Ví dụ: 99.5% SLO = 0.5% Error Budget
```

### Burn Rate
```
Burn Rate = Current Error Rate / Target Error Rate
Ví dụ: 1% / 0.5% = 2x Burn Rate
```

### Time to Exhaustion
```
Time to Exhaustion = Error Budget Hours / Burn Rate
Ví dụ: 3.6h / 2x = 1.8h
```

### Availability SLI
```
Availability = 1 - (Error Requests / Total Requests)
Ví dụ: 1 - (2,000 / 1,000,000) = 99.8%
```

---

## 🎯 Thresholds thường gặp

### Error Budget Levels
| Level | Budget Remaining | Action |
|-------|------------------|---------|
| 🟢 **Normal** | > 50% | Deploy freely |
| 🟡 **Caution** | 20-50% | Deploy with approval |
| 🟠 **Warning** | 10-20% | Pause non-critical deploys |
| 🔴 **Critical** | < 10% | Stop all deploys |

### Burn Rate Levels
| Level | Burn Rate | Time to Exhaustion | Action |
|-------|-----------|-------------------|---------|
| 🟢 **Normal** | < 2x | > 15 days | Monitor |
| 🟡 **Warning** | 2-4x | 7-15 days | Investigate |
| 🟠 **High** | 4-15x | 1-7 days | Pause deploys |
| 🔴 **Critical** | > 15x | < 1 day | Emergency response |

### Availability Levels
| Level | Availability | Status |
|-------|-------------|---------|
| 🟢 **Excellent** | > 99.5% | Above target |
| 🟡 **Good** | 99.0-99.5% | At target |
| 🟠 **Poor** | 95.0-99.0% | Below target |
| 🔴 **Critical** | < 95.0% | Far below target |

---

## 🚨 Alert Response Matrix

### SEV1 - Critical 🔴
**Triggers:**
- Burn rate ≥ 15x
- Time to exhaustion < 24h
- Error budget < 10%
- Availability < 99.0%

**Actions:**
1. Page on-call engineer
2. Stop all deployments
3. Rollback immediately
4. Escalate to management

### SEV2 - Warning 🟡
**Triggers:**
- Burn rate 4x-15x
- Error budget 10-30%
- Availability 99.0-99.5%

**Actions:**
1. Pause non-critical deploys
2. Investigate root cause
3. Notify team
4. Monitor closely

### SEV3 - Info 🟢
**Triggers:**
- Burn rate 1x-4x
- Error budget 30-50%
- Availability > 99.5%

**Actions:**
1. Monitor trends
2. Log for review
3. Schedule investigation
4. Apply preventive measures

---

## 🔧 Troubleshooting Flowchart

```
Alert Received
     ↓
Check Severity Level
     ↓
┌─────────────────┬─────────────────┬─────────────────┐
│   SEV1 (Critical) │   SEV2 (Warning) │   SEV3 (Info)    │
│                 │                 │                 │
│ 1. Page on-call │ 1. Notify team  │ 1. Log for review│
│ 2. Stop deploys │ 2. Investigate  │ 2. Monitor trends│
│ 3. Rollback     │ 3. Pause deploys│ 3. Schedule check│
│ 4. Escalate     │ 4. Monitor      │ 4. Apply prevent │
└─────────────────┴─────────────────┴─────────────────┘
     ↓
Root Cause Analysis
     ↓
┌─────────────────┬─────────────────┬─────────────────┐
│   Recent Deploy │   System Issues │   External Deps │
│                 │                 │                 │
│ 1. Check history│ 1. Check metrics│ 1. Check APIs   │
│ 2. Rollback if  │ 2. Check logs   │ 2. Check DB     │
│    needed       │ 3. Scale up     │ 3. Check network│
│ 3. Fix code     │ 4. Tune config  │ 4. Check DNS    │
└─────────────────┴─────────────────┴─────────────────┘
     ↓
Implement Fix
     ↓
Monitor Improvement
     ↓
Document & Learn
```

---

## 📈 PromQL Queries

### Basic SLI Queries
```promql
# Availability SLI
1 - (
  sum(rate(request_duration_seconds_count{code=~"5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count[30d]))
)

# Latency SLI
sum(rate(request_duration_seconds_bucket{le="0.5"}[30d]))
/
sum(rate(request_duration_seconds_count[30d]))

# Error Rate SLI
1 - (
  sum(rate(request_duration_seconds_count{code=~"4..|5.."}[30d]))
  /
  sum(rate(request_duration_seconds_count[30d]))
)
```

### Burn Rate Queries
```promql
# 1-hour Burn Rate
(
  sum(rate(request_duration_seconds_count{code=~"5.."}[1h]))
  /
  sum(rate(request_duration_seconds_count[1h]))
)
/
0.005  # Target error rate

# 6-hour Burn Rate
(
  sum(rate(request_duration_seconds_count{code=~"5.."}[6h]))
  /
  sum(rate(request_duration_seconds_count[6h]))
)
/
0.005

# 3-day Burn Rate
(
  sum(rate(request_duration_seconds_count{code=~"5.."}[3d]))
  /
  sum(rate(request_duration_seconds_count[3d]))
)
/
0.005
```

### Error Budget Queries
```promql
# Error Budget Remaining (30-day)
1 - (
  (
    sum(rate(request_duration_seconds_count{code=~"5.."}[30d]))
    /
    sum(rate(request_duration_seconds_count[30d]))
  )
  /
  0.005  # Target error rate
)

# Error Budget Remaining (7-day)
1 - (
  (
    sum(rate(request_duration_seconds_count{code=~"5.."}[7d]))
    /
    sum(rate(request_duration_seconds_count[7d]))
  )
  /
  0.01  # Target error rate
)
```

---

## 🛠️ Common Commands

### Kubernetes Commands
```bash
# Check pod status
kubectl get pods -n monitoring-demo

# Check recent deployments
kubectl rollout history deployment/demo-go-api -n monitoring-demo

# Check resource usage
kubectl top pods -n monitoring-demo

# Check logs
kubectl logs -f deployment/demo-go-api -n monitoring-demo
```

### Prometheus Queries
```bash
# Check availability
curl "http://localhost:9090/api/v1/query?query=slo:availability:success_rate_7d"

# Check error budget
curl "http://localhost:9090/api/v1/query?query=slo:availability:error_budget_remaining_7d"

# Check burn rate
curl "http://localhost:9090/api/v1/query?query=slo:availability:burn_rate_1h"

# Check time to exhaustion
curl "http://localhost:9090/api/v1/query?query=slo:availability:time_to_exhaustion_hours"
```

### Grafana Access
```bash
# Port forward Grafana
kubectl port-forward -n monitoring-demo svc/grafana 3000:3000

# Access URLs
# Main Dashboard: http://localhost:3000/d/go-monitoring-demo/
# SLO Dashboard: http://localhost:3000/d/slo-dashboard/
```

---

## 📚 Quick Links

### Documentation
- [SLO_CONCEPTS_VI.md](./SLO_CONCEPTS_VI.md) - Khái niệm cơ bản
- [SLO_EXAMPLES_VI.md](./SLO_EXAMPLES_VI.md) - Tình huống thực tế
- [SLO_CALCULATIONS_VI.md](./SLO_CALCULATIONS_VI.md) - Công thức tính toán
- [SLO_ALERT_RESPONSE_VI.md](./SLO_ALERT_RESPONSE_VI.md) - Xử lý cảnh báo
- [SLO_IMPLEMENTATION.md](./SLO_IMPLEMENTATION.md) - Hướng dẫn triển khai

### External Resources
- [Google SRE Book - SLOs](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook - Implementing SLOs](https://sre.google/workbook/implementing-slos/)
- [The Art of SLOs](https://cloud.google.com/blog/products/devops-sre/sre-fundamentals-sli-vs-slo-vs-sla)

---

## 🎯 Best Practices

### Setting SLOs
1. **Start with historical data** - Bắt đầu với data lịch sử
2. **Set achievable but challenging targets** - Mục tiêu thực tế nhưng thử thách
3. **Review and adjust quarterly** - Xem xét và điều chỉnh hàng quý
4. **Consider business impact** - Xem xét tác động kinh doanh

### Monitoring
1. **Use multiple time windows** - Sử dụng nhiều cửa sổ thời gian
2. **Set appropriate thresholds** - Đặt ngưỡng phù hợp
3. **Avoid alert fatigue** - Tránh mệt mỏi vì alert
4. **Test alerts regularly** - Kiểm tra alert định kỳ

### Incident Response
1. **Have clear escalation paths** - Có đường dẫn escalation rõ ràng
2. **Practice incident response** - Luyện tập phản ứng sự cố
3. **Document everything** - Ghi lại mọi thứ
4. **Learn from incidents** - Học hỏi từ sự cố

### Team Management
1. **Train team regularly** - Đào tạo team định kỳ
2. **Keep runbooks updated** - Giữ runbook cập nhật
3. **Share learnings** - Chia sẻ kinh nghiệm
4. **Celebrate improvements** - Ăn mừng cải thiện

---

## 📞 Emergency Contacts

### On-Call Rotation
- **Primary**: [On-call engineer]
- **Secondary**: [Backup engineer]
- **Manager**: [Team manager]
- **Escalation**: [Management]

### Communication Channels
- **Slack**: #incidents
- **Email**: incidents@company.com
- **Phone**: [Emergency number]
- **Status Page**: [Status page URL]

---

*Last updated: [Current Date]*
*Version: 1.0*
