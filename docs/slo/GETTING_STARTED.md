# Getting Started with SLO System

## Prerequisites

1. **Sloth Tool**: Install Sloth CLI
   ```bash
   # Using Homebrew (macOS)
   brew install sloth
   
   # Using Go
   go install github.com/slok/sloth/cmd/sloth@latest
   
   # Using Docker
   docker pull ghcr.io/slok/sloth:latest
   ```

2. **Kubernetes Cluster**: Access to a Kubernetes cluster with Prometheus and Grafana deployed

3. **kubectl**: Configured to access your cluster

## Installation Steps

### Step 1: Validate SLO Definitions

Before generating rules, validate all SLO definition files:

```bash
./scripts/09-validate-slo.sh
```

Expected output:
```
🔍 Validating SLO definitions...
📋 Found 9 SLO definition files:
  auth.yaml
  cart.yaml
  ...
✅ All SLO definitions are valid!
```

### Step 2: Generate Prometheus Rules

Generate Prometheus recording rules and alerts:

```bash
./scripts/10-generate-slo-rules.sh
```

This creates `slo/generated/prometheus-rules.yaml` with:
- SLI recording rules
- Error budget rules
- Burn rate rules
- Multi-window multi-burn-rate alerts

### Step 3: Deploy to Cluster

Deploy all SLO components:

```bash
./scripts/11-deploy-slo.sh
```

This script:
1. Validates definitions
2. Generates rules
3. Creates Prometheus ConfigMap
4. Updates Prometheus deployment

**Note:** Dashboards should be imported manually via Grafana UI (see Step 4).

### Step 4: Import Sloth Dashboards

Import recommended Sloth dashboards via Grafana UI:

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
```

1. Open Grafana UI: http://localhost:3000
2. Go to **Dashboards** → **Import**
3. Import by ID:
   - **Detailed SLOs**: ID `14348`
   - **Overview**: ID `14643`
4. Select datasource: **Prometheus** (UID: `prometheus`)

### Step 5: Verify Deployment

Check Prometheus rules:

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Query SLO metrics
curl "http://localhost:9090/api/v1/query?query=slo:sli_error:ratio_rate5m{service=\"auth\"}"
```

## First SLO Definition

Example: Creating a new SLO for a service

```yaml
# slo/definitions/myapp.yaml
version: "prometheus/v1"
service: "myapp"
labels:
  team: "platform"
  env: "demo"
  service: "myapp"
  namespace: "myapp"

slos:
  - name: "availability"
    objective: 99.5
    description: "Availability measures the ratio of successful requests (non-5xx) to total requests"
    sli:
      events:
        error_query: |
          sum(rate(request_duration_seconds_count{
            app="myapp",
            namespace="myapp",
            job=~"microservices",
            code=~"5.."
          }[{{.window}}]))
        total_query: |
          sum(rate(request_duration_seconds_count{
            app="myapp",
            namespace="myapp",
            job=~"microservices"
          }[{{.window}}]))
    alerting:
      name: MyappHighErrorRate
      # ... alert configuration
```

## Verification

### Check Rules in Prometheus

1. Open Prometheus UI: http://localhost:9090
2. Go to Status → Rules
3. Verify SLO rules are loaded

### Check Metrics

Query SLO metrics:

```promql
# SLI error ratio
slo:sli_error:ratio_rate5m{service="auth"}

# Error budget remaining
slo:error_budget_remaining:ratio{service="auth"}

# Burn rate
slo:error_budget_burn_rate:ratio{service="auth"}
```

### Check Alerts

1. Open Prometheus UI: http://localhost:9090
2. Go to Alerts
3. Look for alerts like:
   - `AuthHighErrorRate`
   - `UserHighLatency`
   - etc.

## Troubleshooting

### Rules Not Loading

**Problem**: Prometheus shows "No rules found"

**Solution**:
1. Check ConfigMap exists:
   ```bash
   kubectl get configmap prometheus-slo-rules -n monitoring
   ```
2. Check Prometheus logs:
   ```bash
   kubectl logs deployment/prometheus -n monitoring
   ```
3. Verify rule file path in Prometheus config

### Metrics Not Appearing

**Problem**: SLO metrics return "No data"

**Solution**:
1. Verify source metrics exist:
   ```promql
   request_duration_seconds_count{app="auth", job=~"microservices"}
   ```
2. Check time range (SLOs need 30 days of data for full accuracy)
3. Verify labels match in SLO definition

### Validation Errors

**Problem**: `sloth validate` fails

**Solution**:
1. Check YAML syntax
2. Verify all required fields are present
3. Check PromQL query syntax
4. Ensure metric names exist

## Next Steps

- Read [SLI_DEFINITIONS.md](./SLI_DEFINITIONS.md) for detailed SLI specifications
- Review [ALERTING.md](./ALERTING.md) for alert configuration
- Check [ERROR_BUDGET_POLICY.md](./ERROR_BUDGET_POLICY.md) for budget management

