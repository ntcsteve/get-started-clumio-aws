variable "names" {
  description = "The workshop's names, from names.json (shared with ./lab). Only the ones the app uses are listed."
  type = object({
    cluster          = string
    instance         = string
    subnet_group     = string
    database         = string
    login_secret     = string
    bucket_prefix    = string
    documents_prefix = string
    network          = string
    protection_tag   = object({ key = string, value = string })
  })
}

variable "account_id" {
  description = "The workshop's AWS account. Makes the bucket name unique."
  type        = string
}
