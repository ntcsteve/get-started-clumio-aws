# Step 2a: one Clumio backup policy (Backtrack and SecureVault Standard) for buckets chosen by
# name or tag. No Archive tier: Clumio allows one SecureVault tier per S3 policy (error 111).
# Creates Clumio objects only, so no AWS login. Credentials: CLUMIO_API_TOKEN, CLUMIO_API_BASE_URL.

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
  is_by_name = var.protect_by == "name"
  is_by_tag  = var.protect_by == "tag"
  name       = var.name != "" ? var.name : "s3-${var.account_id}-${var.region}" # Must be unique across your Clumio tenant.
  tag        = coalesce(var.bucket_tag, { key = "", value = "" })               # The empty default lets Terraform read the description; a check below stops a missing tag.
}

# --- By name: find each bucket in Clumio, and stop if any is missing ----------------

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
  # Keep only buckets in this account and Region, the ones step 1 connected.
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

  # By tag, Clumio adds every matching bucket, now and later. Limited to this account and
  # Region, because a tag alone matches across your whole tenant.
  bucket_rule = local.is_by_tag ? jsonencode({
    aws_tag               = { "$eq" = { key = local.tag.key, value = local.tag.value } }
    aws_account_native_id = { "$eq" = local.account_id }
    aws_region            = { "$eq" = local.region }
  }) : null

  object_filter {
    # Objects in the Glacier storage classes are not backed up.
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

# By name, each bucket joins the group by its Clumio ID, so it needs no tag.
resource "clumio_protection_group_bucket" "named" {
  for_each            = { for b in local.found_buckets : b.name => b.id }
  protection_group_id = clumio_protection_group.this.id
  bucket_id           = each.value
}

resource "clumio_policy" "lifecycle" {
  name = local.name

  # Backtrack rolls a bucket back in place, using its own object versions. It needs S3 Versioning.
  operations {
    type           = "aws_s3_backtrack"
    action_setting = "immediate" # Start now, not at the next scheduled window.
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

  # SecureVault Standard keeps a daily copy in Clumio, outside your account.
  operations {
    type           = "protection_group_backup"
    action_setting = "immediate" # The first backup starts as soon as the policy is assigned.
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
  policy_id   = clumio_policy.lifecycle.id
  depends_on  = [clumio_protection_group_bucket.named] # Add the buckets before the first backup starts.
}

output "protection_group_id" {
  value = clumio_protection_group.this.id
}

output "next_step" {
  value = local.is_by_name ? "Protecting ${length(local.found_buckets)} bucket(s): ${join(", ", sort([for b in local.found_buckets : b.name]))}. First backup starts now, on protection group ${local.name} in Clumio." : "Protecting buckets tagged ${local.tag.key}=${local.tag.value} in ${local.account_id}/${local.region}. Check protection group ${local.name} in Clumio: 0 buckets means none carries that tag yet."
}
