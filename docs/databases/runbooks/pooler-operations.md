# Pooler Operations Runbook

Day-2 operations for the connection poolers — status checks, rotations, backend
changes, and the failure modes we have actually hit.

The platform runs **two different poolers**, on purpose (ADR-026): PgDog in front
of `product-db`, and the CloudNativePG-native `Pooler` (PgBouncer) in front of
`platform-db`. Most of this page is PgDog; the PgBouncer section at the end
covers what differs.

| Fact | Value |
|------|-------|
| PgDog release | `pgdog-product` (product ns) — fronts `product-db` |
| PgBouncer pooler | `platform-db-pooler-rw` (platform ns, CNPG `Pooler`) — fronts `platform-db`; see [PgBouncer pooler](#pgbouncer-pooler-platform-db) |
| Chart | `pgdog` `v0.39` from the `pgdogdev` HelmRepository (flux-system) |
| Ports | `6432` SQL, `9090` openmetrics (`pgdog_` prefix) |
| Topology | 3 replicas, soft anti-affinity, PDB `minAvailable: 2` |
| Pool mode | `transaction`; R/W splitting: SELECTs → `-r` replicas, writes → `-rw` primary; LSN lag monitoring bans lagging replicas |
| Credentials | Injected per-user via HelmRelease `spec.valuesFrom` targetPath from the per-service ESO Secrets (ADR-014) — never in values |

Concepts, trade-offs, and deployed topology live in [poolers.md](../poolers.md);
this page is purely operational.

## Health & status

```bash
kubectl get pods -n product -l app.kubernetes.io/name=pgdog        # pgdog-product 3/3 Running
kubectl logs -n product deploy/pgdog-product --tail=50             # bans, auth errors
flux get helmrelease pgdog-product -n product                      # reconcile state
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

- [poolers.md](../poolers.md) — architecture, pooling semantics, and PgBouncer/PgDog comparison
- [add-service-database.md](add-service-database.md), [rotate-cnpg-service-password.md](rotate-cnpg-service-password.md)
- PgDog docs: https://docs.pgdog.dev/

## PgBouncer pooler (platform-db)

`platform-db` pools through the CloudNativePG-native `Pooler`
**`platform-db-pooler-rw`** instead of PgDog (ADR-026 pilot). It is a different
tool with different day-2 mechanics — do not carry PgDog habits across.

| Fact | Value |
|------|-------|
| Object | `Pooler/platform-db-pooler-rw` (namespace `platform`) — a CRD the CNPG operator owns, **not** a HelmRelease |
| Endpoint | `platform-db-pooler-rw.platform.svc.cluster.local:**5432**` — PgBouncer's default port, not PgDog's 6432 |
| Instances | 2 · pool mode `transaction` · `max_client_conn` 1000 · `default_pool_size` 30 |
| Topology | `type: rw` — **all** traffic to the primary. No read/write split, no replica load-balancing (the pilot's accepted tradeoff) |
| Credentials | None stored. CNPG configures `auth_query`: PgBouncer looks each login up in `pg_shadow` via a generated `user_search` function, authenticating itself with a TLS client certificate |
| Metrics | `enablePodMonitor: true` → the PgBouncer exporter on `:9127` (`pgbouncer_` prefix), scraped by VMAgent |

### Status

```bash
kubectl get pooler -n platform platform-db-pooler-rw
kubectl get pods -n platform -l cnpg.io/poolerName=platform-db-pooler-rw
kubectl logs -n platform -l cnpg.io/poolerName=platform-db-pooler-rw --tail=50
```

There is no `flux get helmrelease` step: the `Pooler` is reconciled by the CNPG
operator from the manifest under
`kubernetes/infra/configs/databases/clusters/platform-db/poolers/`.

### What differs operationally

- **Credential rotation needs no pooler action.** `auth_query` reads `pg_shadow`
  live, so the `ALTER ROLE` is effective immediately — no reconcile, no rollout
  restart, no window where the pooler serves a stale password. Contrast the
  PgDog path in
  [rotate-cnpg-service-password.md](./rotate-cnpg-service-password.md).
- **Backend changes are the `Cluster`'s business.** PgBouncer follows the
  `-rw` service, so a failover repoints automatically; there is no backend list
  to edit.
- **No replica routing to reason about.** A read-heavy platform service cannot
  be steered at the pooler — it would need its own `type: ro` Pooler, which the
  pilot deliberately did not add.
- **Restarting is safe and cheap** (`kubectl rollout restart deploy -n platform
  -l cnpg.io/poolerName=platform-db-pooler-rw`) but is rarely the fix, precisely
  because there is no cached config to clear.

---
_Last updated: 2026-08-07 — ADR-026: `pgdog-platform` removed; `platform-db` now
pools through the CNPG PgBouncer `Pooler` `platform-db-pooler-rw`, documented in
its own section. The PgDog content applies to `product-db` only._
