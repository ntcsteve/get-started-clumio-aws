terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    clumio = {
      source  = "clumio-code/clumio" # Used by Clumio's aws-template module inside this one.
      version = ">= 0.24.0, < 0.25.0"
    }
  }
}
