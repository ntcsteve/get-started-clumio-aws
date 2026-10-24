# One Clumio policy for RDS and Aurora (AWS PITR, SecureVault Standard and Archive), and the rule
# that applies it to databases chosen by tag or name.

locals {
  name         = var.name != "" ? var.name : "rds-${var.account_id}-${var.region}" # Unique across the Clumio tenant.
  is_by_name   = var.protect_by == "name"
  selected_tag = coalesce(var.database_tag, { key = "", value = "" }) # A missing tag is stopped by a precondition below.
  rule_scope = {
    entity_type           = { "$in" = ["aws_rds_instance", "aws_rds_cluster"] }
    aws_account_native_id = { "$eq" = var.account_id }
    aws_region            = { "$eq" = var.region }
  }
  rule_by_name = merge(local.rule_scope, { asset_name = { "$in" = var.database_names } })
  rule_by_tag  = merge(local.rule_scope, { aws_tag = { "$eq" = { key = local.selected_tag.key, value = local.selected_tag.value } } })
  selection    = local.is_by_name ? "named ${join(", ", var.database_names)}" : "tagged ${local.selected_tag.key}=${local.selected_tag.value}"
}

resource "clumio_policy" "this" {
  name = local.name

  # AWS PITR: Clumio sets each database's PITR window to this, up or down.
  operations {
    type           = "aws_rds_resource_aws_snapshot"
    action_setting = "immediate" # Start now, not at the next window.
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
        apply = "maintenance_window" # Enabling backups restarts an RDS instance.
      }
    }
  }

  # SecureVault Standard: a daily copy in Clumio, outside your account.
  operations {
    type           = "aws_rds_resource_rolling_backup"
    action_setting = "immediate" # The first copy starts when the rule matches a database.
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

  # SecureVault Archive: a monthly long-term copy, made from Standard. Off when retention is 0.
  dynamic "operations" {
    for_each = var.archive_retention_months > 0 ? [var.archive_retention_months] : []
    content {
      type           = "aws_rds_resource_granular_backup"
      action_setting = "immediate" # Start now, not at the next window.
      slas {
        retention_duration {
          unit  = "months"
          value = operations.value
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
}

# By tag: every database with the tag, now and later. By name: exactly those identifiers; a typo
# protects nothing, and nothing checks names at plan time. Clumio applies the first rule that
# matches. Ordered last by default, so existing rules win; before_rule_id puts this rule ahead of an
# older, wider rule that would otherwise claim these databases.
resource "clumio_policy_rule" "this" {
  name           = local.name
  policy_id      = clumio_policy.this.id
  before_rule_id = var.before_rule_id # Empty means last, after every existing rule.
  # Encoded first: a conditional can't return two differently shaped objects.
  condition = local.is_by_name ? jsonencode(local.rule_by_name) : jsonencode(local.rule_by_tag)

  lifecycle {
    precondition {
      condition     = !local.is_by_name || length(var.database_names) > 0
      error_message = "protect_by = \"name\" needs at least one entry in database_names."
    }
    precondition {
      condition     = local.is_by_name || var.database_tag != null
      error_message = "protect_by = \"tag\" needs database_tag = { key = \"...\", value = \"...\" }."
    }
  }
}
