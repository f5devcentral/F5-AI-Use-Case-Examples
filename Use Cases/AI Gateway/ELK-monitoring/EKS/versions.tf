terraform {
  required_version = ">= 1.3"

  required_providers {
    volterra = {
       source = "volterraedge/volterra"
       version = ">=0.0.6"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.34"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
  }
}
