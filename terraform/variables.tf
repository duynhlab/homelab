variable "cluster_name" {
  description = "Logical cluster name. Drives the FluxInstance manifest path under kubernetes/clusters/<cluster_name>/flux-system/instance.yaml."
  type        = string
  default     = "local"
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context targeting the cluster. Kind uses kind-<kind_cluster_name>."
  type        = string
  default     = "kind-homelab"
}

variable "revision" {
  description = "Bump to force a bootstrap Job re-run without changing manifest content."
  type        = number
  default     = 1
}
