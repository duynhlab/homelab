# CertManagerCertExpiryCritical

| | |
|---|---|
| **Severity** | critical |
| **Category** | gitops |
| **Source** | `.../prometheusrules/gitops/cert-manager-alerts.yaml` |
| **Metrics** | `certmanager_certificate_expiration_timestamp_seconds` — 24 certificates on this cluster |
| **Status** | active |
| **Dashboard** | GitOps → cert-manager |
| **Local-stack** | not present — the compose stack uses its own certs |

## Meaning

A certificate expires within **24 hours** and has not renewed. cert-manager
normally renews at two-thirds of lifetime, so reaching 24 hours means renewal has
been failing for a long time — this is the end of a slow failure, not a sudden
one. [CertManagerCertExpiringSoon](CertManagerCertExpiringSoon.md) should have
fired six days earlier.

## Impact

Depends on which certificate, and on this platform they are not equivalent:

- **Edge certificates** (`gateway.duynh.me`, `id.duynh.me`, `local.duynh.me`,
  `grafana.duynh.me`, …) — HTTPS fails for anything behind Envoy Gateway. The SPA
  and every API call from a browser stop.
- **Internal certificates** — whatever mTLS or webhook depends on them breaks.
  A failed **admission webhook** certificate is the sharp case: Kyverno's webhook
  sits on the write path of every apply, so an expired cert can block deploys
  cluster-wide.

## Diagnosis

```bash
kubectl get certificate -A
kubectl get certificate -A -o json | python3 -c "
import sys,json,datetime
d=json.load(sys.stdin)
for c in d['items']:
    na=c.get('status',{}).get('notAfter')
    print(f\"{c['metadata']['namespace']}/{c['metadata']['name']:38} notAfter={na}\")"

kubectl describe certificate -n <ns> <name> | tail -30
kubectl get certificaterequest,order,challenge -A 2>/dev/null | grep -v ' True '
kubectl logs -n cert-manager deploy/cert-manager --tail=100 | grep -i error
```

The `CertificateRequest` → `Order` → `Challenge` chain is where renewal actually
fails; the `Certificate` object only reports the outcome.

### PromQL

```promql
certmanager_certificate_expiration_timestamp_seconds - time() < 24 * 3600
(certmanager_certificate_expiration_timestamp_seconds - time()) / 3600     # hours left
certmanager_certificate_ready_status{condition="False"} == 1
```

## Mitigation

1. Read why renewal fails — issuer unreachable, a challenge that cannot be
   solved, or a misconfigured issuer.
2. Force a renewal once the cause is fixed:
   ```bash
   kubectl cert-manager renew -n <ns> <name>     # if the plugin is available
   # otherwise, delete the CertificateRequest and let cert-manager recreate it
   ```
3. Do not hand-craft a Secret to buy time. cert-manager owns it and will
   overwrite, and you will have hidden the failure.
4. This platform issues from `homelab-ca`, so an expiring cert is usually a
   cert-manager or issuer problem rather than an external ACME failure.

## Escalation

Critical, with a hard deadline. Escalate immediately — unlike most alerts, the
consequence lands at a known time whether or not anyone is looking.

## Related

- [CertManagerCertExpiringSoon](CertManagerCertExpiringSoon.md) — the 7-day
  warning that preceded this.
- [CertManagerCertNotReady](CertManagerCertNotReady.md) — the issuance failure
  underneath.
- [FluxHelmReleaseNotReady](FluxHelmReleaseNotReady.md) — cert-manager runs as a
  HelmRelease.

---
_Last updated: 2026-09-05 — created; the cert-manager alert group had no runbooks_
