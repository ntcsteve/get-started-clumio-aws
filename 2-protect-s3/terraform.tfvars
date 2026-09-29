account_id = "ACCOUNT-ID-REPLACE-THIS" # your 12-digit AWS account ID, as in step 1
region     = "REGION-REPLACE-THIS"     # where your data is, such as ap-southeast-1

# Pick ONE way to choose buckets.
protect_by = "name" # "name" or "tag"

# protect_by = "name": list the buckets (names, not ARNs).
bucket_names = ["BUCKET-NAME-REPLACE-THIS"]

# protect_by = "tag": every bucket with this tag, now and later.
# bucket_tag = { key = "clumio-backup", value = "daily" }

name                       = "" # "" = s3-<account>-<region>; the protection group + policy name in Clumio
standard_retention_days    = 30 # daily SecureVault Standard copies, 30 or more
backtrack_retention_months = 3  # Backtrack window, months (needs S3 Versioning on the bucket)
