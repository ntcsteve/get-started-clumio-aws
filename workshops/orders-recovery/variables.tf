variable "account_id" {
  description = "The test AWS account for the workshop. Terraform stops if you're signed in to any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Set account_id in terraform.tfvars to your 12-digit test account ID."
  }
}

variable "region" {
  description = "The AWS Region for the workshop. It must offer the RDS Data API for Aurora MySQL."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region)) # commercial Regions only
    error_message = "Set region in terraform.tfvars to your AWS Region, such as ap-southeast-1."
  }
}

variable "archive_retention_months" {
  description = "Months to keep each SecureVault Archive copy; 0 means no Archive. The workshop keeps 1, the shortest Clumio allows. Production often keeps years."
  type        = number
  default     = 1
}

variable "rds_rule_before_id" {
  description = "Only if ./lab status says another Clumio policy protects orders-db: the rule ID it shows. The workshop's rule then goes before that older rule. Empty means last."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags your organization requires on every AWS resource. The workshop adds Workshop = orders-recovery."
  type        = map(string)
  default     = {}
}

# Your organization's IAM rules, for the IAM roles Clumio creates.
variable "iam_prefix" {
  description = "The start of the IAM role and policy names Clumio creates. Empty means the default names."
  type        = string
  default     = ""
}

variable "iam_path" {
  description = "The IAM path for every IAM role and policy. \"/clumio/\" is Clumio's default; \"/\" means no path."
  type        = string
  default     = "/clumio/"
}

variable "role_tags" {
  description = "Tags your organization requires on IAM roles."
  type        = map(string)
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "The permissions boundary your organization requires on IAM roles, or empty for none."
  type        = string
  default     = ""
}
