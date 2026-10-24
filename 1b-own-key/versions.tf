terraform {
  required_version = ">= 1.5"
  required_providers {
    clumio = {
      source  = "clumio-code/clumio"
      version = ">= 0.24.0, < 0.25.0" # Narrower than Clumio's module allows, so upgrades are deliberate.
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # A new major version can change behavior, so it's pinned.
    }
    # Used inside Clumio's byok-template module.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
