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
| Chart | `pgdog` `v0.92` (PgDog v0.1.61) from the `pgdogdev` HelmRepository (flux-system) |
| Ports | `6432` SQL, `9090` openmetrics (`pgdog_` prefix) |
| Topology | 3 replicas, soft anti-affinity, PDB `minAvailable: 2` |
| Pool mode | `transaction`; every database points at the `-rw` primary only (ADR-089: no automatic read split) |
| Credentials | None stored. Passthrough auth (`enabled_allow_change`, ADR-025): each client's password is checked against PostgreSQL at its first login and cached per replica |

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

## Rotate a service password

PgDog needs no action. Full procedure: [rotate-cnpg-service-password.md](rotate-cnpg-service-password.md).

1. OpenBAO rotates the runtime password itself (`ALTER ROLE` as `vault_rotator`, every 720 h, or now with `bao write -f database/rotate-role/<svc>-runtime`); ESO refreshes the Secret within 15 s and the pod's mounted file follows.
2. No restart. The service's next new connection logs in with the new password, which replaces PgDog's cached copy on that replica (log line `auth: passthrough`); until then that replica still accepts the old password. After a leak, roll PgDog ([emergency rotation](rotate-cnpg-service-password.md#emergency-rotation-credential-exposed)).
3. Verify: `kubectl logs deploy/pgdog-product -n product | grep -i 'is wrong'` stays quiet; `pgdog_errors_total` flattens.

## Rotate the client TLS certificate

`pgdog-product` terminates client TLS with the cert-manager `Certificate`
`pgdog-product-tls` (ClusterIssuer `homelab-ca`, 90 days, renewed 15 days
before expiry). A renewal needs no manual step and **no roll**:

- kubelet updates the mounted Secret in place (no `subPath`), typically within
  a minute.
- The `tls-reload` sidecar (added to the Deployment by the HelmRelease's
  `postRenderers`, with `shareProcessNamespace`) compares the checksum of the
  certificate, `pgdog.toml` and `users.toml` every 30 s and sends PgDog `SIGHUP`
  when any of them changes. The chart has no config checksum annotation, so
  this is also how a HelmRelease config change reaches running pods.
- On `SIGHUP` PgDog re-reads its TLS files (`TLS certificate reloaded` in its
  log). Open sessions keep their handshake; every new one gets the new
  certificate.

To check or force it:

1. `kubectl get certificate pgdog-product-tls -n product` — Ready, with the new `notAfter`. `cmctl renew pgdog-product-tls -n product` forces a renewal.
2. `kubectl logs -n product <pod> -c tls-reload` shows `sent SIGHUP`, and `-c pgdog` shows `TLS certificate reloaded`, on every pod. Pod restart counts stay 0.
3. Verify: the serial PgDog presents (`openssl s_client -starttls postgres -connect <pod IP>:6432 </dev/null | openssl x509 -noout -serial`, from a pod the NetworkPolicy admits) matches the Secret's, on each pod.

If a pod never reloads (the sidecar is down), `kubectl rollout restart
deploy/pgdog-product -n product` picks the certificate up with a drained roll
(below).

Verified on Kind (2026-10-22): a forced renewal under 2 orders/s reached all
three pods within about a minute of the Secret change, each logged one
`TLS certificate reloaded`, fresh handshakes on all three pod IPs presented the
new serial, no container restarted, and no request failed with `57P01`.

## Rolling restarts drain

PgDog has no option to move idle clients off a pod: on `SIGINT` (the image's
stop signal) it sends every idle client `FATAL: PgDog is shutting down
(SQLSTATE 57P01)` and waits up to `shutdown_timeout` (60 s) for clients still
in a transaction. So the clients leave first, as PgDog's upgrade guide
prescribes:

- Each PgDog pod gets a 70-second `preStop` sleep. The Service stops routing
  new connections to it as soon as deletion starts.
- Every client behind PgDog (product, inventory, cart, order, checkout, payment
  and both workers) sets `DB_POOL_MAX_CONN_LIFETIME=45s` and
  `DB_POOL_HEALTH_CHECK_PERIOD=10s`. An idle pgx connection then lives at most
  45 s × 1.1 + 10 s ≈ 60 s, so by `SIGINT` the pool has replaced every
  connection to the stopping pod with one to another pod.
- `terminationGracePeriodSeconds` is 140: the 70 s sleep, the 60 s drain and a
  margin. With 3 replicas and PDB `minAvailable: 2` a restart is rolling, one
  pod at a time; a full roll finishes in about two and a half minutes.
- As a backstop, `pkg/dbx` checks each pooled connection before handing it out
  and replaces one the pooler already closed
  (`pgx_pool_acquire_evictions_total` counts them).

Measured on Kind (2026-10-22, 2 orders/s for 180 s through the edge, dbx
v0.40.1): **0 server 5xx during a roll against 0 at baseline**, 0 evictions, 0
`57P01`. Before this change a roll cost 5–24 failed requests. Two client-side
defects made it worse and are fixed in dbx v0.40.0/v0.40.1: a two-minute
default connect timeout, and an acquire-check peek that could block forever
behind pgconn's background reader and leak the connection. One residual: a
freshly started pod can refuse a first passthrough login (upstream
pgdog#1798); it surfaced once as `pgx_pool_connect_failures_total{error_type="58000"}`
on a worker, with no request failure.

## Add a database backend (new service)

The full new-service flow (triplet, HBA, seeds) is [add-service-database.md](add-service-database.md); the PgDog slice of it:

1. In the cluster's `poolers/helmrelease.yaml`: append a `databases:` entry (primary `-rw` only, no `replicas:`). There is no user list; passthrough auth admits the service's runtime login once PostgreSQL accepts its password.
2. `make validate`, merge, reconcile. The rollout restarts pooler pods one at a time and each drains (above).

## Known failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `password for user … is wrong` about 5 s after connecting | Passthrough: PostgreSQL refused the password while PgDog tried it (`checkout_timeout`) | The app holds an old or wrong password: compare the ESO Secret with the pod's mounted file (`DB_PASSWORD_FILE`); restart only if the file never changed |
| App migrations hang in Init | migrations connect **direct** to `<cluster>-rw:5432`, not the pooler — NetworkPolicy must admit the app namespace to 5432 | check the cluster namespace's netpol app-services rule |
| A product-db service or worker cannot connect, TLS errors | Every runtime verifies PgDog (`sslmode=verify-full`) against `ca.crt` from `product-db-ca-trust` in its own namespace; PgDog serves `pgdog-product-tls` from `/etc/pgdog-tls` and refuses plaintext | Both Certificates must be Ready (`kubectl get certificate -n product pgdog-product-tls`, `-n <ns> product-db-ca-trust`). `does not match host name`: `db_host` must be one of the certificate's DNS names. `certificate verify failed`: the two are not from the same `homelab-ca`. `only TLS connections are allowed`: the client sent `sslmode=disable`. `make db-tls` checks every pooled hop. `migrate` goes direct to `product-db-rw:5432` |
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
| Client TLS | `clientTLSSecret: platform-db-pooler-tls`, `client_tls_sslmode: require`, `server_tls_sslmode: verify-full`. Clients verify with `sslmode=verify-full` against `platform-db-ca-trust`. A renewal reloads in place, no roll ([poolers](../poolers.md#pgbouncer-platform-db)) |

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
  restart, no window where the pooler serves a stale password. PgDog's
  passthrough also needs no action, but each replica accepts the old password
  until the first login with the new one
  ([rotate-cnpg-service-password.md](./rotate-cnpg-service-password.md)).
- **Backend changes are the `Cluster`'s business.** PgBouncer follows the
  `-rw` service, so a failover repoints automatically; there is no backend list
  to edit.
- **No replica routing to reason about.** A read-heavy platform service cannot
  be steered at the pooler — it would need its own `type: ro` Pooler, which the
  pilot deliberately did not add.
- **Restarting is safe and cheap** (`kubectl rollout restart deploy -n platform
  -l cnpg.io/poolerName=platform-db-pooler-rw`) but is rarely the fix, precisely
  because there is no cached config to clear.
