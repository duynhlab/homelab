# KubeletDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | `.../prometheusrules/kubernetes/controlplane-alerts.yaml` |
| **Metrics** | `absent(up{job="kubelet"} == 1)` — 8 targets on this 4-node cluster |
| **Status** | active |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present |

## Meaning

No kubelet is being scraped. `absent()` again, so a vanished scrape target fires
this just as a dead kubelet would.

Note the shape: this fires only when **all** kubelets are unscraped. A single
node's kubelet dying does not trigger it — that surfaces as
[KubeNodeNotReady](KubeNodeNotReady.md) instead. So this alert means something
cluster-wide, most often the scrape configuration rather than eight
simultaneously dead kubelets.

## Impact

If the kubelets are genuinely down, nothing on those nodes is being managed:
no pod lifecycle, no probes, no restarts. If only the scrape is down, the cluster
is fine and the **monitoring** is blind — including every node and pod metric,
which silences a large fraction of the alert catalog.

Distinguishing those two is the entire job here.

## Diagnosis

```bash
kubectl get nodes -o wide
kubectl get pods -A --field-selector spec.nodeName=<node> | head

# If the nodes are Ready, the kubelets are alive and this is a scrape failure
kubectl get vmnodescrape,servicemonitor -A | grep -i kubelet
kubectl get --raw /api/v1/nodes/homelab-worker/proxy/metrics | head -3
```

Nodes reporting `Ready` while this alert fires is the common case and means the
scrape, not the kubelet.

### PromQL

```promql
absent(up{job="kubelet"} == 1)
count(up{job="kubelet"})            # 8 when healthy
```

## Mitigation

1. **Nodes Ready** → fix the scrape; vmagent runs `selectAllByDefault`, so check
   the VMNodeScrape object and
   [VMAgentScrapePoolHasNoTargets](../victoriametrics/VMAgentScrapePoolHasNoTargets.md).
2. **Nodes NotReady** → this is a node or control-plane incident;
   [KubeNodeNotReady](KubeNodeNotReady.md) and
   [KubeAPIServerDown](KubeAPIServerDown.md).
3. On Kind, a node is a container: `docker ps` will show whether it exists at all.

## Escalation

Critical. State which case it is — "kubelet down" and "kubelet metrics missing"
have completely different urgencies and the alert cannot tell them apart.

## Related

- [KubeNodeNotReady](KubeNodeNotReady.md)
- [KubeAPIServerDown](KubeAPIServerDown.md)
- [KubeletTooManyPods](KubeletTooManyPods.md)

---
_Last updated: 2026-09-05 — created; the controlplane alert group had no runbooks_
