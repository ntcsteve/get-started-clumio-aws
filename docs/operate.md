# Operate

Part of [Get started with Clumio on AWS](../README.md). What you have after the steps, and how to run it day to day.

## What you now have

| Data | Backup | How often | Kept by default | Setting |
|---|---|---|---|---|
| S3 | Backtrack | Daily | 3 months | `backtrack_retention_months` |
| S3 | SecureVault Standard | Daily | 30 days | `standard_retention_days` |
| RDS and Aurora | AWS PITR | Continuous | You choose, 1 to 35 days | `pitr_retention_days` |
| RDS and Aurora | SecureVault Standard | Daily | 7 days | `standard_retention_days` |
| RDS and Aurora | SecureVault Archive | Monthly | 12 months | `archive_retention_months` |

## Choose the way back

Start from what happened. Backtrack works in place. Every other way back gives you a new database, objects in a bucket you choose, or rows in a file: check the result, then put it to use.

| What happened | Choose | Why |
|---|---|---|
| Objects overwritten or deleted, the bucket intact | Backtrack, to a point up to its last daily sync | In place: no new bucket, no change for the application |
| A few rows deleted or wrong, that existed at the last monthly archive recovery point | Record restore from an archive recovery point, with SQL, then load the rows | Only the rows you need, without restoring the whole database |
| Many rows wrong, or a table damaged | A full restore beside the original, then copy back what you need | Any size, and the live database stays online |
| A wrong change minutes ago, the account intact | AWS point-in-time recovery, to a new cluster or instance | The fastest way back inside the account |
| The database, the bucket, or their AWS copies deleted | A SecureVault restore. Recreate the bucket first | The copies live outside the account |
| An account or Region unavailable | A restore into another connected account or Region | No dependency on the source account |
| You need to look, not recover | Record restore's preview, with SQL | No database is restored |

In the Clumio console, open the bucket, database or protection group, and choose **Restore**. Restore to a new prefix, bucket or database, never over live data. Backtrack is the exception: it rolls a bucket back in place. To practice each way back before you need it, run the [orders recovery workshop](../workshops/orders-recovery/README.md).

## Know when a backup fails

Set `report_emails` in step 1, and Clumio emails a compliance report for the Region: whether every asset has a backup each day, kept at least 7 days. It's in code, so it's reviewed and kept like the rest (not yet tested live). In the Clumio console, also turn on alerts, and name who reads them. After any change, check **Activity**, **Tasks**.

## Stop backups

`terraform destroy` in a step 2 folder removes that backup policy. Existing backups stay until their retention ends. For RDS and Aurora, set each database's PITR window yourself afterwards.

## Disconnect

See [step 1, Disconnect](../1-connect-clumio/README.md#disconnect). Step 1 blocks `terraform destroy` on purpose.

## When something goes wrong

| You see | What to do |
|---|---|
| *Set account_id* or *Set region* | Replace the placeholder in `terraform.tfvars`. |
| *AWS account ID not allowed* | You're signed in to another account. Sign in to `account_id`. |
| *AWS connection not found* | Fix `account_id` or `region` in step 2, or run step 1. |
| *AccessDenied* on `CreateRole`, `TagRole` or `CreatePolicy` | The deploy role lacks a permission. Run step 0 with `--as`, grant what BLOCKED lists, apply again. |
| *S3 bucket not found* or *Clumio can't see bucket(s)* | Check the name and `region`. A new bucket can take up to an hour to appear. |
| A chosen database shows another backup policy | An older protection rule matched first. Narrow or remove it. |
| A chosen database shows no backup policy | A typo in the tag or name, or Clumio hasn't found the database yet. Fix it, or wait and check again. |
| A first backup stays queued | Contact Clumio support with the task ID from Tasks. |
| *error_code 320 ... already exists* | An apply was cut off. Run `terraform import <address> <ID from the Clumio console>`, then apply. |
| *error_code 111*, from step 2a's apply | Use one SecureVault tier per S3 backup policy. |
| *Instance cannot be destroyed* | Step 1 protects the connection. See [Disconnect](../1-connect-clumio/README.md#disconnect). |
| *error_code 367* | Your tenant can't delete connections. Keep it, or ask Clumio support. |
| Plan still shows changes after two applies | Save the plan output and contact Clumio support. |
| Anything else | Rerun with `TF_LOG=DEBUG TF_LOG_PATH=./tf-debug.log`. The log can hold secrets; check before sharing. |

## Running it as a team

**Keep state private and shared.** Steps 1 and 1b hold ExternalIds, the secrets Clumio uses to assume its roles, so keep their state off laptops. Use an encrypted S3 backend with locking, in a `backend.tf` in each step (not `versions.tf`, which step 0 reads). The deploy role needs read and write on that bucket and its KMS key. `use_lockfile` needs Terraform 1.10+.

```hcl
terraform {
  backend "s3" {
    bucket       = "<your-state-bucket>"
    key          = "clumio/<account>/<region>/<step>/terraform.tfstate"
    region       = "<region>"
    encrypt      = true
    use_lockfile = true
  }
}
```

**Let Terraform own the backup policies.** Edits in the Clumio console are undone by the next apply. Change `terraform.tfvars` instead.

**Grow by copying.** One copy of these folders per account and Region: don't change `account_id` or `region` in a folder that's already applied. This suits a handful of accounts. For a whole AWS Organization, Clumio documents onboarding with [CloudFormation StackSets](https://documentation.commvault.com/clumio/connecting_multiple_accounts_with_cloudformation_using_aws_organizations.html). Tag data by tier (gold, silver, bronze), with a step 2 folder per tier.

**One Clumio tenant per state.** A token from another tenant can't see the connection and policies this state created, so Terraform would create a second set. Swapping a token within the same tenant is safe at any time.

**Remove workloads carefully.** Removing one from `workloads` deletes its IAM, and Clumio stops protecting that data.

## Upgrade

### From f257189

Settings used to live in each step's committed `terraform.tfvars`; now each step ships `terraform.tfvars.example`, and your `terraform.tfvars` stays out of git.

1. If you applied `sample-data/`, run `terraform destroy` in it first: this version no longer has it, and what it created stays, and bills, until it's destroyed. Then run `git checkout -- sample-data/terraform.tfvars`.
2. Before you pull, copy each step's `terraform.tfvars` somewhere outside the repo.
3. Undo your edits to those files, so the pull can delete them, then pull:

   ```bash
   git checkout -- 1-connect-clumio/terraform.tfvars 2-protect-s3/terraform.tfvars 2-protect-rds/terraform.tfvars
   git pull
   ```

   If you committed your settings, git carries them into each `terraform.tfvars.example`, sometimes with a conflict. Take the new files, then commit:

   ```bash
   git checkout origin/main -- '*/terraform.tfvars.example'
   git commit
   ```
4. Put each copy back as that step's `terraform.tfvars`.
5. In each step you've applied, run `terraform init`, then `terraform plan`. Steps 1, 2a and 2b now call the shared modules, so the plan lists resources that *moved* to new addresses, and ends with `0 to add, 0 to change, 0 to destroy`. If it plans anything else, stop and open an issue.
6. Run `terraform apply`, and enter `yes`. It records the moves, and changes nothing in AWS or Clumio. The next `terraform plan` says *No changes*.
7. Run step 0 again, so the preview matches the new code.

### On purpose

The module version is pinned in `modules/clumio-account-iam/main.tf`, and providers are locked in each `.terraform.lock.hcl`, so step 0 previews exactly what step 1 creates. To upgrade: change the module version, run `terraform init -upgrade` in each step, then step 0 again.

## Clumio's documentation

- [Getting started with the Clumio provider](https://registry.terraform.io/providers/clumio-code/clumio/latest/docs/guides/getting_started): Clumio's one-file quick start, for a sandbox.
- [IAM permissions required to deploy](https://documentation.commvault.com/clumio/iam_permissions_required_to_deploy_clumio_service.html): Clumio's deploy permissions, to compare with step 0.
- [Permissions file details](https://documentation.commvault.com/clumio/permissions_file_details.html): why each role and permission exists.
- [Inventory](https://documentation.commvault.com/clumio/inventory.html): what Clumio found, and its protection status.
- [Best practices](https://documentation.commvault.com/clumio/best_practices_for_clumios_platform.html): tags, access and monitoring.
