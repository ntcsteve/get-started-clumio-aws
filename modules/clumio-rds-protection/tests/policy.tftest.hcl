# Proves offline that databases are chosen as the README says, and that the Archive tier is on or
# off as set. Run: terraform test (in this module; needs Terraform 1.7+). Mock provider: no Clumio calls.

mock_provider "clumio" {}

variables {
  account_id          = "111122223333"
  region              = "ap-southeast-1"
  pitr_retention_days = 7
  database_tag        = { key = "backup-tier", value = "gold" }
}

run "by_tag_matches_rds_and_aurora_with_the_tag_in_this_account_and_region" {
  command = plan
  assert {
    condition = jsondecode(clumio_policy_rule.this.condition) == {
      entity_type           = { "$in" = ["aws_rds_instance", "aws_rds_cluster"] }
      aws_account_native_id = { "$eq" = "111122223333" }
      aws_region            = { "$eq" = "ap-southeast-1" }
      aws_tag               = { "$eq" = { key = "backup-tier", value = "gold" } }
    }
    error_message = "By tag must match the tag, scoped to this account and Region."
  }
  assert {
    condition     = clumio_policy.this.name == "rds-111122223333-ap-southeast-1" && clumio_policy_rule.this.before_rule_id == ""
    error_message = "An empty name must default to rds-<account>-<region>, and the rule must go last."
  }
}

run "by_name_matches_exactly_the_listed_identifiers" {
  command = plan
  variables {
    protect_by     = "name"
    database_names = ["my-uat-db"]
  }
  assert {
    condition     = jsondecode(clumio_policy_rule.this.condition).asset_name == { "$in" = ["my-uat-db"] }
    error_message = "By name must match the listed identifiers."
  }
  assert {
    condition     = !contains(keys(jsondecode(clumio_policy_rule.this.condition)), "aws_tag")
    error_message = "By name must not also require a tag."
  }
}

run "archive_on_adds_the_monthly_tier" {
  command = plan
  variables {
    archive_retention_months = 12
  }
  assert {
    condition     = length([for o in clumio_policy.this.operations : o if o.type == "aws_rds_resource_granular_backup"]) == 1
    error_message = "archive_retention_months = 12 must add the Archive tier."
  }
}

run "archive_zero_turns_the_tier_off" {
  command = plan
  variables {
    archive_retention_months = 0
  }
  assert {
    condition     = length([for o in clumio_policy.this.operations : o if o.type == "aws_rds_resource_granular_backup"]) == 0
    error_message = "archive_retention_months = 0 must leave the Archive tier out."
  }
}

run "the_shipped_pitr_placeholder_is_refused" {
  command = plan
  variables {
    pitr_retention_days = 0
  }
  expect_failures = [var.pitr_retention_days]
}

run "by_name_with_no_names_stops_the_plan" {
  command = plan
  variables {
    protect_by     = "name"
    database_names = []
  }
  expect_failures = [clumio_policy_rule.this]
}

run "before_rule_id_places_the_rule_before_an_older_one" {
  # For a tenant where an older, wider rule would claim the databases first.
  command = plan
  variables {
    before_rule_id = "03427765-b500-4b3d-a189-0da8f278d261"
  }
  assert {
    condition     = clumio_policy_rule.this.before_rule_id == "03427765-b500-4b3d-a189-0da8f278d261"
    error_message = "before_rule_id must place the rule before the named rule."
  }
}
