# ESO Sync Failure

Use this when an `ExternalSecret`, `ClusterExternalSecret`, or a
`ClusterSecretStore` (`openbao` for KV, `openbao-db` for the runtime database
passwords) is not Ready.

```mermaid
flowchart TD
    ES[ExternalSecret not Ready] --> CSS["Check its ClusterSecretStore<br/>openbao (KV) or openbao-db (static-creds)"]
    CSS --> BAO[Check OpenBAO health]
    BAO --> AUTH[Test Kubernetes auth]
    AUTH --> PATH["Verify the path and the eso-read policy<br/>KV path or database/static-creds/&lt;svc&gt;-runtime"]
    PATH --> RECONCILE[Force ESO / Flux reconcile]
```

```bash
# Check ESO pod for errors
kubectl logs -n external-secrets-system deployment/external-secrets | grep ERROR

# Describe the ExternalSecret (shows last sync error)
kubectl describe externalsecret <name> -n <namespace>

# Check ClusterSecretStore connectivity
kubectl get clustersecretstore openbao -o yaml | grep -A10 conditions

# Verify OpenBAO is reachable from ESO namespace
kubectl run -it --rm test --image=curlimages/curl -n external-secrets-system \
  -- curl -s http://openbao.openbao.svc.cluster.local:8200/v1/sys/health
```
