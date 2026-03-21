# OCI sources (local cluster)

Flux `OCIRepository` objects in this directory point at the **in-cluster HTTP registry** used by Kind/homelab (`homelab-registry:5000`). They use `spec.insecure: true` by design.

## Production deployment

When promoting to an environment with a **TLS** container registry:

1. **URL** — Use `oci://` URL to your HTTPS registry host and repository path.
2. **TLS** — Remove `spec.insecure: true` from every `OCIRepository` (default is secure TLS verification).
3. **Tags / digests** — Prefer semver, digest, or promoted release tags instead of mutable `local` tags.
4. **FluxInstance** — In [`../../flux-system/instance.yaml`](../../flux-system/instance.yaml), remove the `spec.kustomize.patches` block that injects `insecure: true` into OCIRepository CRs.
5. **Authentication** — For private registries, set `spec.secretRef` on `OCIRepository` per [Flux docs](https://fluxcd.io/flux/components/source/ocirepositories/#secret-reference).

## Cosign verification (optional)

To verify signed OCI artifacts before reconcile:

- Add `spec.verify` to each `OCIRepository`:

```yaml
spec:
  verify:
    provider: cosign
    secretRef:
      name: flux-oci-cosign-public
```

- Store trusted public key material in the referenced Secret (see Flux Cosign verification docs).

This repo leaves `verify` **commented** in the YAML files so homelab stays simple; enable in production when your pipeline signs artifacts.

## References

- [OCIRepository](https://fluxcd.io/flux/components/source/ocirepositories/)
- [Verify OCI artifacts](https://fluxcd.io/flux/components/source/ocirepositories/#verification)
