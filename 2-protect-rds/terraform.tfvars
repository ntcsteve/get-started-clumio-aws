account_id = "ACCOUNT-ID-REPLACE-THIS" # your 12-digit AWS account ID, as in step 1
region     = "REGION-REPLACE-THIS"     # where your data is, such as ap-southeast-1

# Needs "rds" in step 1's workloads.
database_tag = { key = "backup-tier", value = "gold" } # every RDS instance and Aurora cluster with this tag

name                     = "" # name in Clumio; empty means rds-<account>-<region>
pitr_retention_days      = 0  # REPLACE with today's PITR window, 1 to 35 days; Clumio applies it to every tagged database
standard_retention_days  = 7  # days to keep each daily copy
archive_retention_months = 12 # months to keep each monthly copy; under 12 has an early-deletion fee
