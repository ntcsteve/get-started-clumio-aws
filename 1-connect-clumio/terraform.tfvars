# 0-iam-preview reads this file. After any change, preview again, so what you create is what was approved.
account_id = "ACCOUNT-ID-REPLACE-THIS" # your 12-digit AWS account ID; Terraform refuses any other login
region     = "REGION-REPLACE-THIS"     # where your data is, such as ap-southeast-1

iam_prefix = ""         # e.g. "my-team-clumio" if your IAM names must start with a prefix
iam_path   = "/clumio/" # "/" if your naming rule is role/<prefix>-* (no path)
workloads  = ["s3"]     # add "rds" (RDS + Aurora), "ebs" (EC2 + EBS); then run 0-iam-preview again

# Only if your organization requires them (see SECURITY.md):
# role_tags                = { team = "platform" }
# permissions_boundary_arn = "arn:aws:iam::<account>:policy/<boundary>"
# pass_role_deny_list      = ["arn:aws:iam::<account>:role/<role Clumio must never pass>"]
