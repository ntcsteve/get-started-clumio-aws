# Proves offline that buckets are chosen as the README says, and that a wrong name stops the plan.
# Run: terraform test (in this module; needs Terraform 1.7+). Mock provider: no Clumio calls.
# Adding a named bucket that Clumio finds needs a live run: Terraform's mocks can't fake the
# provider's set of buckets ("incompatible types"), so the mock returns none, as for a typo.

mock_provider "clumio" {}

variables {
  account_id = "111122223333"
  region     = "ap-southeast-1"
}

run "by_tag_selects_every_tagged_bucket_in_this_account_and_region" {
  command = plan
  variables {
    protect_by = "tag"
    bucket_tag = { key = "backup-tier", value = "gold" }
  }
  assert {
    condition = jsondecode(clumio_protection_group.this.bucket_rule) == {
      aws_tag               = { "$eq" = { key = "backup-tier", value = "gold" } }
      aws_account_native_id = { "$eq" = "111122223333" }
      aws_region            = { "$eq" = "ap-southeast-1" }
    }
    error_message = "By tag must match the tag, scoped to this account and Region."
  }
  assert {
    condition     = length(clumio_protection_group_bucket.by_name) == 0
    error_message = "By tag must not add buckets by name."
  }
  assert {
    condition     = clumio_protection_group.this.name == "s3-111122223333-ap-southeast-1"
    error_message = "An empty name must default to s3-<account>-<region>."
  }
}

run "a_name_clumio_cant_see_stops_the_plan" {
  command = plan
  variables {
    protect_by   = "name"
    bucket_names = ["not-there"]
  }
  expect_failures = [clumio_protection_group.this]
}

run "the_shipped_placeholder_stops_the_plan" {
  command = plan
  variables {
    protect_by   = "name"
    bucket_names = ["BUCKET-NAME-REPLACE-THIS"]
  }
  expect_failures = [data.clumio_s3_bucket.by_name]
}

run "standard_retention_under_clumios_s3_minimum_is_refused" {
  command = plan
  variables {
    protect_by              = "tag"
    bucket_tag              = { key = "backup-tier", value = "gold" }
    standard_retention_days = 7
  }
  expect_failures = [var.standard_retention_days]
}
