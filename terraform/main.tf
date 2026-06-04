# Flux Operator bootstrap for the duynhlab homelab.
#
# Terraform/OpenTofu owns only the ephemeral bootstrap mechanism (namespace,
# RBAC, the bootstrap Job). The Job installs Flux Operator and applies the
# FluxInstance with create-if-missing semantics, then Flux adopts those
# resources and reconciles steady-state. When manifests are unchanged,
# `tofu plan` shows zero diff.
#
# The FluxInstance manifest is the single source of truth shared with the
# kubectl/kustomize flow it replaces:
#   kubernetes/clusters/<cluster_name>/flux-system/instance.yaml

module "flux_operator_bootstrap" {
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "0.7.0"

  revision = var.revision

  gitops_resources = {
    instance_yaml = file("${path.root}/../kubernetes/clusters/${var.cluster_name}/flux-system/instance.yaml")
  }

  # PRODUCTION (manage the OCI/Git pull secret declaratively from an external
  # store — see module README "Managed secrets from an external secrets store").
  # Keep this commented for local: the Kind registry is HTTP/insecure and needs
  # no auth. The Secret name must match `spec.sync.pullSecret` in instance.yaml.
  #
  # managed_resources = {
  #   secrets_yaml = <<-YAML
  #     apiVersion: v1
  #     kind: Secret
  #     metadata:
  #       name: flux-system
  #       namespace: flux-system
  #     type: kubernetes.io/dockerconfigjson
  #     stringData:
  #       .dockerconfigjson: '${replace(local.ghcr_auth_dockerconfigjson, "'", "''")}'
  #   YAML
  # }
}

# PRODUCTION: build a registry pull secret from a Terraform variable or an
# external secrets data source (AWS/GCP/Azure/Vault). No secret material is
# stored in state — the module only persists a SHA-256 hash.
#
# locals {
#   ghcr_auth_dockerconfigjson = jsonencode({
#     auths = {
#       "ghcr.io" = {
#         username = "flux"
#         password = var.ghcr_token
#         auth     = base64encode("flux:${var.ghcr_token}")
#       }
#     }
#   })
# }
