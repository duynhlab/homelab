# EtcdMembersDown

| | |
|---|---|
| **Severity** | critical |
| **Category** | availability |
| **Source** | `.../prometheusrules/kubernetes/controlplane-alerts.yaml` |
| **Metrics** | `up{job=~".*etcd.*"}` |
| **Status** | 💤 **inert on Kind** — no etcd scrape exists |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present |

## Meaning

An etcd member is unreachable. On a multi-member cluster, losing one is a
redundancy loss; losing quorum stops all writes to the Kubernetes API.

**It cannot fire here.** Kind runs a single-member etcd inside the control-plane
container and this platform does **not scrape it** — `up{job=~".*etcd.*"}`
returns no series, along with every other `etcd_*` metric. The rule is kept
because its expression is correct on any cluster that does scrape etcd; the
catalog marks it 💤.

## Impact

Where it works: quorum loss means the API server cannot write, so the cluster
becomes read-only and then unmanageable.

Here: etcd failure surfaces indirectly instead, as
[KubeAPIServerDown](KubeAPIServerDown.md) or API-server latency, because the API
server is the only thing talking to it.

## Diagnosis

With no metrics, go to the container:

```bash
docker ps | grep control-plane
docker exec homelab-control-plane crictl ps 2>/dev/null | grep etcd
kubectl logs -n kube-system etcd-homelab-control-plane --tail=80

# The API server's own view of storage health
kubectl get --raw /readyz?verbose 2>/dev/null | grep -i etcd
```

`/readyz?verbose` is the most useful of these — it reports an `etcd` check
without needing a scrape.

## Mitigation

1. On Kind, etcd shares the control-plane container's fate. Restarting that
   container restarts etcd, and the platform survives it.
2. Disk pressure on the node is the usual cause of etcd trouble; the node's
   filesystem is the same one every local-path PV writes to, which is a real
   coupling on this platform.
3. To make this alert live, add an etcd scrape — that is a deliberate change, not
   an incident action.

## Escalation

Not applicable as written. If etcd is genuinely suspected, escalate through the
API-server alerts, which do work.

## Related

- [KubeAPIServerDown](KubeAPIServerDown.md) — how etcd trouble actually surfaces
  here.
- [EtcdHighCommitDurations](EtcdHighCommitDurations.md),
  [EtcdHighFsyncDurations](EtcdHighFsyncDurations.md),
  [EtcdHighNumberOfLeaderChanges](EtcdHighNumberOfLeaderChanges.md) — the other
  three inert etcd rules.

---
_Last updated: 2026-09-05 — created; documents why this rule is inert rather than leaving it looking like coverage_
