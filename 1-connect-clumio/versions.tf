# Step 0 reads this file too, so the preview and the apply use the same versions.
terraform {
  required_version = ">= 1.5"
  required_providers {
    clumio = {
      source  = "clumio-code/clumio"
      version = ">= 0.24.0, < 0.25.0" # Narrower than Clumio's module allows, so upgrades are deliberate.
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # A new major version can change behaviour, so it's pinned.
    }
  }
}
