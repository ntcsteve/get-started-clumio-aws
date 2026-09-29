variable "account_id" {
  description = "The AWS account to protect. Terraform refuses to run with a login to any other account."
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

variable "iam_prefix" {
  description = "The start of every IAM role and policy name Clumio creates. Empty means Clumio's default names."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{0,36}$", var.iam_prefix))
    error_message = "iam_prefix: at most 36 characters, only letters, digits and + = , . @ _ -"
  }
}

variable "iam_path" {
  description = "The IAM path for Clumio's roles and policies. \"/clumio/\" is Clumio's default, and \"/\" means no path."
  type        = string

  validation {
    condition     = can(regex("^/([A-Za-z0-9+=,.@_-]+/)*$", var.iam_path))
    error_message = "iam_path must start and end with / (e.g. / or /clumio/)."
  }
}

variable "workloads" {
  description = "What Clumio may protect in this account + region: \"s3\", \"rds\" (RDS + Aurora), \"ebs\" (EC2 + EBS). Each adds its own IAM."
  type        = list(string)
  default     = ["s3"]

  validation {
    condition     = length(var.workloads) > 0 && alltrue([for w in var.workloads : contains(["s3", "rds", "ebs"], w)])
    error_message = "workloads: one or more of \"s3\", \"rds\", \"ebs\"."
  }
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

  validation {
    condition     = var.permissions_boundary_arn == "" || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be a managed policy ARN (arn:aws:iam::<account>:policy/...) or \"\"."
  }
}

variable "pass_role_deny_list" {
  description = "Roles Clumio must never pass to a service, by ARN. Adds a policy that denies it."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.pass_role_deny_list : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", r))])
    error_message = "pass_role_deny_list: role ARNs only (arn:aws:iam::<account>:role/...)."
  }
}
