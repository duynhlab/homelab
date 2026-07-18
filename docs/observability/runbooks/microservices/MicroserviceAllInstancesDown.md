# MicroserviceAllInstancesDown

| | |
|---|---|
| **Severity** | critical (page) |
| **Manifest** | [`alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/microservices/alerts.yaml) |

## Meaning
Every instance of a service is down simultaneously. Complete outage.

## Impact
See alert summary in [alert catalog](../../alerting/alert-catalog.md#1-microservices-red-metrics).

## Diagnosis
### Possible causes
- Failed deployment (bad image, broken config)
- Shared dependency failure (database down, secret missing)
- Namespace-wide issue (ResourceQuota exhausted, namespace deleted)
- Node failure (all pods scheduled on same node)

### Investigation
```bash
# Check all pods in namespace
kubectl get pods -n $NAMESPACE

# Check deployment spec
kubectl describe deployment/$APP -n $NAMESPACE

# Check events in namespace
kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -20

# Check HelmRelease status
kubectl get helmrelease -n $NAMESPACE
flux get helmrelease -n $NAMESPACE
```

## Mitigation
1. If bad deployment: `kubectl rollout undo deployment/$APP -n $NAMESPACE`
2. If dependency failure: check database alerts (`CNPGClusterOffline`, `CnpgClusterFenced`)
3. If resource issue: check `kubectl describe namespace $NAMESPACE` for quotas

## Escalation
This is a full outage. If not resolved in 15 minutes, escalate to team lead.
