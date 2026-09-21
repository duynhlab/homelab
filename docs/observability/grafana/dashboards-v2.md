# Dashboard V2: which resource carries which schema

Two different things are called a version here, both spell some of their values
`v1beta1`, and picking the wrong one produces a board that either fails to apply or
applies and shows nothing. This page settles which is which, with what was measured
rather than what the docs imply.

Everything below was measured on 2026-09-21 on a Kind cluster built to match this
platform: Grafana Operator **5.25.0**, `grafana/grafana:13.2.0`, one `Grafana` CR
labelled `dashboards: grafana`.

## The two version axes

| Axis | What it is | Values here |
|---|---|---|
| `grafana.integreatly.org/v1beta1` | the **operator's own CRD API**, the `apiVersion:` of the object you `kubectl apply` | `v1beta1`, and nothing else |
| `dashboard.grafana.app/...` | the **Grafana dashboard schema**, the resource Grafana itself stores | see below |

Grafana Operator 5.25.0 ships 13 CRDs and every one has exactly one version, `v1beta1`,
served and stored. There is no `grafana.integreatly.org/v2` and there never has been in
v5. So a `GrafanaDashboard` or `GrafanaManifest` always says `v1beta1`, and that is not
the axis you choose on.

What this Grafana serves, read from its own discovery endpoint:

```
$ curl -u admin:admin http://grafana:3000/apis
dashboard.grafana.app        -> ['v2', 'v2beta1', 'v2alpha1', 'v0alpha1', 'v1', 'v1beta1']
folder.grafana.app           -> ['v1', 'v1beta1']
```

`dashboard.grafana.app/v2` is served, which matters because that is the exact string the
Grafana Foundation SDK's `dashboardv2` package emits. On Grafana 12.0 and 12.1 it is
not served; the newest there is `v2alpha1`.

## The classic resource cannot carry a v2 board

`GrafanaDashboard` posts through the legacy `POST /api/dashboards/db` envelope. That is
not a configuration choice, it is what `controllers/dashboard_controller.go` does, and
`spec.oci` / `spec.url` / `configMapRef` are only transports for the bytes. The operator
docs state the limit plainly since 5.25.0: "The GrafanaDashboard CR only supports V1
dashboards (legacy API)".

Two attempts, both rejected, each with a different message worth recognising.

**Feeding the bare v2 spec** (`elements`, `layout`, no `panels`):

```
DashboardSynchronized=False  reason=ApplyFailed
[POST /dashboards/db][400] {"message":"dashboard appears to be in v2 format.
 Please use the /apis/dashboard.grafana.app/v2 API OR it should include a object
 wrapper with an explicit 'apiVersion' and move the body into a 'spec' element"}
```

**Feeding the wrapped object** the message suggests, that is the full
`{apiVersion, kind, metadata, spec}` manifest:

```
DashboardSynchronized=False  reason=ApplyFailed
[POST /dashboards/db][400] {"message":"The k8s style dashboard must not include
 an id on the root element"}
```

The second one is not fixable from the dashboard side. The operator's content resolver
sets `contentModel["id"] = nil` on every dashboard before posting, so the root always
carries an `id`, and Grafana's v2 path refuses it. The classic resource is closed to v2
in both payload shapes.

On Grafana **12.0.0** the first attempt reports `DashboardSynchronized=True` instead.
That is a false green: the legacy save path accepts fairly arbitrary JSON and stores
something that is not a dashboard. Any CI that only asserts the CR condition on 12.x
proves nothing about whether the board works.

## The resource that does work

`GrafanaManifest` wraps a Grafana App Platform object and applies it with a
discovery-based dynamic client against `/apis`, so it speaks the same protocol as the
schema. Applied on 13.2.0:

```
ManifestSynchronized=True (ApplySuccessful)
```

and read back from Grafana's own apiserver:

| Dashboard | title | elements | layout rows | folder |
|---|---|---|---|---|
| `temporal-worker-v2` | Temporal — Workflows & Activities | 8 | 3 | `as-code-canary` |
| `business-otel-v2` | Microservices — Business KPIs | 38 | 10 | `as-code-canary` |

The wire contract, which is also what `duynhlab/obs-as-code` validates in CI:

- outer: `grafana.integreatly.org/v1beta1`, kind `GrafanaManifest`, namespace `monitoring`,
  `instanceSelector.matchLabels.dashboards: grafana`
- inner: `spec.template` with `apiVersion: dashboard.grafana.app/v2`, kind `Dashboard`,
  `metadata.namespace: default`
- folder: the `grafana.app/folder` annotation on the inner metadata, resolving to a
  sibling manifest wrapping `folder.grafana.app/v1`, kind `Folder`

## What you give up

`GrafanaManifest` has **no content sources at all**: no `oci`, no `url`, no
`configMapRef`, no `grafanaCom`. The dashboard is inline in the CR, so it lands in etcd
and is bounded by the ~1 MiB object limit. Our two canary boards are 10 KiB and 41 KiB
of JSON, which is comfortable, but a board that grows past a few hundred KiB needs a
rethink rather than a bigger file.

That is the honest trade against `spec.oci`, which exists precisely to keep bytes out of
etcd. The compensation, and the reason `obs-as-code` moved anyway, is that the operator's
OCI fetcher has no cache read path: every resync is a full registry pull of an artifact
that is immutable per tag, once per board. Flux pulling a bundle once and applying it is
both cheaper and reports a single revision.

## Ordering

The operator applies each `GrafanaManifest` independently and in no guaranteed order. A
board whose `grafana.app/folder` names a folder that does not exist yet fails with

```
applying resource: creating resource: folders.folder.grafana.app "..." not found
```

and then waits for the operator's next resync, which at `resyncPeriod: 10m` is longer
than a Flux wave's 5m timeout. Listing the folder first inside one kustomization is not
a guarantee; only `dependsOn` between two Flux Kustomizations is. Our three resources
sit in one kustomization today because they arrive together in the same apply; if they
ever split into waves, the dashboards wave must `dependsOn` the folder wave, the way
`obs-as-code-dashboards-local` already does.

`GrafanaManifest` also reports `ManifestSynchronized` rather than `Ready`, so a Flux
Kustomization gating on it needs the `healthCheckExprs` CEL block that
`kubernetes/clusters/local/obs-as-code-dashboards.yaml` carries.

## Reviewing the existing spec.oci boards

`grafana-dashboard-kubernetes-cluster-overview.yaml` and
`grafana-dashboard-kubernetes-workloads.yaml` both fetch from
`ghcr.io/duynhlab/obs-as-code:v0.3.0`. Pulling that tag shows the payload is **classic
v1 JSON**: top-level `title`, `uid`, `panels`, `schemaVersion`. So those two CRs are
correct as written and there is nothing to fix today.

The risk is the pin. The same path in `v0.5.1` holds a v2 manifest with no top-level
`title`:

```
v0.3.0  cluster/dashboards/kubernetes-cluster-overview.json -> panels, title at root
v0.5.1  same path                                            -> dashboard.grafana.app/v2, title under spec
```

Bumping `reference` on those two CRs without also moving them to `GrafanaManifest` swaps
a working board for one of the two 400s above. The version comment in those files should
say so; today it explains why the pin exists but not what breaks if it moves.

## Boards that are not wired yet, and why

Six of the nine boards in `duynhlab/grafana-dashboards` carry query variables, and
Grafana's apiserver **rejects them outright**:

```
Dashboard.dashboard.grafana.app "exp4-pgdog" is invalid:
  DashboardSpec.variables: Invalid value: incompatible list lengths (0 and 7),
  DashboardSpec.variables.0.kind: Invalid value: conflicting values
    "AdhocVariable" and "QueryVariable", ...
```

The generated variable is malformed in three ways, each of which `obs-as-code` already
hit on this platform and fixed:

| Field | What we emit | What works | Consequence |
|---|---|---|---|
| `current` | `{"text":"","value":""}` | `{"text":"All","value":"$__all"}` | Grafana reads the empty string as a real selection, so `$var` expands to `""` and panels match nothing |
| `query` | `{group:"", version:"v0", spec:null}`, with the expression only in `definition` | `spec: {qryType: 1, query: "label_values(...)", refId: "PrometheusVariableQueryEditor-VariableQuery"}` | no expression reaches the datasource, so the dropdown stays empty |
| `allowCustomValue` | `true`, the SDK default | `false` | a reader can type a value that does not exist and get a silently empty panel |

Blocked: `pg-io-waits`, `pg-maintenance`, `pg-query-performance`, `pg-exporter-instance`,
`pgdog`, `microservices-monitoring-001-otel`. Wired here: `temporal-worker`,
`business-otel`. Not wired: `kubernetes-cluster-overview`, which has no variables but
whose name is already taken by the obs-as-code canary.

A fourth difference is a choice rather than a defect. Our panels name the datasource as
a literal `{"name": "prometheus"}`, which in the v2 schema is a uid, and this platform
does have a datasource with uid `prometheus`. It resolves. The alternative is a
`DatasourceVariable` referenced as `${ds}`, which keeps the uid in one place and
survives a rename; `obs-as-code` uses that and rejects literals in CI.

## Upstream work this implies

Three changes in `duynhlab/grafana-dashboards`, in order of how much they block:

1. Fix the query-variable builder to the shape in the table above, and add a
   conformance check so a regression fails the build rather than the cluster.
2. Emit `GrafanaManifest` resources. The generator already writes a
   `*.manifest.json` per board, in the right shape, that nothing consumes; the
   `GrafanaDashboard` + `spec.oci` output it does emit cannot serve these boards.
3. Publish from `main`. The `as-code` branch the release job is gated on no longer
   exists, so `ghcr.io/duynhlab/grafana-dashboards:latest` still holds two boards from
   2026-09-16. Also raise the repo's Kind e2e from Grafana 12.0.0 to 13.x, because 12.0.0
   is the version that returns the false green described above.

Until 1 and 2 land, boards from that repo reach this cluster as hand-written manifests
like the two beside this file.

## Reproducing

The lab script and its log are not committed; the sequence is small enough to restate.
Create a Kind cluster, `helm install` the operator chart at 5.25.0 into `monitoring`,
apply a `Grafana` CR with the deployment image pinned to `grafana/grafana:13.2.0` and the
label `dashboards: grafana`, then port-forward `svc/grafana-service`. `GET /apis` gives
the served group versions. Apply a `GrafanaManifest` and read the result back at
`/apis/dashboard.grafana.app/v2/namespaces/default/dashboards/<name>`; the CR condition
alone is not evidence, which is the whole lesson of the 12.0.0 false green.

_Last updated: 2026-09-21 — first version. Measurements from a Kind run against operator
5.25.0 and grafana/grafana:13.2.0._
