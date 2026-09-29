# Sample data

No data ready to protect? This folder creates a small, realistic S3 bucket and, optionally, a small Aurora database. **Sandbox accounts only.**

Both are tagged `backup-tier = gold`, so step 2 can pick them by tag. All data is fake, and every run creates the same content, so you can check a restore against known values.

## What it creates

**Always: an S3 bucket**, `clumio-sample-<account>-<region>-statements`, versioned so Backtrack works. It holds 24 small CSV statements for two fake customers, under `statements/2026/<month>/`. Private and encrypted by default. About a minute; costs next to nothing.

**With `with_aurora = true`: an Aurora MySQL Serverless v2 cluster**, `clumio-sample-aurora`, at 0.5 to 1 capacity units, the setup tested with Clumio. Encrypted, not public, with seven days of PITR. Its `bank` database has an `accounts` table of 1,000 fake accounts. About ten minutes, and **it costs money while it runs**, even idle.

The cluster needs a default VPC in the Region. AWS Secrets Manager keeps its password, not Terraform. Rows are loaded through the RDS Data API via the AWS CLI, so no network path to the database is needed.

## Run it

Set `account_id`, `region` and `with_aurora` in `terraform.tfvars`, then:

```bash
terraform init
terraform apply
```

Terraform prints `restore_check`, what a restore must reproduce: a file's SHA-256 checksum for S3, and the row count and balance total for Aurora.

*No matching EC2 VPC found* means the Region has no default VPC; create one, or leave `with_aurora` off. *AWS account ID not allowed* means you're logged in to another account.

## Protect it

Run steps 0 and 1 if you haven't. Then in step 2:

- S3: in `2-protect-s3/terraform.tfvars`, set `protect_by = "tag"` and `bucket_tag = { key = "backup-tier", value = "gold" }`.
- Aurora: add `"rds"` to step 1's `workloads`, then in `2-protect-rds/terraform.tfvars` set `database_tag = { key = "backup-tier", value = "gold" }`.

Clumio finds the bucket within minutes. A new database can take about half an hour to get its backup policy.

## Remove it

First `terraform destroy` in the step 2 folders you used, then `terraform destroy` here. It deletes the bucket with all versions and the cluster without a final snapshot, so nothing is left and nothing keeps costing money.
