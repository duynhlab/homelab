# Local homelab defaults — copy to terraform.tfvars only if you need overrides.
# All values below match the variable defaults, shown here for reference.

cluster_name    = "local"
kubeconfig_path = "~/.kube/config"
kube_context    = "kind-homelab"
revision        = 1

# PRODUCTION example (separate tfvars / workspace):
# cluster_name = "production"
# kube_context = "duynhlab-prod"
