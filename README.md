# Get started with Clumio on AWS

This repository connects an AWS account to Clumio and backs up your S3 buckets and your RDS and Aurora databases, using Terraform. Clumio is a managed backup service that keeps copies outside your AWS account, so a mistake, an attack or a lost account can't take the backups with it.

At the end, one AWS account and Region are connected to Clumio, with IAM roles named by your rules and daily backups of the data you chose. A first run takes about an hour, mostly waiting for the first backups.

This is not an official Clumio product. It uses Clumio's Terraform provider and module, pinned to tested versions. [SECURITY.md](SECURITY.md) lists what has and hasn't been tested live. For questions about this repository, open a GitHub issue. For problems with the Clumio service, contact Clumio support.

## Why this exists

Connecting a backup service is mostly an IAM problem. Clumio needs IAM roles and policies in your account. In a company account, the identity that creates them usually has limited permissions and must follow naming rules. When the two don't match, setup fails one permission at a time and can leave a half-built connection.

This repository deals with that first. Before anything is created, it shows every role, policy and permission Clumio will add, and checks that your deploy role, the identity that creates them, is allowed to. You fix gaps before you apply, not halfway through.

## How it works

Three steps, one folder each. In each step you edit one file, `terraform.tfvars`.

```
 Step 0  Preview   ── READY ──▶  Step 1  Connect   ──▶  Step 2  Protect
 read only                       once per account       S3, RDS and Aurora,
 for your security team          and Region             or both
```

**Step 0, Preview,** runs a Terraform plan without applying it. It writes a folder for your security team with every IAM role and policy, what Clumio can do, and the exact policy your deploy role needs. Then it asks AWS whether the deploy role has those permissions: READY or BLOCKED.

**Step 1, Connect,** registers your account and Region with Clumio and creates the IAM roles and policies step 0 showed. You run it once. It refuses any other AWS account and protects the connection from accidental deletion.

**Step 2, Protect,** creates a Clumio backup policy for S3 buckets (step 2a), RDS and Aurora databases (step 2b), or both. It only talks to Clumio; Clumio then works in your account through the roles from step 1.

Each step has its own Terraform state, so you can change protection without touching the connection.

## Before you begin

You need:

1. Terraform 1.5 or later, Python 3 and the AWS CLI.
2. For steps 0 and 1, a login to the AWS account you're connecting. Step 2 needs none.
3. A Clumio API token, from the Clumio UI under Administration > Access Management > API Tokens.

Set your Clumio details as environment variables, so the token never lands in a file:

```bash
export CLUMIO_API_BASE_URL=https://us-west-2.api.clumio.com   # your Clumio portal's API address
read -rs CLUMIO_API_TOKEN && export CLUMIO_API_TOKEN          # paste the token; it stays out of your history
```

Every step's `terraform.tfvars` names the same `account_id` and `region`. Steps 0 and 1 refuse a login to any other account. Step 2 stops if Clumio has no connection for them.

No data to try it on? [Sample data](sample-data/README.md) creates a small bucket and database in a sandbox account.

## Step 0: Preview the IAM

**What it does.** Shows every IAM role, policy and permission step 1 will create, and checks that your deploy role may create them. Nothing is created.

**What you need.** Your settings in `1-connect-clumio/terraform.tfvars`. Step 1 reads the same file, so what you preview is what you get.

- `account_id` and `region`: the account and Region to connect.
- `iam_prefix` and `iam_path`: your naming rule. If roles must start with `platform-`, set `iam_prefix = "platform-clumio"` and `iam_path = "/"`.
- `workloads`: what Clumio may protect. Start with `["s3"]`; add `"rds"` for RDS and Aurora.
- Only if your organization requires them: `role_tags`, `permissions_boundary_arn`, `pass_role_deny_list`. See SECURITY.md.

**Before you run it.** In a sandbox where you're an administrator, step 0 is optional; step 1's plan shows the same resources. In a company account, don't skip it.

**Run it.**

```bash
cd 0-iam-preview
./preview.sh --as arn:aws:iam::<account>:role/<your deploy role>
```

Without `--as`, it checks your own login.

**What you should see.** A summary, and a folder `clumio-iam-preview-<region>-<time>` for your security team. The last line is the answer:

- **READY**: the deploy role can create everything. Go to step 1.
- **BLOCKED**: lists each missing permission. Replace `<ACCOUNT_ID>` in the folder's `policies/deploy-role-policy.json`, grant it to the deploy role, and run step 0 again.
- **CANNOT CHECK**: you're the root user, or can't run the check. Ask someone who can to run it with `--as`.

**If something goes wrong.** *AWS account ID not allowed* means you're logged in to another account. For other errors, see [When something goes wrong](#when-something-goes-wrong).

## Step 1: Connect your account

**What it does.** Registers your account and Region with Clumio, then creates the IAM roles and policies, an SNS topic and some EventBridge rules that Clumio needs.

**What you need.** The `terraform.tfvars` step 0 checked, and a READY (in a sandbox, optional). Changed a setting since? Run step 0 again.

**Before you run it.** `terraform destroy` can't remove the connection. That's deliberate; see [Disconnect](#disconnect).

**Run it.**

```bash
cd 1-connect-clumio
terraform init
terraform plan
terraform apply
terraform plan
```

The first plan adds 32 resources for S3, 42 for S3 and RDS, or 58 for S3, RDS and EBS, plus one with a pass-role deny list.

**What you should see.** The second plan says *No changes*: the connection is complete. *Apply complete* alone isn't enough. The Clumio UI shows your account and Region as Connected. Wait five minutes for Clumio to find your data, then go to step 2.

**If something goes wrong.** Second plan still shows changes? Apply once more; an interrupted apply can need a second pass. Still changes? Save the plan output and contact Clumio support. *AccessDenied* means the deploy role lacks a permission: run step 0 with `--as`, grant what BLOCKED lists, and apply again. Terraform resumes where it stopped.

## Step 2a: Protect S3 buckets

Do step 2a, step 2b, or both, in any order.

**What it does.** Creates one Clumio backup policy with two tiers, and applies it to the buckets you choose:

- **Backtrack** rolls a bucket back to an earlier day, in place. It uses the bucket's own versions, indexed daily, so the data stays in your account.
- **SecureVault Standard** keeps a daily copy in Clumio, outside your account. Restores take minutes.

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

**What you should see.** The second plan says *No changes*. In the Clumio UI, the protection group (your buckets under this policy, named `s3-<account>-<region>` unless you set `name`) shows its first backup and Backtrack index within minutes.

**If something goes wrong.** *AWS connection not found*: `account_id` or `region` doesn't match step 1, or step 1 hasn't run. *S3 bucket not found*: a wrong name, another Region, or a new bucket Clumio hasn't found yet; wait a few minutes and retry.

## Step 2b: Protect RDS and Aurora

Do step 2a, step 2b, or both, in any order.

**What it does.** Creates one Clumio backup policy with three tiers, and a backup rule that applies it to every database with your tag:

- **AWS PITR** (point-in-time recovery) is AWS's continuous backup. Its length is the database's PITR window, AWS's `BackupRetentionPeriod`. Clumio sets it.
- **SecureVault Standard** keeps a daily copy in Clumio, outside your account.
- **SecureVault Archive** keeps a monthly copy long term, at lower cost.

**What you need.** `"rds"` in step 1's `workloads` (if you're adding it now, run steps 0 and 1 again). Tag each database to protect, then set `2-protect-rds/terraform.tfvars`:

- `account_id` and `region`, as in step 1.
- `database_tag`: the tag that selects databases.
- `pitr_retention_days`: the PITR window, 1 to 35 days. No default, because Clumio applies it to your databases.
- `standard_retention_days` and `archive_retention_months`.

**Before you run it.** This step changes your databases.

- Clumio sets the PITR window on every tagged database, longer or shorter than today. Check the current window first: `aws rds describe-db-clusters` (Aurora) or `aws rds describe-db-instances` (RDS).
- Need different windows? Use a tag and a copy of this folder per window.
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

**What you should see.** The first plan adds two resources, the backup policy and rule; the second says *No changes*. In the Clumio UI, AWS > Inventory > RDS Resources shows your policy (`rds-<account>-<region>` unless you set `name`) on each tagged database. Under Tasks, the PITR window is set within minutes, the first Standard copy takes about 15 minutes, and the first Archive copy about 40.

Databases you create or tag later are protected too, after a delay; in our test, about half an hour. Restored databases keep their tag, so they're protected as well.

**If something goes wrong.** A tagged database shows a different policy? Another backup rule matched first. Clumio checks rules in order, and this one goes last so it never overrides yours. Narrow or remove the other rule.

## After setup

### What you now have

| Data | Backup | How often | Kept by default | Setting |
|---|---|---|---|---|
| S3 | Backtrack | Daily | 3 months | `backtrack_retention_months` |
| S3 | SecureVault Standard | Daily | 30 days | `standard_retention_days` |
| RDS and Aurora | AWS PITR | Continuous | You choose, 1 to 35 days | `pitr_retention_days` |
| RDS and Aurora | SecureVault Standard | Daily | 7 days | `standard_retention_days` |
| RDS and Aurora | SecureVault Archive | Monthly | 12 months | `archive_retention_months` |

### Restore

In the Clumio UI, open the bucket, database or protection group and choose Restore. Restore to a new prefix, bucket or database, never over live data. Standard copies restore in minutes, Archive copies in hours. Backtrack is the exception: it rolls a bucket back in place, so use it only to undo recent changes.

With [sample data](sample-data/README.md), its `restore_check` output tells you what a correct restore contains.

### Know when a backup fails

Terraform sets up protection but doesn't report on backups. In the Clumio UI, turn on alerts and a daily compliance report, and name who reads them. After any change, check Tasks.

### Stop backups

`terraform destroy` in a step 2 folder removes that backup policy. Existing backups stay until their retention ends. For RDS and Aurora, set each database's PITR window yourself afterwards.

### Disconnect

A destroy removes Clumio's IAM roles and policies first, then the connection. If Clumio refuses the second part, the connection is left without roles and backups stop. That's why step 1 blocks `terraform destroy`. To disconnect:

1. Stop backups first.
2. Confirm with Clumio that your tenant (your Clumio organization) allows deleting connections. If not, stop: the destroy would fail halfway with error 367.
3. In `1-connect-clumio/main.tf`, delete `prevent_destroy = true`, then run `terraform destroy`.

## When something goes wrong

| You see | What to do |
|---|---|
| *Set account_id* or *Set region* | Replace the placeholder in `terraform.tfvars`. |
| *AWS account ID not allowed* | You're logged in to another account. Log in to `account_id`. |
| *AWS connection not found* | Fix `account_id` or `region` in step 2, or run step 1. |
| *AccessDenied* on `CreateRole`, `TagRole` or `CreatePolicy` | The deploy role lacks a permission. Run step 0 with `--as`, grant what BLOCKED lists, apply again. |
| *S3 bucket not found* or *Clumio can't see bucket(s)* | Check the name and `region`. New buckets appear within minutes. |
| A tagged database shows another backup policy | An older backup rule matched first. Narrow or remove it. |
| First backup still queued after 30 minutes | Contact Clumio support with the task ID from Tasks. |
| *error_code 320 ... already exists* | An apply was cut off. Run `terraform import <address> <ID from the Clumio UI>`, then apply. |
| *error_code 111* | Use one SecureVault tier per S3 backup policy. |
| *Instance cannot be destroyed* | Step 1 protects the connection. See [Disconnect](#disconnect). |
| *error_code 367* | Your tenant can't delete connections. Keep it, or ask Clumio support. |
| Plan still shows changes after two applies | Save the plan output and contact Clumio support. |
| Anything else | Rerun with `TF_LOG=DEBUG TF_LOG_PATH=./tf-debug.log`. The log can hold secrets; check before sharing. |

## Running it as a team

**Keep state private and shared.** Step 1's state holds the ExternalId, the secret Clumio uses to assume its role, so keep it off laptops. Use an encrypted S3 backend with locking, in a `backend.tf` in each step (not `versions.tf`, which step 0 reads). The deploy role needs read and write on that bucket and its KMS key. `use_lockfile` needs Terraform 1.10+.

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

**Upgrade on purpose.** The module version is pinned in `1-connect-clumio/main.tf`, and providers are locked in each `.terraform.lock.hcl`, so step 0 previews exactly what step 1 creates. To upgrade: change the module version, run `terraform init -upgrade` in each step, then step 0 again.

**Let Terraform own the backup policies.** Edits in the Clumio UI are undone by the next apply. Change `terraform.tfvars` instead.

**Grow by copying.** One copy of these folders per account and Region. Tag data by tier (gold, silver, bronze), with a step 2 folder per tier.

**Remove workloads carefully.** Removing one from `workloads` deletes its IAM, and Clumio stops protecting that data.

## Reference

### Terms

| Term | Meaning |
|---|---|
| Backup policy | Clumio's schedule and retention for one kind of data. Not an IAM policy. |
| Backup rule | Which databases a backup policy applies to, by tag. |
| Connection | Clumio's link to one AWS account and Region (step 1). |
| Deploy role | The AWS identity that runs step 1 and creates Clumio's IAM. |
| ExternalId | The secret Clumio presents to use its roles. Kept in step 1's state. |
| PITR window | Days of AWS point-in-time recovery a database keeps (`BackupRetentionPeriod`). |
| Protection group | S3 buckets that share one backup policy. |
| SecureVault | Clumio's storage outside your account. Standard restores in minutes; Archive costs less and restores in hours. |
| Tenant | Your Clumio organization. |
| Workload | What Clumio may protect: `s3`, `rds` (RDS and Aurora), `ebs` (EC2 and EBS). |

### Not covered

BYOK (your own keys), EC2 and EBS protection (`"ebs"` creates only its IAM), DynamoDB, Iceberg, SQL Server on EC2, and SecureVault Archive for S3.

### Clumio documentation

- [Getting started with the Clumio provider](https://registry.terraform.io/providers/clumio-code/clumio/latest/docs/guides/getting_started): Clumio's one-file quick start, for a sandbox.
- [IAM permissions required to deploy](https://documentation.commvault.com/clumio/iam_permissions_required_to_deploy_clumio_service.html): Clumio's deploy permissions, to compare with step 0.
- [Permissions file details](https://documentation.commvault.com/clumio/permissions_file_details.html): why each role and permission exists.
- [Inventory](https://documentation.commvault.com/clumio/inventory.html): what Clumio found, and its protection status.
- [Best practices](https://documentation.commvault.com/clumio/best_practices_for_clumios_platform.html): tags, access and monitoring.

### Changing this repository

Run `./check.sh` before every commit. It checks formatting and validation, confirms the placeholders stop a plan, and compares step 0's output with known-good copies.
