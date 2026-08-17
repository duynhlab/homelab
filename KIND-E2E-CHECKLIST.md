# Kind E2E audit — working checklist

> **This file is temporary.** It exists to be carried to a Linux box, ticked
> through once, and then deleted along with its pull request. Nothing links to
> it and nothing should. If you are reading it on `main`, someone forgot step
> K6.4.

| Attribute | Value |
|-----------|-------|
| **Applies to** | The Kind cluster `homelab`, brought up from this repository |
| **Complements** | [`local-stack/docs/e2e-audit.md`](local-stack/docs/e2e-audit.md) — the Compose gate. This audit does **not** repeat it |
| **Execution** | By hand, on Ubuntu, in `bash` |
| **Estimated** | 60–90 minutes, most of it waiting on reconciliation |
| **Evidence** | The block in K6.1, pasted into the pull request |
| **Pass decision** | `ELIGIBLE` only when every row that is not marked *optional* passes |
| **Failure decision** | `BLOCKED` — a Kind failure blocks the homelab pull request even though the Compose candidate passed |

## What this audit is for

The Compose gate already proved the **application contract** — 20 API rows, 8
browser rows, 21 telemetry rows, and a Playwright suite, all against the same
service code. Repeating that here would cost hours and prove nothing new.

What only a cluster can prove is everything Compose has no equivalent for:

1. **Flux actually delivers** what the manifests promise, in dependency order.
2. **The images running are the images pinned** — Compose builds from a working
   copy and never touches a tag.
3. **Admission, secrets and network policy** exist at all.
4. **The real edge** — TLS, Host-header routing, HTTP→HTTPS.
5. **`k8s.pod.name` exists**, which settles a question Compose could not answer
   (see K5.4).

There is a sixth reason, and it is the uncomfortable one:
`docs/platform/setup.md` marks its own Envoy/Keycloak half as *"planned until
the Kind gate"*, and `docs/secrets/cert-manager.md` says
`envoy-gateway-config-local` *"has not yet reconciled on this Kind cluster"*.
**This is the first time that layer runs.** Expect to find things. A finding is
the audit working, not the audit failing.

## Before you travel

- [ ] **P1** — PR #789 (`fix/kind-preflight-blockers`) is **merged**. Without it
  `id.duynh.me` does not resolve and `customer-spa` cannot sign in at
  `https://local.duynh.me`; the realm import is one-shot, so discovering that
  here costs a full rebuild.
- [ ] **P2** — The nine `feat/shared-http-middleware` service PRs are merged,
  tagged, and the new tags are pinned in `kubernetes/apps/services/*.yaml`.
  This audit asserts against those pins; running it before they move audits
  the previous release.
- [ ] **P3** — homelab #788 is merged (docs + the portal's Compose block).

---

## K0 — The machine

- [ ] **K0.1** Docker is installed **rootful**. `scripts/kind-up.sh` calls
  `docker inspect|run|network connect` directly; podman is not wired in, unlike
  the Compose stack.
  `docker info >/dev/null && echo ok`
  **FAIL:** any permission error, or a podman shim answering.

- [ ] **K0.2** Bring-up tools present: `kind`, `kubectl`, `flux`, `tofu` (≥1.11
  — or export `TF_BIN=terraform`), `git` with an `origin` remote.
  `make prereqs`
  **FAIL:** any `MISS` line.

- [ ] **K0.3** Validation tools present. **`make prereqs` does not check these**
  and `make validate` needs all four:
  `for b in yq kustomize kubeconform curl; do command -v $b >/dev/null && echo "OK $b" || echo "MISS $b"; done`
  Minimums: `yq` ≥4.50, `kustomize` ≥5.8, `kubeconform` ≥0.7.
  **FAIL:** any `MISS`.

- [ ] **K0.4** Host ports 80, 443 and 5050 are free. 80/443 are the kind
  `extraPortMappings`; 5050 is the local registry.
  `ss -ltnp '( sport = :80 or sport = :443 or sport = :5050 )'`
  **FAIL:** anything listening. Rootless Docker cannot bind <1024 at all.

- [ ] **K0.5** Egress reaches Docker Hub, `ghcr.io`, the OpenTofu registry and
  `raw.githubusercontent.com`. Every image pulls anonymously — there is no
  `imagePullSecret` anywhere in `kubernetes/`.
  **FAIL:** a proxy that intercepts TLS, or an airgap.

- [ ] **K0.6** Hostnames resolve: `sudo scripts/setup-hosts.sh`, then
  `getent hosts id.duynh.me local.duynh.me backoffice.duynh.me gateway.duynh.me`
  **FAIL:** fewer than four lines → P1 was not merged.

---

## K1 — Bring-up

- [ ] **K1.1** `make validate` passes on the checked-out revision, before any
  cluster exists. It needs no cluster.
  **FAIL:** any schema or kustomize error.

- [ ] **K1.2** `make up` completes. It is
  **`cluster-up` → `flux-push` → `flux-up`**, in that order, because the
  FluxInstance's sync source `oci://homelab-registry:5000/flux-cluster-sync`
  must exist before the OpenTofu bootstrap runs.
  > `kubernetes/clusters/local/README.md` documents the **opposite** order and
  > several names that no longer exist. It is stale — do not follow it.
  **FAIL:** a non-zero exit; read `scripts/flux-up.sh`'s header before retrying.

- [ ] **K1.3** The cluster is the expected shape: 1 control-plane + 3 workers on
  `kindest/node:v1.34.3`, and the registry container is up.
  `kubectl get nodes -o wide && docker ps --filter name=homelab-registry`
  **FAIL:** fewer than 4 nodes, or no registry.

- [ ] **K1.4** **Every** Flux Kustomization reports Ready. 22 are declared under
  `kubernetes/clusters/local/` plus `flux-system` generated by the
  FluxInstance = **23**. First reconcile takes 5–10 minutes; `temporal-local`
  is the long pole at a 20m timeout.
  ```bash
  flux get kustomizations -A
  kubectl get kustomization -A -o json | jq -r '
    .items[] | select(.status.conditions[]? | select(.type=="Ready" and .status!="True"))
    | "\(.metadata.name): \(.status.conditions[] | select(.type=="Ready") | .message)"'
  ```
  **FAIL:** any name printed by the second command.

- [ ] **K1.5** If and only if `envoy-gateway-config-local` is not Ready, check
  the NodePort collision first — it is the documented failure mode and it looks
  nothing like a traffic problem.
  `kubectl -n envoy-gateway get svc -l gateway.envoyproxy.io/owning-gateway-name=platform -o yaml | grep -A2 nodePort`
  **FAIL signature:** the API server refused to allocate 30080/30443 because
  something else holds them.

- [ ] **K1.6** *(informational)* `make tf-plan` shows a zero diff.
  **FAIL:** a non-empty plan means the bootstrap did not converge.

---

## K2 — GitOps delivered what the manifests promise

This is the largest gap in the repo today: **no command anywhere diffs the
running images against the committed pins.** That is this group's whole job.

- [ ] **K2.1** Read the pins out of Git. Fill the table below at audit time —
  do not trust numbers written here, they will have moved with the middleware
  wave.
  ```bash
  grep -H 'image_tag:' kubernetes/apps/services/*.yaml
  grep -H '  tag:' kubernetes/apps/frontend-rs.yaml kubernetes/apps/backoffice-rs.yaml \
                   kubernetes/apps/mockpay.yaml kubernetes/apps/checkout-worker.yaml \
                   kubernetes/apps/order-worker-*.yaml
  ```

- [ ] **K2.2** Read the images actually running, and compare them to K2.1 line
  by line.
  ```bash
  kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.spec.containers[*].image}{"\n"}{end}' \
    | grep 'ghcr.io/duynhlab' | sort -u
  ```
  **FAIL:** any workload on a tag other than its pin. A pod stuck on the old
  tag usually means its HelmRelease did not upgrade — check
  `flux get hr -A | grep -v True` before blaming the pin.

| Workload | Pinned (K2.1) | Running (K2.2) | ✓ |
|---|---|---|:-:|
| cart | 2.1.0 | | |
| checkout | 0.8.0 | | |
| inventory | 0.5.0 | | |
| notification | 2.1.0 | | |
| order | 2.3.0 | | |
| payment | 2.3.0 | | |
| product | 1.13.0 | | |
| review | 2.1.0 | | |
| shipping | 1.6.0 | | |
| user | 2.2.0 | | |
| frontend | 3.1.0 | | |
| admin-service | 0.3.0 | | |
| mockpay | 1.5.3 | | |
| checkout-worker | 0.8.0 | | |
| order-worker | 1.13.2 | | |

The nine that moved are the ADR-038 wave, tagged after the Compose gate passed.
`inventory` did not move — it is gRPC-only and mounts no Gin middleware, so it
took the `obsx` span helpers back in its own release and has nothing to migrate.

- [ ] **K2.3** The coupled pins hold. These are not derivable from a single
  file, which is why they are their own row:
  - `checkout-worker` tracks `checkout` — **both are 0.8.0**, moved together.
    The worker takes `pkg/httpmw` only for its own probes; the Compose gate ran
    this exact code and `AbandonedCheckoutWorkflow` fired its timer, so no
    pinned execution can hit a non-determinism error.
  - `mockpay` tracks `payment` **by hand**, and is **deliberately left at
    1.5.3** while payment is 2.3.0. That skew predates this wave and was not
    touched by it. Confirm it is intentional or file it — do not "fix" it here.
  - `order-worker` stays at **1.13.2**. Its `TEMPORAL_WORKER_BUILD_ID` must
    equal this file's tag and the cutover CronJob's, and workflows are pinned to
    that build. A new build gets a new `order-worker-<build-id>.yaml` and a
    cutover (RFC-0021 `cutover-rollback.md`) — never a tag bump in place.
  **FAIL:** a skew other than the two named above.

- [ ] **K2.4** `auth` is absent — **10** services, not 11. Its cluster surface
  was deleted; the Compose audit already treats its absence as an assertion.
  `kubectl get ns | grep -c '^auth ' # want 0`
  **FAIL:** an `auth` namespace, Deployment, or database exists.

- [ ] **K2.5** All seven ResourceSets that `apps-local` health-checks are Ready:
  `rs-identity`, `rs-catalog`, `rs-checkout`, `rs-fulfillment`, `rs-comms`,
  `rs-frontend`, `rs-backoffice`.
  `kubectl get resourcesets -A`
  **FAIL:** any not Ready — `docs/platform/application-delivery.md` §8.1 has the
  three recurring template errors and how to read them.

- [ ] **K2.6** Every HelmRelease is Ready.
  `flux get helmreleases -A | grep -v True || echo "all Ready"`

- [ ] **K2.7** *(build-arg contract — cannot be checked with kubectl)* The
  pinned `frontend` and `admin-service` tags were **built** with the cluster's
  Keycloak URL/realm/client baked in. A tag built for Compose loads fine and
  then talks to `localhost` from the operator's browser. Confirm against the CI
  run that produced each tag.
  **FAIL:** K4.6/K4.7 will fail later and the cause will look like a Keycloak
  problem.

---

## K3 — Admission, secrets, isolation

- [ ] **K3.1** Kyverno: the violation set matches the **registered exceptions**.
  Note the assertion carefully — only `disallow-default-namespace` is
  `Enforce`; every other Tier-1 policy is `Audit`, so "no violations" is the
  wrong thing to expect and "it admitted everything" proves little.
  ```bash
  kubectl get clusterpolicyreport -A
  kubectl get policyreport -A -o json | jq -r '
    .items[].results[]? | select(.result=="fail") | "\(.policy)/\(.rule): \(.resources[0].namespace)/\(.resources[0].name)"' | sort | uniq -c
  ```
  **FAIL:** a failing resource that is not covered by `vector-hostpath`,
  `postgres-operators` or `openbao`.

- [ ] **K3.2** Those three exceptions have not expired. All carry
  `platform.duynhlab.dev/expires-at: "2026-12-31"`.
  `grep -rh 'expires-at' kubernetes/infra/configs/kyverno/exceptions/`
  **FAIL:** a date in the past — the exception is live but unowned.

- [ ] **K3.3** OpenBAO self-unsealed and ESO is serving. No manual unseal step
  exists; the bootstrap Job initialises, unseals, seeds, then **revokes root**.
  ```bash
  kubectl -n openbao get pods
  kubectl get clustersecretstore openbao -o jsonpath='{.status.conditions[*].status}{"\n"}'
  kubectl get externalsecrets -A | grep -v SecretSynced || echo "all synced"
  ```
  **FAIL:** a sealed pod, or an ExternalSecret not synced.
  > Do **not** try to fix a missing secret by re-running the Job — it revoked
  > its own root token and a re-run seeds nothing while exiting 0. Use the
  > break-glass procedure in `docs/secrets/openbao.md`.

- [ ] **K3.4** Database isolation holds. `scripts/db-isolation-sweep.sh` is the
  role×database `pg_hba` matrix ADR-015 promised would run "at each bring-up",
  and no document currently schedules it.
  `./scripts/db-isolation-sweep.sh`
  **FAIL:** non-zero exit.

- [ ] **K3.5** Edge isolation holds. `./scripts/edge-isolation-sweep.sh --live`
  **FAIL:** non-zero exit. **Read the script first** — it still lists
  `auth:8080` in `EDGE_ALLOWS`, which looks stale against K2.4. If that is the
  only failure, it is a finding against the script, not against the cluster.

---

## K4 — The real edge and identity

Compose reached everything on a fixed localhost port. The cluster reaches
nothing that way. Translation table:

| Compose | Cluster |
|---|---|
| edge `:8080` | `https://gateway.duynh.me` |
| Keycloak `:8081` | `https://id.duynh.me` |
| storefront `:3001` | `https://local.duynh.me` |
| portal `:3009` | `https://backoffice.duynh.me` |
| Grafana `:3002` | `https://grafana.duynh.me` |
| VictoriaMetrics `:8428` | `https://vmui.duynh.me` |
| VictoriaLogs `:9428` | `https://logs.duynh.me` |
| VictoriaTraces `:10428` | `https://victoriatraces.duynh.me` |
| Pyroscope `:4040` | `https://pyroscope.duynh.me` |
| vmalert `:8880` | `https://vmalert.duynh.me` — **service port is 8080** |
| vmagent `:8429` | **no route** → `kubectl port-forward -n monitoring svc/vmagent-victoria-metrics 8429:8429` |
| ClickHouse `:8123` | **no route, by design** → `kubectl port-forward -n monitoring svc/clickhouse-clickhouse 8123:8123` |

Three cluster-only facts, each its own row because each silently breaks a
command copied from the Compose audit:

- [ ] **K4.1** Plain HTTP is redirected, not served.
  `curl -s -o /dev/null -w '%{http_code}\n' http://gateway.duynh.me/product/v1/public/products`
  **Want 301.** A body here means the redirect route is missing.

- [ ] **K4.2** TLS is the self-signed `homelab-ca`, so **every** `curl` needs
  `-k`. Kind has no Cloudflare token, so `platform-edge-tls` is patched to the
  local issuer.
  `curl -sk https://gateway.duynh.me/product/v1/public/products | head -c 120`
  **FAIL:** a certificate error even with `-k`, or an empty body.

- [ ] **K4.3** Routing is by **Host header**, not by IP.
  `curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/product/v1/public/products`
  **Want 404** — no route matches. A 200 would mean a route is bound too widely.

- [ ] **K4.4** Both realms exist and are the ones from Git.
  ```bash
  curl -sk https://id.duynh.me/realms/duynhlab       | jq -r .realm
  curl -sk https://id.duynh.me/realms/duynhlab-staff | jq -r .realm
  ```
  **FAIL:** a 404 → the ConfigMap did not mount, or the realm import did not run.

- [ ] **K4.5** A customer token mints through the realm. There is **no password
  grant** — Direct Access Grants are disabled on both clients, so the helper
  does the Authorization-Code + PKCE dance.
  `KC_URL=https://id.duynh.me USERNAME=alice PASSWORD=password123 ./local-stack/scripts/keycloak-token.sh`
  **FAIL:** empty output. Check `id.duynh.me` resolves (K0.6) before anything else.

- [ ] **K4.6** The storefront signs in end to end at `https://local.duynh.me`
  as `alice` / `password123`, in a browser.
  **FAIL:** `invalid_redirect_uri` → **P1 was not merged**, and the realm cannot
  be fixed in place. Rebuild.
  > Also note `frontend` 3.1.0 moved the catalog: `/` is search + category
  > buckets, the grid lives at `/products`. An empty `/` is correct.

- [ ] **K4.7** The Backoffice portal signs in at `https://backoffice.duynh.me`
  as `duyne` / `p@ss1234`, lands on the shell with seven nav items, and its
  five dashboard cards show numerals.
  **FAIL:** landing on `/forbidden` is a role problem, not a sign-in problem —
  read which one before reporting.

- [ ] **K4.8** The realm fence holds at the edge. A **customer** token on a
  `/protected/` route dies as wrong-issuer before any service role logic.
  ```bash
  AT=$(KC_URL=https://id.duynh.me USERNAME=alice PASSWORD=password123 ./local-stack/scripts/keycloak-token.sh)
  curl -sk -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $AT" \
    https://gateway.duynh.me/inventory/v1/protected/balances
  ```
  **Want 401.** A 403 means the edge let it through and a service rejected it —
  weaker than the contract, and a finding.

---

## K5 — The four signals

The Compose audit's Phase C, re-pointed at the cluster. Local patches the edge
`samplingRate` to **100**, so trace results here are deterministic.

Drive some traffic first, and tag it so later rows can find one request:
```bash
TAG=$(date +%s)
curl -sk -o /dev/null "https://gateway.duynh.me/product/v1/public/products?audit=$TAG"
sleep 45   # OTLP export is 15s, spanmetrics flushes on 15s
```

- [ ] **K5.1 Traces — the edge is the root and the chain is unbroken.**
  Port-forward ClickHouse, then:
  ```sql
  SELECT ServiceName, SpanName, SpanKind, ParentSpanId != '' AS has_parent
  FROM otel.otel_traces
  WHERE TraceId = (SELECT TraceId FROM otel.otel_traces
                   WHERE SpanAttributes['http.url'] LIKE '%audit=<TAG>%' LIMIT 1)
  ORDER BY Timestamp FORMAT PrettyCompact
  ```
  **Want:** the edge's `ingress` with `has_parent = 0` first, then the service's
  Server span with `has_parent = 1`.
  **FAIL:** two roots, or a service Server span with no parent — propagation is
  broken.

- [ ] **K5.2 Traces — coverage.** All 10 services plus the edge appear with
  `server_spans > 0`; `auth` is absent.
  `curl -sk https://victoriatraces.duynh.me/select/jaeger/api/services | jq -r '.data[]' | sort`

- [ ] **K5.3 Logs — both legs, and correlation.** The OTLP leg is the services'
  own tee; the Vector leg carries containers with no SDK.
  ```bash
  curl -sk 'https://logs.duynh.me/select/logsql/query' --data-urlencode 'query=_time:45m _stream:{"service.name"="cart"} | count()'
  curl -sk 'https://logs.duynh.me/select/logsql/query' --data-urlencode 'query=_time:45m _stream:{service="gateway"} upstream_cluster:* route_name:* | count()'
  ```
  **FAIL:** both empty at once is **one** failure (the Vector leg), not two.

- [ ] **K5.4 Metrics — THE ROW THIS AUDIT EXISTS FOR.**
  On Compose, `order` and `order-worker` publish under an identical identity and
  **overwrite each other's series** — proven by a value alternating between two
  bands (`78 84 84 78 78 84…`) while a single-process service held steady.
  VictoriaMetrics promotes only
  `service.name, service.version, k8s.namespace.name, k8s.pod.name,
  deployment.environment.name`, and Compose sets no k8s attribute at all, so
  nothing separates the two processes. `obsx` sets no `service.instance.id`
  either, and it would be dropped if it did.
  **In the cluster `k8s.pod.name` exists.** So:
  ```bash
  curl -sk 'https://vmui.duynh.me/api/v1/query' --data-urlencode 'query=go_goroutine_count{service_name="order"}' \
    | jq -r '.data.result[] | .metric | "\(.service_name)  pod=\(.k8s_pod_name // "MISSING")"'
  ```
  **Want: exactly 2 series, with different `k8s_pod_name`** — the API pod and
  the worker pod.
  **FAIL — 1 series, or `k8s_pod_name` MISSING:** the identity collision is
  **not** Compose-only. Then `docs/api/metrics.md` is wrong for the cluster too,
  every `go_*` and `db_client_*` series for `order` and `checkout` is a blend of
  two processes, and the fix is `service.instance.id` in `obsx` **plus** adding
  it to VM's `promoteResourceAttributes`. Record the output verbatim either way
  — this is the one row whose negative result is as valuable as its positive.

- [ ] **K5.5 Metrics — the rest.** Series exist for the three legs that fail
  independently: spanmetrics (remote-write), app semconv (OTLP ingest), and
  Temporal SDK.
  ```bash
  for q in 'sum(spanmetrics_calls_total{span_kind="SPAN_KIND_SERVER"})' \
           'sum(http_server_request_duration_seconds_count)' \
           'sum(rpc_server_call_duration_seconds_count{service_name="inventory"})' \
           'count(temporal_workflow_endtoend_latency_seconds_bucket)'; do
    echo -n "$q => "
    curl -sk 'https://vmui.duynh.me/api/v1/query' --data-urlencode "query=$q" | jq -r '.data.result[0].value[1] // "NO SERIES"'
  done
  ```
  `inventory` is gRPC-only with no edge route, so its `rpc_*` count is the only
  metrics evidence it is instrumented at all.

- [ ] **K5.6 Profiles.** Pyroscope carries all 10 services; `auth` is absent.
  ```bash
  curl -sk -X POST 'https://pyroscope.duynh.me/querier.v1.QuerierService/LabelValues' \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"service_name\",\"matchers\":[\"{}\"],\"start\":$(( ($(date +%s)-3600)*1000 )),\"end\":$(( $(date +%s)*1000 ))}" | jq -r '.names[]' | sort
  ```

- [ ] **K5.7 Dashboards resolve, not merely load.** Use the reference-resolution
  check — a dashboard whose panels name an undeclared `${VAR}` returns HTTP 200
  and then renders an error banner on every panel. The command is in
  `local-stack/docs/e2e-audit.md` under C18; point `$GRAF` at
  `https://grafana.duynh.me`.
  **Known and expected:** 21 of the 44 queries in *ClickHouse — Server / Engine*
  read `chi_*`, the Altinity operator's metrics. Nothing here runs that operator,
  so those panels are empty **by design**, in both environments. The other 19
  read the engine's native `ClickHouseMetrics_*` and do work.

- [ ] **K5.8 Alert rules loaded, none firing wrongly.**
  `curl -sk https://vmalert.duynh.me/api/v1/rules | jq -r '[.data.groups[].rules[] | select(.state=="firing") | .name] | unique[]'`
  **Do not** assert a total count: `docs/observability/alerting/alert-catalog.md`
  marks a subset **inactive on Kind** for platform reasons. Assert only that
  rules loaded and that nothing is firing on a healthy stack.

---

## K6 — Evidence and teardown

- [ ] **K6.1** Fill this in and paste it into the pull request.

```markdown
## Kind E2E audit — <date>

Cluster: kind `homelab`, <n> nodes, `kindest/node:v1.34.3`
Revision: <git rev-parse HEAD>
Preconditions: #789 merged · service tags pinned · #788 merged

| Group | Rows | Result | Evidence |
|---|---|---|---|
| K0 machine | 6 | | |
| K1 bring-up | 6 | | 23/23 Kustomizations Ready |
| K2 delivery | 7 | | image↔pin table |
| K3 admission/secrets | 5 | | |
| K4 edge/identity | 8 | | |
| K5 signals | 8 | | **K5.4 verbatim output:** |
| K6 wrap | 4 | | |

Findings: <one line each, or "none">

Decision: ELIGIBLE / BLOCKED
```

- [ ] **K6.2** Every finding is filed — as an issue or a follow-up PR. A finding
  discovered here and left in this file dies with the file.

- [ ] **K6.3** `make down` — deletes the cluster **and** the registry container,
  so all pushed OCI artifacts go with it. A later bring-up must re-run
  `flux-push`, which `make up` does for you.

- [ ] **K6.4** **Delete this file** and close its pull request.

---

## Deliberately not in scope

- **Re-running Phase A/B of the Compose audit.** It proved the application
  contract against this exact service code. Repeating it on Kind costs hours and
  raises confidence by roughly nothing.
- **Asserting the full alert catalogue.** Part of it is inactive on Kind by
  design; a count assertion would fail a healthy cluster.
- **Treating `make flux-sync` as "synced".** It reconciles **6 of 23**
  Kustomizations and skips the edge, Keycloak, Temporal, ClickHouse, tracing and
  cert-manager entirely. Use `flux reconcile kustomization <name>` for anything
  outside its six.
