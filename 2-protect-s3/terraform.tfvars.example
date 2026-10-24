account_id = "ACCOUNT-ID-REPLACE-THIS" # your 12-digit AWS account ID, as in step 1
region     = "REGION-REPLACE-THIS"     # where your data is, such as ap-southeast-1

# Choose buckets one way: by name or by tag.
protect_by = "name" # "name" or "tag"

# By name: list the buckets (names, not ARNs).
bucket_names = ["BUCKET-NAME-REPLACE-THIS"]

# By tag: every bucket with this tag, now and later.
# bucket_tag = { key = "backup-tier", value = "gold" }

name                       = "" # name in Clumio; empty means s3-<account>-<region>
standard_retention_days    = 30 # days to keep each daily copy; 30 or more
backtrack_retention_months = 3  # months Backtrack can roll back; needs S3 Versioning
