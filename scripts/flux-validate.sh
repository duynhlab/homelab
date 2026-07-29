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
  "-verbose"
)

# Kustomize overlays that Flux actually reconciles (matches Flux Kustomization paths).
# These are the ONLY overlays we kustomize-build; auto-discovery causes parent/child
# collisions when intermediate kustomization.yaml files reference subdirectories.
kustomize_overlays=(
  "kubernetes/clusters/local"
  "kubernetes/infra/controllers"
  # temporal is BOTH listed here and excluded from controllers/kustomization.yaml:
  # it needs its own Flux Kustomization so apps-local can depend on the server
  # being Ready, which means `kustomize build kubernetes/infra/controllers` never
  # reaches it. Without these two entries the chart and its ingress/PrometheusRule
  # were validated by nothing at all.
  "kubernetes/infra/controllers/temporal"
  "kubernetes/infra/configs/temporal"
  "kubernetes/infra/configs/databases"
  "kubernetes/infra/configs/observability"
  "kubernetes/infra/configs/secrets"
  "kubernetes/infra/configs/kyverno"
  "kubernetes/infra/configs/network-policies"
)

check_prerequisites() {
  local missing=0
  for cmd in yq kustomize kubeconform curl; do
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

# The order worker pins workflows to a Worker Deployment Version whose Build ID is
# an env var, while its image comes from image.tag in the same file, and the cutover
# CronJob names the same Build ID a third time. If any of the three drift, the
# Temporal server routes new workflows to a version NO worker serves: they sit there
# with no error in any log, no failed activity, and no alert — the cutover simply
# stops progressing. Nothing else compares them, so this does.
#
# Written to fail LOUDLY rather than skip: every path that cannot make the
# comparison exits non-zero. A guard that silently compares nothing is worse than no
# guard, because its green line reads as proof.
validate_worker_build_id() {
  local file="kubernetes/apps/order-worker.yaml"
  local cutover="kubernetes/infra/controllers/temporal/worker-set-current-version-cronjob.yaml"

  if [[ ! -f "${file}" ]]; then
    echo "ERROR - ${file} is missing; cannot verify the Worker Versioning Build ID" >&2
    exit 1
  fi
  if [[ ! -f "${cutover}" ]]; then
    echo "ERROR - ${cutover} is missing; cannot verify the cutover Build ID" >&2
    exit 1
  fi

  local tag env_count
  tag=$(yq '.spec.values.image.tag' "${file}")
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    echo "ERROR - ${file}: .spec.values.image.tag is missing" >&2
    exit 1
  fi

  # The env list itself must exist. Without this check, a chart-side rename
  # (values.env -> values.extraEnv, or env-as-map) makes every read below return
  # empty and the function would conclude "versioning not configured" — reporting
  # success while comparing nothing.
  env_count=$(yq '.spec.values.env | length' "${file}")
  if [[ -z "${env_count}" || "${env_count}" == "null" || "${env_count}" -eq 0 ]]; then
    echo "ERROR - ${file}: .spec.values.env is missing or empty; the Build ID check cannot read anything" >&2
    exit 1
  fi

  local dep_name build_id
  dep_name=$(yq '.spec.values.env[] | select(.name == "TEMPORAL_WORKER_DEPLOYMENT_NAME") | .value' "${file}")
  build_id=$(yq '.spec.values.env[] | select(.name == "TEMPORAL_WORKER_BUILD_ID") | .value' "${file}")
  [[ "${dep_name}" == "null" ]] && dep_name=""
  [[ "${build_id}" == "null" ]] && build_id=""

  # Both absent is legitimate — temporalx treats an unset pair as "not versioned".
  if [[ -z "${dep_name}" && -z "${build_id}" ]]; then
    echo "INFO - order-worker: Worker Versioning not configured (both env vars absent)"
    return 0
  fi
  # Either half alone is the state temporalx exits on, in BOTH directions.
  if [[ -z "${dep_name}" || -z "${build_id}" ]]; then
    echo "ERROR - ${file}: Worker Versioning is half-configured (DEPLOYMENT_NAME='${dep_name}', BUILD_ID='${build_id}'); temporalx refuses to start" >&2
    exit 1
  fi

  if [[ "${build_id}" != "${tag}" ]]; then
    echo "ERROR - ${file}: TEMPORAL_WORKER_BUILD_ID (${build_id}) != image.tag (${tag}). New workflows would pin to a version no worker serves and hang silently." >&2
    exit 1
  fi

  # Third copy: the --build-id argument of the cutover CronJob. Read positionally
  # (the flag's value is the next element), and fail if it cannot be located.
  local idx job_build_id
  idx=$(yq '.spec.jobTemplate.spec.template.spec.containers[0].args | to_entries | map(select(.value == "--build-id")) | .[0].key' "${cutover}")
  if [[ -z "${idx}" || "${idx}" == "null" ]]; then
    echo "ERROR - ${cutover}: no --build-id argument found" >&2
    exit 1
  fi
  job_build_id=$(yq ".spec.jobTemplate.spec.template.spec.containers[0].args[$((idx + 1))]" "${cutover}")
  if [[ -z "${job_build_id}" || "${job_build_id}" == "null" ]]; then
    echo "ERROR - ${cutover}: --build-id has no value" >&2
    exit 1
  fi
  if [[ "${job_build_id}" != "${tag}" ]]; then
    echo "ERROR - ${cutover}: --build-id (${job_build_id}) != order-worker image.tag (${tag}). The cutover would make a version Current that no deployed worker serves." >&2
    exit 1
  fi

  echo "INFO - order-worker: Build ID ${tag} consistent across image.tag, worker env, and the cutover CronJob"
}

# Main
check_prerequisites
download_schemas
validate_yaml_syntax
validate_standalone_manifests
validate_kustomize_overlays
validate_worker_build_id
validate_production
echo "INFO - All validations passed"
