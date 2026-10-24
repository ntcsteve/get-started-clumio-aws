variable "account_id" {
  description = "The AWS account to protect: the one step 1 connected."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "The AWS Region your data is in, such as ap-southeast-1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-gov|-iso[a-z]*)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS Region code, such as ap-southeast-1."
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

  validation {
    condition     = contains(["tag", "name"], var.protect_by)
    error_message = "protect_by must be \"tag\" or \"name\"."
  }
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

  validation {
    condition     = alltrue([for n in var.database_names : can(regex("^[a-z][a-z0-9-]{0,62}$", n))])
    error_message = "database_names must be DB identifiers as RDS shows them, in lowercase (such as my-uat-db), not ARNs."
  }
}

variable "pitr_retention_days" {
  description = "The AWS PITR window, in days, that Clumio sets on every chosen database, higher or lower than today. No default, so you choose it."
  type        = number

  validation {
    condition     = var.pitr_retention_days != 0
    error_message = "Set pitr_retention_days to the PITR window you run today (BackupRetentionPeriod: `aws rds describe-db-clusters` for Aurora, `describe-db-instances` for RDS). Clumio sets it up AND down."
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
  description = "How long each monthly SecureVault Archive copy is kept, in months; 0 means no Archive tier. Under 12 costs an early-deletion fee."
  type        = number
  default     = 12

  validation {
    condition     = var.archive_retention_months >= 0 && floor(var.archive_retention_months) == var.archive_retention_months
    error_message = "archive_retention_months must be a whole number: 0 for no Archive, or the months to keep each copy."
  }
}

variable "before_rule_id" {
  description = "The ID of an existing Clumio policy rule to place this rule before. Empty means last, after every existing rule. Set it only when an older, wider rule claims these databases first."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^$|^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.before_rule_id))
    error_message = "before_rule_id must be empty or a Clumio rule ID, such as 03427765-b500-4b3d-a189-0da8f278d261."
  }
}
