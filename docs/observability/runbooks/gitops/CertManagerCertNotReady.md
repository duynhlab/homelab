# CertManagerCertNotReady

| | |
|---|---|
| **Severity** | warning |
| **Category** | gitops |
| **Source** | `.../prometheusrules/gitops/cert-manager-alerts.yaml` |
| **Metrics** | `certmanager_certificate_ready_status{condition="False"} == 1` |
| **Status** | active · 24 certificate series on this cluster |
| **Dashboard** | GitOps → cert-manager |
| **Local-stack** | not present |

## Meaning

A `Certificate` is not Ready — issuance or renewal is failing **now**. This is
the cause; the two expiry alerts are its eventual consequences.

A brand-new certificate sits `Ready=False` briefly while it is issued, so a short
occurrence during a fresh bring-up is expected. Sustained is the signal.

## Impact

Immediate impact depends on whether a *previous* certificate is still valid:

- **Renewal failing, old cert still valid** → nothing is broken yet, and the
  clock is running toward the expiry alerts.
- **First issuance failing** → there is no certificate at all, so whatever needs
  it is broken right now: TLS on that host, or a webhook that cannot serve.

Check which case it is before deciding urgency.

## Diagnosis

The `Certificate` reports the outcome; the chain below it reports the reason:

```bash
kubectl get certificate -A | grep -v ' True '
kubectl describe certificate -n <ns> <name> | tail -30

# The actual failure lives here
kubectl get certificaterequest -n <ns> | tail -5
kubectl describe certificaterequest -n <ns> <cr-name> | tail -25

# Is the issuer itself healthy
kubectl get issuer,clusterissuer -A
kubectl logs -n cert-manager deploy/cert-manager --tail=100 | grep -iE 'error|fail'
```

Recurring causes here: the `homelab-ca` issuer not ready (it is created by the
`cert-manager` wave and depends on `secrets`), a Secret the issuer needs that ESO
has not populated yet, or a Certificate requesting a DNS name the issuer will not
sign.

## Mitigation

1. **Issuer not ready** → fix the issuer; every certificate under it is blocked.
   Check the Flux wave ordering: `cert-manager` depends on `secrets`.
2. **Secret missing** → an ESO/OpenBAO problem, not a cert-manager one.
3. **Stuck request** → delete the `CertificateRequest` and let cert-manager
   recreate it. Deleting the `Certificate` is heavier and usually unnecessary.

## Escalation

Warning. Escalate if the certificate has no valid predecessor, or if the issuer
is down — one broken issuer blocks every certificate under it at once.

## Related

- [CertManagerCertExpiringSoon](CertManagerCertExpiringSoon.md),
  [CertManagerCertExpiryCritical](CertManagerCertExpiryCritical.md) — the
  consequences if this is not fixed.
- [FluxKustomizationNotReady](FluxKustomizationNotReady.md) — the `cert-manager`
  wave failing is a common upstream cause.

---
_Last updated: 2026-09-05 — created; the cert-manager alert group had no runbooks_
