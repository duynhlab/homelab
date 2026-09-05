# CertManagerCertExpiringSoon

| | |
|---|---|
| **Severity** | warning |
| **Category** | gitops |
| **Source** | `.../prometheusrules/gitops/cert-manager-alerts.yaml` |
| **Metrics** | `certmanager_certificate_expiration_timestamp_seconds` |
| **Status** | active |
| **Dashboard** | GitOps → cert-manager |
| **Local-stack** | not present |

## Meaning

A certificate expires within **7 days**. Under normal operation this should never
fire: cert-manager renews at two-thirds of lifetime, so a certificate reaching 7
days remaining has already missed its renewal window.

Treat it as *renewal is broken*, not as *expiry is approaching*.

## Impact

None yet — 7 days of daylight. The value is entirely in acting now rather than at
[CertManagerCertExpiryCritical](CertManagerCertExpiryCritical.md).

## Diagnosis

Same chain as the critical, with time to be thorough:

```bash
kubectl get certificate -A
kubectl get certificaterequest -A --sort-by=.metadata.creationTimestamp | tail -10
kubectl describe certificate -n <ns> <name> | tail -30
```

```promql
(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400   # days left
certmanager_certificate_ready_status{condition="False"} == 1
```

Ask **why the renewal did not happen** rather than only how long is left. A
certificate that is `Ready=True` but not renewing is a different problem from one
whose issuance is failing outright.

## Mitigation

Fix the renewal path. If the issuer changed — the platform moved to `homelab-ca`
— a certificate created under an old issuer may need recreating rather than
renewing.

## Escalation

Warning. It becomes the critical in 6 days if nothing is done, and the critical
has a hard deadline.

## Related

- [CertManagerCertExpiryCritical](CertManagerCertExpiryCritical.md)
- [CertManagerCertNotReady](CertManagerCertNotReady.md)

---
_Last updated: 2026-09-05 — created; the cert-manager alert group had no runbooks_
