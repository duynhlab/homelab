# CoreDNSHighErrorRate

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability |
| **Source** | `.../prometheusrules/kubernetes/controlplane-alerts.yaml` |
| **Metrics** | `coredns_dns_responses_total{rcode="SERVFAIL"}` over all responses |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present |

## Meaning

CoreDNS is returning `SERVFAIL` on a meaningful fraction of queries. Note the
rcode: `SERVFAIL` is CoreDNS *failing to answer*, not `NXDOMAIN`, which is a
perfectly correct answer meaning the name does not exist.

That distinction matters because a pod looking up a name that does not exist —
common, and harmless — produces `NXDOMAIN` and does not fire this.

## Impact

Intermittent name-resolution failures across the cluster. Clients retry, so the
visible symptom is usually latency and sporadic connection errors rather than a
clean outage, which makes it easy to misattribute to whichever service happened
to fail.

## Diagnosis

```promql
sum by (rcode) (rate(coredns_dns_responses_total[5m]))
sum(rate(coredns_dns_responses_total{rcode="SERVFAIL"}[5m]))
  / sum(rate(coredns_dns_responses_total[5m]))

# Are upstream forwards failing
sum by (rcode) (rate(coredns_forward_responses_total[5m]))
histogram_quantile(0.99, sum by (le) (rate(coredns_dns_request_duration_seconds_bucket[5m])))
```

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100 | grep -iE 'SERVFAIL|error|timeout'
```

Two shapes: failures on **cluster-local** names (a CoreDNS or API-server problem)
versus failures on **external** names (the upstream resolver, which on Kind is
the host's). `coredns_forward_responses_total` separates them.

## Mitigation

1. **Upstream forwards failing** → the host's resolver or egress; CoreDNS is
   reporting, not causing.
2. **Cluster-local failures** → CoreDNS cannot reach the API server to resolve
   Services. Check the API server.
3. **CPU-starved CoreDNS** → it runs on the control-plane node with modest
   resources; pressure there shows up as timeouts.

## Escalation

Warning. Escalate if the ratio is climbing — DNS degradation looks like a dozen
unrelated service failures until someone checks here.

## Related

- [CoreDNSDown](CoreDNSDown.md)
- [KubeAPIServerHighLatency](KubeAPIServerHighLatency.md) — CoreDNS resolves
  Services through the API server.

---
_Last updated: 2026-09-05 — created; the controlplane alert group had no runbooks_
