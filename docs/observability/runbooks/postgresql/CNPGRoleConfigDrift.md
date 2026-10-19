# CNPGRoleConfigDrift

| | |
|---|---|
| **Severity** | critical |
| **Source** | [`role-membership-alerts.yaml`](https://github.com/duynhlab/helm-charts/blob/main/charts/vm-rules/bundles/postgres/role-membership-alerts.yaml) ([ADR-088](../../../proposals/adr/ADR-088-platform-owns-database-authorization/)) |
| **Clusters** | `platform-db` |
| **Custom query** | `pg_role_config` ([`monitoring-queries.yaml`](../../../../kubernetes/infra/configs/databases/clusters/platform-db/configmaps/monitoring-queries.yaml)) |
| **Guarded roles** | `review_migrator` = `{role=review_owner}` |

## Meaning

Fires when `cnpg_pg_role_config_drift` is 1 for **15 minutes**: a guarded
migrator is missing, or its session defaults (`pg_roles.rolconfig`) are not
exactly `role=<svc>_owner`. The role catalog CronJob restores the value every
10 minutes, so a drift that outlives two runs means the CronJob is failing or
something rewrites the value faster than it.

## Impact

The migrator no longer becomes the owner at login. The next migration either
fails (it has no rights of its own) or, if someone granted it rights directly,
creates objects owned by the migrator that the runtime cannot use and that the
owner's default privileges never reach.

## Diagnosis

```bash
PRIMARY="$(kubectl get pod -n platform \
  -l cnpg.io/cluster=platform-db,role=primary \
  -o jsonpath='{.items[0].metadata.name}')"
```

```bash
kubectl exec -n platform "$PRIMARY" -c postgres -- psql -U postgres -d postgres -c \
  "SELECT rolname, rolinherit, rolconfig FROM pg_roles WHERE rolname LIKE '%\_migrator';"
kubectl -n platform get cronjob,jobs -l app.kubernetes.io/name=platform-db-authz
```

A failed catalog Job (`KubeJobFailed`) is the usual cause; its log names the
statement. An `ALTER ROLE … RESET` in the PostgreSQL log points at a person.

## Mitigation

Re-run the catalog; it restores `role=`:

```bash
kubectl -n platform create job --from=cronjob/platform-db-authz authz-manual-$(date +%s)
kubectl -n platform logs -f -l job-name=authz-manual-<suffix>
```

The alert resolves on the next scrape after the 15-minute window clears. If the
run fails, fix what its log names (see
[`authorization.md`](../../../databases/authorization.md#the-role-catalog-job)).

## Escalation

An unexplained `rolconfig` change on a migrator is a change to who owns new
objects: find who made it before closing.
