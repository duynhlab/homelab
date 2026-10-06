# CNPGRoleMembershipGuardMissing

| | |
|---|---|
| **Severity** | warning |
| **Source** | [`role-membership-alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/role-membership-alerts.yaml) ([ADR-086](../../../proposals/adr/ADR-086-guard-membership-options/)) |
| **Clusters** | `platform-db` |
| **Custom query** | `pg_role_membership` ([`monitoring-queries.yaml`](../../../../kubernetes/infra/configs/databases/clusters/platform-db/configmaps/monitoring-queries.yaml)) |

## Meaning

`cnpg_pg_role_membership_drift` has had no series for `vault_rotator →
notification` on `platform-db` for **15 minutes**. The query returns a row for
every guarded edge even when the edge is revoked, so a missing series means the
guard is not running. While this fires,
[`CNPGRoleMembershipDrift`](CNPGRoleMembershipDrift.md) cannot fire.

## Diagnosis

1. Is the cluster scraped at all? `CNPGClusterOffline` or a missing
   `cnpg_collector_up{cnpg_io_cluster="platform-db"}` explains this alert.
2. Is the query loaded? The ConfigMap `platform-db-monitoring-queries` (ns
   `platform`) must contain `pg_role_membership`, and the `Cluster` must list it
   under `monitoring.customQueriesConfigMap`.
3. Did the query fail? The instance manager logs the error:

   ```bash
   kubectl logs -n platform -l cnpg.io/cluster=platform-db -c postgres --since=30m \
     | grep -i pg_role_membership
   ```

   A SQL error usually means an edited `VALUES` list. Run the query by hand on
   the primary (`psql -U postgres -d postgres`) to see the error.
4. Was the edge renamed? The alert selects `member="vault_rotator",
   parent="notification"`. When the guarded edge list changes, update the
   `absent()` selector in the same PR.

## Mitigation

Fix the query or the ConfigMap in Git and reconcile `databases-local`. The CNPG
exporter reloads queries without a restart (`cnpg.io/reload`).

---
_Last updated: 2026-10-06 — first version (ADR-086)._
