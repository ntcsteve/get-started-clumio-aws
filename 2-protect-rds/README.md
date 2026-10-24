# Step 2b: Protect RDS and Aurora

Part of [Get started with Clumio on AWS](../README.md). Set up your terminal as in [Before you begin](../README.md#before-you-begin) first.

Do step 2a, step 2b, or both, in any order.

**What it does.** Creates one Clumio backup policy with three tiers, and a protection rule that applies it to the databases you choose:

- **AWS PITR** (point-in-time recovery) is AWS's continuous backup. Its length is the database's PITR window, AWS's `BackupRetentionPeriod`. Clumio sets it.
- **SecureVault Standard** keeps a daily copy in Clumio's air-gapped, immutable storage.
- **SecureVault Archive** keeps a monthly copy long term, at lower cost.

**What you need.** `"rds"` in step 1's `workloads` (if you're adding it now, run steps 0 and 1 again). Then set `2-protect-rds/terraform.tfvars`:

- `account_id` and `region`, as in step 1.
- One way to choose databases:
  - **By tag** (recommended): `protect_by = "tag"` and `database_tag = { key = "backup-tier", value = "gold" }`. Protects every database with the tag, now and later.
  - **By name** (not yet tested live): `protect_by = "name"` and `database_names = ["my-uat-db"]`, using DB identifiers (an Aurora cluster's, or an RDS instance's), not ARNs. Protects exactly those, without touching their tags. Clumio can't check names when you plan, so a misspelled name protects nothing: check the inventory afterwards.
- `pitr_retention_days`: the PITR window, 1 to 35 days. No default, because Clumio applies it to your databases.
- `standard_retention_days` and `archive_retention_months` (`0` turns the Archive tier off).

**Before you run it.** This step changes your databases.

- Clumio sets the PITR window on every chosen database, longer or shorter than today. Check the current window first: `aws rds describe-db-clusters` (Aurora) or `aws rds describe-db-instances` (RDS).
- Need different windows? Use a copy of this folder per window, each with its own tag or names.
- An RDS instance with backups off restarts in its next maintenance window when Clumio turns them on.
- An `archive_retention_months` below 12 incurs Clumio's early-deletion fee.

**Run it.**

```bash
cd 2-protect-rds
terraform init
terraform plan
terraform apply
terraform plan
```

**What you should see.** The first plan adds two resources, the backup policy and its protection rule; the second says *No changes*. In the Clumio console, AWS, Inventory, RDS resources shows your policy (`rds-<account>-<region>` unless you set `name`) on each chosen database. Under Tasks, you can follow Clumio as it sets the PITR window and takes the first Standard and Archive copies.

By tag, databases you create or tag later are protected too, once Clumio finds them. Restored databases keep their tag, so they're protected as well. By name, only the names you list are protected: a restored copy with a new name is not, until you add it.

**If something goes wrong.** A database shows no policy? Check the tag or name for a typo. A database shows a different policy? Another protection rule matched first. Clumio checks rules in order, and this one goes last so it never overrides yours. Narrow or remove the other rule.

**Next:** [Operate](../docs/operate.md): what you now have, restores, alerts, and running it as a team.
