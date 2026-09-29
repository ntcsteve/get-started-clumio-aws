# Versions for this step.
terraform {
  required_version = ">= 1.5"
  required_providers {
    clumio = {
      source  = "clumio-code/clumio"
      version = ">= 0.24.0, < 0.25.0"
    }
  }
}
