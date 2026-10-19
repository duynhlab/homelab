# CNPGAuthorizationGuardMissing

| | |
|---|---|
| **Severity** | warning |
| **Source** | [`role-membership-alerts.yaml`](https://github.com/duynhlab/helm-charts/blob/main/charts/vm-rules/bundles/postgres/role-membership-alerts.yaml) ([ADR-088](../../../proposals/adr/ADR-088-platform-owns-database-authorization/)) |
| **Clusters** | `platform-db` |
| **Custom queries** | `pg_role_config`, `pg_default_privileges` ([`monitoring-queries.yaml`](../../../../kubernetes/infra/configs/databases/clusters/platform-db/configmaps/monitoring-queries.yaml)) |

## Meaning

Fires when a series the authorization guards always emit has been absent for
**15 minutes**: `cnpg_pg_role_config_drift` for a guarded role, or
`cnpg_pg_default_privileges_drift` for one of a guarded database's three object
types. The queries return one row per expected value even when it drifts, so a
missing series means the query, the ConfigMap or the exporter is broken, or a
guarded database does not exist.

## Impact

None on traffic. Drift of a migrator's `role=` or an owner's default privileges
would go unseen ([`CNPGRoleConfigDrift`](CNPGRoleConfigDrift.md),
[`CNPGDefaultPrivilegesDrift`](CNPGDefaultPrivilegesDrift.md) cannot fire).

## Diagnosis

```promql
count by (role) (cnpg_pg_role_config_drift)
count by (datname, objtype) (cnpg_pg_default_privileges_drift)
```

Then read the instance logs for query errors:

```bash
kubectl logs -n platform -l cnpg.io/cluster=platform-db,role=primary -c postgres \
  | grep -i 'pg_role_config\|pg_default_privileges'
```

A database listed in `target_databases` that CNPG has not created yet (its
owner does not exist) also leaves its rows absent: check the `Database` object
and the catalog Job.

## Mitigation

Fix the query or the ConfigMap in Git; never remove the `absent()` clause to
silence the alert.

## Escalation

Working hours: the guard is blind, nothing is broken yet.
