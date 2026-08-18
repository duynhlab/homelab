# Gateway API + Envoy Gateway CRDs

Vendored CRD manifests, applied by the `gateway-api-crds-local` Flux
Kustomization with **server-side apply**. Deliberately *not* a HelmRelease.

| Attribute | Value |
|-----------|-------|
| Gateway API | standard channel, bundle-version `v1.6.1` |
| Envoy Gateway | extension CRDs, `v1.9.0` |
| Objects | 20 — 10 CRDs `gateway.networking.k8s.io`, 8 CRDs `gateway.envoyproxy.io`, 1 ValidatingAdmissionPolicy + 1 binding (`safe-upgrades`) |
| Applied by | `kustomize-controller` (server-side apply), `prune: false` |
| Owner of `safe-upgrades` | this directory — the controller chart is told to skip it |

## Two different charts, two different blockers

Upstream ships these CRDs twice, and the two packages fail for **different**
reasons. Conflating them is the easy mistake here, so both are named in full
throughout this document:

| Chart | Channel control | Where the CRDs live | Why it is rejected |
|-------|-----------------|---------------------|--------------------|
| `gateway-crds-helm` (standalone) | `crds.gatewayAPI.channel: standard\|experimental` | parent `templates/` | **size** — Helm stores parent templates + the render in one Secret |
| `gateway-helm/charts/crds` (subchart of the controller chart) | none — its `values.yaml` is three lines | `crds/` + `crds/generated/` | **channel** — every Gateway API CRD it ships is `channel: experimental` |

Verified by unpacking both chart packages at `v1.8.3` and `v1.9.0`.

## Why not Helm

`gateway-crds-helm` keeps its CRDs in `templates/`, so Helm stores both the
rendered manifest and the whole chart in the release Secret. Measured for
`v1.9.0`:

| Path | Size | Limit | Result |
|------|------|-------|--------|
| Helm release Secret | ~2.06 MB measured at `v1.8.3`; `v1.9.0`'s inputs are larger still | 1 MiB (Kubernetes `Secret`) | rejected |
| `kubectl apply` (client-side) | `envoyproxies` CRD 1.41 MB | 256 KB (`last-applied-configuration` annotation) | rejected |
| **Server-side apply** | 20 objects | — | **works** |

Helm stores the parent chart's `templates/` and the rendered manifest in that
Secret; subcharts are not stored. Because `gateway-crds-helm` is the parent,
both copies land there. Selecting `channel: standard` does not help: the
unused `experimental-gatewayapi-crds.yaml` (1.40 MB) is still packaged in the
chart, and the render itself is 3.73 MB.

**Upstream says to do exactly this.** The Envoy Gateway install guide installs
CRDs separately with `helm template … | kubectl apply --server-side -f -`
"due to a Helm limitation with large CRDs", then installs the controller chart
with `--skip-crds`. A Flux Kustomization applies server-side, so vendoring the
render and letting Flux apply it is that command expressed as GitOps. The
limitation is tracked upstream in
[envoyproxy/gateway#6105](https://github.com/envoyproxy/gateway/issues/6105),
open since 2025-05 and confirmed there by a maintainer as a known issue whose
answer is the `helm template` route — including a report that splitting into a
second HelmRelease does not escape the ceiling either.

### Why not let the controller chart install them

`gateway-helm` carries CRDs in a `charts/crds` subchart, and subcharts never
enter the release Secret — that path would stay in the tens of KB. It is
rejected on **channel**, not size: `gateway-helm/charts/crds` ships the Gateway
API **experimental** channel and exposes no way to pick standard. Its entire
`values.yaml` is:

```yaml
gatewayAPI:
  safeUpgradePolicy:
    enabled: true
```

— no `channel` key exists, and every Gateway API CRD in
`charts/crds/crds/gatewayapi-crds.yaml` is annotated
`gateway.networking.k8s.io/channel: experimental`: 13 of 13 at `v1.9.0`, 12 of
12 at `v1.8.3`. The `channel` toggle belongs to the *standalone* chart, which
is blocked on size instead. This platform routes only HTTP and gRPC and runs the
standard channel on purpose.

The controller HelmRelease therefore sets `crds.enabled: false`, which drops
that subchart as a chart dependency altogether — verified by rendering
`gateway-helm` `v1.9.0` both ways: 0 CRDs and 0 ValidatingAdmissionPolicy
objects with the flag off, versus the VAP + its binding with it on.

## Regenerating

Re-render whenever Envoy Gateway is upgraded. The chart inserts no Helm labels,
so the output is the upstream CRD YAML verbatim.

```bash
helm pull oci://docker.io/envoyproxy/gateway-crds-helm --version vX.Y.Z -d /tmp
helm template gateway-api-crds /tmp/gateway-crds-helm-vX.Y.Z.tgz -n envoy-gateway \
  --set crds.gatewayAPI.enabled=true \
  --set crds.gatewayAPI.channel=standard \
  --set crds.envoyGateway.enabled=true
```

Split the output by its `# Source:` comments: everything under
`templates/generated/gateway.envoyproxy.io_*` goes to `envoy-gateway-crds.yaml`,
the rest to `gatewayapi-standard-crds.yaml`. Keep both files' generated header.

Bump the controller chart in
[`../envoy-gateway/helmrelease.yaml`](../envoy-gateway/helmrelease.yaml) in the
same change — the CRDs and the controller are versioned together.

## Notes

- The standard channel at `v1.6.1` includes `tlsroutes`, `listenersets`, and —
  new in this bundle — `tcproutes` and `udproutes`, which graduated to
  `gateway.networking.k8s.io/v1`. They are installed even though this platform
  routes only HTTP and gRPC; Envoy Gateway `v1.9.0` reconciles TCP/UDP routes
  through the `v1` API and requires the `v1.6` bundle to be present.
- The `safe-upgrades` policy vendored here carries `bundle-version: v1.6.1` and
  rejects any Gateway API CRD annotated `v1.0`–`v1.4`, or an experimental CRD
  landing on top of a standard one. Upgrading `v1.5.1` → `v1.6.1` passes both
  checks, so the policy does not block its own bundle bump.
- The same VAP is also templated by `gateway-helm/charts/crds`. Disabling that
  subchart is what keeps this directory its single declared owner; the
  HelmRelease additionally sets `crds.gatewayAPI.safeUpgradePolicy.enabled:
  false`, the switch upstream documents for externally managed Gateway API
  CRDs.
- `prune: false` on the Kustomization is load-bearing: deleting a Gateway API
  CRD cascade-deletes every `HTTPRoute` and policy on the cluster.
- Design record: [`ADR-044`](../../../../docs/proposals/adr/ADR-044-envoy-gateway-platform-edge/README.md),
  amendments "CRD delivery" (2026-08-17) and "Envoy Gateway v1.9.0" (2026-08-18).

_Last updated: 2026-08-18_
