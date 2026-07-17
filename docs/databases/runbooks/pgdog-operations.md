# PgDog Operations Runbook

Day-2 operations for the PgDog connection poolers — status checks, rotations, backend changes, and the failure modes we have actually hit.

| Fact | Value |
|------|-------|
| Releases | `pgdog-platform` (platform ns), `pgdog-product` (product ns) — one per operational CNPG cluster |
| Chart | `pgdog` `v0.39` from the `pgdogdev` HelmRepository (flux-system) |
| Ports | `6432` SQL, `9090` openmetrics (`pgdog_` prefix) |
| Topology | 3 replicas, soft anti-affinity, PDB `minAvailable: 2` |
| Pool mode | `transaction`; R/W splitting: SELECTs → `-r` replicas, writes → `-rw` primary; LSN lag monitoring bans lagging replicas |
| Credentials | Injected per-user via HelmRelease `spec.valuesFrom` targetPath from the per-service ESO Secrets (ADR-014) — never in values |

Concept and trade-off background lives in [008-pooler.md](../008-pooler.md); this page is purely operational.

## Health & status

```bash
kubectl get pods -n platform -l app.kubernetes.io/name=pgdog        # pgdog-platform 3/3 Running
kubectl get pods -n product -l app.kubernetes.io/name=pgdog        # pgdog-product 3/3 Running
kubectl logs -n platform deploy/pgdog-platform --tail=50             # bans, auth errors
kubectl logs -n product deploy/pgdog-product --tail=50
flux get helmrelease pgdog-platform -n platform                      # reconcile state
flux get helmrelease pgdog-product -n product
```

Metrics (VictoriaMetrics, scraped via the chart's ServiceMonitor at 15s):

```promql
{__name__=~"pgdog_.*"}                   # everything the pooler exports
group by (__name__) ({__name__=~"pgdog_.*"})   # discover the series names
```

Watch pool saturation (clients vs servers per database) and error counters —
a sudden error spike is almost always auth (see rotation below) or a banned
backend.

A replica ban shows in the logs (`banned replica`) and as traffic concentrating on the primary; bans lift automatically once the replica's LSN catches up (checked every `lsnCheckInterval: 5000` ms).

## Rotate a service password

Order matters — the pooler learns passwords only at Helm reconcile time:

1. Rotate in OpenBAO, let ESO refresh the Secret (or force: `kubectl annotate externalsecret <name> force-sync=$(date +%s) -n <ns>`). Full CNPG-side procedure: [rotate-cnpg-service-password.md](rotate-cnpg-service-password.md).
2. **`flux reconcile helmrelease pgdog-<cluster> -n <ns>`** — helm-controller re-reads `valuesFrom` only on reconcile; skipping this leaves PgDog authenticating with the old password and every new app connection failing.
3. Verify: `kubectl logs … | grep -i auth` goes quiet; `pgdog_errors_total` flattens.

## Add a database backend (new service)

The full new-service flow (triplet, HBA, seeds) is [add-service-database.md](add-service-database.md); the PgDog slice of it:

1. In the cluster's `poolers/helmrelease.yaml`: append a `databases:` entry (primary `-rw`, replica `-r`) **and** a `users:` entry, then a `valuesFrom` block with `targetPath: "users[N].password"`.
2. **Indices are positional** — `users[N]` must match the position in `values.users`. Keep the header comment (`[0]=product, …`) true; a mismatched index silently wires service A's password to service B's user, which surfaces as auth failures for BOTH.
3. `make validate`, merge, reconcile. The rollout restarts pooler pods; with 3 replicas + PDB 2 the restart is rolling, but in-flight transactions on the drained pod are cut — sequence with deploys, not during load tests.

## Known failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| New connections fail after a password rotation | `valuesFrom` read at reconcile time only | `flux reconcile helmrelease pgdog-<cluster>` (step 2 above) |
| Auth failures for two services at once after adding a backend | positional `users[N]` mismatch | re-align `valuesFrom` targetPath indices with `values.users` order |
| App migrations hang in Init | migrations connect **direct** to `<cluster>-rw:5432`, not the pooler — NetworkPolicy must admit the app namespace to 5432 | check the cluster namespace's netpol app-services rule |
| Payment errors that look pooler-related | payment doesn't use PgDog — it connects direct over TLS (`sslmode=require`) because PgDog terminates no TLS yet | debug against `product-db-rw:5432`, not `pgdog-product` |
| `up{job=~"pgdog.*"}` empty | ServiceMonitor scrape broken | `kubectl get servicemonitor -n <ns>`; port 9090 must be admitted from the monitoring namespace in the netpol |

## References

- [008-pooler.md](../008-pooler.md) — architecture, PgBouncer/PgCat comparison (neither deployed)
- [add-service-database.md](add-service-database.md), [rotate-cnpg-service-password.md](rotate-cnpg-service-password.md)
- PgDog docs: https://docs.pgdog.dev/

---
_Last updated: 2026-07-17 — Added pgdog-platform (RFC-0018); product tier unchanged._
