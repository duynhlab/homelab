# Sloth Operator Deployment

This directory contains configuration for deploying the Sloth SLO Operator.

## Overview

Sloth is a Kubernetes operator that automatically generates Prometheus recording and alerting rules from PrometheusServiceLevel custom resources.

**Version**: v0.15.0  
**Chart**: `sloth/sloth`  
**Namespace**: `monitoring`

## Directory Structure

```
k8s/sloth/
├── values.yaml          # Helm values for Sloth Operator
├── crds/                # PrometheusServiceLevel CRDs (9 services)
│   ├── auth-slo.yaml
│   ├── user-slo.yaml
│   ├── product-slo.yaml
│   ├── cart-slo.yaml
│   ├── order-slo.yaml
│   ├── review-slo.yaml
│   ├── notification-slo.yaml
│   ├── shipping-slo.yaml
│   └── shipping-v2-slo.yaml
└── README.md            # This file
```

## Deployment

### Prerequisites

- Kubernetes cluster running
- Prometheus deployed (for SLO rules)
- Helm 3.x installed

### Deploy Sloth Operator

```bash
# Using deployment script (recommended)
./scripts/07-deploy-slo.sh

# Or manually
helm repo add sloth https://slok.github.io/sloth
helm repo update
helm upgrade --install sloth sloth/sloth \
  --namespace monitoring \
  --create-namespace \
  -f k8s/sloth/values.yaml \
  --wait
```

### Deploy SLO Definitions

```bash
# Deploy all PrometheusServiceLevel CRs
kubectl apply -f k8s/sloth/crds/
```

### Verify Deployment

```bash
# Check Sloth Operator
kubectl get pods -n monitoring -l app.kubernetes.io/name=sloth

# Check PrometheusServiceLevel CRs
kubectl get prometheusservicelevels -n monitoring

# Check generated Prometheus rules
kubectl get prometheusrules -n monitoring | grep sloth
```

## SLO Configuration

Each service has 3 SLOs:

1. **Availability** - 99.9% success rate (5xx errors)
2. **Latency** - 99.5% requests under 500ms
3. **Error Rate** - 99.0% overall success rate (4xx + 5xx)

## Grafana Dashboards

Sloth dashboards are automatically deployed via Grafana Operator:

- **Detailed SLOs** - Grafana ID 14348 (per-service metrics)
- **Overview** - Grafana ID 14643 (high-level summary)

Access: http://localhost:3000/dashboards (folder: SLO)

## Alerts

Sloth generates multi-window burn rate alerts for each SLO:

- **Page Alerts** - Critical, requires immediate action
- **Ticket Alerts** - Warning, requires investigation

View alerts in Prometheus: http://localhost:9090/alerts

## Resources

- [Sloth Documentation](https://sloth.dev/)
- [Sloth GitHub](https://github.com/slok/sloth)
- [PrometheusServiceLevel CRD Spec](https://sloth.dev/usage/getting-started/)
- [Common SLI Plugins](https://github.com/slok/sloth-common-sli-plugins)

