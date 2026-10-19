# CNPGDefaultPrivilegesDrift

| | |
|---|---|
| **Severity** | critical |
| **Source** | [`role-membership-alerts.yaml`](https://github.com/duynhlab/helm-charts/blob/main/charts/vm-rules/bundles/postgres/role-membership-alerts.yaml) ([ADR-088](../../../proposals/adr/ADR-088-platform-owns-database-authorization/)) |
| **Clusters** | `platform-db` |
| **Custom query** | `pg_default_privileges` ([`monitoring-queries.yaml`](../../../../kubernetes/infra/configs/databases/clusters/platform-db/configmaps/monitoring-queries.yaml)), per database in `target_databases` |
| **Guarded entries** | per database `<svc>`: tables `<svc>_runtime=arwd/<svc>_owner`, sequences `<svc>_runtime=rU/<svc>_owner` (schema `public`), functions `<svc>_owner=X/<svc>_owner` with no PUBLIC entry (global) |

## Meaning

Fires when `cnpg_pg_default_privileges_drift` is 1 for **15 minutes**: the
owner's default privileges for an object type (`objtype`: `r` table, `S`
sequence, `f` function) in that database are missing or are not exactly the
declared set. The role catalog CronJob (Job-owned databases) or the pgroles
policy restores them; a drift that outlives them means the reconciler is
failing.

## Impact

- Missing table/sequence entry: the next migration's tables are unreadable by
  the runtime; the service fails on its new feature.
- Extra rights (for example `TRUNCATE`, `D`): the runtime gets more than CRUD
  on every future table.
- Function entry missing or PUBLIC present: every new function is executable by
  every login.

## Diagnosis

```bash
PRIMARY="$(kubectl get pod -n platform \
  -l cnpg.io/cluster=platform-db,role=primary \
  -o jsonpath='{.items[0].metadata.name}')"
```

```bash
kubectl exec -n platform "$PRIMARY" -c postgres -- psql -U postgres -d <svc> -c \
  "SELECT pg_get_userbyid(defaclrole), defaclnamespace::regnamespace, defaclobjtype, defaclacl FROM pg_default_acl;"
kubectl -n platform get cronjob,jobs -l app.kubernetes.io/name=platform-db-authz
```

## Mitigation

Re-run the catalog (Job-owned databases):

```bash
kubectl -n platform create job --from=cronjob/platform-db-authz authz-manual-$(date +%s)
kubectl -n platform logs -f -l job-name=authz-manual-<suffix>
```

For a pgroles-owned database, read the policy's status and its latest plan
(`kubectl -n platform get postgrespolicy,postgrespolicyplan`).

## Escalation

Extra rights or a PUBLIC `EXECUTE` default are an access change; find who made
it before closing.
