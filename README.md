# Get started with Clumio on AWS

**Ship fast, with a way back you can prove.**

Cloud teams change data all day: deployments, scripts, migrations, and now AI agents. Many data incidents aren't outages. They're changes that were allowed and wrong, and no alarm fires. Clumio by Commvault keeps copies of your AWS data apart from your account, and recovers them at the size of the mistake: one file, a folder of files, a few database rows, or a whole database, even when every copy in the account is gone.

This repository sets Clumio up on AWS with Terraform, the way a platform team runs it: the permissions Clumio needs, shown before anything is created; protection written as code; and a hands-on workshop to practice recovery before you need it.

## Choose your path

**New to AWS or Clumio? Start with the [workshop](workshops/orders-recovery/README.md),** and keep [Words you'll see](docs/words.md) open beside it. Protect real data later, with the steps.

| You want to | Go to | You need |
|---|---|---|
| Learn recovery hands-on | [Orders recovery workshop](workshops/orders-recovery/README.md) | A test AWS account, and two sessions |
| Protect real data | [Step 0](0-iam-preview/README.md), then steps 1 and 2 | A deploy role in your account, and a Clumio account |
| Review what Clumio can do in your account | [SECURITY.md](SECURITY.md), which also lists what's tested live and what isn't | Nothing but time to read it |
| Run it as a team | [Running it as a team](docs/operate.md#running-it-as-a-team) | Shared state, and someone who reads the alerts |

No Clumio account yet? Start a [free trial](https://portal.clumio.com/register), or subscribe through [AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-hdul2n6jr5dou). The Clumio Region you choose at sign-up can't be changed later.

## Why Clumio

What it gives a cloud team, as Clumio's documentation describes it:

- **Recover at the size of the mistake.** Restore one object, a prefix or a whole bucket. For a database, pull back selected records with SQL from an archive recovery point, or restore the whole database beside the original. You don't roll everything back to fix a part.
- **Roll back without rewiring.** Backtrack rolls an S3 bucket back in place, by writing earlier versions back as current. It's the same bucket, so its policies and your Terraform state don't change.
- **A way back outside the blast radius.** SecureVault keeps copies air-gapped and immutable, outside your organization's security domain. Deleting one before its retention ends takes a request from a Super Admin, approved by a second person in your organization, which Clumio then reviews. A restore can go into another connected account or Region.
- **Protection as code, nothing to run.** Policies are Terraform resources that select data by tag, so new resources are covered once Clumio finds them. Clumio works through IAM roles in your account, with no agents or servers.
- **A record of every recovery.** Every backup and restore is a Clumio task with its start and end times, so each recovery test leaves evidence.

What it isn't: Backtrack needs S3 Versioning, and rolls back only to points up to its last daily sync. For databases, Clumio sets AWS point-in-time recovery rather than replacing it. An Aurora restore creates a new cluster. Archive recovery points in cold storage take up to 48 hours to prepare for a query. This repository doesn't cover EC2 and EBS protection (`"ebs"` creates only its IAM), DynamoDB, Iceberg, SQL Server on EC2, or SecureVault Archive for S3.

How it compares with AWS Backup, and when AWS Backup alone is enough: [Clumio and AWS Backup](docs/clumio-and-aws-backup.md).

## Why this repository

Connecting Clumio is mostly an IAM problem. Clumio needs IAM roles and policies in your account. In a company account, the identity that creates them usually has limited permissions and must follow naming rules. When the two don't match, setup fails one permission at a time and can leave a half-built connection.

This repository deals with that first. Before anything is created, it shows every role, policy and permission Clumio will add, and checks that your deploy role, the identity that creates them, is allowed to. You fix most gaps before you apply, not halfway through; step 0's limits are in [SECURITY.md](SECURITY.md#what-step-0s-check-cant-see).

This is not an official Clumio product. It uses Clumio's Terraform provider and module, pinned to tested versions. For questions about this repository, open a GitHub issue. For problems with the Clumio service, contact Clumio support.

## How it works

Three steps, and an optional step 1b. Step 2 has two folders, one for S3 and one for RDS and Aurora, so you can use either or both. Each folder is a chapter: its README guides you, and you edit one file, `terraform.tfvars`.

```
 Step 0  Preview   ── READY ──▶  Step 1  Connect   ──▶  Step 2  Protect
 read only                       once per account       S3, RDS and Aurora,
 for your security team          and Region             or both
                                     │
                                     └─▶ Step 1b  Your own key: optional, permanent
```

| Step | Chapter | What it does |
|---|---|---|
| 0 | [Preview the IAM](0-iam-preview/README.md) | Shows every IAM role and permission before anything exists. Read only |
| 1 | [Connect your account](1-connect-clumio/README.md) | Connects one account and Region to Clumio, with the IAM step 0 showed |
| 1b | [Use your own key](1b-own-key/README.md) | Optional and permanent: Clumio encrypts with your AWS KMS key |
| 2a | [Protect S3 buckets](2-protect-s3/README.md) | Backtrack and SecureVault, for buckets by name or tag |
| 2b | [Protect RDS and Aurora](2-protect-rds/README.md) | Point-in-time recovery, SecureVault Standard and Archive, by tag or name |
| | [Operate](docs/operate.md) | What you have, choosing the way back, alerts, troubleshooting, running it as a team, upgrading |

Each step has its own Terraform state, so you can change protection without touching the connection.

When you're done, one AWS account and Region are connected to Clumio, with IAM roles named by your rules and daily backups of the data you chose. The first backups start as soon as protection is applied. Backtrack's first sync can take up to 48 hours.

The logic lives once, in `modules/`. Each step folder only sets your values and calls a module. The workshop calls the same modules, so what you learn there is what you run here.

## Before you begin

You need:

1. Terraform 1.5 or later, Python 3 and the AWS CLI.
2. For steps 0 and 1, an AWS sign-in to the account you're connecting. Step 2 needs none.
3. A Clumio API token, from the Clumio console under Administration, Access management, API tokens.

Set your Clumio details as environment variables, so the token never lands in a file:

```bash
export CLUMIO_API_BASE_URL=https://us-west-2.api.clumio.com   # your portal's API URL, from the table below
read -rs CLUMIO_API_TOKEN && export CLUMIO_API_TOKEN          # paste the token; it stays out of your history
```

Your API URL, and your Clumio Region, follow from the portal you sign in to. The Region matters only for step 1b. The URLs are from [Clumio's Terraform provider](https://registry.terraform.io/providers/clumio-code/clumio/latest/docs).

| Clumio portal | `CLUMIO_API_BASE_URL` | Clumio Region |
|---|---|---|
| portal.clumio.com, west.portal.clumio.com | `https://us-west-2.api.clumio.com` | us-west-2 |
| east.portal.clumio.com | `https://us-east-1.api.clumio.com` | us-east-1 |
| canada.portal.clumio.com | `https://ca-central-1.ca.api.clumio.com` | ca-central-1 |
| eu1.portal.clumio.com | `https://eu-central-1.de.api.clumio.com` | eu-central-1 |
| au.portal.clumio.com | `https://ap-southeast-2.au.api.clumio.com` | ap-southeast-2 |
| jp.portal.clumio.com | Ask your Clumio administrator | ap-northeast-1 |

In each step folder you use, create your settings from the example: `cp terraform.tfvars.example terraform.tfvars`. Your copy stays out of git, so an update never conflicts with it.

Every step's `terraform.tfvars` names the same `account_id` and `region`. Steps 0 and 1 refuse to run when you're signed in to any other account. Step 2 stops if Clumio has no connection for them.

Then start with [step 0](0-iam-preview/README.md).

Changing this repository, or using an AI agent with it? Read [AGENTS.md](AGENTS.md) first.
