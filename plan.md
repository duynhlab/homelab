# SRE Practices Implementation Plan

## Overview

Implement comprehensive SRE practices: SLI/SLO definitions, error budgets (30-day + weekly), and toil reduction automation for the Go REST API monitoring project.

## Architecture Approach

**Tools:**

- Primary: `sloth` (Prometheus SLO generator) - generates recording rules automatically
- Integration: VictoriaMetrics (for advanced querying/alerting if needed)
- Deployment: Kubernetes manifests in `k8s/sre/`
- Dashboards: New dedicated SRE dashboard + overview panels in main dashboard

**Key Decision:** Use sloth as the core because it:

- Auto-generates Prometheus recording rules from simple SLO specs
- Creates multi-window, multi-burn-rate alerts (Google SRE Workbook methodology)
- Outputs standardized metrics for error budget tracking
- Is Kubernetes-native (can run as CronJob or one-time job)

## Implementation Steps

### 1. Define SLIs (Service Level Indicators)

Create `k8s/sre/slo-definitions.yaml` with basic SLIs:

**Availability SLI:**

- Definition: Ratio of successful requests (non-5xx) to total requests
- Target: 99.5% (30d), 99.0% (7d)
- Query: `sum(rate(request_duration_seconds_count{code!~"5.."})) / sum(rate(request_duration_seconds_count))`

**Latency SLI:**

- Definition: Ratio of requests faster than 500ms to total requests
- Target: 95% (30d), 90% (7d)
- Query: `histogram_quantile(0.95, rate(request_duration_seconds_bucket)) < 0.5`

**Error Rate SLI:**

- Definition: Ratio of non-error responses (non-4xx, non-5xx) to total
- Target: 99% (30d), 98% (7d)
- Query: `sum(rate(request_duration_seconds_count{code!~"4..|5.."})) / sum(rate(request_duration_seconds_count))`

### 2. Install sloth

Create `k8s/sre/sloth-job.yaml`:

- Run sloth as Kubernetes Job to generate recording rules
- Mount SLO definitions ConfigMap
- Output to Prometheus recording rules ConfigMap
- Can be re-run whenever SLO specs change

File structure:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sloth-generate-slo
spec:
  template:
    spec:
      containers:
      - name: sloth
        image: ghcr.io/slok/sloth:latest
        command: ["sloth", "generate", "-i", "/config/slo-definitions.yaml", "-o", "/output/slo-rules.yaml"]
```

### 3. Create SLO Recording Rules

sloth will auto-generate these, but the pattern will be:

- `slo:service_requests_availability:ratio_rate_30d` - 30-day rolling availability
- `slo:service_requests_availability:ratio_rate_7d` - 7-day rolling availability
- `slo:service_requests_availability:error_budget_remaining` - % budget left
- Multi-window burn rate alerts (1h, 6h, 3d windows)

Update `k8s/prometheus/configmap.yaml` to include:

```yaml
rule_files:
  - "/etc/prometheus/slo-rules.yaml"
```

### 4. Implement Error Budget Tracking

Create `k8s/sre/error-budget-rules.yaml` with custom recording rules:

**30-day Error Budget:**

```promql
# Budget consumed (0-1 scale, 1 = 100% consumed)
1 - (slo:service_requests_availability:ratio_rate_30d / 0.995)

# Budget remaining in hours
(1 - slo:service_requests_availability:ratio_rate_30d) * 720 * (1 - 0.995)
```

**Weekly Error Budget:**

```promql
1 - (slo:service_requests_availability:ratio_rate_7d / 0.99)
```

**Burn Rate Alerts:**

- Critical: Burning through 30d budget in 2 days (15x burn rate)
- Warning: Burning through 30d budget in 7 days (4x burn rate)
- Info: Burning through 30d budget in 30 days (1x burn rate)

### 5. Create SRE Dashboard

Create `sre-dashboard.json` with panels:

**Overview Section:**

1. Current SLO Compliance (Gauge) - Are we meeting 99.5%?
2. Error Budget Remaining (Bar chart) - 30d and 7d side-by-side
3. Error Budget Burn Rate (Time series) - How fast are we consuming budget?
4. Time to Exhaustion (Stat) - "X days until budget exhausted at current rate"

**SLI Details Section:**

5. Availability SLI Trend (30d rolling)
6. Latency SLI Trend (P95 < 500ms compliance)
7. Error Rate SLI Trend
8. SLI Breakdown by Endpoint (Table)

**Incident Impact Section:**

9. Recent SLO Violations (Table with timestamps)
10. Budget Consumption by Time of Day (Heatmap)
11. Budget Consumption by Endpoint (Identify expensive endpoints)

**Deployment:** `k8s/grafana/configmap-sre-dashboard.yaml`

### 6. Add SLO Overview to Main Dashboard

Edit `grafana-dashboard.json` to add 2 new panels at top:

**Panel 26: SLO Compliance Status**

- Type: Stat panel
- Shows: "99.52% (Target: 99.5%)" with green/yellow/red thresholds
- Query: `slo:service_requests_availability:ratio_rate_30d * 100`

**Panel 27: Error Budget Remaining**

- Type: Gauge
- Shows: Percentage of 30-day budget remaining
- Thresholds: Green (>50%), Yellow (20-50%), Red (<20%)
- Query: `(1 - (1 - slo:service_requests_availability:ratio_rate_30d) / (1 - 0.995)) * 100`

### 7. Toil Reduction - Automated Alert Response

Create `k8s/sre/runbooks/` directory with automated runbooks:

**Runbook 1: High Latency Auto-Diagnosis**

- Script: `runbooks/diagnose-latency.sh`
- Triggered by: Latency SLO violation alert
- Actions:
    - Query top 10 slowest endpoints
    - Check Go GC activity (is GC causing pauses?)
    - Check pod resource limits (is throttling happening?)
    - Post findings to Slack/webhook

**Runbook 2: Error Budget Alert**

- Script: `runbooks/error-budget-alert.sh`
- Triggered by: Error budget < 20%
- Actions:
    - Calculate estimated time to exhaustion
    - List top error-generating endpoints
    - Check recent deployments (correlation with errors?)
    - Send summary report

Deploy as Kubernetes Jobs triggered by AlertManager webhooks.

### 8. Toil Reduction - Automated Dashboard Updates

Create `scripts/update-dashboard.sh`:

- Automates dashboard ConfigMap updates
- No manual kubectl commands needed
- Script does:

    1. Validate JSON syntax
    2. Create ConfigMap from JSON
    3. Restart Grafana automatically
    4. Wait for readiness
    5. Print access URL

### 9. Toil Reduction - Automated Incident Classification

Create `k8s/sre/incident-classifier/`:

- Deployment that watches Prometheus alerts
- Classifies incidents by:
    - SEV1: SLO breach + error budget < 10%
    - SEV2: SLO breach + error budget 10-30%
    - SEV3: Warning thresholds
- Auto-creates incident tickets (or logs to webhook)
- Labels: endpoint, error_type, blast_radius

Implementation: Go service or Python script + Prometheus AlertManager webhook receiver.

### 10. Documentation

Create `docs/SRE.md`:

- SLI/SLO definitions and rationale
- Error budget policy (e.g., "Freeze deployments when budget < 10%")
- How to interpret SRE dashboard
- Runbook usage guide
- Toil reduction wins tracking (before/after metrics)

Update `README.md`:

- Add SRE practices section
- Link to SRE dashboard
- Document error budget policies

## File Structure

```
k8s/sre/
├── slo-definitions.yaml          # sloth input specs
├── sloth-job.yaml                # Job to run sloth
├── error-budget-rules.yaml       # Custom Prometheus rules
├── slo-alerts.yaml               # AlertManager alert definitions
└── runbooks/
    ├── diagnose-latency.sh
    ├── error-budget-alert.sh
    └── incident-classifier/
        ├── deployment.yaml
        └── main.go (or main.py)

k8s/grafana/
└── configmap-sre-dashboard.yaml  # New dedicated SRE dashboard

docs/
└── SRE.md                        # SRE practices documentation

scripts/
└── update-dashboard.sh           # Toil reduction script
```

## Integration Points

**With existing Prometheus:**

- Add `rule_files` section to load SLO recording rules
- sloth-generated rules feed into error budget calculations

**With VictoriaMetrics (future):**

- Can export Prometheus data to VM for long-term storage
- VM's MetricsQL supports advanced SLO queries
- VM Operator can manage recording rules via CRDs

**With existing Grafana:**

- Main dashboard gets 2 overview panels
- Separate SRE dashboard for deep-dive
- Both use same Prometheus datasource

## Success Metrics

After implementation, track toil reduction:

1. Dashboard update time: Manual (5 min) → Automated (30 sec)
2. Incident triage time: Manual analysis (15 min) → Auto-classification (instant)
3. SLO visibility: No tracking → Real-time dashboard
4. Error budget awareness: Unknown → Visible in every review

## Next Steps After Implementation

1. Tune SLO targets based on actual performance (iterate on 99.5% vs 99.9%)
2. Add per-endpoint SLOs (critical endpoints may need stricter SLOs)
3. Integrate error budget with deployment pipeline (block deploys when budget low)
4. Expand toil reduction to cover more manual tasks (e.g., capacity planning automation)