# KeycloakRestartLoop

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability |
| **Source** | [`keycloak/alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/keycloak/alerts.yaml) |
| **Metrics** | `kube_pod_container_status_restarts_total{namespace="identity", container="keycloak"}` |
| **Status** | active |
| **Local-stack** | **not present locally** — reads kube-state-metrics, which the compose stack does not run |

## Meaning

The `keycloak` container restarted more than twice in 15 minutes (no `for`
debounce — the increase window is the debounce). Not yet an outage: readiness
gates traffic during each restart, but the loop is consuming the availability
budget and usually degrades into [KeycloakDown](KeycloakDown.md).

## Impact

Intermittent login/refresh failures during each restart window; the JWKS
endpoint flaps, so the edge may log fetch failures too. If the loop is an OOM
or a failing realm import, it will not heal itself.

## Diagnosis

### kubectl / logs

```bash
POD=$(kubectl get pods -n identity -l app.kubernetes.io/name=keycloak -o name | head -1)
kubectl describe -n identity $POD | grep -A5 "Last State"   # OOMKilled? Exit code?
kubectl logs -n identity $POD --previous --tail=100
kubectl get cluster -n databases platform-db                 # the usual dependency
```

Exit code map: `137` → OOM (raise the memory limit — Keycloak needs headroom
during realm import); DB connection stack traces → `platform-db-rw:5432`
unreachable or credentials drift (ESO secret); import errors name the broken
realm resource verbatim.

### VictoriaLogs

`{app="keycloak"} level:ERROR` on the previous container's tail — the last 20
lines before exit name the cause (`loggerName` of Agroal/Hibernate → DB;
`org.keycloak.exportimport` → realm import).

## Mitigation

1. OOMKilled → raise `resources.limits.memory` in the Keycloak manifest via PR;
   do not `kubectl edit` — Flux will revert it.
2. DB unreachable → fix the database first; the loop stops on its own.
3. Broken realm import → fix the realm ConfigMap/manifest; the import runs at
   startup, so every restart re-fails until it is corrected.

## Escalation

Ticket while readiness still gates traffic and logins succeed between restarts.
Page if it degrades into `KeycloakDown` or the restart interval shortens
(back-off climbing means nobody is winning). Do not delete the pod repeatedly —
it resets the CrashLoopBackOff timer and hides the trend.
