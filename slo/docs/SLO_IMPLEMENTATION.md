# SLO Implementation Guide

## Overview

This document describes the Service Level Objectives (SLO) implementation for the Go REST API monitoring project. The SLO system provides error budget tracking, burn rate monitoring, and automated alerting based on Google SRE methodology.

## Prerequisites

Before implementing SLOs, it's important to understand the core concepts:

- **[SLO_CONCEPTS_VI.md](./SLO_CONCEPTS_VI.md)** - Khái niệm cơ bản về SLI/SLO/Error Budget (tiếng Việt)
- **[SLO_EXAMPLES_VI.md](./SLO_EXAMPLES_VI.md)** - Các tình huống thực tế và cách phản ứng
- **[SLO_CALCULATIONS_VI.md](./SLO_CALCULATIONS_VI.md)** - Công thức tính toán chi tiết
- **[SLO_ALERT_RESPONSE_VI.md](./SLO_ALERT_RESPONSE_VI.md)** - Hướng dẫn xử lý cảnh báo
- **[SLO_QUICK_REFERENCE.md](./SLO_QUICK_REFERENCE.md)** - Cheat sheet nhanh

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Go API        │    │   Prometheus     │    │   Grafana       │
│   (Metrics)     │───▶│   (SLO Rules)    │───▶│   (SLO Dashboard)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   AlertManager   │
                       │   (SLO Alerts)   │
                       └──────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   Runbooks       │
                       │   (Auto Response)│
                       └──────────────────┘
```

## SLI Definitions

### 1. Availability SLI
- **Definition**: Ratio of successful requests (non-5xx) to total requests
- **Target**: 99.5% (30-day), 99.0% (7-day)
- **Query**: `1 - (sum(rate(request_duration_seconds_count{code=~"5.."}[30d])) / sum(rate(request_duration_seconds_count[30d])))`

### 2. Latency SLI
- **Definition**: Ratio of requests faster than 500ms to total requests
- **Target**: 95% (30-day), 90% (7-day)
- **Query**: `sum(rate(request_duration_seconds_bucket{le="0.5"}[30d])) / sum(rate(request_duration_seconds_count[30d]))`

### 3. Error Rate SLI
- **Definition**: Ratio of successful requests (non-4xx/5xx) to total requests
- **Target**: 99% (30-day), 98% (7-day)
- **Query**: `1 - (sum(rate(request_duration_seconds_count{code=~"4..|5.."}[30d])) / sum(rate(request_duration_seconds_count[30d])))`

## Error Budget Policy

### Budget Calculation
- **30-day Budget**: 0.5% of total requests (99.5% target)
- **7-day Budget**: 1.0% of total requests (99.0% target)
- **Budget Remaining**: `1 - (actual_errors / budget_errors)`

### Burn Rate Thresholds
- **Critical (15x)**: Budget exhausted in 2 days
- **Warning (4x)**: Budget exhausted in 7 days
- **Info (1x)**: Normal consumption rate

### Deployment Policy
- **Budget > 50%**: Normal deployments allowed
- **Budget 20-50%**: Deployments require approval
- **Budget < 20%**: Deployments paused
- **Budget < 10%**: Emergency response mode

## SLO Dashboard

### Overview Panels
1. **SLO Compliance Status**: Current availability percentage
2. **Error Budget Remaining**: 30d and 7d budget status
3. **Error Budget Burn Rate**: Multi-window burn rate tracking
4. **Time to Exhaustion**: Hours until budget depletion

### SLI Details Panels
5. **SLI Trends (30-day)**: Availability, latency, error rate trends
6. **SLI Trends (7-day)**: Short-term SLI performance

### Access
- **URL**: `http://localhost:3000/d/slo-dashboard/`
- **Port-forward**: `kubectl port-forward -n monitoring-demo svc/grafana 3000:3000`

## Alerting Rules

### Critical Alerts
- **SLOAvailabilityCritical**: 15x burn rate (2-day exhaustion)
- **SLOAvailabilityTimeToExhaustion**: < 24 hours remaining
- **SLOCompositeCritical**: Multiple SLOs failing

### Warning Alerts
- **SLOAvailabilityWarning**: 4x burn rate (7-day exhaustion)
- **SLOLatencyWarning**: Latency budget < 30%
- **SLOErrorRateWarning**: Error rate budget < 30%

### Info Alerts
- **SLOAvailabilityBudgetLow**: Budget < 20%

## Automated Runbooks

### 1. Latency Diagnosis (`diagnose-latency.sh`)
**Triggered by**: SLOLatencyCritical alert

**Actions**:
- Query top 10 slowest endpoints
- Check Go GC activity and frequency
- Analyze resource throttling (CPU/memory)
- Check concurrent request patterns
- Generate recommendations

**Usage**:
```bash
./slo/runbooks/diagnose-latency.sh
```

### 2. Error Budget Alert (`error-budget-alert.sh`)
**Triggered by**: SLOAvailabilityBudgetLow, SLOAvailabilityTimeToExhaustion

**Actions**:
- Calculate time to exhaustion
- List top error-generating endpoints
- Check recent deployments for correlation
- Analyze error patterns (4xx vs 5xx)
- Generate action plan based on budget level

**Usage**:
```bash
./slo/runbooks/error-budget-alert.sh
```

## Deployment

### One-Command Deployment
```bash
./slo/scripts/deploy-slo.sh
```

This script:
1. Deploys SLO recording rules
2. Deploys SLO alerts
3. Updates Prometheus configuration
4. Deploys SLO dashboard
5. Restarts services
6. Verifies deployment

### Manual Deployment
```bash
# 1. Deploy SLO rules
kubectl apply -f slo/k8s/error-budget-rules.yaml

# 2. Deploy SLO alerts
kubectl apply -f slo/k8s/slo-alerts.yaml

# 3. Update Prometheus
kubectl apply -f k8s/prometheus/configmap.yaml
kubectl apply -f k8s/prometheus/deployment.yaml

# 4. Deploy SLO dashboard
kubectl create configmap slo-dashboard-json \
  --from-file=slo-dashboard.json=slo/dashboards/slo-dashboard.json \
  -n monitoring-demo --dry-run=client -o yaml | kubectl apply -f -

# 5. Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring-demo
```

## Key Metrics

### SLO Metrics
- `slo:availability:success_rate_30d` - 30-day availability
- `slo:availability:error_budget_remaining_30d` - Budget remaining (0-1)
- `slo:availability:burn_rate_1h` - 1-hour burn rate
- `slo:availability:time_to_exhaustion_hours` - Hours to exhaustion

### Burn Rate Metrics
- `slo:availability:burn_rate_1h` - 1-hour window
- `slo:availability:burn_rate_6h` - 6-hour window
- `slo:availability:burn_rate_3d` - 3-day window

## Troubleshooting

### Common Issues

#### 1. SLO Metrics Not Appearing
**Symptoms**: No `slo:*` metrics in Prometheus
**Solution**:
```bash
# Check if rules are loaded
kubectl get configmap prometheus-slo-rules -n monitoring-demo

# Check Prometheus logs
kubectl logs deployment/prometheus -n monitoring-demo

# Reload Prometheus configuration
curl -X POST http://localhost:9090/-/reload
```

#### 2. Dashboard Shows No Data
**Symptoms**: SLO dashboard panels show "No data"
**Solution**:
```bash
# Check if metrics exist
curl "http://localhost:9090/api/v1/query?query=slo:availability:success_rate_30d"

# Verify time range (SLOs need 30 days of data)
# Use shorter time range for testing: 7d instead of 30d
```

#### 3. Alerts Not Firing
**Symptoms**: No SLO alerts in AlertManager
**Solution**:
```bash
# Check alert rules
kubectl get configmap prometheus-slo-alerts -n monitoring-demo

# Check AlertManager configuration
kubectl logs deployment/alertmanager -n monitoring-demo
```

### Testing SLOs

#### Generate Test Load
```bash
# High error rate (5xx errors)
for i in {1..1000}; do curl http://localhost:8080/api/error & done

# High latency
for i in {1..1000}; do curl http://localhost:8080/api/slow & done
```

#### Verify SLO Response
```bash
# Check burn rate
curl "http://localhost:9090/api/v1/query?query=slo:availability:burn_rate_1h"

# Check error budget
curl "http://localhost:9090/api/v1/query?query=slo:availability:error_budget_remaining_30d"
```

## Best Practices

### 1. SLO Target Setting
- Start with historical data analysis
- Set achievable but challenging targets
- Review and adjust quarterly
- Consider business impact

### 2. Error Budget Management
- Use budget for feature velocity
- Track budget consumption by team
- Implement budget-based deployment gates
- Regular budget reviews

### 3. Alerting Strategy
- Use multi-window burn rate alerts
- Avoid alert fatigue with proper thresholds
- Include runbook links in alerts
- Test alerting regularly

### 4. Runbook Maintenance
- Keep runbooks up-to-date
- Test runbooks regularly
- Include escalation procedures
- Document lessons learned

## Integration with CI/CD

### Deployment Gates
```yaml
# Example GitHub Actions workflow
- name: Check Error Budget
  run: |
    BUDGET=$(curl -s "http://prometheus:9090/api/v1/query?query=slo:availability:error_budget_remaining_30d" | jq -r '.data.result[0].value[1]')
    if (( $(echo "$BUDGET < 0.2" | bc -l) )); then
      echo "Error budget too low, blocking deployment"
      exit 1
    fi
```

### Budget-Based Feature Flags
```go
// Example Go code
func canDeployFeature() bool {
    budget := getErrorBudget()
    return budget > 0.3 // Only deploy if budget > 30%
}
```

## Monitoring and Maintenance

### Daily Checks
- Review SLO compliance status
- Check error budget consumption
- Monitor burn rate trends

### Weekly Reviews
- Analyze SLO performance
- Review alert effectiveness
- Update runbooks if needed

### Monthly Reviews
- Evaluate SLO targets
- Adjust error budget policies
- Plan capacity improvements

## FAQ

### Q: Tại sao cần SLO?
A: SLO giúp team:
- Định hướng phát triển (tốc độ vs chất lượng)
- Quyết định deploy (có nên deploy feature mới không?)
- Đo lường rủi ro (feature này có làm tăng lỗi không?)
- Cân bằng tốc độ và chất lượng

### Q: SLO khác SLA như thế nào?
A: 
- **SLO**: Mục tiêu nội bộ (team tự đặt)
- **SLA**: Cam kết với khách hàng (có hậu quả pháp lý)
- SLO thường cao hơn SLA để có buffer

### Q: Làm sao chọn SLO target phù hợp?
A: Dựa trên:
- Data lịch sử (availability hiện tại là bao nhiêu?)
- Khả năng team (có thể đạt được không?)
- Nhu cầu business (khách hàng cần gì?)
- Cost vs benefit (chi phí để đạt SLO)

### Q: Error Budget âm có sao không?
A: Có vấn đề! Error Budget âm có nghĩa là:
- Đã vượt quá giới hạn cho phép
- Cần action ngay lập tức
- Có thể cần rollback
- Cần điều tra nguyên nhân

### Q: Burn Rate cao có nghĩa là gì?
A: Burn Rate cao có nghĩa là:
- Error budget đang bị "đốt" nhanh
- Cần action trước khi hết budget
- Có thể có vấn đề nghiêm trọng
- Cần điều tra ngay

### Q: Làm sao biết SLO có phù hợp không?
A: Đánh giá dựa trên:
- Team có đạt được SLO không? (quá dễ hay quá khó?)
- SLO có thúc đẩy cải thiện không?
- SLO có phù hợp với business không?
- Cần điều chỉnh SLO định kỳ

### Q: Có nên thay đổi SLO thường xuyên không?
A: Không! SLO nên:
- Ổn định trong ít nhất 1 quý
- Thay đổi dựa trên data và business needs
- Được team đồng thuận
- Được document rõ ràng

## References

- [Google SRE Book - SLIs, SLOs, and SLAs](https://sre.google/sre-book/service-level-objectives/)
- [Prometheus SLO Examples](https://prometheus.io/docs/practices/alerting/)
- [Grafana SLO Dashboard](https://grafana.com/grafana/dashboards/14631)
- [sloth - Prometheus SLO Generator](https://sloth.dev/)

## Support

For questions or issues with the SLO implementation:
1. Check this documentation
2. Review Prometheus and Grafana logs
3. Test with the provided runbooks
4. Consult the troubleshooting section
5. Read Vietnamese documentation for detailed explanations
