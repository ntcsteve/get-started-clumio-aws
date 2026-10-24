# Step 2a: protect S3 buckets, chosen by name or tag, with one Clumio policy (Backtrack and
# SecureVault Standard). Logic: modules/clumio-s3-protection.
# Creates Clumio objects only, so no AWS sign-in. Credentials: CLUMIO_API_TOKEN, CLUMIO_API_BASE_URL.

provider "clumio" {}

# Step 1's connection. If there's none for this account and Region, such as after a typo, the
# plan stops here with "AWS connection not found".
data "clumio_aws_connection" "existing" {
  account_native_id = var.account_id
  aws_region        = var.region
}

module "s3_protection" {
  source = "../modules/clumio-s3-protection"

  account_id                 = var.account_id
  region                     = var.region
  name                       = var.name
  protect_by                 = var.protect_by
  bucket_names               = var.bucket_names
  bucket_tag                 = var.bucket_tag
  standard_retention_days    = var.standard_retention_days
  backtrack_retention_months = var.backtrack_retention_months
}

# Moves state from before the shared module, so upgrades plan no changes.
moved {
  from = clumio_protection_group.this
  to   = module.s3_protection.clumio_protection_group.this
}

moved {
  from = clumio_protection_group_bucket.named
  to   = module.s3_protection.clumio_protection_group_bucket.by_name
}

moved {
  from = clumio_policy.lifecycle
  to   = module.s3_protection.clumio_policy.this
}

moved {
  from = clumio_policy_assignment.this
  to   = module.s3_protection.clumio_policy_assignment.this
}

output "protection_group_id" {
  value = module.s3_protection.protection_group_id
}

output "next_step" {
  value = "Protecting ${module.s3_protection.selection}. Check protection group ${module.s3_protection.name} (Clumio console: Protection groups): its first backup starts now; 0 buckets means none matches yet."
}
