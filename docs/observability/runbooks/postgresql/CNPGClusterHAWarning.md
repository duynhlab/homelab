# CNPGClusterHAWarning

| | |
|---|---|
| **Severity** | warning |
| **Source** | chart |
| **Clusters** | `platform-db`, `product-db` (3 instances each) |

## Meaning

Fewer than **2 streaming replicas** connected — degraded redundancy (1 of 2
standbys missing). Expected 3-node HA with 1 primary + 2 replicas.

## Impact

Still have one standby for failover, but lost N-1 redundancy. Another failure
drops to HA critical.

## Diagnosis

Same as [CNPGClusterHACritical.md](CNPGClusterHACritical.md).

## Mitigation

1. Identify missing replica pod — CrashLoop, PVC pending, or scheduling.
2. Allow CNPG to recreate instance if pod deleted intentionally.
3. Ticket if self-heals within 15m.

## Escalation

Page if trending to HA critical or during maintenance window.
