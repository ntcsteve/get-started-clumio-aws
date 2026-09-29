# Step 2 (RDS + Aurora): one Clumio policy, AWS PITR + SecureVault Standard + Archive, by tag.
# Creates only Clumio objects; needs no AWS login. Clumio then sets each tagged database's PITR.
# Clumio login: CLUMIO_API_TOKEN, CLUMIO_API_BASE_URL.

provider "clumio" {}

# Step 1's connection. None for this account + region: the plan stops with
# "AWS connection not found" (proven live), so a typo can't protect nothing.
data "clumio_aws_connection" "this" {
  account_native_id = var.account_id
  aws_region        = var.region
}

locals {
  account_id = var.account_id
  region     = var.region
  name       = var.name != "" ? var.name : "rds-${var.account_id}-${var.region}" # unique across the Clumio tenant
}

resource "clumio_policy" "lifecycle" {
  name = local.name

  # 1. AWS PITR: Clumio SETS each database's automated-backup retention to this, up or
  #    DOWN. A lower value than today's shrinks the database's point-in-time window.
  operations {
    type           = "aws_rds_resource_aws_snapshot"
    action_setting = "immediate"
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
        apply = "maintenance_window" # an RDS instance going from 0 to N days needs a restart; wait for its window
      }
    }
  }

  # 2. SecureVault Standard: a daily copy in Clumio, outside your account.
  operations {
    type           = "aws_rds_resource_rolling_backup"
    action_setting = "immediate" # first copy starts once the rule matches
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

  # 3. SecureVault Archive: a monthly long-term copy, built by Clumio from the Standard copy.
  operations {
    type           = "aws_rds_resource_granular_backup"
    action_setting = "immediate"
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
        backup_tier = "frozen" # the Archive tier; the only one Clumio allows for new policies
      }
    }
  }
}

# Every tagged RDS instance and Aurora cluster in this account + region, now and later.
# Lowest priority: an existing rule that also matches a database wins.
resource "clumio_policy_rule" "lifecycle" {
  name           = local.name
  policy_id      = clumio_policy.lifecycle.id
  before_rule_id = "" # "" = lowest priority: after every existing rule
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
