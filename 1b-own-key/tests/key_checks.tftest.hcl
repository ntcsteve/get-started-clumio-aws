# Proves offline that a wrong key stops the plan before anything permanent is created.
# Run: terraform test (in 1b-own-key; needs Terraform 1.7+). Mock providers: no AWS or Clumio calls.

mock_provider "aws" {
  # Clumio's module renders IAM policies; a mock needs valid JSON for them.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}
mock_provider "clumio" {
  mock_resource "clumio_wallet" {
    defaults = {
      clumio_account_id = "999999999999"
      token             = "mock-token"
    }
  }
}
mock_provider "random" {}
mock_provider "time" {}

variables {
  account_id                     = "111122223333"
  clumio_region                  = "us-west-2"
  key_id                         = "mrk-0123456789abcdef0123456789abcdef"
  i_understand_byok_is_permanent = true
}

# A key that passes every check. Each failing run below changes one thing.
override_data {
  target = data.aws_kms_key.yours
  values = {
    key_state                  = "Enabled"
    key_manager                = "CUSTOMER"
    multi_region               = true
    multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
    key_usage                  = "ENCRYPT_DECRYPT"
    key_spec                   = "SYMMETRIC_DEFAULT"
    aws_account_id             = "111122223333"
    origin                     = "AWS_KMS"
    expiration_model           = ""
  }
}

run "a_good_key_plans" {
  command = plan
}

run "a_replica_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Enabled"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "REPLICA", primary_key = [], replica_keys = [] }]
      key_usage                  = "ENCRYPT_DECRYPT"
      key_spec                   = "SYMMETRIC_DEFAULT"
      aws_account_id             = "111122223333"
      origin                     = "AWS_KMS"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "a_disabled_key_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Disabled"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "ENCRYPT_DECRYPT"
      key_spec                   = "SYMMETRIC_DEFAULT"
      aws_account_id             = "111122223333"
      origin                     = "AWS_KMS"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "a_key_pending_deletion_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "PendingDeletion"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "ENCRYPT_DECRYPT"
      key_spec                   = "SYMMETRIC_DEFAULT"
      aws_account_id             = "111122223333"
      origin                     = "AWS_KMS"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "an_aws_managed_key_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Enabled"
      key_manager                = "AWS"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "ENCRYPT_DECRYPT"
      key_spec                   = "SYMMETRIC_DEFAULT"
      aws_account_id             = "111122223333"
      origin                     = "AWS_KMS"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "a_signing_key_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Enabled"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "SIGN_VERIFY"
      key_spec                   = "ECC_NIST_P256"
      aws_account_id             = "111122223333"
      origin                     = "AWS_KMS"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "an_hmac_key_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Enabled"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "GENERATE_VERIFY_MAC"
      key_spec                   = "HMAC_256"
      aws_account_id             = "111122223333"
      origin                     = "AWS_KMS"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "expiring_imported_material_is_refused" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Enabled"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "ENCRYPT_DECRYPT"
      key_spec                   = "SYMMETRIC_DEFAULT"
      aws_account_id             = "111122223333"
      origin                     = "EXTERNAL"
      expiration_model           = "KEY_MATERIAL_EXPIRES"
    }
  }
  expect_failures = [data.aws_kms_key.yours]
}

run "imported_material_that_never_expires_plans" {
  command = plan
  override_data {
    target = data.aws_kms_key.yours
    values = {
      key_state                  = "Enabled"
      key_manager                = "CUSTOMER"
      multi_region               = true
      multi_region_configuration = [{ multi_region_key_type = "PRIMARY", primary_key = [], replica_keys = [] }]
      key_usage                  = "ENCRYPT_DECRYPT"
      key_spec                   = "SYMMETRIC_DEFAULT"
      aws_account_id             = "111122223333"
      origin                     = "EXTERNAL"
      expiration_model           = "KEY_MATERIAL_DOES_NOT_EXPIRE"
    }
  }
}

run "the_permanence_gate_stops_the_plan" {
  command = plan
  variables {
    i_understand_byok_is_permanent = false
  }
  expect_failures = [var.i_understand_byok_is_permanent]
}
