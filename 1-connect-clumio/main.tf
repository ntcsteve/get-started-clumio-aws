# Step 1: connect one AWS account and Region to Clumio, and create the IAM roles, policies and
# event resources Clumio needs there. Step 0 lists them all first.
# Clumio credentials come from CLUMIO_API_TOKEN and CLUMIO_API_BASE_URL.

provider "clumio" {}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # Stops the run if you're signed in to any other account.
}

resource "clumio_aws_connection" "this" {
  account_native_id = var.account_id
  aws_region        = var.region
  description       = "Connected by Terraform (get-started-clumio-aws)"

  lifecycle {
    # A destroy deletes Clumio's IAM, then the connection. If Clumio refuses the second part
    # (error 367), backups stop. So no plan may delete it by accident; see "Disconnect" in README.md here.
    prevent_destroy = true
  }
}

# Clumio's IAM, from the module the workshop uses too.
module "clumio_iam" {
  source     = "../modules/clumio-account-iam"
  connection = clumio_aws_connection.this

  iam_prefix               = var.iam_prefix
  iam_path                 = var.iam_path
  workloads                = var.workloads
  role_tags                = var.role_tags
  permissions_boundary_arn = var.permissions_boundary_arn
  pass_role_deny_list      = var.pass_role_deny_list
}

# Backups that fail quietly are found during an incident. This report says, by email, whether every
# asset in this Region has a backup each day, kept at least 7 days. Optional, so upgrades plan no change.
resource "clumio_report_configuration" "daily_backups" {
  count       = length(var.report_emails) > 0 ? 1 : 0
  name        = "backups-${var.account_id}-${var.region}"
  description = "Every asset in ${var.region} has a backup each day, kept at least 7 days."

  notification {
    email_list = var.report_emails
  }

  parameter {
    controls {
      asset_backup {
        look_back_period {
          unit  = "days"
          value = 1
        }
        window_size {
          unit  = "days"
          value = 1
        }
        minimum_retention_duration {
          unit  = "days"
          value = 7
        }
      }
    }
    filters {
      asset {
        groups {
          type   = "aws"
          region = var.region
        }
      }
    }
  }
}

# Moves state from before the shared module, so upgrades plan no changes.
moved {
  from = module.clumio
  to   = module.clumio_iam.module.aws_template
}

output "next_step" {
  value = "Connected ${clumio_aws_connection.this.account_native_id}/${clumio_aws_connection.this.aws_region} (${join(" + ", var.workloads)}). Next: terraform plan must say No changes; when Clumio's inventory lists your data, go to step 2."
}
