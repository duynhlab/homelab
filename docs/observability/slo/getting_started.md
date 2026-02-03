# Getting Started with SLO System

## Overview

The SLO (Service Level Objective) system is managed by the **Sloth Kubernetes Operator** (v0.15.0), which provides Kubernetes-native SLO management via Custom Resource Definitions (CRDs). This replaces manual bash scripts with automated validation and rule generation.

## Prerequisites

1. **Kubernetes Cluster**: Access to a Kubernetes cluster with Prometheus deployed
2. **kubectl**: Configured to access your cluster
3. **Helm**: v3.14+ for deploying the Sloth Operator

**Note**: You do NOT need to install the Sloth CLI locally. The Sloth Operator handles all validation and rule generation automatically.

## Architecture

The SLO system uses:
- **Sloth Operator**: Kubernetes operator for managing SLOs (`sloth/sloth` Helm chart v0.15.0)
- **PrometheusServiceLevel CRDs**: Kubernetes-native SLO definitions (one per service)
- **PrometheusRule CRs**: Automatically generated Prometheus recording rules and alerts
- **Grafana Dashboards**: Auto-provisioned via Grafana Operator (`GrafanaDashboard` CRs)

## Installation Steps

### Step 1: Deploy Sloth Operator and SLO CRDs

Deploy the complete SLO system:

```bash
./scripts/07-deploy-slo.sh
```

This script:
1. Installs the Sloth Operator via Helm to the `monitoring` namespace
2. Applies all 9 PrometheusServiceLevel CRDs from `k8s/sloth/crds/`
3. Waits for the operator to become ready
4. Automatically generates Prometheus recording rules and alerts

Expected output:
```
🚀 Deploying Sloth SLO System...

1. Installing Sloth Operator (Helm)...
Release "sloth" installed successfully

2. Applying PrometheusServiceLevel CRDs (9 services)...
prometheusservicelevel.sloth.slok.dev/auth created
prometheusservicelevel.sloth.slok.dev/user created
...

✅ Sloth SLO system deployed successfully!
```

### Step 2: Verify Deployment

Check that all components are deployed:

```bash
# Check Sloth Operator pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=sloth

# Check PrometheusServiceLevel CRDs
kubectl get prometheusservicelevels -n monitoring

# Check generated PrometheusRules
kubectl get prometheusrules -n monitoring

# Describe a specific SLO
kubectl describe prometheusservicelevel auth -n monitoring
```

### Step 3: Access Sloth Dashboards

Grafana dashboards are automatically provisioned via the Grafana Operator:

1. Port-forward Grafana: `kubectl port-forward -n monitoring svc/grafana-service 3000:3000`
2. Open Grafana: http://localhost:3000 (anonymous access enabled)
3. Look for dashboards under the **SLO** folder:
   - **Sloth SLO Overview** (Grafana.com ID `14643`) - High-level view of all SLOs
   - **Sloth SLO Detailed** (Grafana.com ID `14348`) - Detailed per-service SLO metrics
4. Both dashboards are pre-configured with the Prometheus datasource

### Step 4: Verify Metrics

Check that SLO metrics are being collected:

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Query SLO metrics (examples)
curl "http://localhost:9090/api/v1/query?query=slo:sli_error:ratio_rate5m{sloth_service=\"auth\"}"
curl "http://localhost:9090/api/v1/query?query=slo:error_budget_remaining:ratio{sloth_service=\"auth\"}"
```

Open Prometheus UI (http://localhost:9090) and navigate to:
- **Status → Rules**: Verify SLO rules are loaded
- **Alerts**: Check for SLO-related alerts (e.g., error budget burn rate alerts)

## Creating a New SLO

To add a new SLO for a service, create a PrometheusServiceLevel CRD:

```yaml
# k8s/sloth/crds/myapp-slo.yaml
apiVersion: sloth.slok.dev/v1
kind: PrometheusServiceLevel
metadata:
  name: myapp-slo
  namespace: monitoring
spec:
  service: "myapp"
  labels:
    team: "platform"
    env: "monitoring"
    namespace: "myapp"
  slos:
    - name: "availability"
      objective: 99.5
      description: "Availability measures the ratio of successful requests (non-5xx) to total requests"
      sli:
        events:
          errorQuery: |
            sum(rate(request_duration_seconds_count{
              app="myapp",
              namespace="myapp",
              job=~"microservices",
              code=~"5.."
            }[{{.window}}]))
          totalQuery: |
            sum(rate(request_duration_seconds_count{
              app="myapp",
              namespace="myapp",
              job=~"microservices"
            }[{{.window}}]))
      alerting:
        name: MyappHighErrorRate
        labels:
          category: "availability"
        annotations:
          summary: "High error rate on myapp service"
        pageAlert:
          labels:
            severity: critical
        ticketAlert:
          labels:
            severity: warning
```

Apply the CRD:

```bash
kubectl apply -f k8s/sloth/crds/myapp-slo.yaml
```

The Sloth Operator will automatically:
1. Validate the SLO definition
2. Generate Prometheus recording rules
3. Create PrometheusRule CRs
4. Set up error budget tracking and alerts

## Verification

### Check Rules in Prometheus

1. Open Prometheus UI: http://localhost:9090
2. Go to **Status → Rules**
3. Look for rule groups like:
   - `sloth-slo-sli-recordings-auth-availability`
   - `sloth-slo-meta-recordings-auth-availability`
   - `sloth-slo-alerts-auth-availability`

### Check Metrics

Query SLO metrics in Prometheus:

```promql
# SLI error ratio (5-minute window)
slo:sli_error:ratio_rate5m{sloth_service="auth"}

# Error budget remaining
slo:error_budget_remaining:ratio{sloth_service="auth"}

# Burn rate
slo:current_burn_rate:ratio{sloth_service="auth"}

# List all SLO services
count by (sloth_service) (slo:sli_error:ratio_rate5m)
```

### Check Alerts

1. Open Prometheus UI: http://localhost:9090
2. Go to **Alerts**
3. Look for Sloth-generated alerts:
   - `AuthHighErrorRate` (Page)
   - `AuthHighErrorRate` (Ticket)
   - Similar alerts for other services


## Next Steps

- Read [sli_definitions.md](./sli_definitions.md) for detailed SLI specifications
- Review [alerting.md](./alerting.md) for alert configuration
- Check [error_budget_policy.md](./error_budget_policy.md) for budget management

