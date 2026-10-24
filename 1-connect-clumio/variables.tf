variable "account_id" {
  description = "The AWS account to protect. Terraform refuses to run when you're signed in to any other account."
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

# The IAM settings below are validated by modules/clumio-account-iam.

variable "iam_prefix" {
  description = "The start of every IAM role and policy name Clumio creates. Empty means Clumio's default names."
  type        = string
}

variable "iam_path" {
  description = "The IAM path for Clumio's roles and policies. \"/clumio/\" is Clumio's default, and \"/\" means no path."
  type        = string
}

variable "workloads" {
  description = "What Clumio may protect in this account and Region: \"s3\", \"rds\" (RDS and Aurora), \"ebs\" (EC2 and EBS). Each adds its own IAM."
  type        = list(string)
  default     = ["s3"]
}

variable "role_tags" {
  description = "Tags your organization requires on IAM roles. Added to Clumio's own tag (Vendor = Clumio)."
  type        = map(string)
  default     = {}
}

variable "permissions_boundary_arn" {
  description = "The permissions boundary your organization requires on IAM roles, or empty for none. It must allow what Clumio's policies grant, or backups fail."
  type        = string
  default     = ""
}

variable "pass_role_deny_list" {
  description = "Roles Clumio must never pass to a service, by ARN. Adds a policy that denies it."
  type        = list(string)
  default     = []
}

variable "report_emails" {
  description = "Who gets Clumio's compliance report for this Region: whether every asset has a backup each day. Empty means no report."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.report_emails : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", e))])
    error_message = "report_emails must be email addresses, such as platform-oncall@example.com."
  }
}
