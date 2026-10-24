# Security review

For the team that approves Clumio's access to an AWS account: what step 1 creates, who can use it, what Clumio can do, and what the deploy role needs.

You don't have to trust this page. Step 0 (`0-iam-preview/preview.sh`) writes the exact list for your settings: every role, policy, permission and ARN, as JSON you can read and diff. This page explains it. Facts come from Clumio's Terraform module 0.41.0 and live tests.

## What you're approving

Step 1 creates two IAM roles (three with S3), some managed and inline IAM policies, an SNS topic and EventBridge rules in one account and Region. [What step 1 creates](#what-step-1-creates) has the numbers. Clumio's AWS account assumes the main role to find, back up and restore data, and must present a secret ExternalId to do so. The ExternalId is kept in step 1's Terraform state.

You're also approving the deploy role, the AWS identity that runs step 1. It creates IAM, so it's the most privileged part of this setup.

## How to review and sign off

1. **Naming.** Set `iam_prefix` and `iam_path` in `1-connect-clumio/terraform.tfvars` to your rule. Allow the names Clumio fixes (see [Names](#names)).
2. **Controls.** If required, set `role_tags`, `permissions_boundary_arn` and `pass_role_deny_list` (see [Your organization's rules](#your-organizations-rules)).
3. **Reach.** Read [What Clumio can do](#what-clumio-can-do-in-your-account) and the highlights in step 0's `summary.md`.
4. **Deploy role.** In step 0's `policies/deploy-role-policy.json`, replace `<ACCOUNT_ID>` and grant it to the deploy role, plus read and write on your Terraform state bucket.
5. **Check.** Run `./preview.sh --as <deploy role ARN>`. Sign off on READY.

## The deploy role, and its risk

The deploy role creates IAM, so use it from CI/CD only, with short-lived credentials, never as a daily login.

Step 0's policy narrows it three ways:

- IAM actions work only on names starting with `[<prefix>-]Clumio`, where `[<prefix>-]` is your `iam_prefix` and a dash, or nothing. SNS and EventBridge actions work only on names starting with `Clumio`, because Clumio fixes those names.
- It can attach only policies named `[<prefix>-]Clumio*`. This limits the name, not the content: it can create such a policy with any permissions.
- With `permissions_boundary_arn`, it can create roles only with your boundary, and can't remove it.

Real power remains. It can create a `Clumio*` role with any trust policy, even one another AWS account can assume, and any permissions. **Without a permissions boundary, the deploy role equals an administrator.** With one, every role it creates is capped by the boundary.

For regulated organizations: set `permissions_boundary_arn`, and alert on, or block with a service control policy (SCP), changes to `Clumio*` roles' trust policies.

## Names

By default, Clumio names its roles and policies `Clumio…` under path `/clumio/`, ending most names with a connection token it issues at connect. With `iam_prefix`, names start with your prefix and drop the token.

| What | Default name | With `iam_prefix` |
|---|---|---|
| Main role | `/clumio/ClumioIAMRole-<r>-<token>` | `<path><prefix>-ClumioIAMRole-<r>` |
| EventBridge role (S3) | `/clumio/ClumioS3EbRole-<r>-<token>` | `<path><prefix>-ClumioS3EbRole-<r>` |
| Support role | `/clumio/ClumioSuppt-<region>-<token>` | `<path><prefix>-ClumioSuppt-<region>` |
| Managed policies | `/clumio/Clumio<Name>Policy-<region>-<token>` | `<path><prefix>-Clumio<Name>Policy-<region>` |
| S3 EventBridge policy | `/ClumioS3EbPolicy-<account>-<region>-<token>` | `/<prefix>-ClumioS3EbPolicy-<region>` |
| Inline policies, SNS topic, EventBridge rules | `Clumio<Name>…<token>` | Unchanged: Clumio sets these |

`<r>` is the short Region, such as `ase-1` for ap-southeast-1.

One exception: Clumio's module always creates the S3 EventBridge policy at path `/`, whatever `iam_path` says. If you enforce a path, it needs an exception. Step 0 lists and grants it at its real path.

## Your organization's rules

| Your rule | Setting | Note |
|---|---|---|
| Names need a prefix | `iam_prefix` | 36 characters at most. |
| Names need a path, or none | `iam_path`, such as `"/"` | Starts and ends with `/`. The S3 EventBridge policy ignores it. |
| Roles need your tags | `role_tags` | Added to Clumio's `Vendor = Clumio`. |
| Roles need a permissions boundary | `permissions_boundary_arn` | Must allow what Clumio's policies grant, or backups fail. |
| Some roles must never be passed | `pass_role_deny_list` | Adds an inline policy that denies passing them. |

Some things can't be set. Inline policies, the SNS topic and EventBridge rules keep Clumio's names, so they need a naming exception. The topic, rules and managed policies can't carry your tags, so an SCP requiring tags on them blocks step 1. The SNS topic isn't encrypted with your key; the module can (`create_clumio_inventory_sns_topic_encryption_key`), but the deploy role then needs KMS permissions.

Two more facts. Clumio tags its roles, so the deploy role needs `iam:TagRole` as well as `iam:CreateRole`, or role creation fails with *AccessDenied*. And changing `iam_prefix` or `iam_path` later replaces all of Clumio's roles and policies.

## Who can use it

| Resource | Who | How |
|---|---|---|
| Main role | Clumio's AWS account (`ClumioCustomerProtectRole`) | Assume, only with your ExternalId |
| Support role | Clumio's AWS account (`ClumioCustomerSupportRole`) | Assume, only with your ExternalId |
| EventBridge role (S3) | Amazon EventBridge | Assume, only for your account |
| SNS topic | Any principal, and EventBridge | Publish, only from your account (`AWS:SourceAccount`) |
| SNS topic | Clumio's AWS account | Subscribe, list subscriptions |

The SNS topic carries changes in your account, such as a new bucket, to Clumio. "Any principal" looks open, but the `AWS:SourceAccount` condition allows only sources in your account to publish.

## What Clumio can do in your account

The permissions reviewers ask about. Step 0 finds them in the policies and lists them under "Review before approving" in `summary.md`. Read every file in `policies/` before approving.

**All workloads:** use any KMS key whose key policy allows IAM principals in your account, to read encrypted data (deny Clumio in a key's policy to exclude it); send events and messages to Clumio's event bus and queues.

**S3:** read objects in any bucket it can reach, including other accounts' buckets that allow it; write and delete objects in your buckets, for restores; change bucket event notifications and inventory; copy backups only to Clumio's own account; at runtime, create EventBridge rules `clumio-s3-event-rule-*` and Storage Lens configurations `clumio-storage-lens-*`.

**RDS and Aurora:** change settings of every database in the Region, not only tagged ones, to manage backup retention; create, copy and delete snapshots; pass any role to RDS, so restored databases get their roles back. The same permissions cover DocumentDB and Neptune.

**EC2 and EBS:** launch instances for restores; terminate only instances it restored; delete only snapshots tagged `Vendor=Clumio`; pass any role to EC2.

**Support:** open, read and update AWS Support cases; read Trusted Advisor. This role is always created; it can't be turned off.

## Step 1b: your own key

Optional. Clumio's `byok-template` module, pinned to version 0.5.7 in `1b-own-key/main.tf`, creates:

- **The IAM role `ClumioKMSRole`** (or `<iam_prefix>-ClumioKMSRole`), at path `/`, with no permissions boundary and no tags: the module takes neither. Only Clumio's role `ClumioCustomerProtectRole` in Clumio's account can assume it, with an ExternalId kept in step 1b's state.
- **Its inline policy `ReplicaAndGrantManagement`**, on your key only, in any Region: replicate it and tag it; describe it; create grants limited to encrypt, decrypt, re-encrypt, generate data keys, describe, create grants and retire grants; list and retire grants. It may also create keys, but only replica keys.
- **Grants are not limited to Clumio.** The policy doesn't restrict who a grant is for, and a grant can allow further grants. So Clumio's role can let any principal, in any account, use your key for those operations. Grants also outlive changes to the role and its policy.
- **The alias `alias/clumio-byok`** on your key.

It doesn't change your key's policy. Clumio's access comes through the role's IAM policy, so the key policy must let IAM in your account grant access, as AWS's default key policy does.

Clumio creates replicas of your key in the Regions where it keeps backups, and sets their key policies; they aren't copied from the primary. After the first backup, review the replicas and their grants (`aws kms list-grants`).

To see Clumio use the key, look in CloudTrail for KMS calls on it by Clumio's users, such as `KMS-backup`, `KMS-restore` and `daebaksrv-S3Backup`. To cut Clumio off, disable the primary key and every replica: backups and restores that need them then stop. Deleting them makes the backups they encrypted unreadable for good.

## What is proven, and what isn't

Tested live on a Clumio test tenant twice: in September 2026 at commit f257189, and on 2026-10-24 on a version just before commit bef3aca, which calls the shared modules in `modules/`. bef3aca adds that run's fixes, tested offline only, like every change since.

**Proven:** connecting; protecting S3 (Backtrack, SecureVault Standard) and RDS and Aurora (PITR, SecureVault Standard, Archive); restoring; tearing down; IAM names matching step 0; `iam:TagRole` being required; READY and BLOCKED results; the IAM simulator allowing every action in the generated deploy policy, at the shipped defaults and with a prefix, boundary and tags; step 2 stopping without a connection; a protection rule picking up a newly created tagged database; upgrading steps 1, 2a and 2b from f257189, where the plan shows only moves, and says No changes after one apply; the shared modules connecting an account and protecting a database and a bucket by tag; placing a protection rule before an older, wider one in a shared tenant (`before_rule_id`); and the orders workshop end to end: a Backtrack roll back, a record restore to a CSV, an Aurora restore beside the original, and a full recovery after the database, the bucket and their AWS backups were deleted.

**Not yet proven:** RDS and Aurora protection by name; step 1 at the default path `/clumio/` (live runs used `/`); a full apply by a least-privilege deploy role, with tags, boundary and deny list; connecting EC2 and EBS (step 0 renders their IAM, but no live run created it); step 1b (BYOK), which has never been applied live: its key checks and permanence gate are tested offline, with mock providers; the optional compliance report (`report_emails`).

**Tested offline, in `./check.sh`:** formatting and validation of every step; the shipped placeholders stopping each plan; step 0's output against known-good copies; the shared modules choosing data and refusing bad input, with mock providers; step 1b's key checks; and the workshop lab's core logic: the check's verdict, the safety gate, the scorecard, the record-restore CSV, and the account check before every deletion.

## What step 0's check can't see

READY comes from AWS's IAM policy simulator. It's strong evidence, but it can't see resource control policies, or every condition your SCPs test, so the deploy role's first apply is the final proof. [The check](0-iam-preview/README.md#the-check) explains what it tests.

## Reference

### What step 1 creates

| What | Always | With S3 | With RDS | With EC2 and EBS |
|---|---|---|---|---|
| IAM roles | 2 (main, support) | +1 | none | none |
| Managed policies | 1 | +3 | +2 | +2 |
| Inline policies | 4, or 5 with a deny list | none | none | none |
| SNS topic, with its policy | 1 | none | none | none |
| EventBridge rules | 1 | +2 | +3 | +6 |

With `report_emails` set, step 1 also creates a Clumio compliance report: a Clumio object, not an AWS one, so step 0 doesn't show it.

### The deploy role's policy

From CloudTrail records of live runs that created, updated and destroyed everything, plus tagging and boundary actions. `[<prefix>-]` appears only when `iam_prefix` is set.

| Statement | Resources | Actions | Condition |
|---|---|---|---|
| Manage roles | `role/<path>[<prefix>-]Clumio*` | `iam:TagRole`, `UntagRole`, `ListRoleTags`, `GetRole`, `DeleteRole`, `ListRolePolicies`, `ListAttachedRolePolicies`, `ListInstanceProfilesForRole`, `PutRolePolicy`, `GetRolePolicy`, `DeleteRolePolicy`, `UpdateAssumeRolePolicy`, `UpdateRole`, and `DeleteRolePermissionsBoundary` without a boundary | None |
| Create roles | Same | `iam:CreateRole`, `PutRolePermissionsBoundary` | Your boundary, if set |
| Attach policies | Same | `iam:AttachRolePolicy`, `DetachRolePolicy` | Policies named as in the next row |
| Managed policies | `policy/<path>[<prefix>-]Clumio*`, and the S3 EventBridge policy at `/` | `iam:CreatePolicy`, `GetPolicy`, `GetPolicyVersion`, `ListPolicyVersions`, `CreatePolicyVersion`, `DeletePolicyVersion`, `DeletePolicy` | None |
| SNS topic | `sns:<region>:<account>:ClumioInventoryTopic_*` | `sns:CreateTopic`, `GetTopicAttributes`, `SetTopicAttributes`, `ListTagsForResource`, `DeleteTopic` | None |
| EventBridge rules | `events:<region>:<account>:rule/Clumio*` | `events:PutRule`, `DescribeRule`, `ListTagsForResource`, `PutTargets`, `ListTargetsByRule`, `RemoveTargets`, `DeleteRule` | None |

`UpdateAssumeRolePolicy` and `UpdateRole` are for module upgrades. The deploy role never needs `iam:PassRole`. State bucket access isn't included. Step 2 needs no AWS permissions.

### Where Clumio's documentation differs

`iam:TagRole` is required, but Clumio's list of deploy permissions leaves it out. Sources: [IAM permissions required to deploy](https://documentation.commvault.com/clumio/iam_permissions_required_to_deploy_clumio_service.html), [Permissions file details](https://documentation.commvault.com/clumio/permissions_file_details.html).
