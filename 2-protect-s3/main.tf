# Step 2 (S3): one Clumio policy, Backtrack + SecureVault Standard, for buckets by name or tag.
# No Archive: Clumio allows one SecureVault tier per S3 policy (error 111).
# Creates only Clumio objects; needs no AWS login. Clumio login: CLUMIO_API_TOKEN, CLUMIO_API_BASE_URL.

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
  is_by_name = var.protect_by == "name"
  is_by_tag  = var.protect_by == "tag"
  name       = var.name != "" ? var.name : "s3-${var.account_id}-${var.region}" # unique across the Clumio tenant
  tag        = coalesce(var.bucket_tag, { key = "", value = "" })               # "" only until the precondition below stops a missing tag
}

# --- By name: find each bucket in Clumio; fail if any is missing -------------------

data "clumio_s3_bucket" "named" {
  count        = local.is_by_name ? 1 : 0
  bucket_names = var.bucket_names

  lifecycle {
    precondition {
      condition     = length(var.bucket_names) > 0
      error_message = "protect_by = \"name\" needs at least one entry in bucket_names."
    }
    precondition {
      condition     = !contains(var.bucket_names, "BUCKET-NAME-REPLACE-THIS")
      error_message = "Replace BUCKET-NAME-REPLACE-THIS in terraform.tfvars with your bucket name."
    }
  }
}

locals {
  # Only this account + region: the connection 1-connect-clumio made.
  found_buckets = local.is_by_name ? [
    for b in data.clumio_s3_bucket.named[0].s3_buckets : b
    if b.account_native_id == local.account_id && b.aws_region == local.region
  ] : []
  missing_names = local.is_by_name ? setsubtract(var.bucket_names, [for b in local.found_buckets : b.name]) : []
}

# --- The group, the policy, and the link between them ------------------------------

resource "clumio_protection_group" "this" {
  name        = local.name
  description = local.is_by_name ? "S3 buckets by name in ${local.account_id}/${local.region}" : "S3 buckets tagged ${local.tag.key}=${local.tag.value} in ${local.account_id}/${local.region}"

  # By tag: Clumio adds every matching bucket, now and later. Pinned to this account +
  # region, because a tag alone matches across the whole Clumio tenant.
  bucket_rule = local.is_by_tag ? jsonencode({
    aws_tag               = { "$eq" = { key = local.tag.key, value = local.tag.value } }
    aws_account_native_id = { "$eq" = local.account_id }
    aws_region            = { "$eq" = local.region }
  }) : null

  object_filter {
    # Objects in other classes (Glacier Instant Retrieval, Glacier, Deep Archive, ...) are not backed up.
    storage_classes = ["S3 Standard", "S3 Standard-IA", "S3 Intelligent-Tiering", "S3 One Zone-IA"]
  }

  lifecycle {
    precondition {
      condition     = length(local.missing_names) == 0
      error_message = "Clumio can't see bucket(s) ${join(", ", local.missing_names)} in ${local.account_id}/${local.region}. Check the name, the region in terraform.tfvars, and that step 1 is applied. New buckets appear within minutes: wait, then retry."
    }
    precondition {
      condition     = !local.is_by_tag || var.bucket_tag != null
      error_message = "protect_by = \"tag\" needs bucket_tag = { key = \"...\", value = \"...\" }."
    }
  }
}

# By name: add each bucket to the group by its Clumio ID (no tags needed).
resource "clumio_protection_group_bucket" "named" {
  for_each            = { for b in local.found_buckets : b.name => b.id }
  protection_group_id = clumio_protection_group.this.id
  bucket_id           = each.value
}

resource "clumio_policy" "lifecycle" {
  name = local.name

  # 1. Backtrack: roll a bucket back in place from its own versions (needs S3 Versioning).
  operations {
    type           = "aws_s3_backtrack"
    action_setting = "immediate"
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

  # 2. SecureVault Standard: a daily copy in Clumio, outside your account.
  operations {
    type           = "protection_group_backup"
    action_setting = "immediate" # first backup starts on assignment
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
        backup_tier = "cold" # SecureVault Standard
      }
    }
  }
}

resource "clumio_policy_assignment" "this" {
  entity_id   = clumio_protection_group.this.id
  entity_type = "protection_group"
  policy_id   = clumio_policy.lifecycle.id
  depends_on  = [clumio_protection_group_bucket.named] # buckets in the group before the first backup
}

output "protection_group_id" {
  value = clumio_protection_group.this.id
}

output "next_step" {
  value = local.is_by_name ? "Protecting ${length(local.found_buckets)} bucket(s): ${join(", ", sort([for b in local.found_buckets : b.name]))}. First backup starts now, on protection group ${local.name} in Clumio." : "Protecting buckets tagged ${local.tag.key}=${local.tag.value} in ${local.account_id}/${local.region}. Check protection group ${local.name} in Clumio: 0 buckets means none carries that tag yet."
}
