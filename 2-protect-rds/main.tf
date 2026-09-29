# Step 2b: one Clumio backup policy (AWS PITR, SecureVault Standard and Archive) and a rule that
# applies it to every database with your tag. Creates Clumio objects only, so no AWS login;
# Clumio then sets each tagged database's PITR window. Credentials: CLUMIO_API_TOKEN, CLUMIO_API_BASE_URL.

provider "clumio" {}

# Step 1's connection. If there's none for this account and Region, such as after a typo, the
# plan stops here with "AWS connection not found".
data "clumio_aws_connection" "this" {
  account_native_id = var.account_id
  aws_region        = var.region
}

locals {
  account_id = var.account_id
  region     = var.region
  name       = var.name != "" ? var.name : "rds-${var.account_id}-${var.region}" # Must be unique across your Clumio tenant.
}

resource "clumio_policy" "lifecycle" {
  name = local.name

  # AWS PITR: Clumio sets each tagged database's PITR window to this, longer or shorter than
  # today. Shorter means less history to recover from.
  operations {
    type           = "aws_rds_resource_aws_snapshot"
    action_setting = "immediate" # Start now, not at the next scheduled window.
    slas {
      retention_duration {
        unit  = "days"
        value = var.pitr_retention_days
      }
      rpo_frequency {
        unit  = "days"
        value = 1
      }
    }
    advanced_settings {
      aws_rds_config_sync {
        apply = "maintenance_window" # Turning backups on for an RDS instance needs a restart, so wait for its maintenance window.
      }
    }
  }

  # SecureVault Standard keeps a daily copy in Clumio, outside your account.
  operations {
    type           = "aws_rds_resource_rolling_backup"
    action_setting = "immediate" # The first copy starts as soon as the rule matches a database.
    slas {
      retention_duration {
        unit  = "days"
        value = var.standard_retention_days
      }
      rpo_frequency {
        unit  = "days"
        value = 1
      }
    }
  }

  # SecureVault Archive keeps a monthly copy for the long term, made from the Standard copy.
  operations {
    type           = "aws_rds_resource_granular_backup"
    action_setting = "immediate" # Start now, not at the next scheduled window.
    slas {
      retention_duration {
        unit  = "months"
        value = var.archive_retention_months
      }
      rpo_frequency {
        unit  = "months"
        value = 1
      }
    }
    advanced_settings {
      aws_rds_resource_granular_backup {
        backup_tier = "frozen" # Clumio's name for SecureVault Archive
      }
    }
  }
}

# Matches every tagged RDS instance and Aurora cluster in this account and Region, now and later.
# It goes last in Clumio's order, so your existing rules always win.
resource "clumio_policy_rule" "lifecycle" {
  name           = local.name
  policy_id      = clumio_policy.lifecycle.id
  before_rule_id = "" # Empty means last, after every existing rule.
  condition = jsonencode({
    entity_type           = { "$in" = ["aws_rds_instance", "aws_rds_cluster"] }
    aws_account_native_id = { "$eq" = local.account_id }
    aws_region            = { "$eq" = local.region }
    aws_tag               = { "$eq" = { key = var.database_tag.key, value = var.database_tag.value } }
  })
}

output "policy_id" {
  value = clumio_policy.lifecycle.id
}

output "rule_id" {
  value = clumio_policy_rule.lifecycle.id
}

output "next_step" {
  value = "Protecting RDS + Aurora tagged ${var.database_tag.key}=${var.database_tag.value} in ${local.account_id}/${local.region}. Check each database shows policy ${local.name} (Clumio UI > AWS > Inventory > RDS Resources); another policy means an older rule won."
}
