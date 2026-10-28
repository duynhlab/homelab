# PostgreSQL / CNPG

The highest-stakes domain. Availability and integrity incidents diverge, and
the wrong recovery replicates a bad write.

## Authoritative docs

- Symptom → metric → SQL → runbook: [databases/observability-and-troubleshooting.md](../../../../../docs/databases/observability-and-troubleshooting.md).
- **Start here when it's down**: [emergency-recovery.md](../../../../../docs/databases/runbooks/emergency-recovery.md).
- Procedural runbooks (backup, pooler, rotation, DR bootstrap, maintenance):
  [databases/runbooks/README.md](../../../../../docs/databases/runbooks/README.md).
- Per-alert CNPG/PgDog: [postgresql runbooks](../../../../../docs/observability/runbooks/postgresql/README.md).
- Plan regression ("10× slower — what plan ran?"):
  [plan-regression-investigation.md](../../../../../docs/observability/runbooks/postgresql/plan-regression-investigation.md).

## Manifests

- `kubernetes/infra/configs/databases/` (CNPG `Cluster`s: `platform-db`,
  `product-db`, DR `product-db-replica`; PgDog; Barman).

## Diagnose (read-only first)

```bash
kubectl get cluster,backup,scheduledbackup -n <ns>
kubectl cnpg status <cluster> -n <ns>        # health, replication, backup
kubectl get pods -n <ns> -l cnpg.io/cluster=<cluster>
make db-isolation                            # pg_hba isolation sweep
```

Interactive SQL only with the bounded session header from
[triage-and-safety § PostgreSQL session header](../triage-and-safety.md#postgresql-interactive-session-header).
Distinguish pool saturation vs lock contention vs I/O vs CPU vs maintenance
debt using the evidence table in the troubleshooting guide — do not start with
failover or `max_connections`.

## The one decision that matters

**Availability** (something is down) or **integrity** (the data is wrong)?

- Availability → HA failover / DR promotion (CNPG usually self-heals; sync
  quorum `ANY 1` makes acknowledged commits RPO-0).
- Integrity → **do not fail over or promote** — the bad WAL already reached
  every standby. Only **PITR** to a new cluster undoes it.

## Boundary

Failover, promotion, PITR, and live `Cluster` edits are **incident-only, IC
go/no-go** ([triage-and-safety](../triage-and-safety.md#approval-gates)). The
manifests are Flux-owned: commit, or `flux suspend` the DR Kustomization before
a live edit and reconcile the commit after.
