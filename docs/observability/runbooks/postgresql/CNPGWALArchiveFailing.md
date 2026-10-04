# CNPGWALArchiveFailing

| | |
|---|---|
| **Severity** | critical |
| **Source** | deep-signal |
| **Clusters** | `platform-db`, `product-db` |
| **Custom queries** | — (built-in `cnpg_pg_stat_archiver_*`) |
| **Grafana** | CloudNativePG Cluster Overview |

> **The rule compares timestamps, not counts.** As of 2026-10-04 the expression
> is `cnpg_pg_stat_archiver_last_failed_time > cnpg_pg_stat_archiver_last_archived_time`.
> The previous `increase(failed_count[30m]) > 0 and increase(archived_count[15m]) == 0`
> paged after a pod restart over a failure two days old: the restarted pod's series
> is re-born at `failed_count = 1`, and VictoriaMetrics' `increase()` counts a small
> re-born counter from 0. Timestamps carry no such history. If this alert fires,
> archiving is stuck now.

## Meaning

For **5 minutes**, the archiver's most recent `archive_command` attempt
(Barman/cloud plugin) has failed and nothing has been archived since. Postgres
retries the same segment until it succeeds. A one-off failure is therefore
followed within seconds by a success that moves `last_archived_time` past
`last_failed_time`, and clears the alert long before the 5 minutes run out. A
quiet cluster never pages: both timestamps read `-1` until the first archive or
failure, and silence changes neither.

**Expect a delay of about 5 minutes** (the debounce, plus a scrape) after
archiving stops. `pg_wal` is already growing by then, so check free space early
(Diagnosis step 3).

### Verified at runtime (2026-08-07, previous rule)

This drill exercised the `increase()` expression that the timestamp rule replaced;
the latency it measured belongs to that rule. Injected by scaling the RustFS object store to zero replicas for 19 minutes and
forcing two WAL switches, then restoring it. The full cycle behaved as designed:

| Time (UTC) | Observation |
|---|---|
| 15:39:49 | Baseline: `platform-db` 17 archived / **0** failed; `product-db` 18 / **0** |
| 15:40:13 | RustFS scaled 1 → 0 |
| 15:40:33 | Two `pg_switch_wal()` on `product-db` → `failed_count` **0 → 1** within seconds |
| 15:52:19 | `increase(archived_count[15m])` reached **0** → alert **pending** on both clusters |
| 15:58:06 | `product-db` → **firing** (its arms matured first) |
| 15:58:16 | `platform-db` genuinely at **36** failures on WAL `…000F` — a segment was in flight when the store vanished, so its page is a true positive, not collateral |
| 15:58:56 | RustFS scaled back to 1; Ready at 15:59:11 (15s) |
| 15:59:18 / 15:59:57 | Both clusters archiving again, backlog drained (17→21, 18→23) |
| ~16:03 | Alert **resolved** — zero rows; `increase(archived_count[15m])` back to 5 |

Two things worth carrying into an incident. **The alert cannot be trusted to
appear promptly** — 18 minutes elapsed between the store dying and the page.
And **the other RustFS writers survived the same outage untouched** — at the time
those were Tempo and Pyroscope, neither of which restarted across 19 minutes,
because they hold their buckets open and write periodically. A crash-looping
writer means a *missing bucket*, not an unreachable store. Do not use a writer's
health as a proxy for object-store health. Tempo has since been retired
([RFC-0027](../../../proposals/rfc/RFC-0027/README.md)), so **Pyroscope and Barman
are the remaining writers** — the lesson is unchanged, there is just one fewer
signal to misread.

## Impact

WAL segments accumulate in `pg_wal`; PITR and base backups become unreliable.
`PostgresBackupTooOld` may still look healthy while archiving is broken — this
alert closes that gap.

## Rule out a switchover first

**A planned promotion makes exactly one archive fail.** The newly promoted primary
fails to archive its timeline history file once. Archiving then succeeds and moves
`last_archived_time` past the failure, so the alert should not fire. If it does
fire around a switchover, confirm it is not that artefact before treating it as
breakage.

```bash
kubectl exec -n "$NAMESPACE" "${CLUSTER}-<primary>" -c postgres -- psql -U postgres -tAc \
  "select archived_count, failed_count, last_failed_wal, last_failed_time from pg_stat_archiver;"
kubectl get cluster "$CLUSTER" -n "$NAMESPACE" \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}'
```

It is the benign case when **all** of these hold:

- `last_failed_wal` ends in `.history` (e.g. `00000002.history`), not a WAL segment;
- `last_failed_time` sits inside a promotion window;
- `archived_count` is still advancing;
- the cluster's `ContinuousArchiving` condition is `True`.

Measured on 2026-08-06 during
[drill DR-2026-08-B](../../../proposals/rfc/RFC-0021/gameday.md#g3--cnpg-switchover-under-load):
`failed_count = 1`, `last_failed_wal = 00000002.history`, 9 s after the promote,
with `ContinuousArchiving: True` and `LastBackupSucceeded: True` throughout.
Real archive breakage looks different — `failed_count` keeps climbing and
`last_failed_wal` names a segment.

## Diagnosis

### PromQL

```promql
cnpg_pg_stat_archiver_last_failed_time > cnpg_pg_stat_archiver_last_archived_time
cnpg_pg_stat_archiver_seconds_since_last_archival
cnpg_collector_pg_wal_archive_status{status="ready"}
```

### kubectl

```bash
kubectl get cluster,backup,scheduledbackup -n "$NAMESPACE"
kubectl logs -n "$NAMESPACE" "${CLUSTER}-1" -c postgres --tail=100 | grep -i archive
kubectl get objectstore -n "$NAMESPACE"
```

See [backup-restore.md](../../../databases/runbooks/backup-restore.md)
for Barman/RustFS connectivity checks.

## Mitigation

1. Verify object store (RustFS) reachable from cluster namespace.
2. Check Barman plugin / CNPG backup credentials (ESO secrets).
3. Retry failed backup job; confirm `last_archived_wal` advances in logs.
4. Monitor [PostgresWALSizeHigh.md](PostgresWALSizeHigh.md) while fixing archive.

## Escalation

**P1** — page if archiving fails >1h or WAL directory grows rapidly. PITR window
at risk.
