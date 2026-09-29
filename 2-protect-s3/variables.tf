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
  description = "Name of the Clumio protection group and its policy. \"\" = s3-<account>-<region>. Unique across the Clumio tenant."
  type        = string
  default     = ""
}

variable "protect_by" {
  description = "How buckets are chosen: \"name\" (bucket_names) or \"tag\" (bucket_tag)."
  type        = string

  validation {
    condition     = contains(["name", "tag"], var.protect_by)
    error_message = "protect_by must be \"name\" or \"tag\"."
  }
}

variable "bucket_names" {
  description = "protect_by = \"name\": the buckets to back up (names, not ARNs)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.bucket_names : n == "BUCKET-NAME-REPLACE-THIS" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", n))])
    error_message = "bucket_names: use bucket names (e.g. my-bucket), not ARNs (arn:aws:s3:::my-bucket)."
  }
}

variable "bucket_tag" {
  description = "protect_by = \"tag\": back up every bucket carrying this tag, including ones added later."
  type = object({
    key   = string
    value = string
  })
  default = null
}

variable "standard_retention_days" {
  description = "How long each daily SecureVault Standard copy is kept, in days."
  type        = number
  default     = 30

  validation {
    condition     = var.standard_retention_days >= 30 && floor(var.standard_retention_days) == var.standard_retention_days
    error_message = "standard_retention_days must be a whole number, 30 or more (Clumio's S3 minimum is 1 month)."
  }
}

variable "backtrack_retention_months" {
  description = "How far back Backtrack can roll a bucket, in months."
  type        = number
  default     = 3

  validation {
    condition     = var.backtrack_retention_months >= 1 && floor(var.backtrack_retention_months) == var.backtrack_retention_months
    error_message = "backtrack_retention_months must be a whole number, 1 or more."
  }
}
