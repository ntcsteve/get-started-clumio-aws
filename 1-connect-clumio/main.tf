# Step 1: connect one AWS account and Region to Clumio, and create the IAM roles, policies and
# event resources Clumio needs there. Step 0 lists them all first.
# Clumio credentials come from CLUMIO_API_TOKEN and CLUMIO_API_BASE_URL.

provider "clumio" {}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id] # Stops the run if you're logged in to any other account.
}

resource "clumio_aws_connection" "this" {
  account_native_id = var.account_id
  aws_region        = var.region
  description       = "Connected by Terraform (get-started-clumio-aws)"

  lifecycle {
    # A destroy deletes Clumio's IAM, then the connection. If Clumio refuses the second part
    # (error 367), backups stop. So no plan may delete it by accident; see README "Disconnect".
    prevent_destroy = true
  }
}

module "clumio" {
  source  = "clumio-code/aws-template/clumio"
  version = "0.41.0" # An exact version, so step 0 previews exactly what this creates.

  clumio_token          = clumio_aws_connection.this.token
  role_external_id      = clumio_aws_connection.this.role_external_id
  aws_account_id        = clumio_aws_connection.this.account_native_id
  aws_region            = clumio_aws_connection.this.aws_region
  clumio_aws_account_id = clumio_aws_connection.this.clumio_aws_account_id
  data_plane_account_id = clumio_aws_connection.this.data_plane_account_id # Limits S3 backup copies to Clumio's own account.

  iam_entities_identifier = var.iam_prefix
  path                    = var.iam_path
  is_s3_enabled           = contains(var.workloads, "s3")
  is_rds_enabled          = contains(var.workloads, "rds") # RDS instances and Aurora clusters
  is_ebs_enabled          = contains(var.workloads, "ebs") # EC2 instances and EBS volumes

  # Your organization's IAM rules, all optional. Clumio's own role tag is always kept.
  clumio_iam_role_tags       = merge({ Vendor = "Clumio" }, var.role_tags)
  permissions_boundary_arn   = var.permissions_boundary_arn
  clumio_pass_role_deny_list = var.pass_role_deny_list
}

output "next_step" {
  value = "Connected ${clumio_aws_connection.this.account_native_id}/${clumio_aws_connection.this.aws_region} (${join(" + ", var.workloads)}). Next: terraform plan must say No changes; wait 5 minutes for Clumio to find your data; then step 2."
}
