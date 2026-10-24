# The orders workshop: a small app (Aurora orders, S3 documents), protected by Clumio
# with the same modules production uses. Terraform builds it once and destroys it once; every
# recovery in between happens in Clumio, as in a real incident.
# Clumio credentials come from CLUMIO_API_TOKEN and CLUMIO_API_BASE_URL.

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # Stops the run if you're signed in to any other account.
  default_tags {
    tags = local.tags
  }
}

provider "clumio" {}

locals {
  # Every name, from names.json, shared with ./lab so neither repeats one. A name may use {account} and
  # {region}; both are filled in here, as ./lab's fill_names() does, so no other code composes a name.
  raw_names = jsondecode(file("${path.module}/names.json"))
  names = merge(local.raw_names, {
    for key, value in local.raw_names : key => replace(replace(value, "{account}", var.account_id), "{region}", var.region)
    if can(tostring(value))
  })
  # On every AWS resource. ./lab reads them from the tags output, and deletes only what carries the workshop tag.
  tags = merge(var.tags, { (local.names.workshop_tag.key) = local.names.workshop_tag.value })
}

module "app" {
  source = "./app"
  names  = local.names
}

# Workshop only: loads the sample data before the Clumio policies exist, so Clumio's first recovery
# points already hold it. Production data never comes from Terraform. Safe to rerun before an incident:
# ./lab seed leaves existing orders as they are, and refuses to run after one.
resource "terraform_data" "sample_data" {
  depends_on = [module.app]

  provisioner "local-exec" {
    command     = "./lab seed"
    working_dir = path.module
  }
}

# Unlike production (1-connect-clumio), no prevent_destroy: the workshop must clean up fully.
resource "clumio_aws_connection" "this" {
  account_native_id = var.account_id
  aws_region        = var.region
  description       = "orders-recovery workshop"
}

module "clumio_iam" {
  source     = "../../modules/clumio-account-iam"
  connection = clumio_aws_connection.this
  workloads  = ["s3", "rds"]

  iam_prefix               = var.iam_prefix
  iam_path                 = var.iam_path
  role_tags                = var.role_tags
  permissions_boundary_arn = var.permissions_boundary_arn
}

# Protection waits for Clumio's IAM and for the data. On destroy, it goes before Clumio's access.
module "rds_protection" {
  source       = "../../modules/clumio-rds-protection"
  depends_on   = [module.clumio_iam, terraform_data.sample_data]
  account_id   = var.account_id
  region       = var.region
  name         = local.names.clumio_rds_policy
  protect_by   = "tag"
  database_tag = local.names.protection_tag

  pitr_retention_days      = 7 # Same as backup_retention_period in app/main.tf, so Clumio changes nothing.
  standard_retention_days  = 7 # Short, to keep the workshop's cost low: Modules 4B and 5 use the newest point.
  archive_retention_months = var.archive_retention_months
  before_rule_id           = var.rds_rule_before_id
}

module "s3_protection" {
  source     = "../../modules/clumio-s3-protection"
  depends_on = [module.clumio_iam, terraform_data.sample_data]
  account_id = var.account_id
  region     = var.region
  name       = local.names.clumio_s3_policy
  protect_by = "tag"
  bucket_tag = local.names.protection_tag

  standard_retention_days    = 30 # Clumio's S3 minimum
  backtrack_retention_months = 1  # Module 3 rolls back hours, not months.
}
