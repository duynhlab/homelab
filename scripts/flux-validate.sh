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
  "kubernetes/infra/configs/databases"
  "kubernetes/infra/configs/monitoring"
  "kubernetes/infra/configs/secrets"
  "kubernetes/infra/configs/kyverno"
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

# Main
check_prerequisites
download_schemas
validate_yaml_syntax
validate_standalone_manifests
validate_kustomize_overlays
validate_production
echo "INFO - All validations passed"
