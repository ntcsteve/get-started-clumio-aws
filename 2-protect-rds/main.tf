# Step 2b: protect RDS and Aurora with one Clumio policy, applied to the databases you choose, by
# tag or by name. Logic: modules/clumio-rds-protection.
# Creates Clumio objects only, so no AWS sign-in. Credentials: CLUMIO_API_TOKEN, CLUMIO_API_BASE_URL.

provider "clumio" {}

# Step 1's connection. If there's none for this account and Region, such as after a typo, the
# plan stops here with "AWS connection not found".
data "clumio_aws_connection" "existing" {
  account_native_id = var.account_id
  aws_region        = var.region
}

module "rds_protection" {
  source = "../modules/clumio-rds-protection"

  account_id               = var.account_id
  region                   = var.region
  name                     = var.name
  protect_by               = var.protect_by
  database_tag             = var.database_tag
  database_names           = var.database_names
  pitr_retention_days      = var.pitr_retention_days
  standard_retention_days  = var.standard_retention_days
  archive_retention_months = var.archive_retention_months
}

# Moves state from before the shared module, so upgrades plan no changes.
moved {
  from = clumio_policy.lifecycle
  to   = module.rds_protection.clumio_policy.this
}

moved {
  from = clumio_policy_rule.lifecycle
  to   = module.rds_protection.clumio_policy_rule.this
}

output "policy_id" {
  value = module.rds_protection.policy_id
}

output "rule_id" {
  value = module.rds_protection.rule_id
}

output "next_step" {
  value = "Protecting RDS and Aurora ${module.rds_protection.selection} in ${var.account_id}/${var.region}. Check each database shows policy ${module.rds_protection.name} (Clumio console: AWS, Inventory, RDS resources); none means a wrong name or tag, another policy means an older rule won."
}
