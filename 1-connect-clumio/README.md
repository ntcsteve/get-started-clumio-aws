# Step 1: Connect your account

Part of [Get started with Clumio on AWS](../README.md). Set up your terminal as in [Before you begin](../README.md#before-you-begin) first.

**What it does.** Registers your account and Region with Clumio, then creates the IAM roles and policies, an SNS topic and some EventBridge rules that Clumio needs.

**What you need.** The `terraform.tfvars` that step 0 checked, and its READY result. In a sandbox, READY is optional. If you changed a setting since, run step 0 again.

**Before you run it.** `terraform destroy` can't remove the connection. That's deliberate; see [Disconnect](#disconnect).

**Run it.**

```bash
cd 1-connect-clumio
terraform init
terraform plan
terraform apply
terraform plan
```

The first plan adds 32 resources for S3, 42 for S3 and RDS, or 58 for S3, RDS and EBS. A pass-role deny list adds one more.

**What you should see.** The second plan says *No changes*: the connection is complete. *Apply complete* alone isn't enough. The Clumio console shows your account and Region as Connected. When Clumio's inventory lists your buckets or databases, go to step 2.

**If something goes wrong.** If the second plan still shows changes, apply once more: an interrupted apply can need a second pass. If changes remain, save the plan output and contact Clumio support. *AccessDenied* means the deploy role lacks a permission: run step 0 with `--as`, grant what BLOCKED lists, and apply again. Terraform resumes where it stopped.

## Disconnect

A destroy removes Clumio's IAM roles and policies first, then the connection. If Clumio refuses the second part, the connection is left without roles and backups stop. That's why step 1 blocks `terraform destroy`. To disconnect:

1. Stop backups first.
2. Confirm with Clumio that your tenant (your Clumio organization) allows deleting connections. If not, stop: the destroy would fail halfway with error 367.
3. In `1-connect-clumio/main.tf`, delete `prevent_destroy = true`, then run `terraform destroy`.

If you used step 1b, keep its key and every replica: the backups it encrypted need them until their retention ends.

**Next:** [Step 1b](../1b-own-key/README.md), only if a rule requires your own key. Otherwise [step 2a](../2-protect-s3/README.md) or [step 2b](../2-protect-rds/README.md).
