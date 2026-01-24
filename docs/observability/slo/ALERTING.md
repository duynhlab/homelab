# SLO Alerting Configuration

## Overview

SLO alerts use the **multi-window multi-burn-rate** methodology from Google SRE Workbook. This approach provides fast detection of critical issues while avoiding alert fatigue.

## Alert Methodology

### Multi-Window Multi-Burn-Rate

Alerts fire based on **burn rate** (how fast error budget is consumed) across **multiple time windows**:

- **1-hour window**: Fast detection (catches immediate issues)
- **6-hour window**: Medium-term detection (catches sustained issues)

### Burn Rate Thresholds

| Alert Type | 1h Window | 6h Window | Time to Exhaustion |
|------------|-----------|-----------|-------------------|
| **Page Alert** | 15x | 6x | ~2 days |
| **Ticket Alert** | 4x | 2x | ~7 days |

**Burn Rate Calculation**:
```
burn_rate = actual_error_rate / target_error_rate
```

Example:
- Target: 99.5% availability (0.5% error budget)
- Actual: 7.5% error rate
- Burn rate: 7.5% / 0.5% = 15x (Page alert fires!)

## Alert Types

### Page Alert (Critical)

**When**: Budget exhausted in ~2 days

**Conditions**:
- 15x burn rate (1h window) OR
- 6x burn rate (6h window)

**Action**: Immediate investigation required

**Example Alert**:
```
Alert: AuthHighErrorRate (Page)
Severity: page
Burn Rate: 15x
Time to Exhaustion: 2 days
```

### Ticket Alert (Warning)

**When**: Budget exhausted in ~7 days

**Conditions**:
- 4x burn rate (1h window) OR
- 2x burn rate (6h window)

**Action**: Investigate within 24 hours

**Example Alert**:
```
Alert: AuthHighErrorRate (Ticket)
Severity: ticket
Burn Rate: 4x
Time to Exhaustion: 7 days
```

## Alert Configuration

### Sloth-Generated Alerts

Sloth automatically generates alerts with proper thresholds:

```yaml
alerting:
  page_alert:
    labels:
      severity: page
      channel: "#alerts"
  ticket_alert:
    labels:
      severity: ticket
      channel: "#incidents"
```

### Alert Labels

All alerts include:
- `service`: Service name (e.g., "auth")
- `severity`: Alert severity (page, ticket)
- `category`: SLO category (availability, latency, error-rate)
- `slo`: SLO name (availability, latency, error-rate)

### Alert Annotations

Alerts include:
- `summary`: Brief description
- `description`: Detailed information
- `runbook_url`: Link to runbook

## Runbooks

### Availability Alert Runbook

**Triggered by**: `AuthHighErrorRate`

**Steps**:
1. Check error rate in Grafana
2. Identify top error endpoints
3. Check recent deployments
4. Review application logs
5. Check dependencies

**Runbook**: `./scripts/10-error-budget-alert.sh`

### Latency Alert Runbook

**Triggered by**: `AuthHighLatency`

**Steps**:
1. Check p95 latency in Grafana
2. Identify slow endpoints
3. Check Go GC activity
4. Review resource usage (CPU/memory)
5. Check concurrent requests

**Runbook**: Manual diagnosis via Grafana dashboards and Prometheus queries

## Escalation Procedures

### Page Alert Escalation

1. **Immediate** (0-15 min):
   - On-call engineer acknowledges
   - Initial investigation begins

2. **Short-term** (15-60 min):
   - Root cause identified
   - Mitigation plan created

3. **Medium-term** (1-4 hours):
   - Issue resolved
   - Post-mortem scheduled

### Ticket Alert Escalation

1. **Short-term** (0-24 hours):
   - Alert acknowledged
   - Investigation begins

2. **Medium-term** (24-72 hours):
   - Root cause identified
   - Fix implemented

3. **Long-term** (1 week):
   - Issue resolved
   - Documentation updated

## Alert Testing

### Generate Test Alerts

**High error rate**:
```bash
# Generate 5xx errors
for i in {1..1000}; do
  curl http://localhost:8080/api/error &
done
```

**High latency**:
```bash
# Generate slow requests
for i in {1..1000}; do
  curl http://localhost:8080/api/slow &
done
```

### Verify Alerts

1. Check Prometheus alerts:
   ```bash
   curl http://localhost:9090/api/v1/alerts
   ```

2. Check AlertManager:
   ```bash
   curl http://localhost:9093/api/v2/alerts
   ```

3. Verify alert firing:
   - Check Prometheus UI: http://localhost:9090/alerts
   - Look for alerts with `severity="page"` or `severity="ticket"`

## Alert Metrics

### Monitoring Alert Health

```promql
# Alert firing rate
rate(alertmanager_alerts_received_total[5m])

# Alert resolution time
histogram_quantile(0.95, alertmanager_notification_duration_seconds_bucket)
```

## Best Practices

1. **Avoid alert fatigue**: Use multi-window to reduce false positives
2. **Include runbooks**: Every alert should have a runbook
3. **Test alerts regularly**: Verify alerts fire correctly
4. **Review alert effectiveness**: Remove unused alerts
5. **Document escalation**: Clear escalation procedures

## References

- [Google SRE Workbook - Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Sloth Alerting Documentation](https://sloth.dev/docs/alerting)

