# EtcdHighFsyncDurations

| | |
|---|---|
| **Severity** | warning |
| **Category** | availability |
| **Source** | `.../prometheusrules/kubernetes/controlplane-alerts.yaml` |
| **Metrics** | `etcd_disk_wal_fsync_duration_seconds_bucket` |
| **Status** | 💤 **inert on Kind** — the metric has **0 series** |
| **Dashboard** | Observability → Kubernetes cluster overview |
| **Local-stack** | not present |

## Meaning

WAL fsync p99 above threshold — the disk cannot flush etcd's write-ahead log fast enough.

**It cannot fire here.** This platform does not scrape etcd, so `etcd_disk_wal_fsync_duration_seconds_bucket`
returns no series and the expression matches nothing. vmalert reports no error,
because a rule that matches nothing is not a rule that fails — which is precisely
why the catalog marks it 💤 rather than counting it as coverage.

Kept rather than deleted: the expression is correct on any cluster that scrapes
etcd.

## Impact

Where it works, this is an early warning that etcd's storage is too slow. Slow
etcd makes every API-server write slow, which makes the whole control plane feel
sluggish before anything actually fails.

Here: none. Etcd trouble surfaces as
[KubeAPIServerDown](KubeAPIServerDown.md) or API-server latency instead.

## Diagnosis

Without the metric, use the API server's view and the node:

```bash
kubectl get --raw /readyz?verbose 2>/dev/null | grep -i etcd
kubectl logs -n kube-system etcd-homelab-control-plane --tail=80 | grep -iE 'slow|took|apply'
```

etcd logs "apply request took too long" lines when it is under storage pressure,
which is the same signal this alert would have carried.

Storage pressure on the control-plane node is the usual cause, and on this
platform the node's filesystem is shared with every local-path PV.

## Mitigation

Reduce disk contention on the control-plane node, or give it faster storage. To
make the alert live, add an etcd scrape — a deliberate change.

## Escalation

Not applicable as written.

## Related

- [EtcdMembersDown](EtcdMembersDown.md)
- [KubeAPIServerDown](KubeAPIServerDown.md),
  [KubeAPIServerHighLatency](KubeAPIServerHighLatency.md) — how this surfaces here

---
_Last updated: 2026-09-05 — created; documents why this rule is inert rather than leaving it looking like coverage_
