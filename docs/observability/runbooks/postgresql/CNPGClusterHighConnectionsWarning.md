# CNPGClusterHighConnectionsWarning

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` |

## Meaning

Instance connection usage **>80%** of `max_connections` for **5 minutes** (same
expr as critical, lower threshold).

## Impact

Approaching connection refusal — proactive window to fix before critical.

## Diagnosis

Same as [CNPGClusterHighConnectionsCritical.md](CNPGClusterHighConnectionsCritical.md).

## Mitigation

Same mitigation steps as critical — act before 95% threshold. Prefer pool tuning
and idle session cleanup over raising `max_connections`.

## Escalation

Ticket unless rising rapidly toward critical.
