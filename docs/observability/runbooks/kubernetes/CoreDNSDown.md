# CoreDNSDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | `.../prometheusrules/kubernetes/controlplane-alerts.yaml` |
| **Metrics** | `absent(up{job="kube-dns"} == 1)` — 2 targets on this cluster |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present — no Kubernetes in the compose stack |

## Meaning

No CoreDNS instance is answering its scrape. The expression uses `absent()`, so
it also fires if the **scrape target disappears** — a deleted ServiceMonitor
produces the same alert as a dead CoreDNS. Confirm with `kubectl` before
concluding DNS is down.

## Impact

Cluster DNS is the substrate everything else assumes. Without it, every
service-to-service call by name fails: the 10 Go services cannot reach each
other, Flux cannot resolve the registry, the OTel Collector cannot reach its
backends, and CNPG cannot resolve its own pooler.

Already-established connections survive; anything that needs a fresh lookup does
not. So the failure spreads gradually, which makes the wave of downstream alerts
arrive minutes after the cause.

## Diagnosis

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Does resolution actually work, independent of the scrape
kubectl run dnstest-$RANDOM --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup kubernetes.default.svc.cluster.local
```

That last check is the one that separates "DNS is down" from "the scrape is
down". They need very different responses and this alert cannot tell them apart.

### PromQL

```promql
absent(up{job="kube-dns"} == 1)
count(up{job="kube-dns"})          # 2 when healthy
sum(rate(coredns_dns_requests_total[5m]))
```

## Mitigation

1. **Pods gone** → the Deployment should recreate them; if it does not, the
   control plane is the problem, not DNS.
2. **Pods up, resolution works** → this is a monitoring failure. Fix the scrape,
   do not touch CoreDNS.
3. **Pods up, resolution fails** → read the logs; a bad Corefile or an upstream
   resolver failure will show there.
4. On Kind, CoreDNS runs on the control-plane node — pressure there affects it.

## Escalation

Critical. Expect co-firing alerts across the platform that are all downstream of
this one; fix here first and do not chase them.

## Related

- [KubeletDown](KubeletDown.md), [KubeAPIServerDown](KubeAPIServerDown.md) — the
  other control-plane absences.
- [CoreDNSHighErrorRate](CoreDNSHighErrorRate.md) — degraded rather than absent.

---
_Last updated: 2026-09-05 — created; the controlplane alert group had no runbooks_
