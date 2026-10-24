# Step 1b (optional, permanent): Clumio encrypts every SecureVault backup taken from now on with
# your AWS KMS key. Run it after step 1 and before step 2, so no backup is made on Clumio's key.
# The key lives in Clumio's control-plane Region; Clumio replicates it to the Regions it needs.
# Clumio credentials come from CLUMIO_API_TOKEN and CLUMIO_API_BASE_URL.

provider "clumio" {}

provider "aws" {
  region              = var.clumio_region
  allowed_account_ids = [var.account_id] # Stops the run if you're signed in to any other account.
}

locals {
  role_name = var.iam_prefix == "" ? "ClumioKMSRole" : "${var.iam_prefix}-ClumioKMSRole"
}

# Your key, checked before anything permanent is created. It's created outside Terraform (see
# README.md here), so no edit or destroy here can delete it: every backup it encrypts depends on it.
# A bare key ID only resolves in the signed-in account and clumio_region, which pins both.
data "aws_kms_key" "yours" {
  key_id = var.key_id

  lifecycle {
    postcondition {
      condition     = self.key_state == "Enabled" && self.key_manager == "CUSTOMER"
      error_message = "Key ${var.key_id} must be an enabled, customer-managed key. It is ${self.key_state}, managed by ${self.key_manager}."
    }
    postcondition {
      condition     = self.multi_region && one(self.multi_region_configuration).multi_region_key_type == "PRIMARY"
      error_message = "Key ${var.key_id} must be a multi-Region PRIMARY key in ${var.clumio_region}, not a replica."
    }
    postcondition {
      condition     = self.key_usage == "ENCRYPT_DECRYPT" && self.key_spec == "SYMMETRIC_DEFAULT"
      error_message = "Key ${var.key_id} must be a symmetric encryption key (ENCRYPT_DECRYPT, SYMMETRIC_DEFAULT)."
    }
    # Imported material that expires makes the key, and every backup, unusable on that date.
    postcondition {
      condition     = self.origin != "EXTERNAL" || self.expiration_model == "KEY_MATERIAL_DOES_NOT_EXPIRE"
      error_message = "Key ${var.key_id} has imported key material that expires. Import it again with no expiry."
    }
  }
}

# The wallet binds your Clumio tenant to this key. Clumio refuses to delete it once BYOK is on,
# and a destroy would delete ClumioKMSRole first, cutting Clumio off from the key.
resource "clumio_wallet" "this" {
  account_native_id = var.account_id
  aws_region        = var.clumio_region
  depends_on        = [data.aws_kms_key.yours] # Only after the key passes its checks.

  lifecycle {
    prevent_destroy = true
  }
}

# Clumio's own BYOK setup: the IAM role Clumio uses for the key, the alias alias/clumio-byok on
# the key, and a final call that turns BYOK on in Clumio. SECURITY.md lists what the role can do.
module "byok" {
  source  = "clumio-code/byok-template/clumio"
  version = "0.5.7" # An exact version: SECURITY.md describes this one.

  account_native_id = clumio_wallet.this.account_native_id
  aws_region        = clumio_wallet.this.aws_region
  clumio_account_id = clumio_wallet.this.clumio_account_id
  token             = clumio_wallet.this.token
  existing_cmk_id   = var.key_id # Always set, so the module never makes a key of its own.
  role_name         = local.role_name
}

# BYOK can't be undone, but the module's role, policy and alias can be. This guard refuses any plan
# that would change the key or the role's name, or destroy the module, even with -target.
resource "terraform_data" "byok_is_permanent" {
  triggers_replace = [var.key_id, local.role_name]
  depends_on       = [module.byok]

  lifecycle {
    prevent_destroy = true
  }
}

output "next_step" {
  value = "BYOK is on with key ${var.key_id} in ${var.clumio_region}. Check the Encryption Key page in the Clumio console, then go to step 2. Never disable or delete this key."
}
