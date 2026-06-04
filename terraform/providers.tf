# Provider configuration for the local Kind cluster.
#
# The Kind kubeconfig context is `kind-<cluster_name>` (default: kind-homelab).
# Both providers read the local kubeconfig directly — no cluster connectivity is
# required at plan time, so this root can run before the cluster is fully up.
#
# PRODUCTION: replace `config_context` with explicit endpoint/token/CA wiring
# (or an `exec` credential plugin: `aws eks get-token`, gke-gcloud-auth-plugin,
# kubelogin for AKS, …) sourced from the cluster module's outputs. See the
# module README "Same-module cluster creation" section.

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
