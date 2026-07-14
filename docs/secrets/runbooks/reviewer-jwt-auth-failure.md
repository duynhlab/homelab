# Reviewer JWT Auth Failure

Use this when ESO works after bootstrap but starts failing about one hour later with `permission denied` from OpenBAO Kubernetes auth.

| Root cause | Fix |
|---|---|
| Bootstrap wrote a short-lived projected service-account token as `token_reviewer_jwt` | Omit `token_reviewer_jwt` and set `disable_local_ca_jwt=false` so OpenBAO uses its own rotated pod token |

## `permission denied` ~1 h after bootstrap (reviewer-JWT pitfall, fb14349)

**Symptom**: every ExternalSecret reports `ClusterSecretStore "openbao" is not ready`; ESO logs show `Code: 403 ... permission denied` on `/v1/auth/kubernetes/login`. Often appears 1–2 h after `make up`, not at start.

**Root cause**: legacy bootstrap wrote `auth/kubernetes/config` with `token_reviewer_jwt` set to its own projected SA token (1 h TTL via `BoundServiceAccountTokenVolume`). After expiry, every K8s-auth login fails. Fix in `fb14349`: omit `token_reviewer_jwt` and set `disable_local_ca_jwt=false` so OpenBAO uses its own pod's auto-rotated SA token.

**Verify**:

```bash
ROOT=$(kubectl get secret openbao-init-keys -n openbao -o jsonpath='{.data.root_token}' | base64 -d)
kubectl exec -n openbao openbao-0 -- sh -c "BAO_TOKEN=$ROOT bao read auth/kubernetes/config"
# Expect: token_reviewer_jwt_set=false, disable_local_ca_jwt=false
```

**Runtime fix** (deadlock: `secrets-local` is what installs the fix — break the loop manually):

```bash
kubectl exec -n openbao openbao-0 -- sh -c \
  "BAO_TOKEN=$ROOT bao write auth/kubernetes/config \
    kubernetes_host=https://10.96.0.1:443 \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    disable_local_ca_jwt=false token_reviewer_jwt=''"
kubectl annotate clustersecretstore openbao force-sync=$(date +%s) --overwrite
```

**Persistent fix** (bootstrap script now ships corrected logic):

```bash
kubectl delete job -n openbao openbao-bootstrap
flux reconcile ks secrets-local --with-source
```

## General K8s auth checks

```bash
# Check Kubernetes auth config in OpenBAO
bao read auth/kubernetes/config

# Test the K8s auth manually
SA_TOKEN=$(kubectl create token external-secrets -n external-secrets-system)
curl -s http://openbao.openbao.svc.cluster.local:8200/v1/auth/kubernetes/login \
  -d "{\"role\":\"eso-reader\",\"jwt\":\"$SA_TOKEN\"}"

# Check audit log (Vector → VictoriaLogs) for denied requests
# In Grafana (VictoriaLogs, LogsQL): _stream:{namespace="openbao"} stream:=stdout | unpack_json | type:=response error:!=""
```

_Last updated: 2026-07-14 - Split from `docs/secrets/README.md` during the runbook refactor._
