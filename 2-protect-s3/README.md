# Step 2a: Protect S3 buckets

Part of [Get started with Clumio on AWS](../README.md). Set up your terminal as in [Before you begin](../README.md#before-you-begin) first.

Do step 2a, step 2b, or both, in any order.

**What it does.** Creates one Clumio backup policy with two tiers, and applies it to the buckets you choose:

- **Backtrack** rolls a bucket back to a point in time, in place. It uses the bucket's own versions, indexed daily, so the data stays in your account.
- **SecureVault Standard** keeps a daily copy in Clumio's air-gapped, immutable storage.

**What you need.** `account_id` and `region` in `2-protect-s3/terraform.tfvars`, as in step 1, and one way to pick buckets:

- **By name**: `protect_by = "name"` and `bucket_names = ["my-bucket"]`. Protects exactly those. If Clumio can't see one, the plan stops and names it.
- **By tag**: `protect_by = "tag"` and `bucket_tag = { key = "backup-tier", value = "gold" }`. Protects every bucket with the tag, now and later. Nothing fails if none has it yet, so check the bucket count in Clumio.

Then set retention: `standard_retention_days` (30 or more) and `backtrack_retention_months`.

**Before you run it.**

- Turn on S3 Versioning, or Backtrack has nothing to roll back to. A lifecycle rule that deletes old versions shortens Backtrack too.
- Only S3 Standard, Standard-IA, Intelligent-Tiering and One Zone-IA are backed up, not Glacier classes.
- There's no Archive tier: Clumio allows one SecureVault tier per S3 backup policy.
- Clumio's role can change a bucket's event notifications and inventory, and write and delete objects during restores.

**Run it.**

```bash
cd 2-protect-s3
terraform init
terraform plan
terraform apply
terraform plan
```

**What you should see.** The second plan says *No changes*. In the Clumio console, the protection group (your buckets under this policy, named `s3-<account>-<region>` unless you set `name`) shows its first backup when it completes. Backtrack is ready after its first daily sync, which can take up to 48 hours.

**If something goes wrong.** *AWS connection not found*: `account_id` or `region` doesn't match step 1, or step 1 hasn't run. *S3 bucket not found*: a wrong name, another Region, or a new bucket Clumio hasn't found yet; wait, then retry.

**Next:** [Step 2b](../2-protect-rds/README.md) for databases, or [Operate](../docs/operate.md).
