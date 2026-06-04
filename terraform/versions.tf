terraform {
  required_version = ">= 1.11.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0.0"
    }
  }

  # Local backend for the homelab Kind cluster (state is gitignored).
  # PRODUCTION: switch to a remote backend (e.g. S3 + DynamoDB lock, GCS, or
  # Terraform Cloud) so state is shared and locked across operators.
  #
  # backend "s3" {
  #   bucket         = "duynhlab-tfstate"
  #   key            = "homelab/flux-operator-bootstrap.tfstate"
  #   region         = "ap-southeast-1"
  #   dynamodb_table = "duynhlab-tfstate-lock"
  #   encrypt        = true
  # }
}
