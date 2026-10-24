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
  description = "Name of the Clumio protection group and its policy, unique across your tenant. Empty means s3-<account>-<region>."
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
  description = "With protect_by = \"name\": the buckets to back up, by name (not ARN)."
  type        = list(string)
  default     = []

  # The shipped placeholder passes here, so a precondition in main.tf can say exactly what to replace.
  validation {
    condition     = alltrue([for n in var.bucket_names : n == "BUCKET-NAME-REPLACE-THIS" || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", n))])
    error_message = "bucket_names must be bucket names (such as my-bucket), not ARNs (arn:aws:s3:::my-bucket)."
  }
}

variable "bucket_tag" {
  description = "With protect_by = \"tag\": back up every bucket with this tag, including buckets tagged later."
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
