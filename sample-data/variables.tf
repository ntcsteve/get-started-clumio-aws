variable "account_id" {
  description = "A sandbox AWS account. Terraform refuses to run with a login to any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Set account_id in terraform.tfvars to your 12-digit AWS account ID."
  }
}

variable "region" {
  description = "The AWS region for the sample data, such as ap-southeast-1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov|-iso[a-z]*)?-[a-z]+-[0-9]$", var.region))
    error_message = "Set region in terraform.tfvars to your AWS region, such as ap-southeast-1."
  }
}

variable "with_aurora" {
  description = "Also create a small Aurora MySQL cluster with 1,000 rows. About 10 minutes; costs money while it runs."
  type        = bool
  default     = false
}

variable "backup_tag" {
  description = "Tag on the bucket and the Aurora cluster. Step 2 picks them by this tag."
  type = object({
    key   = string
    value = string
  })
  default = { key = "backup-tier", value = "gold" }
}
