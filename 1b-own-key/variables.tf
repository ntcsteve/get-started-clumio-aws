variable "account_id" {
  description = "The AWS account that holds the key: the one step 1 connected. Terraform refuses to run when you're signed in to any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Set account_id in terraform.tfvars to your 12-digit AWS account ID."
  }
}

variable "clumio_region" {
  description = "Your Clumio control-plane Region, set when your Clumio account was created (portal.clumio.com is us-west-2). Often not your data's Region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.clumio_region))
    error_message = "Set clumio_region in terraform.tfvars to your Clumio control-plane Region, such as us-west-2. See README.md in 1b-own-key."
  }
}

variable "key_id" {
  description = "Your AWS KMS multi-Region primary key's ID (mrk-...), in clumio_region. Created outside Terraform, so no Terraform change can delete it."
  type        = string

  validation {
    condition     = can(regex("^mrk-[0-9a-f]{32}$", var.key_id))
    error_message = "Set key_id in terraform.tfvars to your key's ID: mrk- and 32 hex characters. A single-Region key can't be used. No key yet? See README.md in 1b-own-key."
  }
}

variable "iam_prefix" {
  description = "The start of the name of the IAM role Clumio uses for the key, as in step 1. Empty means ClumioKMSRole."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{0,49}$", var.iam_prefix))
    error_message = "iam_prefix must be at most 49 characters: letters, digits and + = , . @ _ - only."
  }
}

variable "i_understand_byok_is_permanent" {
  description = "Set to true to turn on BYOK. Your Clumio tenant stays bound to this key and AWS account for good."
  type        = bool
  default     = false

  validation {
    condition     = var.i_understand_byok_is_permanent
    error_message = "BYOK is permanent: read README.md in 1b-own-key, then set i_understand_byok_is_permanent = true."
  }
}
