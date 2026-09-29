# Get started with Clumio on AWS

Terraform to back up S3 buckets and RDS / Aurora databases with Clumio, a backup service that
keeps copies outside your AWS account. One folder per step; steps 1 and 2 keep separate state.

```
step               who          when        does
0-iam-preview      security     first       Shows the IAM Clumio will create; checks the deploy role may create it
1-connect-clumio   platform     once        Connects one AWS account + region to Clumio; creates that IAM
2-protect-s3       backup ops   as needed   One policy: Backtrack + SecureVault Standard. Buckets by name or tag
2-protect-rds      backup ops   as needed   One policy: AWS PITR + SecureVault Standard + Archive. By tag
```

Use either step 2, or both. Security team: read [SECURITY.md](SECURITY.md).
Not an official Clumio product. Uses Clumio's Terraform provider and module (`aws-template` 0.41.0).

## Terms

| Term | Meaning |
|---|---|
| Connection | Clumio's link to one AWS account + region (step 1) |
| Workload | What Clumio may protect: `s3`, `rds` (RDS + Aurora), `ebs` (EC2 + EBS) |
| Deploy role | The AWS identity that runs step 1. It creates Clumio's IAM |
| API token | Your Clumio API credential. Never stored in state |
| ExternalId | Secret Clumio needs to use its roles. Stored in step 1's state |
| SecureVault | Clumio's storage, outside your account. Standard: restores in minutes. Archive: cheaper, restores in hours |
| Backtrack | Rolls an S3 bucket back in place, from its own versions. Data stays in your account |
| AWS PITR | AWS point-in-time recovery for RDS and Aurora. Clumio sets its retention |
| Policy / rule | Clumio's schedule and retention / which databases it applies to (by tag) |
| Protection group | A set of S3 buckets under one policy |

## Before you start

- Terraform 1.5+, python3, the AWS CLI.
- Steps 0 and 1: an AWS login to the account you'll connect. Step 2: no AWS login.
- A Clumio API token: Clumio UI > Administration > Access Management > API Tokens.

```bash
export CLUMIO_API_BASE_URL=https://us-west-2.api.clumio.com   # your Clumio portal's API URL
read -rs CLUMIO_API_TOKEN && export CLUMIO_API_TOKEN          # paste; stays out of shell history
```

Each step's `terraform.tfvars` holds `account_id` and `region`. Step 1 refuses a login to any
other account. Step 2 stops if Clumio has no connection for them.

## Step 0: set your IAM rules, then preview (read only)

In `1-connect-clumio/terraform.tfvars`, set:

- `account_id`, `region`
- `iam_prefix`, `iam_path`: your IAM naming rule
- `workloads`: `"s3"`, `"rds"`, `"ebs"` (`"ebs"` adds IAM only; EC2/EBS protection isn't in this kit)
- Only if required: `role_tags`, `permissions_boundary_arn`, `pass_role_deny_list`

```bash
cd 0-iam-preview
./preview.sh                          # checks your login
./preview.sh --as <deploy role ARN>   # checks the role that will run step 1
```

| Result | Do |
|---|---|
| READY | Go to step 1 |
| BLOCKED | In the output folder's `policies/deploy-role-policy.json`, replace `<ACCOUNT_ID>`, grant it, run again |
| CANNOT CHECK | Root login or no permission to check: run it with `--as` |

Pass: READY, and security signs off.

## Step 1: connect

Uses the settings step 0 checked. Changed them? Run step 0 again.

```bash
cd 1-connect-clumio
terraform init
terraform plan      # 32 to add (S3), 42 (S3 + RDS), 58 (+ EC2/EBS); +1 with a deny list
terraform apply
terraform plan      # must say No changes
```

| Second plan says | Do |
|---|---|
| No changes | Wait 5 minutes (Clumio finds your data), then step 2 |
| Changes | `terraform apply` once more. Still changes after that: see Known errors |
| `AccessDenied` | Run step 0 with `--as`, grant what BLOCKED lists, apply again |

Pass: No changes, and Clumio shows the account + region as Connected.

## Step 2: protect S3

| Tier | Does | Set | First run |
|---|---|---|---|
| Backtrack | Rolls a bucket back in place. Needs S3 Versioning | `backtrack_retention_months` | Minutes |
| SecureVault Standard | Daily copy in Clumio | `standard_retention_days` (30+) | Minutes |

- No Archive tier: Clumio allows one SecureVault tier per S3 policy (error 111).
- Backed up: S3 Standard, Standard-IA, Intelligent-Tiering, One Zone-IA. Not Glacier classes.
- A lifecycle rule that deletes old versions also shortens Backtrack.
- Clumio's role may change a bucket's event notifications and inventory, and write and delete
  objects (restores).

In `2-protect-s3/terraform.tfvars`, set `account_id`, `region`, and how to pick buckets:

| `protect_by` | Set | Backs up | Bucket missing |
|---|---|---|---|
| `"name"` | `bucket_names = ["a", "b"]` | Exactly those | Plan fails and names it |
| `"tag"` | `bucket_tag = { key = "k", value = "v" }` | Every tagged bucket, now and later | Nothing fails: check the group's bucket count |

```bash
cd 2-protect-s3
terraform init
terraform apply     # adds 3 + one per bucket (by name), or 3 (by tag)
```

Pass: a second plan says No changes; protection group `s3-<account>-<region>` shows a backup
and a Backtrack sync.

## Step 2: protect RDS and Aurora

Needs `"rds"` in `workloads` (steps 0 and 1 again). Tag each database, then set
`2-protect-rds/terraform.tfvars`.

| Tier | Does | Set | First run |
|---|---|---|---|
| AWS PITR | Clumio sets each database's backup retention | `pitr_retention_days` (required) | Minutes |
| SecureVault Standard | Daily copy in Clumio | `standard_retention_days` | About 15 minutes |
| SecureVault Archive | Monthly long-term copy | `archive_retention_months` (under 12 has a fee) | About 40 minutes |

**PITR changes your databases:**

- Clumio sets `pitr_retention_days` on every tagged database, **lower or higher** than today.
  Today's value: `BackupRetentionPeriod` in `aws rds describe-db-clusters` / `describe-db-instances`.
- Different windows need different tags: one copy of this folder per window.
- An RDS instance with backups off restarts in its maintenance window when Clumio turns them on.

```bash
cd 2-protect-rds
terraform init
terraform apply     # adds 2: policy + rule
```

Pass: a second plan says No changes; each tagged database shows policy `rds-<account>-<region>`
(Clumio UI > AWS > Inventory > RDS Resources); Tasks show PITR sync, Standard and Archive done.

- **An older rule wins:** this rule is added last in Clumio's order.
- **Restores keep the tag,** so restored databases are protected too.

## Restore

Clumio UI: open the bucket, database or protection group > Restore. Restore to a **new**
prefix, bucket or database; never overwrite live data. Backtrack is the exception: it rolls
the bucket back in place.

## Monitoring

Terraform doesn't report failed backups. In Clumio, set alerts and a daily compliance report,
and name who reads them. Check Clumio UI > Tasks after any change.

## Stop backups

`terraform destroy` in a step 2 folder removes that policy. Backups taken stay until they
expire. For RDS, then set each database's retention yourself.

## Disconnect

1. Stop backups first.
2. Confirm with Clumio that your tenant allows deleting connections. **If not, stop:** the
   destroy would delete Clumio's IAM, then fail (error 367), leaving the connection broken.
3. In `1-connect-clumio/main.tf`, delete `prevent_destroy = true`, then `terraform destroy`.

## Known errors

| You see | Do |
|---|---|
| `Set account_id` / `Set region` | Fill in `terraform.tfvars` |
| `AWS account ID not allowed` (steps 0, 1) | Log in to the `account_id` account |
| `AWS connection not found` (step 2) | Fix `account_id` / `region`, or run step 1 |
| `AccessDenied` on `CreateRole`, `TagRole`, `CreatePolicy` (step 1) | Step 0 with `--as`; grant what BLOCKED lists; apply again (it resumes) |
| `S3 bucket not found` / `Clumio can't see bucket(s)` (step 2) | Check the name and `region`; new buckets appear within minutes |
| A tagged database shows another policy | An older rule matched first: narrow or remove it in Clumio |
| First backup "queued" after 30 minutes | Contact Clumio support with the task ID (Clumio UI > Tasks) |
| `error_code 320 ... already exists` | An apply was cut off: `terraform import <address> <id from Clumio UI>`, then apply |
| `error_code 111` (step 2 S3) | Keep one SecureVault tier per S3 policy |
| `Instance cannot be destroyed` (step 1) | Protected on purpose: see Disconnect |
| `error_code 367` | Your tenant can't delete connections: keep it, or ask Clumio support |
| Plan still shows changes after two applies | Save the plan output; contact Clumio support |
| Anything else | Re-run with `TF_LOG=DEBUG TF_LOG_PATH=./tf-debug.log`. The log can hold secrets: check before sharing |

## Running it as a team

- **State:** step 1's state holds the ExternalId. Use a private, encrypted S3 backend with
  locking (Terraform 1.10+ for `use_lockfile`), in each step's `backend.tf` (not `versions.tf`,
  which step 0 reads). The deploy role also needs access to that bucket and its KMS key.

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

- **Versions:** the module (`0.41.0`) and providers (`.terraform.lock.hcl`) are pinned, so step 0
  shows exactly what step 1 creates. To upgrade: change the version in `1-connect-clumio/main.tf`,
  `terraform init -upgrade` in each step, then step 0 again.
- **Ownership:** Terraform owns these Clumio policies; UI edits are undone by the next apply.
- **Scale:** one copy of these folders per account + region.
- **Workloads:** removing one deletes its IAM; Clumio stops protecting it.
- **Tags:** tag data by backup tier (gold, silver, bronze); Clumio's rules match tags.
- **Changing this kit:** run `./check.sh` before every commit.

## Not covered

BYOK; EC2/EBS protection (its IAM is ready with `"ebs"`); DynamoDB; Iceberg; SQL Server on EC2;
S3 SecureVault Archive.

## Clumio documentation

- [IAM permissions required to deploy](https://documentation.commvault.com/clumio/iam_permissions_required_to_deploy_clumio_service.html): compare with step 0's list
- [Permissions file details](https://documentation.commvault.com/clumio/permissions_file_details.html): why each role and permission exists
- [Inventory](https://documentation.commvault.com/clumio/inventory.html): what Clumio found, and its protection status
- [Best practices](https://documentation.commvault.com/clumio/best_practices_for_clumios_platform.html): tags, access, monitoring
