# Gateway API + Envoy Gateway CRDs

Vendored CRD manifests, applied by the `gateway-api-crds-local` Flux
Kustomization with **server-side apply**. Deliberately *not* a HelmRelease.

| Attribute | Value |
|-----------|-------|
| Gateway API | standard channel, bundle-version `v1.5.1` |
| Envoy Gateway | extension CRDs, `v1.8.3` |
| Objects | 18 — 8 CRDs `gateway.networking.k8s.io`, 8 CRDs `gateway.envoyproxy.io`, 1 ValidatingAdmissionPolicy + 1 binding (`safe-upgrades`) |
| Applied by | `kustomize-controller` (server-side apply), `prune: false` |
| Owner of `safe-upgrades` | this directory — the controller chart is told to skip it |

## Why not Helm

Upstream ships these CRDs in `templates/` of the `gateway-crds-helm` chart, so
Helm stores both the rendered manifest and the whole chart in the release
Secret. Measured for `v1.8.3`:

| Path | Size | Limit | Result |
|------|------|-------|--------|
| Helm release Secret | ~2.06 MB | 1 MiB (Kubernetes `Secret`) | rejected |
| `kubectl apply` (client-side) | `envoyproxies` CRD 1.35 MB | 256 KB (`last-applied-configuration` annotation) | rejected |
| **Server-side apply** | 18 objects | — | **works** |

Helm stores the parent chart's `templates/` and the rendered manifest in that
Secret; subcharts are not stored. `gateway-crds-helm` keeps its CRDs in the
parent `templates/`, so both copies land there. Dropping the unused experimental
channel file still leaves ~1.63 MB, and `v1.9.0` packages the same way.

**Upstream says to do exactly this.** The Envoy Gateway install guide installs
CRDs separately with `helm template … | kubectl apply --server-side -f -`
"due to a Helm limitation with large CRDs", then installs the controller chart
with `--skip-crds`. A Flux Kustomization applies server-side, so vendoring the
render and letting Flux apply it is that command expressed as GitOps.

### Why not let the controller chart install them

`gateway-helm` carries the same CRDs in a `charts/crds` subchart, and subcharts
never enter the release Secret — that path would stay in the tens of KB. It is
rejected on **channel**, not size: the subchart ships the Gateway API
**experimental** channel and exposes no way to pick standard, in `v1.8.3` and
`v1.9.0` alike. This platform routes only HTTP and gRPC and runs the standard
channel on purpose.

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

- The standard channel at `v1.5.1` includes `tlsroutes` and `listenersets`;
  they are installed even though this platform routes only HTTP and gRPC.
- `prune: false` on the Kustomization is load-bearing: deleting a Gateway API
  CRD cascade-deletes every `HTTPRoute` and policy on the cluster.
- Design record: [`ADR-044`](../../../../docs/proposals/adr/ADR-044-envoy-gateway-platform-edge/README.md),
  amendment "CRD delivery".

_Last updated: 2026-08-17_
