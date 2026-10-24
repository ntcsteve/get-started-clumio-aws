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
  description = "Name of the Clumio protection group and its policy, unique across your tenant. Empty means s3-<account>-<region>."
  type        = string
  default     = ""
}

variable "protect_by" {
  description = "How buckets are chosen: \"name\" (bucket_names) or \"tag\" (bucket_tag)."
  type        = string
}

variable "bucket_names" {
  description = "With protect_by = \"name\": the buckets to back up, by name (not ARN)."
  type        = list(string)
  default     = []
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
}

variable "backtrack_retention_months" {
  description = "How far back Backtrack can roll a bucket, in months."
  type        = number
  default     = 3
}
