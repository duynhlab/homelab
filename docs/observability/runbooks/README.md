# Operational Runbooks

Runbooks for investigating, troubleshooting, and resolving incidents in the observability stack.

## Runbook Index

| Runbook | Purpose | When to Use |
|---------|---------|-------------|
| [Observability Deep Dive](observability-deep-dive.md) | RED/USE/Golden Signals theory, 4-pillar stack architecture, middleware chain, correlation workflow, interview preparation | Learning, onboarding, interview prep |
| [Microservices Alerts](microservices-alerts.md) | Per-alert investigation and resolution guide for all 18 application alerts | On-call, when an application alert fires |

## Runbook Structure

Each alert runbook follows a consistent format:

1. **Alert definition** -- what fires and when
2. **Investigation steps** -- what to check first
3. **Resolution actions** -- how to fix it
4. **Escalation** -- when to escalate and to whom

## Related Documentation

- [Alerting Strategy](../alerting/README.md) -- 2-layer alerting architecture
- [SLO System](../slo/README.md) -- SLO definitions and burn-rate alerts
- [Grafana Datasources](../grafana/datasources.md) -- how to view rules in Grafana UI
- [Database HA Scaling](../../databases/runbooks/zalando-ha-scaling.md) -- PostgreSQL HA runbook
- [Prepared Databases](../../databases/runbooks/prepared-databases.md) -- preparedDatabases issue runbook
