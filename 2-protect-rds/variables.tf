variable "account_id" {
  description = "The AWS account to protect: the one step 1 connected."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Set account_id in terraform.tfvars to your 12-digit AWS account ID."
  }
}

variable "region" {
  description = "The AWS region your data is in, such as ap-southeast-1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov|-iso[a-z]*)?-[a-z]+-[0-9]$", var.region))
    error_message = "Set region in terraform.tfvars to your AWS region, such as ap-southeast-1."
  }
}

variable "name" {
  description = "Name of the Clumio policy and rule, unique across your tenant. Empty means rds-<account>-<region>."
  type        = string
  default     = ""
}

variable "database_tag" {
  description = "Protect every RDS instance and Aurora cluster carrying this tag, including ones added later."
  type = object({
    key   = string
    value = string
  })
}

variable "pitr_retention_days" {
  description = "The AWS PITR window, in days, that Clumio sets on every tagged database, higher or lower than today. No default, so you choose it."
  type        = number

  validation {
    condition     = var.pitr_retention_days != 0
    error_message = "Set pitr_retention_days in terraform.tfvars to the PITR window you run today (BackupRetentionPeriod: `aws rds describe-db-clusters` for Aurora, `describe-db-instances` for RDS). Clumio sets it up AND down."
  }

  # 0 is the shipped placeholder, stopped by the check above with a clearer message.
  validation {
    condition     = var.pitr_retention_days == 0 || (var.pitr_retention_days >= 1 && var.pitr_retention_days <= 35 && floor(var.pitr_retention_days) == var.pitr_retention_days)
    error_message = "pitr_retention_days must be a whole number from 1 to 35 (AWS's range)."
  }
}

variable "standard_retention_days" {
  description = "How long each daily SecureVault Standard copy is kept, in days."
  type        = number
  default     = 7

  validation {
    condition     = var.standard_retention_days >= 1 && floor(var.standard_retention_days) == var.standard_retention_days
    error_message = "standard_retention_days must be a whole number, 1 or more."
  }
}

variable "archive_retention_months" {
  description = "How long each monthly SecureVault Archive copy is kept, in months. Under 12 costs an early-deletion fee."
  type        = number
  default     = 12

  validation {
    condition     = var.archive_retention_months >= 1 && floor(var.archive_retention_months) == var.archive_retention_months
    error_message = "archive_retention_months must be a whole number, 1 or more."
  }
}
