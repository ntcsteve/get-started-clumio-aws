# Optional sample data, sandbox accounts only: a versioned S3 bucket of fake statements and,
# with with_aurora, a small Aurora MySQL cluster of 1,000 fake accounts. Both carry backup_tag
# so step 2 can pick them by tag. Remove with terraform destroy.

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Purpose = "clumio-sample-data" }
  }
}

locals {
  name = "clumio-sample-${var.account_id}-${var.region}" # Bucket names are global, so the account and Region keep it unique.
  tag  = { (var.backup_tag.key) = var.backup_tag.value }

  # 24 small CSV files, 12 months for 2 fake customers, 20 rows each. Every run creates the same
  # content, so a restored file can be checked against a known checksum.
  statements = {
    for pair in setproduct(range(1, 13), [1, 2]) :
    format("statements/2026/%02d/customer-%04d.csv", pair[0], pair[1]) => join("\n", concat(
      ["date,description,amount"],
      [for day in range(1, 21) : format("2026-%02d-%02d,%s,%.2f", pair[0], day,
      element(["Salary", "Groceries", "Utilities", "Transfer"], day), (day * 37 + pair[1] * 11) % 900 + 0.5)]
    ))
  }
  sample_file = "statements/2026/01/customer-0001.csv"
}

# --- S3 ----------------------------------------------------------------------------
# New buckets are private and encrypted by default. Versioning is the one setting Backtrack needs.

resource "aws_s3_bucket" "statements" {
  bucket        = "${local.name}-statements"
  force_destroy = true # Destroy removes every object version, too.
  tags          = local.tag
}

resource "aws_s3_bucket_versioning" "statements" {
  bucket = aws_s3_bucket.statements.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "statement" {
  for_each     = local.statements
  bucket       = aws_s3_bucket.statements.id
  key          = each.key
  content      = each.value
  content_type = "text/csv"
  depends_on   = [aws_s3_bucket_versioning.statements]
}

# --- Aurora (with_aurora) ---------------------------------------------------------------
# Aurora MySQL Serverless v2, 0.5 to 1 capacity units: the setup tested with Clumio. Encrypted,
# private, in the default VPC. Rows load through the RDS Data API, so no network path is needed.

data "aws_vpc" "default" {
  count   = var.with_aurora ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.with_aurora ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

resource "aws_db_subnet_group" "core_banking" {
  count      = var.with_aurora ? 1 : 0
  name       = "clumio-sample-aurora"
  subnet_ids = data.aws_subnets.default[0].ids
}

resource "aws_rds_cluster" "core_banking" {
  count                       = var.with_aurora ? 1 : 0
  cluster_identifier          = "clumio-sample-aurora"
  engine                      = "aurora-mysql"
  database_name               = "bank"
  master_username             = "sampleadmin"
  manage_master_user_password = true # AWS keeps the password in Secrets Manager, never in state.
  db_subnet_group_name        = aws_db_subnet_group.core_banking[0].name
  storage_encrypted           = true
  backup_retention_period     = 7 # AWS PITR days, until Clumio's policy sets its own.
  enable_http_endpoint        = true
  skip_final_snapshot         = true      # Sample data: destroy leaves nothing behind.
  apply_immediately           = true      # Sample data: apply changes now, not in a maintenance window.
  tags                        = local.tag # On the cluster only, because Clumio protects Aurora by cluster.

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 1
  }
}

resource "aws_rds_cluster_instance" "core_banking" {
  count              = var.with_aurora ? 1 : 0
  identifier         = "clumio-sample-aurora-1"
  cluster_identifier = aws_rds_cluster.core_banking[0].id
  engine             = aws_rds_cluster.core_banking[0].engine
  instance_class     = "db.serverless"
}

# Loads 1,000 fake accounts in one statement. INSERT IGNORE makes it safe to run again.
resource "terraform_data" "seed" {
  count            = var.with_aurora ? 1 : 0
  triggers_replace = [aws_rds_cluster.core_banking[0].id]
  depends_on       = [aws_rds_cluster_instance.core_banking]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      AWS_REGION  = var.region
      CLUSTER_ARN = aws_rds_cluster.core_banking[0].arn
      SECRET_ARN  = aws_rds_cluster.core_banking[0].master_user_secret[0].secret_arn
      DATABASE    = aws_rds_cluster.core_banking[0].database_name
    }
    command = <<-EOT
      set -euo pipefail
      run() { aws rds-data execute-statement --resource-arn "$CLUSTER_ARN" --secret-arn "$SECRET_ARN" --database "$DATABASE" --sql "$1" > /dev/null; }
      # The Data API can lag the new instance by a minute, so try up to 10 times, 15 seconds apart.
      for try in $(seq 10); do run "SELECT 1" && break; [ "$try" = 10 ] && exit 1; sleep 15; done
      run "CREATE TABLE IF NOT EXISTS accounts (id INT PRIMARY KEY, customer VARCHAR(40), balance DECIMAL(12,2))"
      run "INSERT IGNORE INTO accounts WITH RECURSIVE seq (n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 1000) SELECT n, CONCAT('Demo Customer ', LPAD(n, 4, '0')), (n * 37) % 10000 + 0.25 FROM seq"
    EOT
  }
}

# --- What a restore must reproduce -------------------------------------------------------

output "restore_check" {
  value = join("\n", compact([
    "S3: bucket ${aws_s3_bucket.statements.id}, ${length(local.statements)} files. After restoring ${local.sample_file}, its sha256 must be ${sha256(local.statements[local.sample_file])}.",
    var.with_aurora ? "Aurora: cluster clumio-sample-aurora, database bank. On a restored cluster, SELECT COUNT(*), SUM(balance) FROM accounts must return 1000, ${format("%.2f", sum([for n in range(1, 1001) : (n * 37) % 10000 + 0.25]))}." : "",
  ]))
}

output "next_step" {
  value = "Protect it by tag ${var.backup_tag.key} = ${var.backup_tag.value}: 2-protect-s3 with protect_by = \"tag\"${var.with_aurora ? ", and 2-protect-rds (needs \"rds\" in step 1's workloads)" : ""}."
}
