# CNPGDRClusterOffline

The product database can still serve while its disaster-recovery layer has
silently disappeared; this alert names that loss directly.

| Quick facts | |
|---|---|
| **Severity** | critical |
| **Category** | databases |
| **Cluster** | `product/product-db-replica` |
| **Metric** | `cnpg_collector_up` |
| **Threshold** | zero collector targets for 5 minutes |
| **Source** | `prometheusrules/postgres/dr-cluster-offline.yaml` |
| **Dashboard** | Databases → PostgreSQL / CloudNativePG |

## Meaning

No CNPG collector series exists for any `product-db-replica` instance. The
`OR on() vector(0)` half is deliberate: the alert must remain evaluable when
the failure removes every series it would otherwise inspect.

This differs from `CNPGClusterStandbyNotStreaming`. That alert sees a running
standby whose WAL receiver stopped; this alert sees a DR cluster with no
observable instances at all.

## Impact

The primary `product-db` may still be healthy, so this is not automatically a
customer-facing outage. Recovery posture is critical, however: continuous
recovery, the tested promotion target, and the independent DR backup chain are
unavailable until the cluster returns.

## Diagnosis

Confirm the alert signal and serving-primary health separately:

```promql
count by (cnpg_io_cluster) (
  cnpg_collector_up{
    namespace="product",
    cnpg_io_cluster=~"product-db|product-db-replica"
  }
)
```

```bash
kubectl -n product get cluster product-db product-db-replica
kubectl -n product get pods,jobs -l cnpg.io/cluster=product-db-replica
kubectl -n product describe cluster product-db-replica
kubectl -n product get events --sort-by=.lastTimestamp | tail -n 40
```

If a full-recovery Job failed, read its logs before retrying:

```bash
JOB=$(kubectl -n product get jobs -o name \
  | grep 'product-db-replica.*full-recovery' | tail -n 1)
kubectl -n product logs "$JOB" --all-containers --tail=200
```

An `Expected empty archive` error is the rebuild precondition from
[CNPG disaster recovery](../../../databases/disaster-recovery.md), not a reason
to delete the primary archive.

## Mitigation

1. Prove `product-db` is healthy and its source backup/WAL chain is current.
2. Identify whether the failure is scheduling, credentials, source recovery,
   or the DR write-prefix empty-archive gate.
3. Follow the DR rebuild procedure. Never delete an object-store prefix from an
   alert annotation or an unreviewed shell command.
4. Reconcile `databases-cnpg-dr-local` only after the failed precondition is
   resolved.

## Recovery validation

Recovery requires all of the following:

```bash
kubectl -n product get cluster product-db-replica
kubectl -n product get pods -l cnpg.io/cluster=product-db-replica
flux get kustomization databases-cnpg-dr-local -n flux-system
```

- The CNPG Cluster is healthy with 3/3 instances.
- One designated primary remains in recovery from `product-db-primary`; two
  cascading instances are healthy.
- `cnpg_collector_up{cnpg_io_cluster="product-db-replica"}` has three series.
- `databases-cnpg-dr-local` is `Ready=True`.
- The alert is inactive after the five-minute window clears.

## Escalation

Page the database/platform owner immediately if the source `product-db` is also
degraded, no current source backup exists, or WAL continuity cannot be proven.
Otherwise keep the incident open until DR observability and recoverability are
restored; application health alone does not close it.

## References

- [Database disaster recovery](../../../databases/disaster-recovery.md)
- [CNPG DR replica bootstrap](../../../databases/runbooks/cnpg-dr-replica-bootstrap.md)
- [PostgreSQL runbooks](README.md)

---

_Last updated: 2026-09-14 — added explicit coverage for complete DR-cluster
absence and separated it from standby-streaming failures._
