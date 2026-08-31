# Restore & Failover Drills

Child playbook of the [PostgreSQL Disaster Recovery Plan](../disaster-recovery.md). The DRP
defines *what* recovery looks like and the
[evidence checklist](../disaster-recovery.md#compliance-and-evidence-checklist); this page
defines *how often* we rehearse, *who* runs it, and *what proof* each run leaves
behind. A backup you have never restored is a hypothesis, not a backup — these
drills are the only thing that turns the estimated RTOs in
[reliability targets](../reliability-targets.md) into measured ones.

It is the canonical owner of drill cadence, roles, procedures, and sign-off
records.

## Drill calendar

| Drill | Cadence | Target cluster | Proves | RTO SLO |
|-------|---------|----------------|--------|---------|
| **A — Restore-test (PITR to throwaway)** | Monthly | `product-db` | Backups + WAL are actually restorable; PITR works | ≤ 30 min to validated throwaway |
| **B — Planned switchover** | Monthly | `product-db` | HA failover path + app reconnect | ≤ 1 min |
| **C — DR promotion rehearsal** | Quarterly | `product-db-replica` | Whole-cluster-loss recovery | ≤ 30 min |
| **D — Restore-test (platform-db)** | Quarterly | `platform-db` | Barman restore-to-new-cluster works for the consolidated platform cluster | ≤ 30 min to validated throwaway |

Each run produces one [evidence record](#evidence-log-template). A drill with no
recorded evidence did not happen.

## Roles (per [disaster-recovery.md ownership](../disaster-recovery.md#ownership))

| Role | Responsibility during a drill |
|------|-------------------------------|
| Incident commander | Schedules the drill, owns the timeline, gives go/no-go |
| Database recovery owner | Executes restore/promotion commands, captures timings |
| Service owner | Runs the app smoke test against the recovered cluster |
| Security owner | Confirms restore used the read-only/restore identity, reviews access |

## Drill A — Restore-test (monthly)

Restore to a **throwaway** cluster, never over the live one. This is the canonical
proof that `s3://pg-backups-cnpg/product-db/` is restorable.

1. **Mark the start** and pick a target time before a known test write:
   ```bash
   date -u +%Y-%m-%dT%H:%M:%SZ           # drill start — record it
   ```
   Then take the plugin-backed on-demand backup that makes this the Barman
   acceptance gate — **the method flags are mandatory**, the plugin CLI defaults
   to the in-tree method and fails on these clusters:
   ```bash
   kubectl cnpg backup product-db -n product \
     --method plugin --plugin-name barman-cloud.cloudnative-pg.io
   ```
2. **Create a PITR restore cluster** from the checked-in example, adding a
   `recoveryTarget`:
   ```yaml
   bootstrap:
     recovery:
       source: product-db-backup
       recoveryTarget:
         targetTime: "2026-06-19 03:00:00+00"   # just before the test write
   ```
   ```bash
   kubectl apply -f kubernetes/infra/configs/databases/clusters/product-db/restore-cluster-example.yaml
   kubectl get cluster -n product -w
   ```
   The example carries `postgresql.parameters` (WAL sizing) on purpose — see the
   [restore runbook](./backup-restore.md#restore-to-a-new-cluster):
   omitting them makes Postgres refuse to start on a cluster whose data
   directory uses 64MB WAL segments.
3. **Wait for healthy**, then **validate** (schema + critical row counts):
   ```bash
   kubectl exec -it product-db-restore-1 -n product -- psql -U product -d product -c "\dt"
   kubectl exec -it product-db-restore-1 -n product -- psql -U product -d product -c "SELECT count(*) FROM products;"
   ```
4. **App smoke test** against the restored cluster (service owner).
5. **Record** start/end, backup ID, target timestamp, measured RTO/RPO in the
   [evidence log](#evidence-log-template).
6. **Tear down only after evidence is captured:**
   ```bash
   kubectl delete cluster product-db-restore -n product
   ```

Full command reference: [Backup and restore](./backup-restore.md).

## Drill B — Planned switchover (monthly)

Rehearses the HA path without an outage. Requires the CNPG plugin.

```bash
kubectl cnpg status product-db -n product              # note current primary
kubectl cnpg promote product-db product-db-2 -n product  # promote a replica, demote primary
kubectl cnpg status product-db -n product              # confirm new primary, 3/3 ready
```

There is **no `kubectl cnpg switchover`** — the plugin (v1.30.0) exposes
`promote <cluster> <instance>` and nothing else for this, so the instance to
promote is named explicitly. `switchover` returns
`Error: unknown command "switchover"`, found by
[drill DR-2026-08-B](../../proposals/rfc/RFC-0021/gameday.md#0102-evidence-record).

Then confirm PgDog still routes and the app reconnects cleanly (service owner).
Record the observed cut-over time against the **≤ 1 min** SLO. Measure it with a
write probe rather than the cluster `phase`: on the recorded run the phase
reported `healthy` at +30.5 s while writes had already recovered at +12.2 s.

## Drill C — DR promotion rehearsal (quarterly)

Rehearses recovery from **whole-cluster loss** using `product-db-replica`. Do **not**
promote the live DR target during a routine drill — rehearse against a restored
copy so the real DR replica keeps following the primary. Go/no-go first
(see [disaster-recovery.md](../disaster-recovery.md#dr-promotion-outline)):

- Primary cluster confirmed down or intentionally frozen — no split-brain risk.
- DR replica replay point is within the incident RPO.
- Incident commander approval.

Promotion is a manifest change (the replica cluster stops recovery and becomes
read-write):

```yaml
spec:
  replica:
    enabled: false     # changed from true → triggers promotion
```
```bash
kubectl cnpg status product-db-replica -n product    # expect: Primary, accepting connections
```

Then cut PgDog over to `product-db-replica-rw.product.svc.cluster.local` and smoke
test. Record measured RTO/RPO.

## Drill D — Restore-test for platform-db (quarterly)

Restore `platform-db` into a **throwaway** cluster from its Barman
Cloud Plugin backup (`s3://pg-backups-cnpg/platform-db/`)
and validate — same CNPG PITR flow as Drill A, only the source `ObjectStore` and
namespace differ. Platform-db has per-cluster CNPG backup/HA alerting
(`cnpg-platform-db/` PrometheusRules), so this drill confirms the
backups are restorable rather than being their only health signal.

## Evidence log template

Copy one block per drill into the drill record. This is the artifact the
[disaster-recovery.md evidence checklist](../disaster-recovery.md#compliance-and-evidence-checklist)
asks for.

| Field | Value |
|-------|-------|
| Drill ID | `DR-2026-06-A` |
| Date / operator | 2026-06-19 / `<recovery owner>` |
| Drill type | A / B / C / D |
| Cluster + namespace | `product-db` / `product` |
| Backup ID + completion time | |
| Recovery target (timestamp/LSN) | |
| Start → end (UTC) | |
| **Measured RTO** | |
| **Measured/estimated RPO** | |
| Schema validation | pass / fail |
| Row-count validation | pass / fail |
| App smoke test | pass / fail |
| Deviations & follow-ups | |
| Sign-off (IC) | |


### `DR-2026-08-A` — Drill A, product-db PITR (the Barman acceptance gate)

| Field | Value |
|-------|-------|
| Drill ID | `DR-2026-08-A` |
| Date / operator | 2026-08-07 / owner (`duynhne`) held IC, recovery, service and security roles; executed by agent under the debt-clearing program grant |
| Drill type | A — PITR restore-test |
| Cluster + namespace | `product-db` / `product` (restored into throwaway `product-db-restore`) |
| Backup ID + completion time | `product-db-20260807172544` (plugin method), started 10:25:45Z, **completed 10:53:08Z** |
| Recovery target (timestamp/LSN) | `2026-08-07 10:22:05+00` — between two marker rows written 6 s apart |
| Start → end (UTC) | drill 10:22:01Z → validated 11:15:00Z; **restore attempt 2**: applied 11:12:36Z → healthy 11:14:48Z |
| **Measured RTO** | **2 m 12 s** to a validated throwaway (SLO ≤ 30 min). The two preceding steps are not RTO: the on-demand backup took ~27 min, and attempt 1 failed on a manifest defect (below) |
| **Measured/estimated RPO** | 0 for the requested target — WAL replay stopped exactly at it |
| Schema validation | **pass** — 4 tables (`categories`, `products`, `schema_migrations`, `drill_marker`) |
| Row-count validation | **pass** — `products` = 1 on both sides; `drill_marker` contained ONLY `before-target`, the row written 3 s AFTER the target was correctly absent |
| App smoke test | **pass** (indirect) — the source cluster served the full checkout funnel before and after the drill; the throwaway is not wired to services by design |
| Deviations & follow-ups | Two defects found and fixed in [#704](https://github.com/duynhlab/homelab/pull/704): (1) `restore-cluster-example.yaml` carried no `postgresql.parameters`, so the restore took CNPG's default `min_wal_size` (80MB) against the data directory's 64MB WAL segments and Postgres refused to start — `FATAL: "min_wal_size" must be at least twice "wal_segment_size"`, cluster `unrecoverable` (attempt 1, 10:54:29Z → 11:08:50Z); (2) `kubectl cnpg backup <cluster>` defaults to `barmanObjectStore` and fails on a plugin-backed cluster (`cluster has no backup section`) — the plugin flags are mandatory. Both artifacts had never been exercised before this drill. Base backup selection was correct: the last backup before the target (`20260807T091421`) plus WAL replay |
| Sign-off (IC) | pending owner review on the PR that adds this record |

**Gate outcome: the Barman Cloud Plugin is production-accepted.** A plugin-backed
on-demand backup and a PITR restore from it are both recorded. The retention hold
it carried does not apply on this platform: the Kind cluster and its RustFS bucket
are rebuilt by every `make up`, and the bucket holds only plugin-era prefixes
(`pg-backups-cnpg/{product-db,platform-db,product-db-replica}/`) — there is no
surviving in-tree prefix to retire. The hold stays meaningful for a durable store,
which arrives with the bare-metal migration ([RFC-0011](../../proposals/rfc/RFC-0011/)).

## Where evidence lives

Until a dedicated drill log exists, append completed records to the DRP's
evidence trail and link them from the PR that schedules the drill. Recording
drills as recurring evidence is an open item in
[disaster-recovery.md → Known Gaps](../disaster-recovery.md#known-gaps-and-next-improvements).

### Completed records

| Drill ID | Type | Date | Cluster | Measured RTO | Record |
|----------|------|------|---------|--------------|--------|
| `DR-2026-08-A` | A — PITR restore-test | 2026-08-07 | `product-db` | **2 m 12 s** (SLO ≤ 30 min) | [above](#dr-2026-08-a--drill-a-product-db-pitr-the-barman-acceptance-gate) |
| `DR-2026-08-B` | B — planned switchover | 2026-08-06 | `product-db` | **11.4 s** (SLO `< 30 s`) | [RFC-0021 GameDay § 010.2 evidence record](../../proposals/rfc/RFC-0021/gameday.md#0102-evidence-record) |

Drill B lives inside the RFC-0021 GameDay record because it ran as one of that
RFC's five phase-7 scenarios, alongside four application-saga drills that have no
home in this file. A dedicated cross-domain drill log is still the missing
artifact.

## References

- [disaster-recovery.md](../disaster-recovery.md) — DRP, decision flow, evidence checklist.
- [reliability-targets.md](../reliability-targets.md) — the targets these drills verify.
- [Emergency recovery](./emergency-recovery.md) — the real-incident version of these procedures.
- [Backup and restore](./backup-restore.md) — full backup/restore runbook.

---
_Last updated: 2026-08-31._
