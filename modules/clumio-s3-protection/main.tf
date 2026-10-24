# One Clumio protection group and policy for S3 (Backtrack and SecureVault Standard), for buckets
# chosen by tag or name. S3 policies allow one SecureVault tier, so there is no Archive.

locals {
  is_by_name   = var.protect_by == "name"
  is_by_tag    = var.protect_by == "tag"
  name         = var.name != "" ? var.name : "s3-${var.account_id}-${var.region}" # Unique across the Clumio tenant.
  selected_tag = coalesce(var.bucket_tag, { key = "", value = "" })               # A missing tag is stopped by a precondition below.
}

# By name: look each bucket up in Clumio, and stop if any is missing.
data "clumio_s3_bucket" "by_name" {
  count        = local.is_by_name ? 1 : 0
  bucket_names = var.bucket_names

  lifecycle {
    precondition {
      condition     = length(var.bucket_names) > 0
      error_message = "protect_by = \"name\" needs at least one entry in bucket_names."
    }
    precondition {
      condition     = !contains(var.bucket_names, "BUCKET-NAME-REPLACE-THIS")
      error_message = "Replace BUCKET-NAME-REPLACE-THIS with your bucket name."
    }
  }
}

locals {
  # Only buckets in this account and Region.
  found_buckets = local.is_by_name ? [
    for b in data.clumio_s3_bucket.by_name[0].s3_buckets : b
    if b.account_native_id == var.account_id && b.aws_region == var.region
  ] : []
  missing_names = local.is_by_name ? setsubtract(var.bucket_names, [for b in local.found_buckets : b.name]) : []
  selection     = local.is_by_name ? "${length(local.found_buckets)} bucket(s) in ${var.account_id}/${var.region}: ${join(", ", sort([for b in local.found_buckets : b.name]))}" : "buckets tagged ${local.selected_tag.key}=${local.selected_tag.value} in ${var.account_id}/${var.region}"
}

resource "clumio_protection_group" "this" {
  name        = local.name
  description = local.is_by_name ? "S3 buckets by name in ${var.account_id}/${var.region}" : "S3 buckets tagged ${local.selected_tag.key}=${local.selected_tag.value} in ${var.account_id}/${var.region}"

  # By tag: every matching bucket, now and later. Scoped to this account and Region, because a
  # tag alone matches across the whole tenant.
  bucket_rule = local.is_by_tag ? jsonencode({
    aws_tag               = { "$eq" = { key = local.selected_tag.key, value = local.selected_tag.value } }
    aws_account_native_id = { "$eq" = var.account_id }
    aws_region            = { "$eq" = var.region }
  }) : null

  object_filter {
    # Glacier storage classes are not backed up.
    storage_classes = ["S3 Standard", "S3 Standard-IA", "S3 Intelligent-Tiering", "S3 One Zone-IA"]
  }

  lifecycle {
    precondition {
      condition     = length(local.missing_names) == 0
      error_message = "Clumio can't see bucket(s) ${join(", ", local.missing_names)} in ${var.account_id}/${var.region}. Check the name and Region, and that the account is connected. A new bucket can take up to an hour to appear: wait, then retry."
    }
    precondition {
      condition     = !local.is_by_tag || var.bucket_tag != null
      error_message = "protect_by = \"tag\" needs bucket_tag = { key = \"...\", value = \"...\" }."
    }
  }
}

# By name: each bucket joins by its Clumio ID, so it needs no tag.
resource "clumio_protection_group_bucket" "by_name" {
  for_each            = { for b in local.found_buckets : b.name => b.id }
  protection_group_id = clumio_protection_group.this.id
  bucket_id           = each.value
}

resource "clumio_policy" "this" {
  name = local.name

  # Backtrack: rolls a bucket back in place from its own versions. Needs S3 Versioning.
  operations {
    type           = "aws_s3_backtrack"
    action_setting = "immediate" # Start now, not at the next window.
    slas {
      retention_duration {
        unit  = "months"
        value = var.backtrack_retention_months
      }
      rpo_frequency {
        unit  = "days"
        value = 1
      }
    }
  }

  # SecureVault Standard: a daily copy in Clumio, outside your account.
  operations {
    type           = "protection_group_backup"
    action_setting = "immediate" # The first backup starts when the policy is assigned.
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
    advanced_settings {
      protection_group_backup {
        backup_tier = "cold" # Clumio's name for SecureVault Standard
      }
    }
  }
}

resource "clumio_policy_assignment" "this" {
  entity_id   = clumio_protection_group.this.id
  entity_type = "protection_group"
  policy_id   = clumio_policy.this.id
  depends_on  = [clumio_protection_group_bucket.by_name] # Buckets first, then the first backup.
}
