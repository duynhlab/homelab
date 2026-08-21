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


# Versioned order workers pin new workflows to a Worker Deployment Version whose
# Build ID is an env var, while the image comes from image.tag in the same file,
# and the cutover CronJob names a Build ID and deployment name again. If any copy
# drifts, the Temporal server routes new workflows to a version NO worker serves:
# they sit there with no error in any log, no failed activity, and no alert — the
# cutover simply stops progressing. Nothing else compares them, so this does.
#
# Written to fail LOUDLY rather than skip: every path that cannot make a
# comparison exits non-zero. A guard that silently compares nothing is worse than
# no guard, because its green line reads as proof.
#
# Layout it enforces (ADR-030):
#   kubernetes/apps/order-worker.yaml        — the unversioned worker. OPTIONAL:
#     the retirement PR deletes it. While present it must carry NO versioning env
#     (an in-place flip is the proven silent-hang mistake).
#   kubernetes/apps/order-worker-*.yaml      — one file per versioned build,
#     discovered by glob so the next release is covered without editing this.
#   the cutover CronJob                      — its --build-id must name a build
#     some deployed versioned worker serves.
validate_worker_build_id() {
  local unversioned="kubernetes/apps/order-worker.yaml"
  local cutover="kubernetes/infra/controllers/temporal/worker-set-current-version-cronjob.yaml"

  if [[ ! -f "${cutover}" ]]; then
    echo "ERROR - ${cutover} is missing; cannot verify the Worker Versioning wiring" >&2
    exit 1
  fi

  # --- The unversioned worker, while it exists, must stay unversioned.
  if [[ -f "${unversioned}" ]]; then
    local env_count stray
    # Existence first: with .spec.values.env absent, the select below returns 0
    # rather than erroring, and the check would pass while reading nothing.
    env_count=$(yq '.spec.values.env | length' "${unversioned}")
    if [[ -z "${env_count}" || "${env_count}" == "null" || "${env_count}" -eq 0 ]]; then
      echo "ERROR - ${unversioned}: .spec.values.env is missing or empty; the versioning check cannot read anything" >&2
      exit 1
    fi
    stray=$(yq '[.spec.values.env[] | select(.name == "TEMPORAL_WORKER_BUILD_ID" or .name == "TEMPORAL_WORKER_DEPLOYMENT_NAME")] | length' "${unversioned}")
    if [[ "${stray}" -ne 0 ]]; then
      echo "ERROR - ${unversioned}: carries Worker Versioning env. Versioning ships as a SIDE-BY-SIDE deployment (order-worker-<build>.yaml), never as an in-place flip — see ADR-030." >&2
      exit 1
    fi
  fi

  # --- Every versioned worker file, by glob.
  local -a versioned_files=()
  local f
  for f in kubernetes/apps/order-worker-*.yaml; do
    [[ -f "${f}" ]] && versioned_files+=("${f}")
  done
  if [[ ${#versioned_files[@]} -eq 0 ]]; then
    echo "ERROR - no kubernetes/apps/order-worker-<build>.yaml found while the cutover CronJob exists; its --build-id would name a version no worker serves" >&2
    exit 1
  fi

  local -a tags=() dep_names=() recon_enabled=()
  local tag env_count dep_name build_id fname_build
  for f in "${versioned_files[@]}"; do
    tag=$(yq '.spec.values.image.tag' "${f}")
    if [[ -z "${tag}" || "${tag}" == "null" ]]; then
      echo "ERROR - ${f}: .spec.values.image.tag is missing" >&2
      exit 1
    fi
    env_count=$(yq '.spec.values.env | length' "${f}")
    if [[ -z "${env_count}" || "${env_count}" == "null" || "${env_count}" -eq 0 ]]; then
      echo "ERROR - ${f}: .spec.values.env is missing or empty; the Build ID check cannot read anything" >&2
      exit 1
    fi
    dep_name=$(yq '.spec.values.env[] | select(.name == "TEMPORAL_WORKER_DEPLOYMENT_NAME") | .value' "${f}")
    build_id=$(yq '.spec.values.env[] | select(.name == "TEMPORAL_WORKER_BUILD_ID") | .value' "${f}")
    [[ "${dep_name}" == "null" ]] && dep_name=""
    [[ "${build_id}" == "null" ]] && build_id=""
    if [[ -z "${dep_name}" || -z "${build_id}" ]]; then
      echo "ERROR - ${f}: Worker Versioning env incomplete (DEPLOYMENT_NAME='${dep_name}', BUILD_ID='${build_id}')" >&2
      exit 1
    fi
    if [[ "${build_id}" != "${tag}" ]]; then
      echo "ERROR - ${f}: TEMPORAL_WORKER_BUILD_ID (${build_id}) != image.tag (${tag}). New workflows would pin to a version no worker serves and hang silently." >&2
      exit 1
    fi
    # The filename is the human's copy of the Build ID; a file whose name lies
    # about its contents defeats the one-file-per-build layout.
    fname_build=$(basename "${f}" .yaml); fname_build=${fname_build#order-worker-}
    if [[ "${fname_build}" != "${tag//./-}" ]]; then
      echo "ERROR - ${f}: filename says build '${fname_build}' but image.tag is '${tag}' (expected order-worker-${tag//./-}.yaml)" >&2
      exit 1
    fi
    tags+=("${tag}")
    dep_names+=("${dep_name}")

    # The reconciler is a SINGLE-JUDGE role: its scan claims nothing (no FOR
    # UPDATE SKIP LOCKED), so two runners judge the same orders concurrently and
    # can both act on one. Side-by-side worker builds make that easy to get
    # wrong — every build carries the env, and leaving the old one enabled at an
    # activation is invisible until the judgements disagree.
    local recon
    recon=$(yq '[.spec.values.env[] | select(.name == "ORDER_RECONCILER_ENABLED") | .value] | .[0]' "${f}")
    if [[ "${recon}" == "true" ]]; then
      recon_enabled+=("${tag}")
    fi
  done

  if [[ ${#recon_enabled[@]} -ne 1 ]]; then
    echo "ERROR - order-worker: ORDER_RECONCILER_ENABLED must be \"true\" on EXACTLY ONE build (found: ${recon_enabled[*]:-none}). It is a single-judge role; enable it on the build the cutover CronJob makes Current and disable it on every draining build." >&2
    exit 1
  fi

  # --- The CronJob's args must actually invoke this subcommand — flag equality
  # on a job that runs something else entirely proves nothing.
  local arg0 subcmd
  arg0=$(yq '.spec.jobTemplate.spec.template.spec.containers[0].args[0]' "${cutover}")
  subcmd=$(yq '[.spec.jobTemplate.spec.template.spec.containers[0].args[] | select(. == "set-current-version")] | length' "${cutover}")
  if [[ "${arg0}" != "temporal" || "${subcmd}" != "1" ]]; then
    echo "ERROR - ${cutover}: args do not invoke 'temporal ... set-current-version' (args[0]='${arg0}')" >&2
    exit 1
  fi

  local flag idx job_build_id job_dep_name flag_count
  for flag in --build-id --deployment-name; do
    # Exactly once: the CLI lets a LATER duplicate win, so a drifted second copy
    # would pass a first-occurrence read while being the value that executes.
    flag_count=$(yq "[.spec.jobTemplate.spec.template.spec.containers[0].args[] | select(. == \"${flag}\")] | length" "${cutover}")
    if [[ "${flag_count}" != "1" ]]; then
      echo "ERROR - ${cutover}: ${flag} must appear exactly once (found ${flag_count})" >&2
      exit 1
    fi
    idx=$(yq ".spec.jobTemplate.spec.template.spec.containers[0].args | to_entries | map(select(.value == \"${flag}\")) | .[0].key" "${cutover}")
    if [[ -z "${idx}" || "${idx}" == "null" ]]; then
      echo "ERROR - ${cutover}: no ${flag} argument found" >&2
      exit 1
    fi
    local val
    val=$(yq ".spec.jobTemplate.spec.template.spec.containers[0].args[$((idx + 1))]" "${cutover}")
    if [[ -z "${val}" || "${val}" == "null" ]]; then
      echo "ERROR - ${cutover}: ${flag} has no value" >&2
      exit 1
    fi
    [[ "${flag}" == "--build-id" ]] && job_build_id="${val}" || job_dep_name="${val}"
  done

  # The reconciler must be Current-build-only; compare after the CronJob is read.
  if [[ "${recon_enabled[0]}" != "${job_build_id}" ]]; then
    echo "ERROR - order-worker: ORDER_RECONCILER_ENABLED is \"true\" on build ${recon_enabled[0]}, but the cutover CronJob makes ${job_build_id} Current. The judge must be the Current build." >&2
    exit 1
  fi

  local hit=0 t
  for t in "${tags[@]}"; do [[ "${t}" == "${job_build_id}" ]] && hit=1; done
  if [[ ${hit} -ne 1 ]]; then
    echo "ERROR - ${cutover}: --build-id (${job_build_id}) matches no deployed versioned worker (have: ${tags[*]}). The cutover would make a version Current that no worker serves." >&2
    exit 1
  fi
  for t in "${dep_names[@]}"; do
    if [[ "${t}" != "${job_dep_name}" ]]; then
      echo "ERROR - ${cutover}: --deployment-name (${job_dep_name}) != a worker's TEMPORAL_WORKER_DEPLOYMENT_NAME (${t})" >&2
      exit 1
    fi
  done

  echo "INFO - order-worker versioning: builds [${tags[*]}] consistent across manifests and the cutover CronJob (--build-id ${job_build_id}, deployment ${job_dep_name})"
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
validate_worker_build_id
validate_kyverno_policies
validate_production
echo "INFO - All validations passed"
