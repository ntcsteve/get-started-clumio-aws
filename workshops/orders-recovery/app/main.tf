# The orders app: Aurora holds the orders, and S3 holds one delivery document per order. Every name
# comes from names.json, which ./lab reads too.

locals {
  documents_bucket = "${var.names.bucket_prefix}${var.account_id}"
  protection_tags  = { (var.names.protection_tag.key) = var.names.protection_tag.value }
  db_username      = "ordersadmin" # In the secret and on the cluster; restores keep it, so the secret keeps working.
}

# --- Network: private only. ./lab reaches Aurora through the RDS Data API. ---------------------

data "aws_availability_zones" "standard" {
  state = "available"
  filter { # Aurora can't use Local Zones or Wavelength Zones.
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "this" {
  cidr_block = "10.42.0.0/16"
  tags       = { Name = var.names.network }
}

resource "aws_subnet" "private" {
  count             = 2 # Aurora needs two Availability Zones.
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.standard.names[count.index]
  tags              = { Name = "${var.names.network}-private-${count.index + 1}" }
}

resource "aws_db_subnet_group" "this" {
  name       = var.names.subnet_group
  subnet_ids = aws_subnet.private[*].id
}

# --- Database login: one secret that never rotates and outlives the cluster. -----------------
# Restored clusters keep this password, so ./lab works after every recovery.
# Workshop only: the password is also in local Terraform state.

resource "random_password" "db" {
  length           = 32
  override_special = "!#%^*()-_=+[]{}<>:?" # Aurora refuses / @ " and spaces.
}

resource "aws_secretsmanager_secret" "db_login" {
  name                    = var.names.login_secret
  recovery_window_in_days = 0 # Deleted at once on clean-up, so the workshop can run again.
}

resource "aws_secretsmanager_secret_version" "db_login" {
  secret_id     = aws_secretsmanager_secret.db_login.id
  secret_string = jsonencode({ username = local.db_username, password = random_password.db.result })
}

# --- Aurora: provisioned, because the RDS Data API and Clumio record restore both need it. ---

resource "aws_rds_cluster" "orders" {
  cluster_identifier      = var.names.cluster
  engine                  = "aurora-mysql" # The Region's default version. The Data API needs 3.07 or later.
  database_name           = var.names.database
  master_username         = local.db_username
  master_password         = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  storage_encrypted       = true
  backup_retention_period = 7    # Clumio's policy sets the same value.
  enable_http_endpoint    = true # The RDS Data API.
  skip_final_snapshot     = true # ./lab down leaves no snapshot to bill. Clumio keeps its recovery points.
  apply_immediately       = true # A change takes effect now, not at the next maintenance window.
  tags                    = local.protection_tags
}

resource "aws_rds_cluster_instance" "orders" {
  identifier         = var.names.instance
  cluster_identifier = aws_rds_cluster.orders.id
  engine             = aws_rds_cluster.orders.engine
  instance_class     = "db.r6g.large" # The smallest class the Data API supports (no T classes).
}

# --- Documents: versioned, so Clumio Backtrack can roll them back in place. ------------------

resource "aws_s3_bucket" "documents" {
  bucket        = local.documents_bucket
  force_destroy = true # Workshop only: destroy removes every object version.
  tags          = local.protection_tags
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
