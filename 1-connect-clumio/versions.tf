# Versions for this step. 0-iam-preview reads 1-connect-clumio's copy, so preview and apply match.
terraform {
  required_version = ">= 1.5"
  required_providers {
    clumio = {
      source  = "clumio-code/clumio"
      version = ">= 0.24.0, < 0.25.0" # narrowed from the range Clumio's module accepts
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # major version pinned: a new major can change behaviour
    }
  }
}
