variable "account_id" {
  description = "The AWS account to protect: the one step 1 connected."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Set account_id in terraform.tfvars to your 12-digit AWS account ID."
  }
}

variable "region" {
  description = "The AWS Region your data is in, such as ap-southeast-1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov|-iso[a-z]*)?-[a-z]+-[0-9]$", var.region))
    error_message = "Set region in terraform.tfvars to your AWS Region, such as ap-southeast-1."
  }
}

variable "name" {
  description = "Name of the Clumio policy and rule, unique across your tenant. Empty means rds-<account>-<region>."
  type        = string
  default     = ""
}

variable "protect_by" {
  description = "How databases are chosen: \"tag\" (database_tag) or \"name\" (database_names)."
  type        = string
  default     = "tag" # Configs written before protect_by existed set only database_tag, so they keep working.
}

variable "database_tag" {
  description = "With protect_by = \"tag\": protect every RDS instance and Aurora cluster with this tag, including ones tagged later."
  type = object({
    key   = string
    value = string
  })
  default = null
}

variable "database_names" {
  description = "With protect_by = \"name\": the RDS instances and Aurora clusters to protect, by identifier (not ARN)."
  type        = list(string)
  default     = []
}

variable "pitr_retention_days" {
  description = "The AWS PITR window, in days, that Clumio sets on every chosen database, higher or lower than today. No default, so you choose it."
  type        = number
}

variable "standard_retention_days" {
  description = "How long each daily SecureVault Standard copy is kept, in days."
  type        = number
  default     = 7
}

variable "archive_retention_months" {
  description = "How long each monthly SecureVault Archive copy is kept, in months; 0 means no Archive tier. Under 12 costs an early-deletion fee."
  type        = number
  default     = 12
}
