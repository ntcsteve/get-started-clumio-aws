account_id = "ACCOUNT-ID-REPLACE-THIS" # your 12-digit AWS account ID, as in step 1
region     = "REGION-REPLACE-THIS"     # where your data is, such as ap-southeast-1

# Needs "rds" in 1-connect-clumio's workloads.
database_tag = { key = "clumio-backup", value = "rds-lifecycle" } # every RDS instance + Aurora cluster with this tag

name                     = "" # "" = rds-<account>-<region>; the Clumio policy + rule name
pitr_retention_days      = 0  # REPLACE: your current PITR window, 1 to 35 (Clumio sets it DOWN too)
standard_retention_days  = 7  # daily SecureVault Standard copies, days
archive_retention_months = 12 # monthly SecureVault Archive copies, months (under 12 has a fee)
