# Security review

For the team that approves Clumio's IAM. Step 0 (`0-iam-preview/preview.sh`) lists every role,
policy, permission and ARN for your settings, plus the deploy role's policy. This page explains
it. Facts come from Clumio's module (`aws-template` 0.41.0) and live tests.

## Sign-off checklist

1. **Naming:** set `iam_prefix` and `iam_path`. Allow the names Clumio fixes (below).
2. **Controls:** set `role_tags`, `permissions_boundary_arn`, `pass_role_deny_list` if required.
3. **Reach:** review what Clumio's roles and topic may do (below, and step 0's highlights).
4. **Deploy role:** in step 0's output folder, `policies/deploy-role-policy.json`: replace `<ACCOUNT_ID>`, then grant it,
   plus read and write on your Terraform state bucket.
5. **Check:** `./preview.sh --as <deploy role ARN>` says READY.

## The deploy role is privileged

It creates IAM, so use it from CI/CD only, with short-lived credentials.

`deploy-role-policy.json` narrows it:

- IAM actions are limited to names starting with `[<prefix>-]Clumio`; SNS and EventBridge to
  `Clumio*` (Clumio fixes those names).
- It attaches only policies named `[<prefix>-]Clumio*` (`iam:PolicyARN`). This limits the
  **name, not the content**: it can create such a policy with any content.
- With `permissions_boundary_arn`, it creates roles only with that boundary and can't remove it.

What remains: it can create a `Clumio*` role with any trust policy (even one another account
can assume) and any permissions. **Without a permissions boundary, it is equivalent to an
administrator.** With one, every role it creates is capped by the boundary.

Regulated organizations: set `permissions_boundary_arn`, and alert on (or SCP-block) changes to
`Clumio*` roles' trust policies.

## Names

| Entity | Default (`iam_prefix = ""`, `iam_path = "/clumio/"`) | With `iam_prefix` |
|---|---|---|
| Main role | `/clumio/ClumioIAMRole-<r>-<token>` | `<path><prefix>-ClumioIAMRole-<r>` |
| EventBridge role (S3) | `/clumio/ClumioS3EbRole-<r>-<token>` | `<path><prefix>-ClumioS3EbRole-<r>` |
| Support role | `/clumio/ClumioSuppt-<region>-<token>` | `<path><prefix>-ClumioSuppt-<region>` |
| Managed policies | `/clumio/Clumio<Name>Policy-<region>-<token>` | `<path><prefix>-Clumio<Name>Policy-<region>` |
| S3 EventBridge policy | `/ClumioS3EbPolicy-<account>-<region>-<token>` | `/<prefix>-ClumioS3EbPolicy-<region>` |
| Inline policies, SNS topic, EventBridge rules | `Clumio<Name>…<token>` | Unchanged: Clumio sets these |

`<r>`: short Region (`ase-1` for ap-southeast-1). `<token>`: issued by Clumio at connect.

> **Important** The S3 EventBridge policy is always at path `/`: the module ignores `iam_path`
> for it. A path rule or SCP needs an exception. Step 0 shows and grants it correctly.

## Your organization's rules

| Your rule | Set in `1-connect-clumio/terraform.tfvars` | Note |
|---|---|---|
| Names need a prefix | `iam_prefix` | 36 characters at most |
| Names need a path, or none | `iam_path`, such as `"/"` | Starts and ends with `/`. Not applied to the S3 EventBridge policy |
| Roles need your tags | `role_tags` | Added to Clumio's `Vendor = Clumio` |
| Roles need a permissions boundary | `permissions_boundary_arn` | Must allow what Clumio's policies grant, or backups fail |
| Some roles must never be passed | `pass_role_deny_list` | Adds an inline deny policy |
| Inline policy, topic, rule names | Not settable | Allow an exception |
| Tags on the topic, rules or managed policies | Not supported | An SCP requiring them blocks step 1 |
| Encrypted SNS topic | Not in this kit | Module input `create_clumio_inventory_sns_topic_encryption_key`; the deploy role then needs KMS |

> **Important** Clumio tags its roles, so the deploy role needs `iam:TagRole`. Without it,
> `CreateRole` fails with `AccessDenied` (proven live).

> **Important** Changing `iam_prefix` or `iam_path` later replaces Clumio's roles and policies.

## Who can use Clumio's roles and topic

| Resource | Who | How |
|---|---|---|
| Main role | Clumio's account (`ClumioCustomerProtectRole`) | Assume, only with your ExternalId |
| Support role | Clumio's account (`ClumioCustomerSupportRole`) | Assume, only with your ExternalId |
| EventBridge role (S3) | Amazon EventBridge | Assume, only from your account |
| SNS topic | Any principal, and EventBridge | Publish, only from your account (`AWS:SourceAccount`) |
| SNS topic | Clumio's account | Subscribe, list subscriptions |

The ExternalId is a secret in step 1's state.

## What Clumio's roles may do

Highlights; step 0 derives them from the policies. Read every file in `policies/`.

| Workload | May do |
|---|---|
| All | Use any KMS key whose key policy lets IAM grant access (deny it in the key policy to exclude). Send events to Clumio's event bus and queues |
| S3 | Read objects in any bucket it can reach, including other accounts' that allow it. Write and delete objects in this account's buckets (restores). Change bucket notifications and inventory. Copy backups only to Clumio's own account. At runtime, create EventBridge rules `clumio-s3-event-rule-*` and Storage Lens configs `clumio-storage-lens-*` |
| RDS / Aurora | Change settings of every database in the region, not only tagged ones (backup retention). Create, copy, delete snapshots. Pass any role, only to RDS (restores). Same IAM serves DocumentDB and Neptune |
| EC2 / EBS | Launch instances (restores). Terminate only instances it restored. Delete only snapshots tagged `Vendor=Clumio`. Pass any role, only to EC2 |
| Support | Open, read, update AWS Support cases; read Trusted Advisor. Always created: no setting to turn it off |

## What step 1 creates

| Kind | Always | + S3 | + RDS | + EC2/EBS |
|---|---|---|---|---|
| IAM roles | 2 (main, support) | +1 | 0 | 0 |
| Managed policies | 1 | +3 | +2 | +2 |
| Inline policies | 4 (+1 with a deny list) | 0 | 0 | 0 |
| SNS topic (+ its policy) | 1 | 0 | 0 | 0 |
| EventBridge rules | 1 | +2 | +3 | +6 |

## What the deploy role needs

From CloudTrail on live runs (create, update, destroy), plus tagging and boundary actions.
`[<prefix>-]` appears only when `iam_prefix` is set.

| Statement | On | Actions | Condition |
|---|---|---|---|
| Manage roles | `role/<path>[<prefix>-]Clumio*` | `iam:TagRole, UntagRole, ListRoleTags, GetRole, DeleteRole, ListRolePolicies, ListAttachedRolePolicies, ListInstanceProfilesForRole, PutRolePolicy, GetRolePolicy, DeleteRolePolicy, UpdateAssumeRolePolicy, UpdateRole`; `DeleteRolePermissionsBoundary` only without a boundary | None |
| Create roles | same | `iam:CreateRole, PutRolePermissionsBoundary` | Your boundary, if set |
| Attach policies | same | `iam:AttachRolePolicy, DetachRolePolicy` | Policy name as in the next row |
| Managed policies | `policy/<path>[<prefix>-]Clumio*`, and the S3 EventBridge policy at `/` | `iam:CreatePolicy, GetPolicy, GetPolicyVersion, ListPolicyVersions, CreatePolicyVersion, DeletePolicyVersion, DeletePolicy` | None |
| SNS topic | `sns:<region>:<account>:ClumioInventoryTopic_*` | `sns:CreateTopic, GetTopicAttributes, SetTopicAttributes, ListTagsForResource, DeleteTopic` | None |
| EventBridge rules | `events:<region>:<account>:rule/Clumio*` | `events:PutRule, DescribeRule, ListTagsForResource, PutTargets, ListTargetsByRule, RemoveTargets, DeleteRule` | None |

`UpdateAssumeRolePolicy` and `UpdateRole` are for module upgrades. No `iam:PassRole`. Not
included: your state bucket. Step 2 needs no AWS permissions.

## What the check can't see

Step 0 asks AWS's IAM policy simulator, which evaluates the deploy role's policies, boundary and
SCPs with the Region, tags, boundary and policy ARN step 1 sends. It can't see resource control
policies or other condition keys your SCPs test. READY is strong evidence; the first apply by
the deploy role is the proof.

## Proven live, and not yet

| Proven live (test tenant, 2026-09) | Not yet |
|---|---|
| Connect; protect S3 (Backtrack + Standard), RDS and Aurora (PITR + Standard + Archive); restore; teardown | EC2/EBS connect (IAM rendered only) |
| Preview names match the IAM created | `role_tags`, boundary, deny list applied by a least-privilege role |
| `iam:TagRole` required; READY and BLOCKED | `iam:PolicyARN` and boundary conditions under a real apply |
| Step 2 stops without a connection (`AWS connection not found`) | Step 1 at the default `iam_path = "/clumio/"` (live runs used `/`) |

## Where Clumio's documentation differs

- `iam:TagRole` is required; Clumio's deploy list omits it.
- `ClumioSSMNotificationRole` (SQL Server on EC2, not used here) is trusted by
  `ssm.amazonaws.com` in the module; Clumio's docs say Clumio's control plane.

Sources: [IAM permissions required to deploy](https://documentation.commvault.com/clumio/iam_permissions_required_to_deploy_clumio_service.html),
[Permissions file details](https://documentation.commvault.com/clumio/permissions_file_details.html).
