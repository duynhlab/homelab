# Vendored kubeconform schemas

JSON schemas that `scripts/flux-validate.sh` reads before the community
[datree CRDs-catalog](https://github.com/datreeio/CRDs-catalog), for CRDs whose
catalog copy lags the version this platform runs. Layout matches kubeconform's
`{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json`.

| File | Source |
|------|--------|
| `temporal.io/workerdeployment_v1alpha1.json` | `temporal-worker-controller-crds` chart **0.31.0** |
| `temporal.io/clusterconnection_v1alpha1.json` | `temporal-worker-controller-crds` chart **0.31.0** |

Regenerate when the chart pin in
`kubernetes/clusters/local/sources/oci/temporal-worker-controller-crds-oci.yaml`
moves:

```bash
v=0.31.0   # the new chart version
helm pull oci://docker.io/temporalio/temporal-worker-controller-crds --version "$v" --untar --untardir /tmp/twc
for k in workerdeployment clusterconnection; do
  scripts/kubeconform-schemas/generate.py \
    "/tmp/twc/temporal-worker-controller-crds/templates/temporal.io_${k}s.yaml" v1alpha1 \
    "scripts/kubeconform-schemas/temporal.io/${k}_v1alpha1.json"
done
```

`generate.py` adds `additionalProperties: false` to every object that lists its
properties (except `x-kubernetes-preserve-unknown-fields`), as the catalog's own
generator does, so a misspelt field fails `make validate`.
