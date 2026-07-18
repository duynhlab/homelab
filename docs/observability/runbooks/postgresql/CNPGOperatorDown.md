# CNPGOperatorDown

| | |
|---|---|
| **Severity** | critical |
| **Source** | operator-health (global singleton, ns `cloudnative-pg`) |

## Meaning

`up{namespace="cloudnative-pg"} == 0` for **5 minutes** — CloudNativePG operator
is not reachable on its metrics endpoint.

## Impact

No cluster reconciliation — failovers, backup jobs, scaling, and recovery may not
run. Existing Postgres processes continue until next failure needing operator.

## Diagnosis

```bash
kubectl get pods -n cloudnative-pg
kubectl logs -n cloudnative-pg -l app.kubernetes.io/name=cloudnative-pg --tail=100
flux get helmrelease -n cloudnative-pg
```

## Mitigation

1. Restart operator deployment if crash looping.
2. Flux reconcile `cloudnative-pg` HelmRelease.
3. Verify PodMonitor scrape for operator metrics.

## Escalation

**P1** — page platform on-call; clusters may be stable short-term but cannot self-heal.
