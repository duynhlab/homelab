#!/usr/bin/env bash

# Validate Flux custom resources and kustomize overlays using kubeconform.
# Based on: https://github.com/fluxcd/flux2-kustomize-helm-example/blob/main/scripts/validate.sh
#
# Prerequisites:
#   - yq >= 4.50
#   - kustomize >= 5.8
#   - kubeconform >= 0.7
#   - curl
#
# Usage:
#   ./scripts/flux-validate.sh

set -o errexit
set -o pipefail

kustomize_flags=("--load-restrictor=LoadRestrictionsNone")

kubeconform_flags=("-skip=Secret")
kubeconform_flags=("-skip=Secret")
kubeconform_config=(
  "-strict" 
  "-ignore-missing-schemas" 
  "-schema-location" "default" 
  "-schema-location" "/tmp/flux-crd-schemas/{{.ResourceKind}}-fluxcd-{{.ResourceAPIVersion}}.json"
  "-schema-location" "/tmp/flux-crd-schemas/{{.ResourceKind}}-helm-{{.ResourceAPIVersion}}.json"
  "-schema-location" "/tmp/flux-crd-schemas/{{.ResourceKind}}-source-{{.ResourceAPIVersion}}.json"
  "-schema-location" "/tmp/flux-crd-schemas/{{.ResourceKind}}-image-{{.ResourceAPIVersion}}.json"
  "-schema-location" "/tmp/flux-crd-schemas/{{.ResourceKind}}-notification-{{.ResourceAPIVersion}}.json"
  # Community CRD schemas (datree CRDs-catalog): validates ExternalSecret,
  # DatabaseRole/Database, ServiceMonitor/PrometheusRule and — next train —
  # Gateway API CRs, which -ignore-missing-schemas used to wave through.
  "-schema-location" "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
  "-verbose"
)

# Kustomize overlays that Flux actually reconciles (matches Flux Kustomization paths).
# These are the ONLY overlays we kustomize-build; auto-discovery causes parent/child
# collisions when intermediate kustomization.yaml files reference subdirectories.
kustomize_overlays=(
  "kubernetes/clusters/local"
  "kubernetes/infra/controllers"
  # temporal/ is excluded from controllers/kustomization.yaml (it needs its own
  # Kustomization so apps-local can depend on a Ready server), so a build of
  # controllers never reaches it — without these lines nothing validated it.
  "kubernetes/infra/controllers/temporal"
  # keycloak/ is excluded from controllers/kustomization.yaml for the same
  # reason (its own Kustomization, keycloak-local) — validate it explicitly.
  "kubernetes/infra/controllers/keycloak"
  "kubernetes/infra/configs/temporal"
  "kubernetes/infra/configs/databases"
  "kubernetes/infra/configs/observability"
  "kubernetes/infra/configs/secrets"
  "kubernetes/infra/configs/kyverno"
  "kubernetes/infra/configs/network-policies"
  # Envoy Gateway train (RFC-0024 P2): each excluded from controllers/
  # kustomization.yaml (own Flux Kustomizations) — validate them explicitly.
  "kubernetes/infra/controllers/gateway-api-crds"
  "kubernetes/infra/controllers/envoy-gateway"
  "kubernetes/infra/configs/envoy-gateway"
)

check_prerequisites() {
  local missing=0
  for cmd in yq kustomize kubeconform curl kyverno; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "ERROR - $cmd is not installed" >&2
      missing=1
    fi
  done
  if [[ $missing -ne 0 ]]; then
    exit 1
  fi
}

download_schemas() {
  echo "INFO - Downloading Flux OpenAPI schemas"
  mkdir -p /tmp/flux-crd-schemas

  # Flux Operator schemas
  echo "  fetching flux-operator schemas"
  curl -sL https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/crd-schemas.tar.gz | \
    tar zxf - -C /tmp/flux-crd-schemas
  
  # Flux CD v2 schemas
  echo "  fetching flux2 schemas"
  curl -sL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz | \
    tar zxf - -C /tmp/flux-crd-schemas
}

validate_yaml_syntax() {
  echo "INFO - Validating YAML syntax"
  local count=0
  local failed=0
  while IFS= read -r -d $'\0' file; do
    if ! yq e 'true' "$file" > /dev/null 2>&1; then
      echo "  FAIL - $file"
      yq e 'true' "$file"
      failed=1
    fi
    count=$((count + 1))
  done < <(find kubernetes/ -path '*/.*' -prune -o -type f -name '*.yaml' -print0)
  echo "  checked $count files"
  if [[ $failed -ne 0 ]]; then
    echo "ERROR - YAML syntax validation failed" >&2
    exit 1
  fi
}

validate_standalone_manifests() {
  echo "INFO - Validating standalone Kubernetes manifests"
  local count=0
  while IFS= read -r -d $'\0' f; do
    kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" "$f"
    count=$((count + 1))
  done < <(find kubernetes/apps/ -type f -name '*.yaml' -print0)
  echo "  validated $count app manifests"
}

validate_kustomize_overlays() {
  echo "INFO - Validating kustomize overlays"
  for overlay in "${kustomize_overlays[@]}"; do
    if [[ ! -d "$overlay" ]]; then
      echo "  SKIP - $overlay (not found)"
      continue
    fi
    echo "  building $overlay"
    kustomize build "$overlay" "${kustomize_flags[@]}" | \
      kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}"
    if [[ ${PIPESTATUS[0]} != 0 || ${PIPESTATUS[1]} != 0 ]]; then
      echo "ERROR - kustomize overlay validation failed: $overlay" >&2
      exit 1
    fi
  done
}

validate_production() {
  if [[ -d "kubernetes/clusters/production" ]]; then
    echo "INFO - Validating production cluster overlay"
    kustomize build "kubernetes/clusters/production" "${kustomize_flags[@]}" | \
      kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}"
    if [[ ${PIPESTATUS[0]} != 0 || ${PIPESTATUS[1]} != 0 ]]; then
      echo "ERROR - production overlay validation failed" >&2
      exit 1
    fi
  fi
}


# Worker Versioning wiring, RFC-0026 / ADR-054 shape.
#
# The controller now owns the version identity: it derives the Build ID and
# injects TEMPORAL_DEPLOYMENT_NAME + TEMPORAL_WORKER_BUILD_ID into every pod of
# every version it creates. So the three-way build-id comparison this function
# used to make has nothing left to compare — there is one file, and it states the
# Build ID nowhere. What replaces it are the mistakes that ARE still reachable,
# and every one of them fails the same way the old drift did: silently, with new
# workflows pinned to a version no worker serves.
#
# Written to fail LOUDLY rather than skip: every path that cannot make a
# comparison exits non-zero. A guard that silently compares nothing is worse than
# no guard, because its green line reads as proof.
validate_worker_versioning() {
  local wd="kubernetes/apps/order-worker.yaml"

  if [[ ! -f "${wd}" ]]; then
    echo "ERROR - ${wd} is missing; cannot verify the Worker Versioning wiring" >&2
    exit 1
  fi

  # --- No per-build files may survive the cutover. One left behind means the old
  # HelmRelease and the controller both write Deployments for one deployment name,
  # and the loser is whichever reconciles second.
  local -a legacy=()
  local f
  for f in kubernetes/apps/order-worker-*.yaml; do
    [[ -f "${f}" ]] && legacy+=("${f}")
  done
  if [[ ${#legacy[@]} -gt 0 ]]; then
    echo "ERROR - per-build worker manifests still present (${legacy[*]}). ADR-054 replaced them with the single ${wd}; two writers of one deployment name is the drift this check used to police." >&2
    exit 1
  fi

  # --- The WorkerDeployment and its Connection must both be there, and the
  # connectionRef must resolve. A dangling ref leaves the controller unable to
  # reach Temporal, which surfaces as a version that is never registered.
  local kinds conn_name ref_name
  kinds=$(yq eval-all '[.kind] | join(",")' "${wd}")
  if [[ "${kinds}" != *"WorkerDeployment"* || "${kinds}" != *"Connection"* ]]; then
    echo "ERROR - ${wd}: expected both a Connection and a WorkerDeployment, found kinds [${kinds}]" >&2
    exit 1
  fi
  conn_name=$(yq eval-all 'select(.kind == "Connection") | .metadata.name' "${wd}")
  ref_name=$(yq eval-all 'select(.kind == "WorkerDeployment") | .spec.workerOptions.connectionRef.name' "${wd}")
  if [[ -z "${conn_name}" || "${conn_name}" == "null" || "${ref_name}" != "${conn_name}" ]]; then
    echo "ERROR - ${wd}: workerOptions.connectionRef.name (${ref_name}) does not name the Connection in this file (${conn_name})" >&2
    exit 1
  fi

  # --- The pod template must NOT hand-set the identity the controller injects.
  # Both spellings are rejected: the current one would give the pod two
  # identities (pkg/temporalx exits 1 on a disagreement, but failing here beats
  # failing at pod start), and the retired TEMPORAL_WORKER_DEPLOYMENT_NAME would
  # be a variable no binary reads any more — a manifest that lies quietly.
  local stray
  stray=$(yq eval-all '[select(.kind == "WorkerDeployment") | .spec.template.spec.containers[].env[]? | select(.name == "TEMPORAL_DEPLOYMENT_NAME" or .name == "TEMPORAL_WORKER_BUILD_ID" or .name == "TEMPORAL_WORKER_DEPLOYMENT_NAME")] | length' "${wd}")
  if [[ -n "${stray}" && "${stray}" != "null" && "${stray}" -ne 0 ]]; then
    echo "ERROR - ${wd}: the pod template hand-sets versioning env. The controller injects TEMPORAL_DEPLOYMENT_NAME and TEMPORAL_WORKER_BUILD_ID per version (internal/k8s/deployments.go); a hand-set copy is a second identity." >&2
    exit 1
  fi

  # --- Unversioned workers must stay unversioned. checkout-worker is not under
  # versioning (RFC-0026 deferred it), and an in-place env flip is the proven
  # silent-hang mistake.
  local unversioned="kubernetes/apps/checkout-worker.yaml"
  if [[ -f "${unversioned}" ]]; then
    local env_count uv_stray
    # Existence first: with .spec.values.env absent the select below returns 0
    # rather than erroring, and the check would pass while reading nothing.
    env_count=$(yq '.spec.values.env | length' "${unversioned}")
    if [[ -z "${env_count}" || "${env_count}" == "null" || "${env_count}" -eq 0 ]]; then
      echo "ERROR - ${unversioned}: .spec.values.env is missing or empty; the versioning check cannot read anything" >&2
      exit 1
    fi
    uv_stray=$(yq '[.spec.values.env[] | select(.name == "TEMPORAL_DEPLOYMENT_NAME" or .name == "TEMPORAL_WORKER_BUILD_ID" or .name == "TEMPORAL_WORKER_DEPLOYMENT_NAME")] | length' "${unversioned}")
    if [[ "${uv_stray}" -ne 0 ]]; then
      echo "ERROR - ${unversioned}: carries Worker Versioning env but is not a WorkerDeployment. Versioning is the controller's to grant (ADR-054); setting it here polls as a version nothing routes to." >&2
      exit 1
    fi
  fi

  echo "INFO - order-worker versioning: single WorkerDeployment wired to Connection '${conn_name}', no per-build manifests, no hand-set version identity"
}

# Kyverno policy behaviour. kubeconform only checks SHAPE, and it runs with
# -ignore-missing-schemas, so a Kyverno CRD whose schema is absent is waved
# through silently -- schema validation is not policy validation. `kyverno test`
# asks the only question that matters: given this manifest, does this policy
# pass or fail? That is the class of bug this repo has actually shipped. The
# first run of these fixtures found one: require-probes returned `error`, not a
# verdict, for any Pod with no ownerReferences.
#
# Pin the CLI to the engine the cluster runs (chart 3.8.2 -> v1.18.2). A CLI
# ahead of the engine can agree with itself and disagree with admission.
validate_kyverno_policies() {
  local dir="kubernetes/infra/configs/kyverno/tests"
  if [[ ! -d "$dir" ]]; then
    echo "ERROR - $dir is missing; the policy fixtures are not optional" >&2
    exit 1
  fi
  local count
  count=$(find "$dir" -name 'kyverno-test.yaml' | wc -l | tr -d ' ')
  if [[ "$count" -eq 0 ]]; then
    echo "ERROR - no kyverno-test.yaml found under $dir" >&2
    exit 1
  fi
  echo "INFO - Running $count Kyverno policy test suite(s)"
  if ! kyverno test "$dir"; then
    echo "ERROR - Kyverno policy tests failed" >&2
    exit 1
  fi
  echo "INFO - Kyverno policy tests passed"
}

# Main
check_prerequisites
download_schemas
validate_yaml_syntax
validate_standalone_manifests
validate_kustomize_overlays
validate_worker_versioning
validate_kyverno_policies
validate_production
echo "INFO - All validations passed"
