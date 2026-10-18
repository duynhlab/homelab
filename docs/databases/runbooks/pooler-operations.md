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

1. Rotate in OpenBAO and let ESO and CNPG apply it (`ALTER ROLE`).
2. Restart the app. Its first login with the new password on each replica replaces PgDog's cached copy (log line `auth: passthrough`); until then that replica still accepts the old password.
3. Verify: `kubectl logs deploy/pgdog-product -n product | grep -i 'is wrong'` stays quiet; `pgdog_errors_total` flattens.

## Rotate the client TLS certificate

`pgdog-product` terminates client TLS with the cert-manager `Certificate`
`pgdog-product-tls` (ClusterIssuer `homelab-ca`, 90 days, renewed 15 days
before expiry). A renewal needs no manual step:

- The Secret carries `reconcile.fluxcd.io/watch: Enabled`, so helm-controller
  reconciles `pgdog-product` when cert-manager rewrites it.
- The HelmRelease copies `tls.crt` into the pod annotation `pgdog-tls-crt`
  (`valuesFrom`), so a new certificate changes the pod template and the
  Deployment rolls, draining each pod (below).

To check or force it:

1. `kubectl get certificate pgdog-product-tls -n product` — Ready, with the new `notAfter`. `cmctl renew pgdog-product-tls -n product` forces a renewal.
2. The pods roll on their own; `kubectl rollout status deploy/pgdog-product -n product`. If they did not, `flux reconcile helmrelease pgdog-product -n product`.
3. Verify: the serial PgDog presents (`openssl s_client -starttls postgres -connect pgdog-product.product.svc:6432 </dev/null | openssl x509 -noout -serial`, from a pod the NetworkPolicy admits) matches the Secret's.

PgDog itself can reload the certificate without a restart (`SIGHUP` or the
admin `RELOAD`), but nothing in the chart can send either, so the roll is the
mechanism.

## Rolling restarts drain

Each PgDog pod gets a 10-second `preStop` sleep, so the Service stops routing to
it before PgDog is signalled, and then `SIGINT` (the image's stop signal) makes
PgDog stop accepting connections and wait up to `shutdown_timeout` (60 s) for
clients to finish. `terminationGracePeriodSeconds` is 75 so the sleep and the
drain both fit. With 3 replicas and PDB `minAvailable: 2` a restart is
rolling, one pod at a time.

The drain does not reach the idle connections a client's pgx pool holds to the
pod being stopped: the next statement on one gets `FATAL: PgDog is shutting
down (SQLSTATE 57P01)`, and the service answers that request with a fail-closed
503. Measured on Kind (2026-10-17): 5 of 1993 server requests during one
rollout under 2 orders/s, all in checkout. A retry on a fresh connection in
`pkg/dbx` (duynhlab/pkg#124) closes it; until then expect a few 503s per roll,
including the automatic roll on a certificate renewal.

Verified on Kind (2026-10-17): `cmctl renew` rolled the three pods in about
87 s with no manual step, and six fresh TLS handshakes all presented the new
serial.

## Add a database backend (new service)

The full new-service flow (triplet, HBA, seeds) is [add-service-database.md](add-service-database.md); the PgDog slice of it:

1. In the cluster's `poolers/helmrelease.yaml`: append a `databases:` entry (primary `-rw` only, no `replicas:`). There is no user list; passthrough auth admits the service's runtime login once PostgreSQL accepts its password.
2. `make validate`, merge, reconcile. The rollout restarts pooler pods one at a time and each drains (above).

## Known failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `password for user … is wrong` about 5 s after connecting | Passthrough: PostgreSQL refused the password while PgDog tried it (`checkout_timeout`) | The app holds an old or wrong password: check the ESO Secret and restart the app |
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
