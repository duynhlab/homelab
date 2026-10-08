# CNPGRoleMembershipDrift

| | |
|---|---|
| **Severity** | critical |
| **Source** | [`role-membership-alerts.yaml`](../../../../kubernetes/infra/configs/observability/metrics/prometheusrules/postgres/role-membership-alerts.yaml) ([ADR-086](../../../proposals/adr/ADR-086-guard-membership-options/)) |
| **Clusters** | `platform-db` |
| **Custom query** | `pg_role_membership` ([`monitoring-queries.yaml`](../../../../kubernetes/infra/configs/databases/clusters/platform-db/configmaps/monitoring-queries.yaml)) |
| **Guarded edges** | `vault_rotator → notification_runtime` = `ADMIN TRUE, INHERIT FALSE, SET FALSE` |

## Meaning

Fires when `cnpg_pg_role_membership_drift` is 1 for **5 minutes**. A guarded
membership is missing, or its `ADMIN`, `INHERIT` or `SET` option differs from the
shape written in the query. CNPG `DatabaseRole.inRoles` models only the
membership's name: if CNPG recreates it, PostgreSQL defaults apply
(`ADMIN FALSE, INHERIT TRUE, SET TRUE`), and CNPG never checks the catalog
afterwards.

## Impact

For `vault_rotator → notification_runtime`:

- **`ADMIN` lost, or the edge revoked:** OpenBAO can no longer rotate
  notification's password. The current credential keeps working; the next
  rotation fails.
- **`INHERIT` or `SET` gained:** the rotation administrator can read and write
  notification's data, which the edge is shaped to prevent.

## Diagnosis

### PromQL

```promql
# Which edge, and which option
max by (cnpg_io_cluster, member, parent) (cnpg_pg_role_membership_drift)
max by (member, parent) (cnpg_pg_role_membership_present)
max by (member, parent) (cnpg_pg_role_membership_admin_option)
max by (member, parent) (cnpg_pg_role_membership_inherit_option)
max by (member, parent) (cnpg_pg_role_membership_set_option)
```

### psql

```bash
PRIMARY="$(kubectl get pod -n platform \
  -l cnpg.io/cluster=platform-db,role=primary \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n platform "$PRIMARY" -c postgres -- psql -U postgres -d postgres -c "
SELECT member.rolname AS member, parent.rolname AS parent,
       grantor.rolname AS grantor,
       m.admin_option, m.inherit_option, m.set_option
  FROM pg_auth_members m
  JOIN pg_roles member  ON member.oid  = m.member
  JOIN pg_roles parent  ON parent.oid  = m.roleid
  JOIN pg_roles grantor ON grantor.oid = m.grantor
 WHERE member.rolname = 'vault_rotator';"
```

PostgreSQL 16+ keeps one row per grantor. The query ORs the options across rows,
because any one grant is enough to confer the option.

Before repairing, find out why it drifted. Check whether a `DatabaseRole` was
recreated (`kubectl get databaserole -n platform`, events) or a manual `GRANT`
was run (the PostgreSQL log on the primary).

## Mitigation

Restore the specified shape on the primary as `postgres`:

```bash
kubectl exec -n platform "$PRIMARY" -c postgres -- psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -c \
  "GRANT notification_runtime TO vault_rotator WITH INHERIT FALSE, SET FALSE, ADMIN TRUE;"
```

If a second grantor's row still carries `INHERIT` or `SET`, revoke that grant:
`REVOKE notification_runtime FROM vault_rotator GRANTED BY <grantor>`. Then run the
`GRANT` above again. The alert resolves within one scrape plus 5 minutes.

If `ADMIN` was missing for a while, check that notification rotation still
works: step 3 of [Rotate the `vault_rotator` credential](../../../databases/runbooks/rotate-vault-rotator-credential.md#verification).

## Escalation

- Gained `INHERIT` / `SET`: treat it as a security incident. Find who changed it,
  then review notification data access in the PostgreSQL audit log.
- Lost `ADMIN`: restore it in working hours; rotation is paused, not broken for
  traffic.
