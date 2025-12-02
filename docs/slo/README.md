# SLO System Documentation

## Overview

This SLO (Service Level Objective) system provides comprehensive monitoring and alerting for all microservices using [Sloth](https://sloth.dev), following Google SRE best practices with multi-window multi-burn-rate alerts.

## Quick Start

### 1. Validate SLO Definitions

```bash
./scripts/08a-validate-slo.sh
```

### 2. Generate Prometheus Rules

```bash
./scripts/08b-generate-slo-rules.sh
```

This generates Prometheus recording rules and alerts from all SLO definitions in `slo/definitions/`.

### 3. Deploy SLO System

```bash
./scripts/08-deploy-slo.sh
```

This script:
- Validates SLO definitions
- Generates Prometheus rules using Sloth
- Deploys rules to Prometheus ConfigMap
- Updates Prometheus configuration

**Note:** Dashboards should be imported manually via Grafana UI (see [GETTING_STARTED.md](./GETTING_STARTED.md#step-4-import-sloth-dashboards)).

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   SLO Definitions│    │   Sloth Tool     │    │   Prometheus    │
│   (YAML files)   │───▶│   (Generator)    │───▶│   (Rules)       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
                                                ┌──────────────────┐
                                                │   Grafana        │
                                                │   (SLO Dashboard)│
                                                └──────────────────┘
                                                         │
                                                         ▼
                                                ┌──────────────────┐
                                                │   AlertManager   │
                                                │   (Alerts)       │
                                                └──────────────────┘
```

## Services with SLOs

All 9 microservices have SLO definitions:

1. **auth** - Authentication service
2. **user** - User management service
3. **product** - Product catalog service
4. **cart** - Shopping cart service
5. **order** - Order processing service
6. **review** - Product review service
7. **notification** - Notification service
8. **shipping** - Shipping service (v1)
9. **shipping-v2** - Shipping service (v2)

## SLO Types

Each service has 3 SLOs:

### 1. Availability SLO
- **Target**: 99.5% (30-day window)
- **SLI**: Ratio of successful requests (non-5xx) to total requests
- **Purpose**: Measure service uptime and reliability

### 2. Latency SLO
- **Target**: 95% of requests < 500ms (30-day window)
- **SLI**: Ratio of requests faster than 500ms to total requests
- **Purpose**: Measure response time performance

### 3. Error Rate SLO
- **Target**: 99% success rate (30-day window)
- **SLI**: Ratio of successful requests (non-4xx/5xx) to total requests
- **Purpose**: Measure overall request quality

## Alerting

Multi-window multi-burn-rate alerts (Google SRE methodology):

- **Page Alert**: 15x burn rate (1h window) OR 6x burn rate (6h window)
- **Ticket Alert**: 4x burn rate (1h window) OR 2x burn rate (6h window)

## Documentation

- **[GETTING_STARTED.md](./GETTING_STARTED.md)** - Quick start guide
- **[SLI_DEFINITIONS.md](./SLI_DEFINITIONS.md)** - Detailed SLI specifications
- **[SLO_TARGETS.md](./SLO_TARGETS.md)** - SLO targets per service
- **[ALERTING.md](./ALERTING.md)** - Alert configuration and runbooks
- **[ERROR_BUDGET_POLICY.md](./ERROR_BUDGET_POLICY.md)** - Error budget management

## References

- [Sloth Documentation](https://sloth.dev)
- [Sloth GitHub](https://github.com/slok/sloth)
- [Google SRE Workbook - Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Google SRE Book - SLIs, SLOs, and SLAs](https://sre.google/sre-book/service-level-objectives/)
